-- Roadside Emergencies: recovery straps you hook where you choose (DESIGN F26).
-- On foot, look at a spot on a carcass or a wreck and press the strap key (K by default): the strap hooks exactly there. Look at a spot
-- on any vehicle or trailer and press it again: the other end goes there (onto an attacher joint if you aimed within
-- STRAP_SNAP of one). Press it on a strapped carcass or vehicle to remove the strap, or at nothing to drop the strap you
-- hold. A joint keeps the two ends at most as far apart as they were when attached; the base-game rope model shows it.
-- A joint's limits are a box along its own axes, so one axis of the joint is kept turned along the line: that makes the box a real line, which pulls
-- where it runs. Only while really towing does the joint lie along the vehicle's own axes, to keep the wreck straight behind (strap.boxed).
-- Straps are saved (carcass, the vehicle's unique id, both points, length) and put back after a reload.

RseStrap = {
    straps = {},          -- { entry or wreckVehicle, vehicle, jointIndex, vehiclePoint, hookNode, rope, ropeAimed }
    holding = nil,        -- { entry or wreckVehicle, body, hookNode }
    actionEventId = nil,
    aimHit = nil,
    shownText = nil,
    shownActive = nil
}

local ropeSchema = nil

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

local function onFoot()
    return g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() == nil
end

local function distance3D(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function createRope(towPoint, modDir, file)
    if ropeSchema == nil then
        ropeSchema = XMLSchema.new("rseStrapRope")
        ForestryRope.registerXMLPaths(ropeSchema, "strapRope.rope")
    end
    local xmlFile = XMLFile.load("rseStrapRope", Utils.getFilename(file or RseConfig.STRAP_ROPE_FILE, modDir), ropeSchema)
    if xmlFile == nil then
        return nil
    end
    local rope = ForestryRope.new(nil, towPoint)
    rope:loadFromXML(xmlFile, "strapRope.rope", modDir)
    xmlFile:delete()
    return rope
end

RseStrap.createRope = createRope

-- the vehicle component (physics body) a node belongs to
local function componentOf(vehicle, node)
    local current, depth = node, 0
    while nodeExists(current) and depth < 40 do
        for _, component in ipairs(vehicle.components) do
            if component.node == current then
                return current
            end
        end
        current = getParent(current)
        depth = depth + 1
    end
    return vehicle.components[1].node
end

-- an attacher joint of the vehicle within STRAP_SNAP of the aimed spot, as a world position
local function snapToJoint(vehicle, x, y, z)
    local spec = vehicle.spec_attacherJoints
    local best, bestDistance = nil, RseConfig.STRAP_SNAP
    for _, joint in ipairs(spec ~= nil and spec.attacherJoints or {}) do
        local node = joint.jointTransform
        if nodeExists(node) then
            local jx, jy, jz = getWorldTranslation(node)
            local d = distance3D(x, y, z, jx, jy, jz)
            if d < bestDistance then
                best, bestDistance = { node = node, x = jx, y = jy, z = jz }, d
            end
        end
    end
    return best
end

---------------------------------------------------------------------------------------------------
-- Aiming
---------------------------------------------------------------------------------------------------

function RseStrap:onAimRaycast(hitObjectId, x, y, z)
    if hitObjectId == nil or hitObjectId == 0 then
        return true
    end
    local entry = RseCarcasses:findByNode(hitObjectId)
    if entry ~= nil then
        self.aimHit = { kind = "carcass", entry = entry, node = hitObjectId, x = x, y = y, z = z }
        return false
    end
    -- a loose log, such as a downed pole; a standing tree only stops the look
    if getHasClassId(hitObjectId, ClassIds.MESH_SPLIT_SHAPE) and getSplitType(hitObjectId) ~= 0 then
        if getRigidBodyType(hitObjectId) == RigidBodyType.DYNAMIC then
            self.aimHit = { kind = "log", node = hitObjectId, x = x, y = y, z = z }
        end
        return false
    end
    local node, depth = hitObjectId, 0
    while nodeExists(node) and depth < 40 do
        local object = g_currentMission:getNodeObject(node)
        if object ~= nil then
            if object.components ~= nil and object.configFileName ~= nil then
                self.aimHit = { kind = "vehicle", vehicle = object, node = hitObjectId, x = x, y = y, z = z }
            end
            return false
        end
        node = getParent(node)
        depth = depth + 1
    end
    return false
end

-- what the player looks at within reach: a carcass, a vehicle, or nothing
function RseStrap:aim()
    self.aimHit = nil
    local camera = g_cameraManager ~= nil and g_cameraManager:getActiveCamera() or nil
    if camera == nil then
        return nil
    end
    local cx, cy, cz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    raycastClosest(cx, cy, cz, dx, dy, dz, RseConfig.STRAP_REACH, "onAimRaycast", self,
        CollisionFlag.VEHICLE + CollisionFlag.DYNAMIC_OBJECT + CollisionFlag.TREE)
    return self.aimHit
end

function RseStrap:isStrapped(entry)
    for _, strap in ipairs(self.straps) do
        if strap.entry == entry then
            return true
        end
    end
    return false
end

local function strapOnBody(self, node)
    for _, strap in ipairs(self.straps) do
        if strap.body == node then
            return strap
        end
    end
    return nil
end

local function strapOnVehicle(self, vehicle)
    for _, strap in ipairs(self.straps) do
        if strap.vehicle == vehicle or strap.wreckVehicle == vehicle then
            return strap
        end
    end
    return nil
end

-- what pressing the key would do now: "hook", "attach", "drop", "remove" or nil
function RseStrap:pendingAction(hit)
    if self.holding ~= nil then
        local canAttach = hit ~= nil and hit.kind == "vehicle" and hit.vehicle ~= self.holding.wreckVehicle
        return canAttach and "attach" or "drop"
    end
    if hit == nil then
        return nil
    end
    if hit.kind == "carcass" then
        return self:isStrapped(hit.entry) and "remove" or "hook"
    end
    if hit.kind == "log" then
        return strapOnBody(self, hit.node) ~= nil and "remove" or "hook"
    end
    if hit.kind == "vehicle" and strapOnVehicle(self, hit.vehicle) ~= nil then
        return "remove"
    end
    -- a wreck that has been prepared can take a strap where you choose (F26)
    local wreck = hit.kind == "vehicle" and RseWrecks.byVehicle[hit.vehicle] or nil
    if wreck ~= nil and wreck.state ~= "locked" then
        return "hook"
    end
    return nil
end

---------------------------------------------------------------------------------------------------
-- Hooking, attaching, removing
---------------------------------------------------------------------------------------------------

local function dropHolding(self)
    if self.holding ~= nil and nodeExists(self.holding.hookNode) then
        delete(self.holding.hookNode)
    end
    self.holding = nil
end

-- what the strap is hooked on, for the messages
local function labelOf(holding)
    if holding.wreckVehicle ~= nil then
        return holding.wreckVehicle:getFullName()
    end
    if holding.log then
        return RseText.get("rse_strap_log")
    end
    return RseText.animal(holding.entry.kind)
end

local function hook(self, hit)
    local body
    local x, y, z = hit.x, hit.y, hit.z
    local seated, offCentre = false, false
    if hit.kind == "carcass" then
        body = RseCarcasses:bodyNode(hit.entry)
    elseif hit.kind == "log" then
        body = hit.node
    else
        body = componentOf(hit.vehicle, hit.node)
        -- on its wheels: it hooks where you aim, so that a pull at an angle can swing it round; it moves to the end of the wreck once you really tow
        local wreck = RseWrecks.byVehicle[hit.vehicle]
        if wreck ~= nil and wreck.state == "ready" then
            x, y, z, offCentre = RseWrecks:hookPoint(wreck, x, y, z)
            body = hit.vehicle.components[1].node
            seated = true
        end
    end
    if body == nil then
        return
    end
    local hookNode = createTransformGroup("rseStrapHook")
    link(body, hookNode)
    setTranslation(hookNode, worldToLocal(body, x, y, z))
    self.holding = { entry = hit.entry, wreckVehicle = hit.kind == "vehicle" and hit.vehicle or nil, body = body, hookNode = hookNode,
        seated = seated, offCentre = offCentre, log = hit.kind == "log" }
    RseText.notify(RseText.get("rse_strap_hooked", labelOf(self.holding)))
end

-- Joins hookNode (on `body`: a carcass body or a wreck's component) to a point on a vehicle component (local px, py, pz) with a strap
-- of `length`. target: { entry } or { wreckVehicle }. Returns the strap, or nil.
local function connect(self, target, body, hookNode, vehicle, component, px, py, pz, length)
    if not nodeExists(body) or not nodeExists(hookNode) or not nodeExists(component) then
        return nil
    end
    local vehiclePoint = createTransformGroup("rseStrapVehiclePoint")
    link(component, vehiclePoint)
    setTranslation(vehiclePoint, px, py, pz)
    local jointFrame = createTransformGroup("rseStrapJointFrame")
    link(vehiclePoint, jointFrame)
    -- never shorter than it really is, so that attaching one moves nothing; a saved strap may have lain across the corner of the old box
    local sx, sy, sz = getWorldTranslation(vehiclePoint)
    local ex, ey, ez = getWorldTranslation(hookNode)
    length = math.max(length, distance3D(sx, sy, sz, ex, ey, ez) + RseConfig.STRAP_HOOK_SLACK)
    local constructor = JointConstructor.new()
    constructor:setActors(component, body)
    constructor:setJointTransforms(vehiclePoint, hookNode)
    for axis = 0, 2 do
        constructor:setRotationLimit(axis, -math.pi, math.pi)
        constructor:setTranslationLimit(axis, true, -length, length)
    end
    constructor:setEnableCollision(true)
    local ok, jointIndex = RseLog.try("strap joint", constructor.finalize, constructor)
    if not ok or jointIndex == nil then
        delete(vehiclePoint)
        return nil
    end
    local okRope, rope = RseLog.try("strap rope", createRope, vehiclePoint, RoadsideEmergencies.MOD_DIR)
    local strap = { entry = target.entry, wreckVehicle = target.wreckVehicle, log = target.log == true, body = body, vehicle = vehicle, component = component,
        jointIndex = jointIndex,
        vehiclePoint = vehiclePoint, jointFrame = jointFrame, boxed = false, offCentre = target.offCentre == true,
        hookNode = hookNode, length = length, rope = okRope and rope or nil, ropeAimed = false }
    strap.startX, strap.startY, strap.startZ = getWorldTranslation(vehiclePoint)
    strap.startLength, strap.lateral, strap.seated = length, length, target.seated == true
    table.insert(self.straps, strap)
    return strap
end

local function attach(self, hit)
    local holding = self.holding
    if not nodeExists(holding.body) or not nodeExists(holding.hookNode) then
        dropHolding(self)
        return
    end
    local vehicle = hit.vehicle
    local component = componentOf(vehicle, hit.node)
    local joint = snapToJoint(vehicle, hit.x, hit.y, hit.z)
    local ax, ay, az = hit.x, hit.y, hit.z
    if joint ~= nil then
        ax, ay, az = joint.x, joint.y, joint.z
    end
    local hx, hy, hz = getWorldTranslation(holding.hookNode)
    local gap = distance3D(ax, ay, az, hx, hy, hz)
    if gap > RseConfig.STRAP_MAX_LENGTH then
        RseText.notify(RseText.get("rse_strap_tooFar", gap, RseConfig.STRAP_MAX_LENGTH), true)
        return
    end
    local length = math.max(RseConfig.STRAP_MIN_LENGTH, math.min(gap, RseConfig.STRAP_MAX_LENGTH))
    local px, py, pz = worldToLocal(component, ax, ay, az)
    if connect(self, holding, holding.body, holding.hookNode, vehicle, component, px, py, pz, length) == nil then
        return
    end
    self.holding = nil
    RseLog.debug("strap: %s -> '%s' (%s), %.1f m", labelOf(holding), tostring(vehicle:getFullName()),
        joint ~= nil and "attacher joint" or "aimed spot", gap)
    RseText.notify(RseText.get("rse_strap_attached", labelOf(holding), vehicle:getFullName()))
end

-- what the savegame keeps of each strap; indexOf: carcass entry -> its number in the saved carcass list
function RseStrap:saveData(indexOf)
    local list = {}
    for _, strap in ipairs(self.straps) do
        local index = indexOf[strap.entry]
        local uniqueId = strap.vehicle.getUniqueId ~= nil and strap.vehicle:getUniqueId() or nil
        local componentIndex = nil
        for i, component in ipairs(strap.vehicle.components or {}) do
            if component.node == strap.component then
                componentIndex = i
            end
        end
        if index ~= nil and uniqueId ~= nil and componentIndex ~= nil and nodeExists(strap.hookNode) and nodeExists(strap.vehiclePoint) then
            local hx, hy, hz = getTranslation(strap.hookNode)
            local vx, vy, vz = getTranslation(strap.vehiclePoint)
            table.insert(list, { carcass = index, vehicle = uniqueId, component = componentIndex, hx = hx, hy = hy, hz = hz,
                vx = vx, vy = vy, vz = vz, length = strap.length })
        end
    end
    return list
end

-- puts saved straps back; entries: the carcass entry for each saved carcass number. Returns how many.
function RseStrap:restore(saved, entries)
    local restored = 0
    local vehicleSystem = g_currentMission.vehicleSystem
    for _, data in ipairs(saved) do
        local entry = entries[data.carcass]
        local vehicle = vehicleSystem ~= nil and vehicleSystem:getVehicleByUniqueId(data.vehicle) or nil
        local component = vehicle ~= nil and vehicle.components ~= nil and vehicle.components[data.component] or nil
        local body = entry ~= nil and RseCarcasses:bodyNode(entry) or nil
        if body ~= nil and component ~= nil then
            local hookNode = createTransformGroup("rseStrapHook")
            link(body, hookNode)
            setTranslation(hookNode, data.hx, data.hy, data.hz)
            if connect(self, { entry = entry }, body, hookNode, vehicle, component.node, data.vx, data.vy, data.vz, data.length) ~= nil then
                restored = restored + 1
            else
                delete(hookNode)
            end
        else
            RseLog.info("a saved strap could not be put back (carcass %s, vehicle %s)", tostring(body ~= nil),
                tostring(vehicle ~= nil))
        end
    end
    return restored
end

function RseStrap:remove(strap)
    if strap.rope ~= nil then
        RseLog.try("strap rope delete", strap.rope.delete, strap.rope)
    end
    RseLog.try("strap joint remove", removeJoint, strap.jointIndex)
    if strap.wreckVehicle ~= nil then
        RseLog.try("park the wreck", RseWrecks.endTow, RseWrecks, strap.wreckVehicle)
    end
    if nodeExists(strap.vehiclePoint) then
        delete(strap.vehiclePoint)
    end
    if nodeExists(strap.hookNode) then
        delete(strap.hookNode)
    end
    for i, candidate in ipairs(self.straps) do
        if candidate == strap then
            table.remove(self.straps, i)
            break
        end
    end
end

-- every strap on this wreck or from it, and the one in your hand if it belongs to it
function RseStrap:releaseForVehicle(vehicle)
    for i = #self.straps, 1, -1 do
        if self.straps[i].wreckVehicle == vehicle then
            self:remove(self.straps[i])
        end
    end
    if self.holding ~= nil and self.holding.wreckVehicle == vehicle then
        dropHolding(self)
    end
end

-- every strap on this log, and the one in your hand if it belongs to it: before the log is cut or removed
function RseStrap:releaseForNode(node)
    for i = #self.straps, 1, -1 do
        if self.straps[i].body == node then
            self:remove(self.straps[i])
        end
    end
    if self.holding ~= nil and self.holding.body == node then
        dropHolding(self)
    end
end

-- every strap on this carcass, and the one in your hand if it belongs to it
function RseStrap:releaseFor(entry)
    for i = #self.straps, 1, -1 do
        if self.straps[i].entry == entry then
            self:remove(self.straps[i])
        end
    end
    if self.holding ~= nil and self.holding.entry == entry then
        dropHolding(self)
    end
end

function RseStrap:onAction()
    if not onFoot() then
        return
    end
    local hit = self:aim()
    local action = self:pendingAction(hit)
    if action == "hook" then
        hook(self, hit)
    elseif action == "attach" then
        attach(self, hit)
    elseif action == "drop" then
        dropHolding(self)
    elseif action == "remove" then
        if hit.kind == "carcass" then
            self:releaseFor(hit.entry)
        elseif hit.kind == "log" then
            self:releaseForNode(hit.node)
        else
            self:remove(strapOnVehicle(self, hit.vehicle))
        end
        RseText.notify(RseText.get("rse_strap_removed"))
    end
end

---------------------------------------------------------------------------------------------------
-- Key, frame update, clean-up
---------------------------------------------------------------------------------------------------

-- added to the local player's own key registration (PlayerInputComponent.registerActionEvents, see RoadsideEmergencies.lua)
function RseStrap:registerActionEvents()
    if InputAction.RSE_STRAP == nil then
        return
    end
    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    if self.actionEventId ~= nil then
        g_inputBinding:removeActionEvent(self.actionEventId)
    end
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.RSE_STRAP, self, self.onAction, false, true, false, false)
    self.actionEventId = eventId
    self.shownText, self.shownActive = nil, nil
    for _, reel in ipairs({ { key = "reelInEventId", action = InputAction.RSE_STRAP_IN, callback = self.onReelIn, textKey = "rse_strap_reelIn" },
        { key = "reelOutEventId", action = InputAction.RSE_STRAP_OUT, callback = self.onReelOut, textKey = "rse_strap_reelOut" } }) do
        if self[reel.key] ~= nil then
            g_inputBinding:removeActionEvent(self[reel.key])
            self[reel.key] = nil
        end
        if reel.action ~= nil then
            local _, reelId = g_inputBinding:registerActionEvent(reel.action, self, reel.callback, false, true, true, false)
            self[reel.key] = reelId
            if reelId ~= nil then
                g_inputBinding:setActionEventText(reelId, RseText.get(reel.textKey))
                g_inputBinding:setActionEventTextPriority(reelId, GS_PRIO_VERY_HIGH)
                g_inputBinding:setActionEventTextVisibility(reelId, false)
            end
        end
    end
    self.reelShown = false
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
    g_inputBinding:endActionEventsModification()
end

local ACTION_TEXTS = { hook = "rse_strap_hook", attach = "rse_strap_attach", drop = "rse_strap_drop", remove = "rse_strap_remove" }

local function showAction(self, action)
    if self.actionEventId == nil then
        return
    end
    local active = action ~= nil
    local text = active and RseText.get(ACTION_TEXTS[action]) or nil
    if active ~= self.shownActive then
        g_inputBinding:setActionEventActive(self.actionEventId, active)
        g_inputBinding:setActionEventTextVisibility(self.actionEventId, active)
        self.shownActive = active
    end
    if text ~= nil and text ~= self.shownText then
        g_inputBinding:setActionEventText(self.actionEventId, text)
        self.shownText = text
    end
end

-- a wreck on its side is held until the vehicle on its strap pulls away with the strap tight
local function checkPull(strap)
    local wreck = strap.wreckVehicle ~= nil and RseWrecks.byVehicle[strap.wreckVehicle] or nil
    if wreck == nil or wreck.state ~= "tipped" or wreck.pin == nil or not nodeExists(strap.vehiclePoint) or not nodeExists(strap.hookNode) then
        return
    end
    local vx, vy, vz = getWorldTranslation(strap.vehiclePoint)
    local hx, hy, hz = getWorldTranslation(strap.hookNode)
    local pulled = distance3D(vx, vy, vz, strap.startX, strap.startY, strap.startZ) > RseConfig.WRECK_PULL_MOVED
        and distance3D(vx, vy, vz, hx, hy, hz) >= strap.length - RseConfig.WRECK_PULL_SLACK
    if pulled or strap.length < strap.startLength - RseConfig.WRECK_PULL_MOVED then -- driven away, or reeled in
        RseWrecks:release(wreck)
    end
end

-- the strap's limits, in the vehicle's own axes: side to side, up and down, along. Changing them live is how the game's own joints adjust.
local function applyLimits(strap)
    setJointTranslationLimit(strap.jointIndex, 0, true, -strap.lateral, strap.lateral)
    setJointTranslationLimit(strap.jointIndex, 1, true, -strap.length, strap.length)
    setJointTranslationLimit(strap.jointIndex, 2, true, -strap.length, strap.length)
end

-- turns the joint along the line, whenever the line has moved off it
local function aimJoint(strap)
    local hx, hy, hz = getWorldTranslation(strap.hookNode)
    local offX, offY = worldToLocal(strap.jointFrame, hx, hy, hz)
    if math.abs(offX) < RseConfig.STRAP_AIM_TOLERANCE and math.abs(offY) < RseConfig.STRAP_AIM_TOLERANCE then
        return
    end
    local dx, dy, dz = worldToLocal(strap.vehiclePoint, hx, hy, hz)
    local gap = math.sqrt(dx * dx + dy * dy + dz * dz)
    if gap < RseConfig.STRAP_AIM_TOLERANCE then
        return
    end
    dx, dy, dz = dx / gap, dy / gap, dz / gap
    if math.abs(dy) > 0.95 then
        setDirection(strap.jointFrame, dx, dy, dz, 1, 0, 0)
    else
        setDirection(strap.jointFrame, dx, dy, dz, 0, 1, 0)
    end
    setJointFrame(strap.jointIndex, 0, strap.jointFrame)
end

local function keepAlongLine(strap)
    if strap.boxed or not nodeExists(strap.jointFrame) or not nodeExists(strap.hookNode) then
        return
    end
    if not RseLog.try("aim the strap", aimJoint, strap) then
        strap.boxed, strap.aimFailed = true, true -- once in the log, and it goes on working as a box
    end
end

-- the joint along the vehicle's own axes while really towing, along the line otherwise
local function setBoxed(strap, boxed, gap)
    strap.boxed = boxed
    if boxed then
        setRotation(strap.jointFrame, 0, 0, 0)
        setJointFrame(strap.jointIndex, 0, strap.jointFrame)
    else
        -- the corner of a box is further out than the line was long
        strap.length = math.max(strap.length, gap)
        strap.lateral = strap.length
        applyLimits(strap)
    end
end

-- A strap hooked high on the side to right a wreck moves to the end of the wreck once it stands on its wheels,
-- and one hooked off the middle does when you really tow
local function seatForTow(self, strap, wreck)
    local target, vehicle, component, manual, tow = strap.wreckVehicle, strap.vehicle, strap.component, strap.manual, strap.tow
    local px, py, pz = getTranslation(strap.vehiclePoint)
    local vx, vy, vz = getWorldTranslation(strap.vehiclePoint)
    self:remove(strap)
    local x, y, z = RseWrecks:towPoint(wreck, vx, vy, vz)
    local body = target.components[1].node
    local hookNode = createTransformGroup("rseStrapHook")
    link(body, hookNode)
    setTranslation(hookNode, worldToLocal(body, x, y, z))
    local length = math.max(RseConfig.STRAP_MIN_LENGTH, distance3D(vx, vy, vz, x, y, z))
    local seated = connect(self, { wreckVehicle = target, seated = true }, body, hookNode, vehicle, component, px, py, pz, length)
    if seated == nil then
        delete(hookNode)
    else
        seated.manual, seated.tow = manual, tow
    end
end

-- A wreck on its wheels on a strap. Hooking up moves nothing: you can reel it in and out, onto a rollback or into another position, for as long as you like.
-- Only once you drive off with the strap tight does the strap shorten by itself (unless you reeled it by hand) and keep the wreck straight behind.
-- A strap can only pull, so when you stop, the wreck would roll on into you: it brakes as soon as the strap goes slack, except while you are reeling.
local function updateTow(strap, wreck, dt)
    local vx, vy, vz = getWorldTranslation(strap.vehiclePoint)
    local hx, hy, hz = getWorldTranslation(strap.hookNode)
    local gap = distance3D(vx, vy, vz, hx, hy, hz)
    if strap.lastGap ~= nil and dt > 0 then
        strap.closing = (strap.closing or 0) * 0.8 + (strap.lastGap - gap) / (dt / 1000) * 0.2
    end
    strap.lastGap = gap
    local slack = strap.length - gap
    if strap.boxed then
        -- the limits work along each of the vehicle's axes: the slack is what the nearest of them has left
        local sideways, _, along = worldToLocal(strap.vehiclePoint, hx, hy, hz)
        slack = math.min(strap.length - math.abs(along), strap.lateral - math.abs(sideways))
    end
    local reeling = (strap.reelMs or 0) > 0
    if reeling then
        strap.reelMs = strap.reelMs - dt
    end
    local brake = reeling and 0 or RseWreckRules.towBrake(slack, strap.closing or 0, RseConfig)
    strap.tow = strap.tow or {}
    local speed = strap.vehicle.getLastSpeed ~= nil and strap.vehicle:getLastSpeed() or 0
    local towing = RseWreckRules.isTowing(strap.tow, dt, { speed = speed, slack = slack, reeling = reeling }, RseConfig)
    RseLog.try("tow the wreck", RseWrecks.assistTow, RseWrecks, wreck, vx, vy, vz, brake, towing, reeling)
    if towing ~= strap.boxed and not strap.aimFailed then
        RseLog.try("turn the strap's joint", setBoxed, strap, towing, gap)
    end
    local changed = false
    if towing then
        local step = RseConfig.TOW_REEL_SPEED * dt / 1000
        if not strap.manual and strap.length > RseConfig.TOW_LENGTH then
            strap.length = math.max(RseConfig.TOW_LENGTH, strap.length - step)
            changed = true
        end
        if strap.lateral > RseConfig.TOW_LATERAL then
            strap.lateral = math.max(RseConfig.TOW_LATERAL, strap.lateral - step)
            changed = true
        end
    elseif strap.lateral ~= strap.length then
        -- not towing: the wreck may lie at any angle to the vehicle
        strap.lateral = strap.length
        changed = true
    end
    if changed then
        RseLog.try("shorten the strap", applyLimits, strap)
    end
end

-- the strap nearest you on foot, in reach to be reeled, or nil
local function strapNear(self)
    if g_localPlayer == nil then
        return nil
    end
    local x, y, z = g_localPlayer:getPosition()
    local best, bestDistance = nil, RseConfig.STRAP_REEL_NEAR
    for _, strap in ipairs(self.straps) do
        if nodeExists(strap.hookNode) and nodeExists(strap.vehiclePoint) then
            local hx, hy, hz = getWorldTranslation(strap.hookNode)
            local vx, vy, vz = getWorldTranslation(strap.vehiclePoint)
            local distance = math.min(distance3D(x, y, z, hx, hy, hz), distance3D(x, y, z, vx, vy, vz))
            if distance < bestDistance then
                best, bestDistance = strap, distance
            end
        end
    end
    return best
end

-- the two reel keys show only near a strap, and work while held
local function updateReel(self, dt)
    local near = onFoot() and strapNear(self) or nil
    local active = near ~= nil
    if active ~= self.reelShown then
        self.reelShown = active
        for _, eventId in ipairs({ self.reelInEventId or false, self.reelOutEventId or false }) do
            if eventId then
                g_inputBinding:setActionEventActive(eventId, active)
                g_inputBinding:setActionEventTextVisibility(eventId, active)
            end
        end
    end
    if near ~= nil and (self.reelIn or self.reelOut) then
        local step = RseConfig.STRAP_REEL_SPEED * dt / 1000
        near.manual = true
        near.reelMs = RseConfig.TOW_REEL_HOLD_MS
        if self.reelIn then
            -- any slack goes first, at once, so that reeling in always shows
            local vx, vy, vz = getWorldTranslation(near.vehiclePoint)
            local hx, hy, hz = getWorldTranslation(near.hookNode)
            near.length = math.min(near.length, distance3D(vx, vy, vz, hx, hy, hz))
        end
        near.length = math.max(RseConfig.STRAP_MIN_LENGTH, math.min(RseConfig.STRAP_MAX_LENGTH, near.length + (self.reelOut and step or -step)))
        near.lateral = near.length
        RseLog.try("reel the strap", applyLimits, near)
    end
    self.reelIn, self.reelOut = false, false
end

-- called every frame while the event is active; inputValue tells whether the key is down
function RseStrap:onReelIn(_, inputValue)
    self.reelIn = (inputValue or 0) > 0
end

function RseStrap:onReelOut(_, inputValue)
    self.reelOut = (inputValue or 0) > 0
end

function RseStrap:update(dt)
    local toSeat = nil
    for i = #self.straps, 1, -1 do
        local strap = self.straps[i]
        checkPull(strap)
        local wreck = strap.wreckVehicle ~= nil and RseWrecks.byVehicle[strap.wreckVehicle] or nil
        local towable = wreck ~= nil and wreck.state == "ready" and nodeExists(strap.vehiclePoint) and nodeExists(strap.hookNode)
        if towable and not strap.vehicle.isDeleted and not strap.wreckVehicle.isDeleted then
            if strap.seated then
                updateTow(strap, wreck, dt)
            end
            if not strap.seated or (strap.offCentre and strap.boxed and not strap.aimFailed) then
                toSeat = { strap = strap, wreck = wreck }
            end
        end
        keepAlongLine(strap)
        local gone = strap.wreckVehicle ~= nil and strap.wreckVehicle.isDeleted or (strap.entry ~= nil and RseCarcasses:bodyNode(strap.entry) == nil)
            or (strap.log and not nodeExists(strap.hookNode))
        if strap.vehicle.isDeleted or gone then
            self:remove(strap)
        elseif strap.rope ~= nil and not strap.ropeAimed and strap.rope.referenceFrame ~= nil then
            RseLog.try("strap rope aim", strap.rope.setTargetNode, strap.rope, strap.hookNode, true)
            strap.ropeAimed = true
        end
    end
    if toSeat ~= nil then
        RseLog.try("put the strap on the end of the wreck", seatForTow, self, toSeat.strap, toSeat.wreck)
    end
    updateReel(self, dt)
    if self.holding ~= nil and not nodeExists(self.holding.body) then
        dropHolding(self)
    end
    if onFoot() then
        showAction(self, self:pendingAction(self:aim()))
    else
        showAction(self, nil)
    end
end

function RseStrap:clear()
    for i = #self.straps, 1, -1 do
        self:remove(self.straps[i])
    end
    dropHolding(self)
end

-- while the map unloads: the game deletes vehicles with their joints, strap points and ropes; only forget ours
function RseStrap:forget()
    self.straps = {}
    self.holding = nil
    self.actionEventId = nil
    self.shownText, self.shownActive = nil, nil
end
