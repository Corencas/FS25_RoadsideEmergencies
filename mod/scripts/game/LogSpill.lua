-- Roadside Emergencies: the logs of a logging crash (core/LogRules.lua). The trailer is a wreck nobody recovers (`scenery`): the logs are the job (Z).
--   They are real logs, like the power line's pole: the game's chainsaw cuts them, whatever handles logs handles them, and every piece is followed through the
--     game's TREE_SHAPE_CUT message. PowerLine.lua has the parts both use, and the rule that lets a chainsaw cut them on a public road.
--   A piece is in once it is clear of the road: on a vehicle, or lying still well off to the side (Z: load them on a crane truck, and it counts). One brought
--     to a recovery point goes at once, and one sold or chipped counts as well.
--   When the job is over the trailer and the logs stay a while, because vanishing on completion is unrealistic (Z), and go once you have left (Cleanup.lua).
--     All the logs go with the job (Z), also those you have loaded. A job handed over early is different: the logs on your vehicle stay yours.

--   A tree on a car: one more log, leaning on the roof of the job's car with its foot on the ground (Z: no tree of its own, only logs). The car stays pinned,
--     and the driver can't get out, until nothing lies on the car (carBlocked). The rest works like any log.

RseLogSpill = {}

local function parts()
    return RsePowerLine.logs
end

local function newSpill(def, total, dirX, dirZ)
    return { def = def, total = total, dirX = dirX, dirZ = dirZ, pieces = {}, lost = {}, trees = {}, queue = {},
        gone = 0, inCount = 0, bestIn = 0 }
end

-- the logs still to be asked for, one at a time: the game cuts each out of a whole tree over two frames
local function queueLogs(spill, spots)
    local range = RseConfig.LOG_LENGTH
    for i, spot in ipairs(spots) do
        table.insert(spill.queue, { x = spot.x, z = spot.z, dirX = math.sin(spot.yaw), dirZ = math.cos(spot.yaw),
            length = range[1] + math.random() * (range[2] - range[1]), lift = RseConfig.LINE_POLE_DROP + (i - 1) * RseConfig.LOG_STACK })
    end
end

local function treeKind(spill)
    if spill.desc == nil then
        for _, name in ipairs(RseConfig.LINE_POLE_TREES) do
            spill.desc = spill.desc or g_treePlantManager:getTreeTypeDescFromName(name)
        end
    end
    return spill.desc
end

-- lays a fresh trunk with its foot on the ground and its body on the car: a log's own Y axis runs along it, and the game leaves its reference point off to
-- one side
local function leanTrunk(node, lean)
    local cosLean, sinLean = math.cos(lean.angle), math.sin(lean.angle)
    local axisX, axisY, axisZ = lean.dirX * cosLean, sinLean, lean.dirZ * cosLean
    local _, middleY = getCenterOfMass(node)
    local sizeX, sizeY, sizeZ = getSplitShapeStats(node)
    local length = sizeX ~= nil and math.max(sizeX, sizeY, sizeZ) or RseConfig.TREE_TRUNK_LENGTH
    local footY = middleY - length / 2
    removeFromPhysics(node)
    setDirection(node, lean.dirZ, 0, -lean.dirX, axisX, axisY, axisZ)
    setWorldTranslation(node, lean.footX - axisX * footY, lean.footY - axisY * footY, lean.footZ - axisZ * footY)
    addToPhysics(node)
end

