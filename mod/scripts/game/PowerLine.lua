-- Roadside Emergencies: what lies around a car that has hit a utility pole (core/LineRules.lua; the car itself is an ordinary wreck, Wrecks.lua).
--   The fallen pole is a real log (TreePlantManager:loadTreeTrunk), so the game's chainsaw cuts it, and whatever handles logs handles it. The game saves loose
--     logs itself.
--     Every piece of it is followed through the game's TREE_SHAPE_CUT message, and has to reach a recovery point, or be sold or chipped.
--     The game only lets you cut where you may work, and this pole lies on a public road, so the pieces of a running job are allowed (installCutRule).
--     A piece that can't be accounted for is looked for, never counted as brought in. A saved pole that can't be found is replaced.
--   The poles still standing are the map's own US model, by path.
--   The wires are the base-game rope model. You roll each one up on foot, holding the key, once the power is off: the wire comes down from the pole and
--     winds into a coil on the ground, loop by loop, each loop short pieces of the same rope, and the coil stays there until the job ends. Let go and it stops
--     where it is; hold again and it goes on.

RsePowerLine = {
    subscribed = false
}

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

local function playerPosition()
    if g_localPlayer == nil then
        return nil
    end
    local vehicle = g_localPlayer:getCurrentVehicle()
    if vehicle ~= nil and vehicle.rootNode ~= nil then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        return x, z
    end
    local x, _, z = g_localPlayer:getPosition()
    return x, z
end

local function groundAt(x, z)
    return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
end

---------------------------------------------------------------------------------------------------
-- Pins over what is still to do once the power is off: the same markers as over an animal (Scenes.lua)
---------------------------------------------------------------------------------------------------

local function removePin(holder)
    if holder.pin ~= nil then
        RseLog.try("remove a pin", holder.pin.delete, holder.pin)
        holder.pin = nil
    end
end

local function placePin(holder, x, y, z, px, pz)
    if holder.pin == nil and type(NavigationMarker) == "table" then
        local ok, pin = RseLog.try("create a pin", NavigationMarker.new)
        holder.pin = ok and pin or nil
    end
    if holder.pin ~= nil then
        holder.pin:setWorldPosition(x, y + RseConfig.PIN_HEIGHT, z)
        holder.pin:setVisibility(px ~= nil and (x - px) ^ 2 + (z - pz) ^ 2 <= RseConfig.PIN_RANGE ^ 2)
    end
end

local function updatePins(line)
    local px, pz = playerPosition()
    local on = line.state.powerOff == true
    for _, wire in ipairs(line.wires) do
        if on and not wire.done and not wire.rolling then
            placePin(wire, wire.x, wire.y, wire.z, px, pz)
        else
            removePin(wire)
        end
    end
    for _, piece in ipairs(line.pieces) do
        if on and nodeExists(piece.node) then
            local x, y, z = getWorldTranslation(piece.node)
            placePin(piece, x, y, z, px, pz)
        else
            removePin(piece)
        end
    end
end

local function renderPins(list)
    for _, holder in ipairs(list) do
        if holder.pin ~= nil and not RseLog.try("draw a pin", holder.pin.render, holder.pin) then
            return false
        end
    end
    return true
end

---------------------------------------------------------------------------------------------------
-- The poles still standing
---------------------------------------------------------------------------------------------------

local function childNamed(node, name)
    for i = 0, getNumOfChildren(node) - 1 do
        local child = getChildAt(node, i)
        if getName(child) == name then
            return child
        end
    end
    return nil
end