local function requestNext(spill)
    local spot = table.remove(spill.queue, 1)
    if spot == nil then
        return
    end
    spill.pendingSpot = spot
    local desc = treeKind(spill)
    if desc == nil then
        spill.queue = {}
        return
    end
    local manager = g_treePlantManager
    manager:loadTreeTrunk(desc, spot.x, parts().groundAt(spot.x, spot.z) + spot.lift, spot.z, spot.dirX, 0, spot.dirZ, spot.length, #desc.stages, 1, true,
        false)
    spill.pending = manager.loadTreeTrunkDatas[#manager.loadTreeTrunkDatas]
    table.insert(spill.trees, { x = spot.x, z = spot.z })
    RseSavedLogs:remember(spot.x, spot.z)
end

local function collect(spill)
    local pending = spill.pending
    if pending ~= nil then
        if pending.framesLeft > 0 then
            return
        end
        spill.pending = nil
        for _, part in pairs(pending.parts or {}) do
            if not part.isBelow and parts().nodeExists(part.shape) then
                parts().addPiece(spill, part.shape)
                if spill.pendingSpot ~= nil and spill.pendingSpot.lean ~= nil then
                    RseLog.try("lean the log on the car", leanTrunk, part.shape, spill.pendingSpot.lean)
                end
            end
        end
    end
    requestNext(spill)
end

local probe = {}

function probe:onHit(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.hit = true
        return false
    end
    return true
end

local function blocked(x1, y1, z1, x2, y2, z2, mask)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-3 then
        return false
    end
    probe.hit = false
    raycastClosest(x1, y1, z1, dx / length, dy / length, dz / length, length, "onHit", probe, mask)
    return probe.hit
end

-- Can a tree stand on this side of a car on a road along (dirX, dirZ)? y: the road's own height there (on a bridge, well above the ground under it). side: 1
-- or -1. Its foot TREE_BASE_AWAY to the side has to be on dry ground near the road's height (not down a bank or under a bridge), and nothing solid (a guard
-- rail, a fence, a wall) between it and the roof.
function RseLogSpill:treeFits(x, y, z, dirX, dirZ, side, roofHeight)
    local away = RseConfig.TREE_BASE_AWAY
    local footX, footZ = x + dirZ * side * away, z - dirX * side * away
    local footY = getTerrainHeightAtWorldPos(g_terrainNode, footX, 0, footZ)
    if math.abs(footY - y) > RseConfig.TREE_FOOT_STEP then
        return false, "step"
    end
    if blocked(footX, footY + RseConfig.WATER_RAY_START, footZ, footX, footY - 0.2, footZ, CollisionFlag.WATER or 0) then
        return false, "water"
    end
    local solid = (CollisionFlag.STATIC_OBJECT or 0) + (CollisionFlag.BUILDING or 0)
    if blocked(footX, footY + 1, footZ, x, y + (roofHeight or 1.4), z, solid) or blocked(footX, footY + 0.5, footZ, x, y + 0.8, z, solid) then
        return false, "in the way"
    end
    return true
end

-- A road spot where a tree can come down on a car, for the next call (CallPlan.lua), or nil: either side will do.
function RseLogSpill:pickTreeSpot()
    local reasons = {}
    for _ = 1, RseConfig.LINE_SPOT_TRIES do
        local spot = RseScenes:nextSpot(true)
        if spot == nil then
            break
        end
        local length = math.max(math.sqrt(spot.dirX * spot.dirX + spot.dirZ * spot.dirZ), 1e-6)
        local dirX, dirZ = spot.dirX / length, spot.dirZ / length
        local y = spot.y or getTerrainHeightAtWorldPos(g_terrainNode, spot.x, 0, spot.z) -- the lane's own height, from the road's spline
        local fits, why = self:treeFits(spot.x, y, spot.z, dirX, dirZ, 1)
        if not fits then
            fits, why = self:treeFits(spot.x, y, spot.z, dirX, dirZ, -1)
        end
        if fits then
            return spot
        end
        reasons[why] = (reasons[why] or 0) + 1
    end
    local said = {}
    for why, count in pairs(reasons) do
        table.insert(said, string.format("%s %d", why, count))
    end
    RseLog.info("a tree on a car: no road spot where a tree reaches the car (%s)", table.concat(said, ", "))
    return nil
end

-- The car has settled and is pinned: the log comes down on it, from the side away from the road, or the other side if a tree can't stand there.
local function dropOnCar(spill, scene)
    local vehicle = scene.wreck.vehicle
    local cx, cy, cz = getWorldTranslation(vehicle.rootNode)
    local height = vehicle.size ~= nil and vehicle.size.height or 1.6
    local sideX, sideZ = spill.dirZ, -spill.dirX
    local away = RseConfig.TREE_BASE_AWAY
    local fromOne = RseRoadClearRule.distanceToRoad(cx + sideX * away, cz + sideZ * away, scene.segments) or 0
    local fromOther = RseRoadClearRule.distanceToRoad(cx - sideX * away, cz - sideZ * away, scene.segments) or 0
    local side = fromOne >= fromOther and 1 or -1
    local roadY = scene.y or (cy - 0.3) -- the call's spot is on the lane, at the road's own height
    local ok, fits = RseLog.try("see where the tree can stand", RseLogSpill.treeFits, RseLogSpill, cx, roadY, cz, spill.dirX, spill.dirZ, side, height)
    if ok and not fits then
        side = -side
    end
    local jitter = (math.random() - 0.5) * RseConfig.TREE_TRUNK_JITTER
    local towardCarX, towardCarZ = -sideX * side, -sideZ * side
    local dirX = towardCarX * math.cos(jitter) + towardCarZ * math.sin(jitter)
    local dirZ = towardCarZ * math.cos(jitter) - towardCarX * math.sin(jitter)
    local footX, footZ = cx - dirX * away, cz - dirZ * away
    local footY = parts().groundAt(footX, footZ) + 0.25
    local angle = math.max(0.05, math.min(RseConfig.TREE_LEAN_MAX, math.atan2(cy + height + RseConfig.TREE_ROOF_CLEAR - footY, away)))
    table.insert(spill.queue, 1, { x = footX, z = footZ, dirX = dirX, dirZ = dirZ, length = RseConfig.TREE_TRUNK_LENGTH, lift = 0.5,
        lean = { footX = footX, footY = footY, footZ = footZ, dirX = dirX, dirZ = dirZ, angle = angle } })
    RseLog.info("a log on a car: leaning %.0f degrees, its foot at %.1f, %.1f", math.deg(angle), footX, footZ)
end

-- Follows each piece. A piece gone with no cut message was sold or chipped, unless a cut went unreported, so findLostPieces looks around where it lay.
local function checkPieces(spill, scene, dt)
    local L = parts()
    local inCount = 0
    local i = 1
    while i <= #spill.pieces do
        local piece = spill.pieces[i]
        if not L.nodeExists(piece.node) then
            L.removePin(piece)
            if not piece.cut then
                table.insert(spill.lost, { x = piece.lastX, y = piece.lastY, z = piece.lastZ })
                spill.lostMs = RseConfig.LINE_LOST_MS
                spill.gone = spill.gone + 1
            end
            table.remove(spill.pieces, i)
        else
            local x, y, z = getWorldTranslation(piece.node)
            local moved = math.abs(x - piece.lastX) + math.abs(z - piece.lastZ)
            piece.lastX, piece.lastY, piece.lastZ = x, y, z
            piece.restMs = moved <= 0.02 and piece.restMs + dt or 0
            local held = getUserAttribute(piece.node, "isTensionBeltMounted") == true or getRigidBodyType(piece.node) ~= RigidBodyType.DYNAMIC
            if RsePoints:at(x, z, "recovery") ~= nil and not held and piece.restMs >= RseConfig.DELIVER_REST_MS then
                L.removePin(piece)
                L.deleteLog(piece.node)
                table.remove(spill.pieces, i)
                spill.gone = spill.gone + 1
            else
                local midX, midY, midZ = L.logMiddle(piece.node)
                local onVehicle = held or RseScenes:isOnVehicle(midX, midY, midZ, scene.wreck.vehicle)
                piece.status = RseLogRules.status({ x = midX, z = midZ, loaded = onVehicle, atRest = piece.restMs >= RseConfig.CLEAR_REST_MS,
                    ends = L.logEnds(piece.node) }, scene, RseConfig)
                -- nobody should have to chase a sliver
                piece.isIn = RseLogRules.counts(piece.status, piece.isIn, piece.restMs, RseConfig) or getMass(piece.node) < RseConfig.LOG_TINY_MASS
                inCount = inCount + (piece.isIn and 1 or 0)
                i = i + 1
            end
        end
    end
    spill.inCount = inCount
    local done = inCount + spill.gone
    local all = #spill.pieces + spill.gone
    -- not while the log for the car is still to come: that one coming down isn't a cut (Z had the message the moment the job began, from 5000 feet away)
    if spill.pending == nil and #spill.queue == 0 and spill.searchMs == nil and not spill.leaning then
        if spill.lastAll ~= nil and all > spill.lastAll then
            RseText.notify(RseText.get("rse_logs_cut", all)) -- a cut clears nothing, but it does make one more to clear
        end
        spill.lastAll = all
    end
    if done > spill.bestIn then
        spill.bestIn = done
        if done < all then
            RseText.notify(RseText.get("rse_logs_progress", done, all))
        end
    end
end

-- A saved job: the game has put the logs back itself, with new node numbers. If none can be found, new ones lie in their place: the job needs them.
local function findSaved(spill, scene, dt)
    spill.searchMs = spill.searchMs - dt
    if spill.searchMs > 0 then
        return
    end
    spill.searchTries = (spill.searchTries or 0) + 1
    local L = parts()
    local host = RsePowerLine
    host.foundLogs, host.searchLine = {}, spill
    local data = g_treePlantManager.treesData
    for _, tree in ipairs(data ~= nil and data.splitTrees or {}) do
        for _, spot in ipairs(spill.trees) do
            if tree.x ~= nil and (tree.x - spot.x) ^ 2 + (tree.z - spot.z) ^ 2 <= RseConfig.LINE_TREE_MATCH ^ 2 and L.nodeExists(tree.node) then
                L.collectShapes(host, spill, tree.node)
                break
            end
        end
    end
    local expected = #(spill.savedPieces or {})
    for _, saved in ipairs(spill.savedPieces or {}) do
        L.searchAround(host, saved.x, saved.y, saved.z, RseConfig.LINE_SEARCH_RADIUS)
    end
    L.adoptFound(host, spill)
    if (#spill.pieces >= expected and #spill.pieces > 0) or spill.searchTries >= RseConfig.LINE_SEARCH_TRIES then
        RseLog.info("logging crash: %d of %d saved piece(s) found again", #spill.pieces, expected)
        RseLog.try("put the logs back", L.putBack, spill, spill.savedPieces or {}, "logging crash")
        spill.searchMs, spill.savedPieces = nil, nil
        if #spill.pieces == 0 and spill.gone == 0 then
            RseLog.info("logging crash: the saved logs are gone, so new ones lie in their place")
            queueLogs(spill, RseSceneSpec.scatter(spill.total, scene.x, scene.z, spill.dirX, spill.dirZ, { span = RseConfig.LOG_SPREAD,
                width = RseConfig.WRECK_BALE_WIDTH, gap = RseConfig.LOG_GAP, maxRoadDistance = RseConfig.CLEAR_DISTANCE }, math.random, scene.segments))
        end
    else
        spill.searchMs = RseConfig.LINE_SEARCH_MS
    end
end

local function updatePins(spill)
    local L = parts()
    local px, pz = L.playerPosition()
    for _, piece in ipairs(spill.pieces) do
        if L.nodeExists(piece.node) and not piece.isIn then
            local x, y, z = L.logMiddle(piece.node)
            L.placePin(piece, x, y, z, px, pz)
        else
            L.removePin(piece)
        end
    end
end

-- Lays it out around a new scene. road: what RseRoads measured; spots: { { x, z, yaw }, ... }, where the logs lie. Their number is the job's size.
-- onCar: one more comes down on the job's car, once that has settled.
function RseLogSpill:spawn(scene, road, spots, onCar)
    RsePowerLine:watchLogs()
    local def = RseConfig.WRECKS[scene.wreck.kind]
    local dirX, dirZ = road.dirX or 1, road.dirZ or 0
    local length = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-6)
    dirX, dirZ = dirX / length, dirZ / length
    local spill = newSpill(def, #spots + (onCar and 1 or 0), dirX, dirZ)
    queueLogs(spill, spots)
    if onCar then
        spill.leaning, spill.leanWaitMs = true, RseConfig.TREE_PIN_WAIT_MS
    end
    scene.spill = spill
    RseLog.info("logs at %.1f, %.1f: %d, and %s on a car", scene.x, scene.z, #spots, onCar and "one" or "none")
end

-- every frame, from the steps
function RseLogSpill:update(scene, dt)
    local spill = scene.spill
    if spill == nil or spill.failed then
        return
    end
    local function step()
        if spill.leaning and scene.wreck.vehicle ~= nil then
            spill.leanWaitMs = spill.leanWaitMs - dt
            if scene.wreck.pin ~= nil or spill.leanWaitMs <= 0 then
                spill.leaning = nil
                dropOnCar(spill, scene)
            end
        end
        collect(spill)
        if spill.searchMs ~= nil then
            findSaved(spill, scene, dt)
        end
        if spill.lostMs ~= nil then
            spill.lostMs = spill.lostMs - dt
            if spill.lostMs <= 0 then
                local before = #spill.pieces
                spill.lostMs = 0
                parts().findLostPieces(RsePowerLine, spill, 0)
                spill.gone = math.max(0, spill.gone - (#spill.pieces - before)) -- found again: it wasn't gone
            end
        end
        checkPieces(spill, scene, dt)
        if #spill.pieces == 0 and spill.gone == 0 and spill.pending == nil and #spill.queue == 0 and spill.searchMs == nil and not spill.leaning then
            RseLog.problem("logging crash: no kind of tree gave a log")
            scene.wreck.failed = true
            spill.failed = true
        end
    end
    if not RseLog.try("the logs", step) then
        spill.failed = true -- once in the log; the player can still hand the job over
    end
    if not spill.pinsFailed and not RseLog.try("the logs' pins", updatePins, spill) then
        spill.pinsFailed = true
    end
end

-- every frame, from RseScenes:draw. Returns false when a pin failed to draw.
function RseLogSpill:draw(scene)
    return scene.spill == nil or parts().renderPins(scene.spill.pieces)
end

function RseLogSpill:share(scene)
    local spill = scene.spill
    if spill == nil then
        return 0
    end
    return RseLogRules.share(spill.inCount, spill.gone, #spill.pieces)
end

function RseLogSpill:hasProgress(scene)
    return self:share(scene) > 0
end

-- how many logs still have to be dealt with, for the call panel: pieces not yet in, and those still coming (being laid out, or found again after a load)
function RseLogSpill:left(scene)
    local spill = scene.spill
    if spill == nil then
        return 0
    end
    local left = #spill.queue + (spill.pending ~= nil and 1 or 0)
    for _, piece in ipairs(spill.pieces) do
        if not piece.isIn then
            left = left + 1
        end
    end
    return left
end

function RseLogSpill:isDone(scene)
    local spill = scene.spill
    if spill == nil or spill.failed or spill.leaning or spill.pending ~= nil or #spill.queue > 0 or spill.searchMs ~= nil or spill.lostMs ~= nil then
        return false
    end
    if #spill.pieces == 0 then
        return spill.gone > 0
    end
    for _, piece in ipairs(spill.pieces) do
        if not piece.isIn then
            return false
        end
    end
    return true
end

-- Is a log still lying on the job's car? Only that holds the door (Z: once it is off the door opens, though the job isn't finished). Nobody has to chase a
-- sliver.
function RseLogSpill:carBlocked(scene)
    local spill = scene.spill
    local vehicle = scene.wreck ~= nil and scene.wreck.vehicle or nil
    if spill == nil or spill.failed or vehicle == nil or vehicle.rootNode == nil then
        return false
    end
    if spill.leaning or spill.pending ~= nil or #spill.queue > 0 or spill.searchMs ~= nil then
        return true -- it hasn't come down yet, or a load is still finding it
    end
    local L = parts()
    local node = vehicle.rootNode
    local size = vehicle.size or {}
    local car = { width = size.width or 2, length = size.length or 4.5, offsetZ = size.lengthOffset or 0 }
    for _, piece in ipairs(spill.pieces) do
        if L.nodeExists(piece.node) and getMass(piece.node) >= RseConfig.LOG_TINY_MASS then
            local ends = L.logEnds(piece.node)
            if #ends == 2 then
                local ax, ay, az = worldToLocal(node, ends[1].x, ends[1].y, ends[1].z)
                local bx, by, bz = worldToLocal(node, ends[2].x, ends[2].y, ends[2].z)
                if RseLogRules.onCar({ x = ax, y = ay, z = az }, { x = bx, y = by, z = bz }, car, RseConfig) then
                    return true
                end
            end
        end
    end
    return false
end

-- The job is over: nothing is followed any more, and its logs wait for the county with the rest (Cleanup.lua). All the logs stay with the job (Z), but
-- if you hand a logging job over early, those on a vehicle stay with you, as ordinary logs (keepLoaded). Returns how many stay with you.
function RseLogSpill:leaveBehind(scene, item, keepLoaded)
    local spill = scene.spill
    if spill == nil then
        return 0
    end
    local yours = 0
    for _, piece in ipairs(spill.pieces) do
        parts().removePin(piece)
        if keepLoaded and piece.status == "loaded" then
            yours = yours + 1
        elseif parts().nodeExists(piece.node) then
            table.insert(item.logs, piece.node)
        end
    end
    spill.pieces = {}
    return yours
end

-- what the savegame keeps. The logs are saved by the game; this only remembers where to look for them.
function RseLogSpill:saveData(scene)
    local spill = scene.spill
    if spill == nil then
        return nil
    end
    local data = { total = spill.total, gone = spill.gone, dirX = spill.dirX, dirZ = spill.dirZ,
        splitType = spill.splitType, trees = spill.trees, pieces = {} }
    for _, piece in ipairs(spill.pieces) do
        if parts().nodeExists(piece.node) then
            local x, y, z = getWorldTranslation(piece.node)
            local rx, ry, rz = getWorldRotation(piece.node)
            table.insert(data.pieces, { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz })
        end
    end
    for _, saved in ipairs(spill.savedPieces or {}) do
        table.insert(data.pieces, saved)
    end
    return data
end

function RseLogSpill:restore(scene, data)
    RsePowerLine:watchLogs()
    local spill = newSpill(RseConfig.WRECKS[scene.wreck.kind], data.total, data.dirX or 1, data.dirZ or 0)
    spill.gone, spill.bestIn, spill.splitType, spill.trees = data.gone or 0, data.gone or 0, data.splitType, data.trees or {}
    spill.savedPieces = data.pieces or {}
    spill.searchMs = RseConfig.LINE_SEARCH_MS
    scene.spill = spill
end

-- while the map unloads: the game deletes its own objects
function RseLogSpill:unload()
    for _, scene in pairs(RseScenes.scenes) do
        if scene.spill ~= nil then
            for _, piece in ipairs(scene.spill.pieces) do
                parts().removePin(piece)
            end
        end
    end
end