-- one pole out of the map's file of poles. Returns { node, sharedId }, or nil.
local function loadStanding(spot, yaw)
    local filename = Utils.getFilename(RseConfig.LINE_POLE_FILE, RoadsideEmergencies.MOD_DIR)
    local ok, root, sharedId = RseLog.try("load a utility pole", g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or root == nil or root == 0 then
        RseLog.info("power line: the utility pole model did not load (%s)", tostring(filename))
        return nil
    end
    local piece = childNamed(root, RseConfig.LINE_POLE_PIECE) or (getNumOfChildren(root) > 0 and getChildAt(root, 0)) or nil
    if piece == nil then
        delete(root)
        g_i3DManager:releaseSharedI3DFile(sharedId)
        return nil
    end
    link(getRootNode(), piece)
    delete(root)
    setWorldTranslation(piece, spot.x, groundAt(spot.x, spot.z), spot.z)
    setWorldRotation(piece, 0, yaw, 0)
    addToPhysics(piece)
    return { node = piece, sharedId = sharedId }
end

local function removeStanding(line)
    for _, pole in ipairs(line.standing) do
        if nodeExists(pole.node) then
            delete(pole.node)
        end
        if pole.sharedId ~= nil then
            g_i3DManager:releaseSharedI3DFile(pole.sharedId)
        end
    end
    line.standing = {}
end

---------------------------------------------------------------------------------------------------
-- The wires
---------------------------------------------------------------------------------------------------

local RseWireActivatable = {}
local RseWireActivatable_mt = Class(RseWireActivatable)

local function newActivatable(line, wire)
    local self = setmetatable({}, RseWireActivatable_mt)
    self.line, self.wire = line, wire
    self.activateText = RseText.get("rse_line_rollUp")
    return self
end

-- how far from a wire, along the ground: anywhere from its end on the road to the pole it hangs from
local function wireDistance(wire, x, z)
    return RseRoadClearRule.segmentDistance(x, z, wire.x, wire.z, wire.topX, wire.topZ)
end

-- The prompt is there before the power is off too, and pressing it says how long is left: a player must never be left wondering why nothing happens.
function RseWireActivatable:getIsActivatable()
    local wire = self.wire
    if wire.done or g_localPlayer == nil or g_localPlayer:getCurrentVehicle() ~= nil then
        return false
    end
    local x, _, z = g_localPlayer:getPosition()
    return wireDistance(wire, x, z) <= RseConfig.LINE_WIRE_REACH
end

function RseWireActivatable:getDistance(x, _, z)
    return wireDistance(self.wire, x, z)
end

-- The game's prompt only knows a single press, so the key is registered here: an object with its own input gets to do that, like the game's winch control.
function RseWireActivatable:registerCustomInput()
    local _
    _, self.actionEventId = g_inputBinding:registerActionEvent(InputAction.ACTIVATE_OBJECT, self, self.onHold, false, true, true, true)
    if self.actionEventId ~= nil then
        g_inputBinding:setActionEventTextPriority(self.actionEventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(self.actionEventId, self.activateText)
    end
end

function RseWireActivatable:removeCustomInput()
    g_inputBinding:removeActionEventsByTarget(self)
    self.actionEventId = nil
end

function RseWireActivatable:onHold(_, inputValue)
    if (inputValue or 0) > 0 then
        self.wire.held = true
    end
end

function RseWireActivatable:run()
    -- nothing: onHold does the work
end

-- a wire from the ground up to where it hangs from the pole
local function addWire(line, spec)
    local head = createTransformGroup("rseWireHead")
    link(getRootNode(), head)
    setWorldTranslation(head, spec.x, spec.y, spec.z)
    local tail = createTransformGroup("rseWireTail")
    link(getRootNode(), tail)
    setWorldTranslation(tail, spec.topX, spec.topY, spec.topZ)
    local wire = { x = spec.x, y = spec.y, z = spec.z, topX = spec.topX, topY = spec.topY, topZ = spec.topZ, head = head, tail = tail, aimed = false,
        done = false }
    local ok, rope = RseLog.try("a wire", RseStrap.createRope, head, RoadsideEmergencies.MOD_DIR, RseConfig.LINE_WIRE_FILE)
    wire.rope = ok and rope or nil
    wire.activatable = newActivatable(line, wire)
    g_currentMission.activatableObjectsSystem:addActivatable(wire.activatable)
    table.insert(line.wires, wire)
    return wire
end

local function removeWire(wire)
    if wire.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(wire.activatable)
        wire.activatable = nil
    end
    if wire.rope ~= nil then
        RseLog.try("remove a wire", wire.rope.delete, wire.rope)
        wire.rope = nil
    end
    for _, node in ipairs({ wire.head, wire.tail }) do
        if nodeExists(node) then
            delete(node)
        end
    end
    wire.head, wire.tail = nil, nil
end

local function removeCoil(wire)
    for _, piece in ipairs(wire.coil or {}) do
        if piece.rope ~= nil then
            RseLog.try("remove a coil", piece.rope.delete, piece.rope)
        end
        if nodeExists(piece.node) then
            delete(piece.node)
        end
    end
    wire.coil = nil
end

-- where the wire is after n pieces of its coil; the coil's first point is where the wire ended on the ground
local function coilAt(wire, n)
    local dx, dy, dz = RseLineRules.coilPoint(n, RseConfig)
    return wire.x + dx, wire.y + dy, wire.z - RseConfig.LINE_COIL_RADIUS + dz
end

-- one more short piece of wire lies in the coil, from point n to the next. Its rope model loads a moment later, and stays where it is.
local function layPiece(wire, n)
    local node = createTransformGroup("rseWireCoil")
    link(getRootNode(), node)
    setWorldTranslation(node, coilAt(wire, n))
    local ok, rope = RseLog.try("a coil", RseStrap.createRope, node, RoadsideEmergencies.MOD_DIR, RseConfig.LINE_WIRE_FILE)
    table.insert(wire.coil, { node = node, rope = ok and rope or nil, n = n, aimed = false })
end

-- rolling up: the wire's end goes round and round, laying the coil behind it, while the rest comes down from the pole
local function rollWire(line, wire, dt)
    wire.rollMs = wire.rollMs + dt
    local share = math.min(1, wire.rollMs / RseConfig.LINE_WIRE_ROLL_MS)
    local total = RseConfig.LINE_COIL_RINGS * RseConfig.LINE_COIL_POINTS
    wire.coil = wire.coil or {}
    while #wire.coil < math.floor(share * total) do
        layPiece(wire, #wire.coil)
    end
    if nodeExists(wire.head) then
        setWorldTranslation(wire.head, coilAt(wire, share * total))
    end
    if nodeExists(wire.tail) then
        setWorldTranslation(wire.tail, wire.topX + (wire.x - wire.topX) * share, wire.topY + (wire.y - wire.topY) * share,
            wire.topZ + (wire.z - wire.topZ) * share)
    end
    if share >= 1 then
        removeWire(wire)
        wire.rollMs, wire.rolling, wire.done = nil, false, true
        line.wiresIn = line.wiresIn + 1
        RseText.notify(RseText.get("rse_line_wireDone", RsePowerLine:wiresLeft(line)))
    end
end

local function updateWire(line, wire, dt)
    if wire.rope ~= nil and not wire.aimed and wire.rope.referenceFrame ~= nil then
        RseLog.try("aim a wire", wire.rope.setTargetNode, wire.rope, wire.tail, true)
        wire.aimed = true
    end
    -- the key sets this each frame it is held, and a press before the power is off says how long is left
    local held = wire.held == true
    wire.held = false
    if held and not wire.wasHeld and not line.state.powerOff then
        RsePowerLine:warnLive(line)
    end
    wire.wasHeld = held
    wire.rolling = held and line.state.powerOff == true
    if wire.rolling then
        if wire.rollMs == nil then
            wire.rollMs = 0
            RseLog.info("power line: rolling up a wire")
        end
        rollWire(line, wire, dt)
    end
end

-- each piece of a coil points at the next as soon as its model has loaded; it never moves again, so nothing has to follow it
local function aimCoil(wire)
    for _, piece in ipairs(wire.coil or {}) do
        if not piece.aimed and piece.rope ~= nil and piece.rope.referenceFrame ~= nil then
            piece.aimed = true
            RseLog.try("aim a coil", piece.rope.setTargetPosition, piece.rope, coilAt(wire, piece.n + 1))
        end
    end
end

---------------------------------------------------------------------------------------------------
-- The pole
---------------------------------------------------------------------------------------------------

local function addPiece(line, node)
    line.hadPole = true
    line.splitType = line.splitType or getSplitType(node)
    local x, y, z = getWorldTranslation(node)
    table.insert(line.pieces, { node = node, lastX = x, lastY = y, lastZ = z, restMs = 0 })
end

local function isTracked(line, node)
    for _, piece in ipairs(line.pieces) do
        if piece.node == node then
            return true
        end
    end
    return false
end

-- a log lying loose that could be a piece of this pole
local function isLooseLog(line, node)
    return nodeExists(node) and getHasClassId(node, ClassIds.MESH_SPLIT_SHAPE) and getSplitType(node) ~= 0
        and getRigidBodyType(node) ~= RigidBodyType.STATIC and (line.splitType == nil or getSplitType(node) == line.splitType)
end

local function deleteLog(node)
    RseStrap:releaseForNode(node)
    delete(node)
    g_treePlantManager:removingSplitShape(node)
end

-- asks the game for a loose log; the next kind of tree if the first gave none
local requestPole
requestPole = function(line)
    local manager = g_treePlantManager
    local kinds = RseConfig.LINE_POLE_TREES
    line.treeIndex = (line.treeIndex or 0) + 1
    local name = kinds[line.treeIndex]
    if name == nil then
        RseLog.problem("power line: no kind of tree gave a pole, so that part of the job counts as done")
        line.poleIn = true
        return
    end
    local desc = manager:getTreeTypeDescFromName(name)
    if desc == nil then
        RseLog.info("power line: this map has no tree kind %s", name)
        requestPole(line)
        return
    end
    local pole = line.layout.pole
    manager:loadTreeTrunk(desc, pole.x, groundAt(pole.x, pole.z) + RseConfig.LINE_POLE_DROP, pole.z, pole.dirX, 0, pole.dirZ, RseConfig.LINE_POLE_LENGTH,
        #desc.stages, 1, true, false)
    line.pending = manager.loadTreeTrunkDatas[#manager.loadTreeTrunkDatas]
    line.pendingName = name
    if line.pending == nil then
        RseLog.info("power line: tree kind %s gave no log", name)
        requestPole(line)
    end
end

-- the game cuts the log out of a whole tree over two frames, and leaves the last pieces it made in its own record of the job
local function collectPole(line)
    local pending = line.pending
    if pending == nil or pending.framesLeft > 0 then
        return
    end
    line.pending = nil
    for _, part in pairs(pending.parts or {}) do
        if not part.isBelow and nodeExists(part.shape) then
            addPiece(line, part.shape)
        end
    end
    if #line.pieces == 0 then
        RseLog.info("power line: tree kind %s gave no log", tostring(line.pendingName))
        requestPole(line)
        return
    end
    local node = line.pieces[1].node
    local x, y, z = getWorldTranslation(node)
    RseLog.info("power line: the pole is a %s log at %.1f, %.1f, %.1f, mass %.2f t, volume %.2f", tostring(line.pendingName), x, y, z, getMass(node),
        getVolume(node))
end

-- a piece is in once it lies still at a recovery point, and nothing holds it: a machine, or tension belts you still have to open
local function checkPieces(line, dt)
    local i = 1
    while i <= #line.pieces do
        local piece = line.pieces[i]
        if not nodeExists(piece.node) then
            -- Cut: its new pieces are on the list. Otherwise sold or chipped, unless a cut went unreported, so look around before believing that.
            removePin(piece)
            if not piece.cut then
                table.insert(line.lost, { x = piece.lastX, y = piece.lastY, z = piece.lastZ })
                line.lostMs = RseConfig.LINE_LOST_MS
            end
            table.remove(line.pieces, i)
        else
            local x, y, z = getWorldTranslation(piece.node)
            local moved = math.abs(x - piece.lastX) + math.abs(z - piece.lastZ)
            piece.lastX, piece.lastY, piece.lastZ = x, y, z
            local belted = getUserAttribute(piece.node, "isTensionBeltMounted") == true
            local held = belted or getRigidBodyType(piece.node) ~= RigidBodyType.DYNAMIC
            if RsePoints:at(x, z, "recovery") ~= nil and moved <= 0.02 and not held then
                piece.restMs = piece.restMs + dt
            else
                piece.restMs = 0
            end
            if piece.restMs >= RseConfig.DELIVER_REST_MS then
                removePin(piece)
                deleteLog(piece.node)
                table.remove(line.pieces, i)
                if #line.pieces > 0 then
                    RseText.notify(RseText.get("rse_line_pieceIn", #line.pieces))
                end
            else
                i = i + 1
            end
        end
    end
    if RseLineRules.poleIsIn(line) then
        line.poleIn = true
        RseText.notify(RseText.get("rse_line_poleIn"))
        RseLog.info("power line: the pole is in")
    end
end

-- Returns nothing, as the game's own callback for this does: the search has to go on past the first thing it touches.
function RsePowerLine:onLogOverlap(node)
    if node ~= nil and node ~= 0 and isLooseLog(self.searchLine, node) then
        self.foundLogs[node] = true
    end
end

local function searchAround(self, x, y, z, radius)
    overlapSphere(x, y, z, radius, "onLogOverlap", self, CollisionFlag.TREE + CollisionFlag.DYNAMIC_OBJECT, true, true, false, false)
end

-- whatever the searches found and isn't on the list yet. Returns how many.
local function adoptFound(self, line)
    local count = 0
    for node in pairs(self.foundLogs) do
        if not isTracked(line, node) then
            addPiece(line, node)
            count = count + 1
        end
    end
    self.foundLogs, self.searchLine = nil, nil
    return count
end

-- A piece went without a cut message. Anything of the same kind around where it lay is still ours; if there is nothing, it was sold or chipped.
local function findLostPieces(self, line, dt)
    line.lostMs = line.lostMs - dt
    if line.lostMs > 0 then
        return
    end
    self.foundLogs, self.searchLine = {}, line
    for _, spot in ipairs(line.lost) do
        searchAround(self, spot.x, spot.y, spot.z, RseConfig.LINE_POLE_LENGTH + 1)
    end
    local found = adoptFound(self, line)
    if found > 0 then
        RseLog.info("power line: a piece of the pole went without a cut message, and %d piece(s) were found where it lay", found)
    end
    line.lost, line.lostMs = {}, nil
end

local function collectShapes(self, line, node)
    for i = 0, getNumOfChildren(node) - 1 do
        local child = getChildAt(node, i)
        if isLooseLog(line, child) then
            self.foundLogs[child] = true
        end
        collectShapes(self, line, child)
    end
end

-- Pieces the game has loaded from the savegame hang under the tree they came from, in its own list of cut trees. That tree stands where the pole was asked for.
local function findInTreeRecord(self, line)
    local pole = line.layout.pole
    local data = g_treePlantManager.treesData
    if pole == nil or data == nil or data.splitTrees == nil then
        return
    end
    for _, tree in ipairs(data.splitTrees) do
        if tree.x ~= nil and (tree.x - pole.x) ^ 2 + (tree.z - pole.z) ^ 2 <= RseConfig.LINE_TREE_MATCH ^ 2 and nodeExists(tree.node) then
            collectShapes(self, line, tree.node)
        end
    end
end

-- A saved job: the game has put the loose logs back itself, with new node numbers. If the pole can't be found at all, it gets a new one: the job can't be
-- finished without one, and it must not count as brought in.
local function findSavedPieces(self, line, dt)
    line.searchMs = line.searchMs - dt
    if line.searchMs > 0 then
        return
    end
    line.searchTries = (line.searchTries or 0) + 1
    self.foundLogs, self.searchLine = {}, line
    findInTreeRecord(self, line)
    local expected = #(line.savedPieces or {})
    for _, saved in ipairs(line.savedPieces or {}) do
        searchAround(self, saved.x, saved.y, saved.z, RseConfig.LINE_SEARCH_RADIUS)
    end
    adoptFound(self, line)
    if #line.pieces >= expected and #line.pieces > 0 or line.searchTries >= RseConfig.LINE_SEARCH_TRIES then
        RseLog.info("power line: %d of %d saved piece(s) of the pole found again", #line.pieces, expected)
        line.searchMs, line.savedPieces = nil, nil
        if #line.pieces == 0 then
            RseLog.info("power line: the saved pole is gone, so a new one lies in its place")
            requestPole(line)
        end
    else
        line.searchMs = RseConfig.LINE_SEARCH_MS
    end
end

-- the game has cut a log: if it was ours, both ends are still ours
function RsePowerLine:onShapeCut(oldShape, shape)
    if oldShape == nil or shape == nil then
        return
    end
    for _, scene in pairs(RseScenes.scenes) do
        local line = scene.line
        if line ~= nil then
            for _, piece in ipairs(line.pieces) do
                if piece.node == oldShape then
                    piece.cut = true
                    RseStrap:releaseForNode(oldShape)
                    addPiece(line, shape)
                    RseLog.debug("power line: the pole was cut, %d piece(s)", #line.pieces)
                    return
                end
            end
        end
    end
end

-- Is this log part of a running job? A piece on the list, or a loose log of the pole's kind at the scene (a saved job, before its search has finished).
function RsePowerLine:ownsLog(shape)
    if shape == nil or shape == 0 or not entityExists(shape) then
        return false
    end
    for _, scene in pairs(RseScenes.scenes) do
        local line = scene.line
        if line ~= nil then
            if isTracked(line, shape) then
                return true
            end
            if isLooseLog(line, shape) then
                local x, _, z = getWorldTranslation(shape)
                if (x - scene.x) ^ 2 + (z - scene.z) ^ 2 <= RseConfig.LINE_OWN_RADIUS ^ 2 then
                    return true
                end
            end
        end
    end
    return false
end

-- The game asks this before any cut, by chainsaw or harvester, and only allows it where you may work; the pole lies on a public road. It says yes only where
-- the game said no and the log belongs to a job. Set on the game's manager, in front of whatever is there by now, and it comes off when the map unloads.
local function installCutRule(self)
    local manager = g_splitShapeManager
    if self.cutRule ~= nil then
        return
    end
    if manager == nil or type(manager.getIsShapeCutAllowed) ~= "function" then
        RseLog.info("power line: the game has no cut rule to answer, so the land decides where the pole can be cut")
        return
    end
    local original = manager.getIsShapeCutAllowed
    self.cutRule = function(target, x, z, shape, ...)
        local allowed = original(target, x, z, shape, ...)
        if allowed then
            return allowed
        end
        local ok, owned = RseLog.try("check a cut", self.ownsLog, self, shape)
        if ok and owned then
            if not self.cutLogged then
                self.cutLogged = true
                RseLog.info("chainsaw: the game refuses cuts on this land, and this log is the job's pole, so it goes ahead")
            end
            return true
        end
        return allowed
    end
    manager.getIsShapeCutAllowed = self.cutRule
end

local function removeCutRule(self)
    local manager = g_splitShapeManager
    if manager ~= nil and self.cutRule ~= nil and manager.getIsShapeCutAllowed == self.cutRule then
        manager.getIsShapeCutAllowed = nil -- the game's own, on its class, shows through again
    end
    self.cutRule, self.cutLogged = nil, false
end

---------------------------------------------------------------------------------------------------
-- The whole thing
---------------------------------------------------------------------------------------------------

local function subscribe(self)
    installCutRule(self)
    if not self.subscribed and g_messageCenter ~= nil and MessageType ~= nil and MessageType.TREE_SHAPE_CUT ~= nil then
        self.subscribed = true
        g_messageCenter:subscribe(MessageType.TREE_SHAPE_CUT, self.onShapeCut, self)
    end
end

local function newLine(def, layout)
    return { def = def, layout = layout, state = {}, standing = {}, wires = {}, pieces = {}, lost = {}, wiresIn = 0, wiresTotal = 0, poleIn = false }
end

-- where a wire hangs from the pole it leads to
local function wireSpec(layout, wire)
    local pole = layout.standing[wire.pole]
    return { x = wire.x, y = groundAt(wire.x, wire.z) + RseConfig.LINE_WIRE_GROUND, z = wire.z, topX = pole.x,
        topY = groundAt(pole.x, pole.z) + RseConfig.LINE_POLE_TOP, topZ = pole.z }
end

-- lays it all out around a new scene; road: what RseRoads measured, size: the job size
function RsePowerLine:spawn(scene, road, size)
    subscribe(self)
    local def = RseConfig.WRECKS[scene.wreck.kind]
    local dirX, dirZ = road.dirX or 1, road.dirZ or 0
    local length = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-6)
    dirX, dirZ = dirX / length, dirZ / length
    local side = RseLineRules.roadside(scene.x, scene.z, dirX, dirZ, road.segments, RseConfig)
    local wireCount = RseSceneSpec.count(def.wires, math.random, size)
    local layout = RseLineRules.layout(scene.x, scene.z, dirX, dirZ, side, wireCount, RseConfig)
    local line = newLine(def, layout)
    line.yaw = math.atan2(dirX, dirZ)
    line.wiresTotal = wireCount
    scene.line = line
    for _, spot in ipairs(layout.standing) do
        local ok, pole = RseLog.try("a utility pole", loadStanding, spot, line.yaw)
        if ok and pole ~= nil then
            table.insert(line.standing, pole)
        end
    end
    for _, wire in ipairs(layout.wires) do
        RseLog.try("a wire", addWire, line, wireSpec(layout, wire))
    end
    RseLog.try("the pole", requestPole, line)
    scene.wreck.waitForPower = line
    RseLog.info("power line at %.1f, %.1f: %d standing pole(s), %d wire(s)", scene.x, scene.z, #line.standing, wireCount)
end

function RsePowerLine:wiresLeft(line)
    local left = 0
    for _, wire in ipairs(line.wires) do
        if not wire.done then
            left = left + 1
        end
    end
    return left
end

-- how many things are left to do of the pole and the wires
function RsePowerLine:remaining(scene)
    local line = scene.line
    if line == nil then
        return 0
    end
    return self:wiresLeft(line) + (line.poleIn and 0 or 1)
end

function RsePowerLine:pay(scene)
    local line = scene.line
    return line ~= nil and RseLineRules.pay(line.def, line.poleIn, line.wiresIn) or 0
end

-- anything done of it yet
function RsePowerLine:hasProgress(scene)
    local line = scene.line
    return line ~= nil and (line.poleIn or line.wiresIn > 0)
end

-- for the progress bar, and for noticing that the job moves on
function RsePowerLine:share(scene)
    local line = scene.line
    local total = line.wiresTotal + 1
    return (line.wiresIn + (line.poleIn and 1 or 0)) / total
end

function RsePowerLine:progressKey(scene)
    local line = scene.line
    return line ~= nil and string.format("%d/%d/%s", line.wiresIn, #line.pieces, tostring(line.poleIn)) or ""
end

-- every frame of the job, from before you arrive
function RsePowerLine:update(scene, dt)
    local line = scene.line
    if line == nil or line.failed then
        return
    end
    line.warnMs = math.max(0, (line.warnMs or 0) - dt)
    local function step()
        collectPole(line)
        if line.searchMs ~= nil then
            findSavedPieces(self, line, dt)
        end
        if line.lostMs ~= nil then
            findLostPieces(self, line, dt)
        end
        for _, wire in ipairs(line.wires) do
            if not wire.done then
                updateWire(line, wire, dt)
            end
            aimCoil(wire)
        end
        checkPieces(line, dt)
    end
    if not RseLog.try("the power line", step) then
        line.failed = true -- once in the log; the player can still hand the job over
    end
    if not line.pinsFailed and not RseLog.try("the power line's pins", updatePins, line) then
        line.pinsFailed = true
    end
end

-- every frame, from RseScenes:draw. Returns false when a pin failed to draw.
function RsePowerLine:draw(scene)
    local line = scene.line
    return line == nil or (renderPins(line.wires) and renderPins(line.pieces))
end

-- someone tried to start on the car or a wire too early
function RsePowerLine:warnLive(line)
    if (line.warnMs or 0) > 0 then
        return
    end
    line.warnMs = RseConfig.LINE_WARN_MS
    RseText.notify(RseText.get("rse_line_stillLive", RseLineRules.secondsLeft(line.state, RseConfig)), true)
end

-- The wires may be live until the crew has been: every frame until then, once you have arrived. Returns true when the power is off.
function RsePowerLine:updatePower(scene, dt)
    local line = scene.line
    local radius = RseConfig.LINE_DANGER_RADIUS
    local x, z = playerPosition()
    local inside = x ~= nil and (x - scene.x) ^ 2 + (z - scene.z) ^ 2 <= radius * radius
    local event = RseLineRules.tickPower(line.state, dt, inside, RseConfig)
    if event == "warn" then
        RseText.notify(RseText.get("rse_line_danger"), true)
    elseif event == "cut" then
        RseText.notify(RseText.get("rse_line_dangerCut", math.floor(RseConfig.LINE_DANGER_CUT * 100 + 0.5)), true)
        RseLog.info("scene %d: stayed too long near the live wires", scene.id)
    elseif event == "off" then
        scene.wreck.waitForPower = nil
        RseText.notify(RseText.get("rse_line_powerOff"))
        RseLog.info("scene %d: the power is off", scene.id)
    end
    return line.state.powerOff == true
end

-- the job has ended: everything goes
function RsePowerLine:remove(scene)
    local line = scene.line
    if line == nil then
        return
    end
    for _, wire in ipairs(line.wires) do
        removePin(wire)
        removeWire(wire)
        removeCoil(wire)
    end
    line.wires = {}
    removeStanding(line)
    for _, piece in ipairs(line.pieces) do
        removePin(piece)
        if nodeExists(piece.node) then
            deleteLog(piece.node)
        end
    end
    line.pieces = {}
end

-- what the savegame keeps. The pieces of the pole are saved by the game; this only remembers where to look for them.
function RsePowerLine:saveData(scene)
    local line = scene.line
    if line == nil then
        return nil
    end
    local data = { powerOff = line.state.powerOff == true, liveMs = line.state.liveMs or 0, insideMs = line.state.insideMs or 0,
        warned = line.state.warned == true,
        penalized = line.state.penalized == true, wiresIn = line.wiresIn, poleIn = line.poleIn, yaw = line.yaw, splitType = line.splitType, standing = {},
        wires = {}, pieces = {} }
    local pole = line.layout.pole
    if pole ~= nil then
        data.poleX, data.poleZ, data.poleDirX, data.poleDirZ = pole.x, pole.z, pole.dirX, pole.dirZ
    end
    for _, spot in ipairs(line.layout.standing) do
        table.insert(data.standing, { x = spot.x, z = spot.z })
    end
    for _, wire in ipairs(line.wires) do
        if not wire.done then
            table.insert(data.wires, { x = wire.x, y = wire.y, z = wire.z, topX = wire.topX, topY = wire.topY, topZ = wire.topZ })
        end
    end
    for _, piece in ipairs(line.pieces) do
        if nodeExists(piece.node) then
            local x, y, z = getWorldTranslation(piece.node)
            table.insert(data.pieces, { x = x, y = y, z = z })
        end
    end
    for _, saved in ipairs(line.savedPieces or {}) do
        table.insert(data.pieces, saved)
    end
    return data
end

-- a saved job comes back: the poles and wires as they were, the pieces of the pole found again
function RsePowerLine:restore(scene, data)
    subscribe(self)
    local def = RseConfig.WRECKS[scene.wreck.kind]
    local layout = { standing = data.standing or {}, wires = {}, pole = RseLineRules.savedPoleSpot(data, scene.x, scene.z) }
    local line = newLine(def, layout)
    line.yaw = data.yaw or 0
    line.splitType = data.splitType
    line.state = { powerOff = data.powerOff, liveMs = data.liveMs, insideMs = data.insideMs, warned = data.warned, penalized = data.penalized }
    line.wiresIn = data.wiresIn or 0
    line.poleIn = data.poleIn == true
    line.wiresTotal = line.wiresIn + #(data.wires or {})
    scene.line = line
    for _, spot in ipairs(layout.standing) do
        local ok, pole = RseLog.try("a utility pole", loadStanding, spot, line.yaw)
        if ok and pole ~= nil then
            table.insert(line.standing, pole)
        end
    end
    for _, wire in ipairs(data.wires or {}) do
        RseLog.try("a wire", addWire, line, wire)
    end
    if not line.poleIn then
        line.hadPole = true
        line.savedPieces = data.pieces or {}
        line.searchMs = RseConfig.LINE_SEARCH_MS
    end
    if not line.state.powerOff then
        scene.wreck.waitForPower = line
    end
end

-- while the map unloads: the game deletes its own objects
function RsePowerLine:unload()
    for _, scene in pairs(RseScenes.scenes) do
        if scene.line ~= nil then
            for _, wire in ipairs(scene.line.wires) do
                removePin(wire)
                if wire.activatable ~= nil then
                    g_currentMission.activatableObjectsSystem:removeActivatable(wire.activatable)
                end
            end
            for _, piece in ipairs(scene.line.pieces) do
                removePin(piece)
            end
        end
    end
    removeCutRule(self)
    if self.subscribed and g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end
    self.subscribed = false
end
