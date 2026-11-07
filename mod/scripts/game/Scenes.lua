-- Roadside Emergencies: the scene of one emergency. Lays the animals in the road where the Emergency Pack put the
-- emergency, watches whether each one is still in the road (RseRoadClearRule), and tidies up afterwards:
--   finished (road clear): the pay follows what you did with each animal (RsePayRules.callReward). Loaded ones stay yours to deliver;
--     the rest count as left behind at once: a warning, a map marker and the bill if the county has to collect them.
--   abandoned (the emergency ended before the road was clear): animals still at the scene go; loaded ones stay.
-- Every animal still in the road has a pin over it: the pack's own marker sits on the first of them, and the same game marker
-- (NavigationMarker) on each of the others while you are near. A pin goes when its animal is off the road.
-- Carcasses left lying anywhere are warned about, marked on the map, and collected by the county for a bill (LeftBehindRule.lua).
-- A call in progress is saved and comes back after loading (the pack itself doesn't keep it; M2 round 1 and 4): its animals
-- and items are put back, and the pack is asked to run the same emergency again at the same spot, without the pager.
-- The carcass bodies are physical objects, so traffic stops for them by itself (P1: traffic stops for any physical object).

RseScenes = {
    scenes = {},       -- id -> scene
    nextId = 1,
    checkMs = 0,
    onEnded = nil,     -- called after a scene finished or was abandoned (the main file restarts the call gap)
    store = nil,
    resuming = nil,    -- { data, entries, timerMs }: a saved call on its way back after loading
    spotNear = nil,    -- { x, z, radius }: the next call comes from around here (a twister's end)
    spotExact = nil,   -- a spot: the next call comes from exactly here (a railroad crossing)
    plannedKinds = nil, -- the animals the pager promised (CallPlan.lua), for the next scene
    plannedLoad = nil,  -- and the load
    lastPayRatio = nil, -- what the pack paid for our amount last time (CallPanel.lua asks it), for the pager's "about"
    forcedLoad = nil,  -- test: the load of every spilled-load job (rseLoad)
    drawFailed = false
}

local CHECK_INTERVAL_MS = 250

local function bodyHeight(def)
    return RseConfig.BODY_SIZE[def.body][2]
end

function RseScenes:get(id)
    return id ~= nil and self.scenes[id] or nil
end

-- the road around x, z (empty if it can't be measured)
local function measureRoad(x, z, radius)
    local ok, road = RseLog.try("measure the road", RseRoads.around, x, z, radius or RseConfig.ROAD_SEARCH_RADIUS)
    if not ok or road == nil then
        return { segments = {}, lanes = 0 }
    end
    return road
end

-- on a road on the ground, the terrain under each animal; on a bridge, the terrain lies far below the road
local function groundAt(x, y, z)
    local terrain = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    if y ~= nil and y - terrain > RseConfig.BRIDGE_HEIGHT then
        return y
    end
    return terrain
end

-- not inside a wreck at x, z: pushed along the road, out of its way
local function clearOfWreck(p, x, z, dirX, dirZ, radius)
    local away = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
    if away < radius then
        local dirLength = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-6)
        local along = ((p.x - x) * dirX + (p.z - z) * dirZ) >= 0 and 1 or -1
        local push = (radius - away) * along / dirLength
        p.x, p.z = p.x + dirX * push, p.z + dirZ * push
    end
end

-- dead animals scattered over the road, added to the scene's entries; aroundWreck: a wreck lies in the middle, and they stay this far from it
local function layAnimals(scene, kinds, road, aroundWreck)
    local gap = RseConfig.SCATTER_GAP.small
    for _, kind in ipairs(kinds) do
        if RseAnimalCatalog.get(kind).body == RseAnimalCatalog.BODY_LARGE then
            gap = RseConfig.SCATTER_GAP.large
        end
    end
    local positions = RseSceneSpec.scatter(#kinds, scene.x, scene.z, road.dirX or 1, road.dirZ or 0, {
        span = math.min(RseConfig.SCATTER_SPAN_BASE + RseConfig.SCATTER_SPAN_PER_ANIMAL * #kinds, RseConfig.SCATTER_SPAN_MAX),
        width = RseConfig.SCATTER_WIDTH,
        gap = gap,
        maxRoadDistance = RseConfig.CLEAR_DISTANCE - 0.6
    }, math.random, road.segments)
    for i, kind in ipairs(kinds) do
        local p = positions[i]
        if aroundWreck then
            clearOfWreck(p, scene.x, scene.z, road.dirX or 1, road.dirZ or 0, aroundWreck)
        end
        local def = RseAnimalCatalog.get(kind)
        local entry, reason = RseCarcasses:spawn(kind, p.x, groundAt(p.x, scene.y, p.z) + bodyHeight(def) / 2 + 0.05, p.z, 0, p.yaw, 0)
        if entry ~= nil then
            entry.sceneId = scene.id
            entry.sceneLastX, entry.sceneLastZ, entry.sceneRestMs = p.x, p.z, 0
            table.insert(scene.entries, entry)
        else
            RseLog.info("scene %d: a %s did not load (%s)", scene.id, kind, tostring(reason))
        end
    end
end

-- Lays the animals of `spec` ("cow:1-2") around x, y, z for the emergency `emergency` ("cow"). Returns the scene, or nil and a
-- reason.
function RseScenes:create(x, y, z, spec, emergency)
    local label = spec
    local parts, warnings = RseSceneSpec.parse(spec)
    for _, warning in ipairs(warnings) do
        RseLog.info("scene '%s': %s", tostring(label), warning)
    end
    local kinds = self.plannedKinds or RseSceneSpec.pick(parts, math.random, self.store ~= nil and self.store.settings.jobSize or nil)
    self.plannedKinds, self.plannedLoad = nil, nil
    if #kinds == 0 then
        return nil, "no animals in '" .. tostring(spec) .. "'"
    end
    local road = measureRoad(x, z)
    local id = self.nextId
    self.nextId = id + 1
    local scene = { id = id, emergency = emergency, label = label, x = x, y = y, z = z, segments = road.segments, entries = {},
        finished = false }
    layAnimals(scene, kinds, road)
    if #scene.entries == 0 then
        return nil, "no carcass loaded"
    end
    local placedKinds = {}
    for _, entry in ipairs(scene.entries) do
        table.insert(placedKinds, entry.kind)
    end
    scene.kinds = placedKinds
    scene.reward = RsePayRules.callReward(placedKinds, {}, RseConfig)
    self.scenes[id] = scene
    RseLog.info("scene %d (%s) at %.1f, %.1f: %d animal(s), full call reward $%d; %d lane(s) and %d road segment(s) measured, closest lane %s m away",
        id, tostring(label), x, z, #scene.entries, scene.reward, road.lanes, #road.segments,
        road.distance ~= nil and string.format("%.1f", road.distance) or "-")
    return scene
end

local function exists(entry)
    return RseCarcasses:bodyNode(entry) ~= nil
end

local function playerPosition()
    if g_localPlayer == nil then
        return nil
    end
    local vehicle = g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil
    if vehicle ~= nil and vehicle.rootNode ~= nil then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        return x, z
    end
    local x, _, z = g_localPlayer:getPosition()
    return x, z
end

local function removePin(entry)
    if entry.pin ~= nil then
        RseLog.try("remove a pin", entry.pin.delete, entry.pin)
        entry.pin = nil
    end
end

local function removePins(scene)
    for _, entry in ipairs(scene.entries) do
        removePin(entry)
    end
end

-- tells the player about carcasses left behind: one message for all those with the same time left
local function warnLeft(entries)
    local groups, order = {}, {}
    for _, entry in ipairs(entries) do
        local minutes = RseLeftBehindRule.minutesLeft(entry.left, RseConfig)
        if groups[minutes] == nil then
            groups[minutes] = {}
            table.insert(order, minutes)
        end
        table.insert(groups[minutes], entry)
    end
    for _, minutes in ipairs(order) do
        local group = groups[minutes]
        if #group == 1 then
            RseText.notify(RseText.get("rse_left_warn", RseText.animal(group[1].kind), RseText.minutes(minutes)), true)
        else
            RseText.notify(RseText.get("rse_left_warnMany", #group, RseText.minutes(minutes)), true)
        end
    end
end

-- what hauling a wreck from here pays, by the way to the nearest recovery point
local function haulPayFrom(self, def, x, z)
    local point = self.store ~= nil and self.store.points:nearest(x, z, "recovery") or nil
    if point == nil then
        return 0
    end
    return RseWreckRules.haulPay(def, math.sqrt((point.x - x) ^ 2 + (point.z - z) ^ 2), RseConfig)
end

-- what the haul from (x, z) to the nearest recovery point pays, for the pager (CallPlan.lua)
function RseScenes:haulPayAt(def, x, z)
    return haulPayFrom(self, def, x, z)
end

-- A wreck scene (F9, F10, F15, F16, F17): the wreck across the lane or in the ditch, a spilled load scattered around it. It ends at a recovery point.
function RseScenes:createWreck(x, y, z, kind, emergency)
    local def = RseConfig.WRECKS[kind]
    local road = measureRoad(x, z, def.flock ~= nil and RseConfig.FLOCK_ROAD_RADIUS or nil)
    local dirX, dirZ = road.dirX or 1, road.dirZ or 0
    local yaw = math.atan2(dirX, dirZ)
    local variant = RseWrecks:takeVariant(kind)
    local wreckLength = variant ~= nil and variant.length or 0
    local across = wreckLength > RseConfig.WRECK_LONG and math.pi / 4 or math.pi / 2
    local clear = math.max(RseConfig.WRECK_BALE_CLEAR, wreckLength / 2 + 1) -- nothing is laid inside it
    local position = { x = x, z = z, yaw = yaw + across + (math.random() - 0.5) * 0.5 }
    if def.crossing then
        position.y, position.yaw = y, math.random() * 2 * math.pi -- any which way on the tracks (Z), at the height of the rails, above any road surface
    end
    local waterPlace = def.water and RseRiver:takeChosen() or nil
    if waterPlace ~= nil then
        position.yaw = waterPlace.yaw + (math.random() - 0.5) * RseConfig.WATER_YAW_JITTER
    end
    if def.treeOnCar then
        position.yaw = yaw + (math.random() < 0.5 and math.pi or 0) + (math.random() - 0.5) * RseConfig.TREE_CAR_JITTER -- going either way along its lane
    end
    local penPlace = nil
    if def.flock ~= nil then
        penPlace = RseFlockPlaces:takePen(x, z, road)
        if penPlace ~= nil then
            local truck = RseFlockRules.truckSpot(RseFlockRules.newPen(penPlace.x, penPlace.z, penPlace.gateYaw, RseConfig), RseConfig)
            position = { x = truck.x, z = truck.z, yaw = truck.yaw }
        end
    end
    if def.ditch then
        local length = math.sqrt(dirX * dirX + dirZ * dirZ)
        local side = math.random() < 0.5 and -1 or 1
        position.x = x + side * RseConfig.WRECK_DITCH_OFFSET * dirZ / length
        position.z = z - side * RseConfig.WRECK_DITCH_OFFSET * dirX / length
        position.yaw = yaw
    end
    local size = self.store ~= nil and self.store.settings.jobSize or nil
    local load = self.plannedLoad or RseWreckRules.pickLoad(def, math.random(), RseConfig, RseCalls ~= nil and RseCalls:fleet() or nil)
    self.plannedKinds, self.plannedLoad = nil, nil
    if load ~= nil and self.forcedLoad ~= nil then
        load = RseWreckRules.loadById(def, self.forcedLoad, RseConfig)
    end
    local spots = {}
    local count = RseWreckRules.baleCount(load, math.random, size, variant or def)
    if count > 0 then
        local scattered = RseSceneSpec.scatter(count, x, z, dirX, dirZ, { span = RseConfig.WRECK_BALE_SPREAD, width = RseConfig.WRECK_BALE_WIDTH,
            gap = load.gap, maxRoadDistance = RseConfig.CLEAR_DISTANCE }, math.random, road.segments)
        for _, p in ipairs(scattered) do
            clearOfWreck(p, x, z, dirX, dirZ, clear)
            table.insert(spots, { x = p.x, y = groundAt(p.x, y, p.z) + load.size[2] / 2 + 0.1, z = p.z, ry = p.yaw })
        end
    end
    local id = self.nextId
    self.nextId = id + 1
    local scene = { id = id, emergency = emergency, label = kind, x = x, y = y, z = z, segments = road.segments, entries = {}, kinds = {}, finished = false }
    scene.wreck = RseWrecks:spawn(kind, position, def.held and "held" or "locked", spots, false, load, variant)
    if def.water and waterPlace == nil then
        scene.wreck.failed = true -- no water to be had after all: the call is cancelled, with no pay and no penalty
    end
    if def.crossing and not RseLevelCrossing:begin(scene) then
        scene.wreck.failed = true -- no train to be had after all: the call is cancelled, with no pay and no penalty
    end
    if def.line then
        RseLog.try("lay out the power line", RsePowerLine.spawn, RsePowerLine, scene, road, size)
    end
    if def.flock ~= nil and penPlace == nil then
        scene.wreck.failed = true -- no meadow for the pen here: the call is cancelled, with no pay and no penalty, rather than a pen on the road
    elseif def.flock ~= nil then
        local animal = def.flockKinds[math.random(#def.flockKinds)]
        local ok = RseLog.try("lay out the flock", RseFlock.spawn, RseFlock, scene, road, animal, RseSceneSpec.count(def.flock, math.random, size), penPlace)
        if not ok or scene.flock == nil or scene.flock.total == 0 then
            scene.wreck.failed = true
        end
    end
    if def.treeOnCar then
        scene.wreck.waitForTree = scene
    end
    if def.logs ~= nil then
        local logSpots = RseSceneSpec.scatter(RseSceneSpec.count(def.logs, math.random, size), x, z, dirX, dirZ, { span = RseConfig.LOG_SPREAD,
            width = RseConfig.WRECK_BALE_WIDTH, gap = RseConfig.LOG_GAP, maxRoadDistance = RseConfig.CLEAR_DISTANCE }, math.random, road.segments)
        for _, p in ipairs(logSpots) do
            clearOfWreck(p, x, z, dirX, dirZ, clear)
        end
        if not RseLog.try("lay out the logs", RseLogSpill.spawn, RseLogSpill, scene, road, logSpots, def.treeOnCar == true) then
            scene.wreck.failed = true
        end
    end
    if def.kinds ~= nil then
        -- a livestock trailer: dead animals in the road, loose ones around it, one kind per call
        local animal = RseSurvivors:pickKind(def.kinds)
        local dead = {}
        for _ = 1, RseSceneSpec.count(def.dead, math.random, size) do
            table.insert(dead, animal)
        end
        layAnimals(scene, dead, road, clear)
        for _, entry in ipairs(scene.entries) do
            table.insert(scene.kinds, entry.kind)
        end
        local standing = RseSceneSpec.scatter(RseSceneSpec.count(def.survivors, math.random, size), x, z, dirX, dirZ, {
            span = RseConfig.SCATTER_SPAN_MAX,
            width = RseConfig.SCATTER_WIDTH + 2,
            gap = RseConfig.SCATTER_GAP.large,
            maxRoadDistance = RseConfig.CLEAR_DISTANCE + 2
        }, math.random, road.segments)
        local survivorSpots = {}
        for _, p in ipairs(standing) do
            clearOfWreck(p, x, z, dirX, dirZ, clear)
            table.insert(survivorSpots, { x = p.x, y = groundAt(p.x, y, p.z), z = p.z, yaw = p.yaw })
        end
        RseSurvivors:spawn(scene, animal, survivorSpots)
    end
    scene.haulPay = haulPayFrom(self, def, x, z)
    scene.reward = RseWreckRules.reward(def, #scene.wreck.bales, load, scene.haulPay)
    if scene.spill ~= nil then
        scene.reward = RseLogRules.pay(def, scene.spill.total, 1) + scene.haulPay
    end
    if scene.flock ~= nil then
        scene.reward = RseFlockRules.pay(def, 0, scene.flock.total, false)
    end
    if def.twoParts then
        scene.handover, scene.led = {}, 0
    end
    self.scenes[id] = scene
    RseLog.info("scene %d (wreck %s) at %.1f, %.1f: %d %s bale(s), pay $%d with $%d for the haul; %d lane(s) measured", id, kind, x, z, #scene.wreck.bales,
        load ~= nil and load.id or "no", scene.reward, scene.haulPay, road.lanes)
    return scene
end

-- everything reached a recovery point: the job is done
function RseScenes:finishWreck(scene)
    if scene.finished then
        return
    end
    scene.finished = true
    scene.reward = RsePayRules.scaled(scene.reward, self.store ~= nil and self.store.settings.payFactor or 1)
    if scene.lightsOn then
        scene.reward = RsePayRules.withLightsBonus(scene.reward, RseConfig)
        RseText.notify(RseText.get("rse_call_lightsBonus", math.floor(RseConfig.CALL_LIGHTS_BONUS * 100 + 0.5)))
    end
    self.scenes[scene.id] = nil
    RseLog.info("scene %d (wreck %s) delivered: pay $%d", scene.id, tostring(scene.label), scene.reward)
    if self.onEnded ~= nil then
        self.onEnded(scene)
    end
end

local function currentPayFactor(self)
    return self.store ~= nil and self.store.settings.payFactor or 1
end

-- A job you said yes to that ends with no pay costs a small part of that pay (Z). Saying no costs nothing. Returns what it cost.
function RseScenes:chargePenalty(scene)
    if scene.penaltyCharged then
        return 0
    end
    scene.penaltyCharged = true
    local amount = RsePayRules.penalty(scene.reward, currentPayFactor(self), RseConfig)
    local mission = g_currentMission
    if amount > 0 and mission ~= nil and mission.addMoney ~= nil then
        local farmId = mission.getFarmId ~= nil and mission:getFarmId() or 1
        RseLog.try("addMoney(job penalty)", mission.addMoney, mission, -amount, farmId, RoadsideEmergencies.moneyTypePenalty or MoneyType.OTHER, true, true)
        RseLog.info("scene %d (%s): a job left with no pay costs $%d", scene.id, tostring(scene.label), amount)
    end
    return amount
end

-- what handing the running job over would cost, for the settings panel
function RseScenes:handOverFee()
    local scene = self:get(self:activeId())
    return scene ~= nil and RsePayRules.penalty(scene.reward, currentPayFactor(self), RseConfig) or 0
end

-- The train got there first (Z: you can fail this one). No pay, and the vehicle stays where the train left it until the county has been (Cleanup.lua).
function RseScenes:loseCrossing(scene)
    if scene.finished then
        return
    end
    scene.finished = true
    local fee = self:chargePenalty(scene)
    RseText.notify(fee > 0 and RseText.get("rse_crossing_hitFee", RseText.money(fee)) or RseText.get("rse_crossing_hit"), true)
    local item = RseCleanup.newItem(scene)
    item.wreck = scene.wreck
    RseCleanup:add(item)
    scene.wreck = nil
    self.scenes[scene.id] = nil
    RseLog.info("scene %d: the train hit the vehicle on the crossing, and the job is lost", scene.id)
    if self.onEnded ~= nil then
        self.onEnded(scene)
    end
    RseEpBridge.cancel()
end

-- The logs are in, or handed over with some of them in: the pay follows the logs, and the trailer and the logs wait for the owner's crew (Z).
function RseScenes:finishLogs(scene)
    if scene.finished then
        return
    end
    local handedOver = scene.handOverNow == true
    local def = RseConfig.WRECKS[scene.wreck.kind]
    local carIn = scene.wreck.delivered == true
    if def.treeOnCar then
        -- handed over: what you have done of the three parts
        scene.reward = RseLogRules.logsPay(def, scene.spill.total, RseLogSpill:share(scene)) + (scene.rescueEarned or 0)
            + (carIn and def.pay + (scene.haulPay or 0) or 0)
    else
        scene.reward = RseLogRules.pay(def, scene.spill.total, handedOver and RseLogSpill:share(scene) or 1)
    end
    local item = RseCleanup.newItem(scene)
    if not carIn then
        item.wreck = scene.wreck
    end
    local yours = RseLogSpill:leaveBehind(scene, item, handedOver)
    RseCleanup:add(item)
    local says = handedOver and "rse_logs_crewLeft" or "rse_logs_crew"
    RseText.notify(RseText.get(def.treeOnCar and "rse_tree_handedOver" or says))
    if yours > 0 then
        RseText.notify(RseText.get("rse_logs_yours"))
    end
    self:finishWreck(scene)
end

-- The flock is in, or handed over with some of them in: the farmer sees to the rest, and everything stays until you have gone.
function RseScenes:finishFlock(scene)
    if scene.finished then
        return
    end
    local handedOver = scene.handOverNow == true
    scene.reward = RseFlockRules.pay(RseConfig.WRECKS[scene.wreck.kind], RseFlock:pennedCount(scene), scene.flock.total, handedOver)
    if not handedOver then
        RseLog.try("close the gate", RseFlock.closeGate, RseFlock, scene)
    end
    local item = RseCleanup.newItem(scene)
    item.wreck = scene.wreck
    RseFlock:leaveBehind(scene, item)
    RseSurvivors:leaveBehind(scene, item)
    RseCleanup:add(item)
    RseText.notify(handedOver and RseText.get("rse_flock_handedOver") or RseText.get("rse_flock_done", scene.flock.total))
    self:finishWreck(scene)
end

-- the driver is out: in time for the bonus? (Z asked for more to the missions.)
function RseScenes:noteRescue(scene)
    local def = RseConfig.WRECKS[scene.wreck.kind]
    if not def.treeOnCar or scene.rescueNoted then
        return
    end
    scene.rescueNoted = true
    if (scene.rescueMs or 0) <= RseConfig.TREE_RESCUE_MS then
        scene.rescueEarned = def.rescueBonus
        scene.reward = scene.reward + def.rescueBonus
        RseText.notify(RseText.get("rse_tree_rescueBonus",
            RseText.money(RsePayRules.scaled(def.rescueBonus, self.store ~= nil and self.store.settings.payFactor or 1))))
    end
end

-- A job with no second part, handed over with only some of its load in: each bale that came in pays (Z), and the rest is someone else's.
function RseScenes:finishPartial(scene)
    scene.reward = RseWreckRules.partialReward(scene.wreck.load, scene.wreck.balesIn)
    local item = RseCleanup.newItem(scene)
    item.wreck = scene.wreck
    RseCleanup:add(item)
    RseText.notify(RseText.get("rse_crash_handedOver"))
    self:finishWreck(scene)
end

-- has anything moved on at a crash since last asked? More animals dealt with, the wreck prepared or righted, or the wreck on its way somewhere.
local function crashProgress(scene)
    local cleared = 0
    for _, entry in ipairs(scene.entries) do
        if not exists(entry) or RseRoadClearRule.isClear(entry.sceneStatus) then
            cleared = cleared + 1
        end
    end
    local key = string.format("%d/%d/%d/%s/%s/%s", scene.led or 0, cleared, scene.wreck.balesIn or 0, scene.wreck.state, tostring(RseSurvivors.leading ~= nil),
        RsePowerLine:progressKey(scene))
    local progress = key ~= scene.progressKey
    scene.progressKey = key
    local x, z = RseWrecks:position(scene.wreck)
    if x ~= nil and (scene.wreckX == nil or (x - scene.wreckX) ^ 2 + (z - scene.wreckZ) ^ 2 > 1) then
        scene.wreckX, scene.wreckZ = x, z
        progress = true
    end
    return progress
end

-- the pack's marker: the recovery point once the wreck can be towed there, otherwise the scene (each animal has its own pin and map marker)
local function moveCrashMarker(self, scene, scenario)
    local target = "scene"
    local lineOpen = scene.line ~= nil and scene.line.state.powerOff and not scene.line.poleIn
    if (scene.wreck.state == "ready" and not scene.wreck.delivered) or (scene.wreck.balesLeft or #scene.wreck.bales) > 0 or lineOpen then
        target = "point"
    end
    if scene.markerTarget == target or scenario == nil then
        return
    end
    scene.markerTarget = target
    local x, z = scene.x, scene.z
    local point = target == "point" and self.store ~= nil and self.store.points:nearest(scene.x, scene.z, "recovery") or nil
    if point then
        x, z = point.x, point.z
    end
    RseEpBridge.moveMarker(scenario, x, getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z), z)
end

-- Called every frame by the crash step. Returns true when the job is over.
function RseScenes:updateCrash(scene, scenario, dt)
    local wreck = scene.wreck
    RseWrecks:checkDelivered(wreck, dt)
    if scene.wreckState ~= wreck.state then
        if scene.wreckState ~= nil and wreck.state == "tipped" then
            RseText.notify(RseText.get("rse_wreck_hint_upright"))
        elseif scene.wreckState ~= nil and wreck.state == "ready" then
            RseText.notify(RseText.get("rse_wreck_upright"))
            RseText.notify(RseText.get("rse_wreck_hint_deliver"))
        end
        scene.wreckState = wreck.state
    end
    moveCrashMarker(self, scene, scenario)
    local trailer = wreck.delivered == true
    local hasBales = wreck.load ~= nil
    local hasLine = scene.line ~= nil
    local animals = self:isClear(scene) and RseSurvivors:remaining(scene) == 0 and (wreck.balesLeft or #wreck.bales) == 0 and RsePowerLine:remaining(scene) == 0
    local input = { trailer = trailer, animals = animals, progress = crashProgress(scene), now = scene.handOverNow }
    local event = RseWreckRules.tickHandover(scene.handover, dt, input, RseConfig)
    if event == "partDone" then
        local percent = math.floor(RseConfig.WRECKS[wreck.kind].bothBonus * 100 + 0.5)
        local wait = RseText.minutes(math.ceil(RseConfig.CRASH_HANDOVER_MS / 60000))
        local text = hasBales and "rse_crash_balesDone" or (hasLine and "rse_crash_lineDone" or "rse_crash_animalsDone")
        if trailer then
            text = hasBales and "rse_crash_trailerDoneBales" or (hasLine and "rse_crash_carDone" or "rse_crash_trailerDone")
        end
        RseText.notify(RseText.get(text, percent, wait))
    elseif event == "warn" then
        RseText.notify(RseText.get("rse_crash_warn", RseText.minutes(math.ceil(RseConfig.CRASH_HANDOVER_WARN_MS / 60000))), true)
    elseif event == "handover" then
        RseText.notify(RseText.get("rse_crash_handedOver"))
        return true
    end
    return event == "finish"
end

-- A tree on a car, every frame: get the log off and the door opens; the driver, the road and the car can then go in whatever order suits you (Z: the door opens
-- for realism, but the job can't finish before all of it is done). Returns true when it is.
function RseScenes:updateTree(scene, scenario, dt)
    local wreck = scene.wreck
    if wreck.state == "locked" then
        scene.rescueMs = (scene.rescueMs or 0) + dt
        scene.doorCheckMs = (scene.doorCheckMs or 0) - dt
        if not scene.doorFree and scene.doorCheckMs <= 0 then
            scene.doorCheckMs = RseConfig.TREE_DOOR_CHECK_MS
            if not RseLogSpill:carBlocked(scene) then
                scene.doorFree = true
                RseText.notify(RseText.get("rse_tree_doorFree"))
            end
        end
    elseif not scene.driverSaid then
        scene.driverSaid = true
        self:noteRescue(scene)
        if not wreck.delivered then
            RseText.notify(RseText.get("rse_wreck_hint_deliver"))
        end
    end
    RseWrecks:checkDelivered(wreck, dt)
    moveCrashMarker(self, scene, scenario)
    local road = RseLogSpill:isDone(scene)
    if road and wreck.delivered then
        return true
    end
    if road and not scene.roadSaid then
        scene.roadSaid = true
        RseText.notify(RseText.get(wreck.state == "locked" and "rse_tree_roadClearDriver" or "rse_tree_roadClear"))
    elseif wreck.delivered and not scene.carSaid then
        scene.carSaid = true
        RseText.notify(RseText.get("rse_tree_carIn"))
    end
    return false
end

-- All of it is done: the pay stands, and all the logs go with the job (Z), also those you have loaded
function RseScenes:finishTree(scene)
    if scene.finished then
        return
    end
    local item = RseCleanup.newItem(scene)
    RseLogSpill:leaveBehind(scene, item, false)
    RseCleanup:add(item)
    RseText.notify(RseText.get("rse_tree_crew"))
    self:finishWreck(scene)
end

-- Something else has removed the wreck: see RseWrecks:onVehicleReset. It doesn't count as brought in: the rest goes to another contractor, with pay for what
-- you did. Returns true when that has just happened.
function RseScenes:checkWreckGone(scene)
    local wreck = scene.wreck
    if wreck.vehicle == nil or not wreck.vehicle.isDeleted then
        return false
    end
    RseLog.info("scene %d: the %s wreck was removed by something else", scene.id, wreck.kind)
    RseWrecks:removeVehicle(wreck)
    self:handOver(true) -- not the player's doing, so it costs nothing
    return true
end

-- Any job can go to another contractor at any moment, from the settings panel (Z: a wreck stuck in water must not trap you in the job).
function RseScenes:canHandOver()
    return self:get(self:activeId()) ~= nil
end

-- at a crash you are paid for what you have done, and for each bale of any load that came in; otherwise there is no pay
function RseScenes:handOverPays()
    local scene = self:get(self:activeId())
    if scene == nil or scene.wreck == nil then
        return false
    end
    if scene.flock ~= nil then
        return RseFlock:pennedCount(scene) > 0
    end
    if scene.spill ~= nil then
        return RseLogSpill:hasProgress(scene) or (scene.rescueEarned or 0) > 0 or scene.wreck.delivered == true
    end
    if scene.handover == nil then
        return (scene.wreck.balesIn or 0) > 0
    end
    if (scene.led or 0) > 0 or (scene.wreck.balesIn or 0) > 0 or scene.wreck.delivered or RsePowerLine:hasProgress(scene) then
        return true
    end
    for _, entry in ipairs(scene.entries) do
        if not exists(entry) or RseRoadClearRule.isClear(entry.sceneStatus) then
            return true
        end
    end
    return false
end

function RseScenes:handOver(noFee)
    local scene = self:get(self:activeId())
    if scene == nil then
        return
    end
    if self:handOverPays() then
        scene.handOverNow = true
    elseif RseEpBridge.cancel() then
        RseLog.info("scene %d (%s) handed to another contractor by the player", scene.id, tostring(scene.label))
        local fee = noFee and 0 or self:chargePenalty(scene)
        RseText.notify(fee > 0 and RseText.get("rse_call_handedOverFee", RseText.money(fee)) or RseText.get("rse_call_handedOver"), true)
    else
        RseText.notify(RseText.get("rse_call_cantHandOver"), true)
    end
end

-- A crash is over: pay for each part you did, the bonus if you did both. What you left goes to another contractor, with no pay and no bill, except
-- dead animals you moved off the road yourself, which are yours like on any other call.
function RseScenes:finishCrash(scene)
    if scene.finished then
        return
    end
    scene.finished = true
    removePins(scene)
    local def = RseConfig.WRECKS[scene.wreck.kind]
    local trailer = scene.wreck.delivered == true
    local animals = RseSurvivors:remaining(scene) == 0 and (scene.wreck.balesLeft or #scene.wreck.bales) == 0 and RsePowerLine:remaining(scene) == 0
    local balesIn = scene.wreck.balesIn or 0
    local linePay = RsePowerLine:pay(scene)
    local item = RseCleanup.newItem(scene)
    item.wreck = scene.wreck
    RsePowerLine:leaveBehind(scene, item)
    RseSurvivors:leaveBehind(scene, item)
    local dealtWith = {}
    for _, kind in ipairs(scene.kinds) do
        table.insert(dealtWith, kind)
    end
    local roadsideKinds, leftBehind, hauled = {}, {}, {}
    for _, entry in ipairs(scene.entries) do
        if exists(entry) then
            entry.sceneId = nil
            if entry.sceneStatus == "loaded" or (entry.sceneStatus == "away" and RseStrap:isStrapped(entry)) then
                table.insert(hauled, entry)
            elseif RseRoadClearRule.isClear(entry.sceneStatus) then
                table.insert(roadsideKinds, entry.kind)
                table.insert(leftBehind, entry)
                entry.left = { leftMs = 0, warned = true, reminders = 0 }
            else
                animals = false
                for i, kind in ipairs(dealtWith) do
                    if kind == entry.kind then
                        table.remove(dealtWith, i)
                        break
                    end
                end
                table.insert(item.carcasses, entry)
            end
        end
    end
    RseCleanup:add(item)
    local done = { trailer = trailer, animals = animals, kinds = dealtWith, roadsideKinds = roadsideKinds, led = scene.led, bales = balesIn,
        haulPay = scene.haulPay, payPerBale = RseWreckRules.balePay(scene.wreck.load, trailer), linePay = linePay }
    local reward, bonus = RseWreckRules.crashReward(def, done, RseConfig)
    reward = RseLineRules.afterPenalty(reward, scene.line ~= nil and scene.line.state or nil, RseConfig)
    local payFactor = self.store ~= nil and self.store.settings.payFactor or 1
    scene.reward = RsePayRules.scaled(reward, payFactor)
    if bonus > 0 then
        RseText.notify(RseText.get("rse_crash_bonus", math.floor(def.bothBonus * 100 + 0.5)))
    end
    if scene.lightsOn then
        scene.reward = RsePayRules.withLightsBonus(scene.reward, RseConfig)
        RseText.notify(RseText.get("rse_call_lightsBonus", math.floor(RseConfig.CALL_LIGHTS_BONUS * 100 + 0.5)))
    end
    for _, entry in ipairs(hauled) do
        entry.unearned = RsePayRules.scaled(RsePayRules.unearnedPay(dealtWith, roadsideKinds, entry.kind, RseConfig), payFactor)
    end
    scene.hauled = hauled
    self.scenes[scene.id] = nil
    RseLog.info("scene %d (crash) over: trailer %s, animals %s, %d live loaded, %d dead dealt with, bonus $%d, pay $%d", scene.id, tostring(trailer),
        tostring(animals), scene.led or 0, #dealtWith, bonus, scene.reward)
    warnLeft(leftBehind)
    if #hauled > 0 then
        RseText.notify(RseText.get("rse_scene_deliver"))
    end
    if self.onEnded ~= nil then
        self.onEnded(scene)
    end
end

-- on a vehicle: held by a machine, or a vehicle right below it (a trailer bed, a fork, a bucket)
function RseScenes:isLoaded(entry)
    if RseCarcasses:isMounted(entry) then
        return true
    end
    return self:isOnVehicle(getWorldTranslation(RseCarcasses:bodyNode(entry)))
end

-- a vehicle right below this point; the job's own wreck doesn't count, if `except` names it
function RseScenes:isOnVehicle(x, y, z, except)
    self.rayHit, self.rayExcept = false, except
    raycastClosest(x, y, z, 0, -1, 0, RseConfig.LOADED_RAY, "onLoadedRaycast", self, CollisionFlag.VEHICLE)
    return self.rayHit
end

function RseScenes:onLoadedRaycast(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.rayHit = self.rayExcept == nil or g_currentMission:getNodeObject(hitObjectId) ~= self.rayExcept
        return false
    end
    return true
end

-- updates entry.sceneStatus for one carcass of `scene`
local function judge(self, scene, entry, dt)
    local x, _, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
    local moved = math.abs(x - entry.sceneLastX) + math.abs(z - entry.sceneLastZ)
    entry.sceneLastX, entry.sceneLastZ = x, z
    -- a strap may stay on: once the vehicle stops, the carcass lies still where it was pulled to
    if moved > 0.02 or RseCarcassDrag.dragged == entry then
        entry.sceneRestMs = 0
    else
        entry.sceneRestMs = entry.sceneRestMs + dt
    end
    local status = RseRoadClearRule.status({ x = x, z = z, loaded = self:isLoaded(entry),
        atRest = entry.sceneRestMs >= RseConfig.CLEAR_REST_MS }, scene, RseConfig)
    if status ~= entry.sceneStatus then
        RseLog.debug("scene %d: carcass %d (%s) %s -> %s", scene.id, entry.id, entry.kind, tostring(entry.sceneStatus), status)
        entry.sceneStatus = status
    end
end

-- every animal of the scene is off the road (or gone: delivered, collected)
function RseScenes:isClear(scene)
    for _, entry in ipairs(scene.entries) do
        if exists(entry) and not RseRoadClearRule.isClear(entry.sceneStatus) then
            return false
        end
    end
    return true
end

-- dead animals of the scene still in the road, and how many there were, for the call panel
function RseScenes:animalsLeft(scene)
    local left = 0
    for _, entry in ipairs(scene.entries) do
        if exists(entry) and not RseRoadClearRule.isClear(entry.sceneStatus) then
            left = left + 1
        end
    end
    return left, #(scene.kinds or {})
end

-- counts per status, for the log and rseScene
function RseScenes:counts(scene)
    local counts = { onRoad = 0, verge = 0, loaded = 0, away = 0, gone = 0 }
    for _, entry in ipairs(scene.entries) do
        local status = exists(entry) and (entry.sceneStatus or "onRoad") or "gone"
        counts[status] = counts[status] + 1
    end
    return counts
end

-- Callout details (DESIGN F21): who called it in and where, once the job is accepted.
function RseScenes:announce(scene)
    local caller = RseText.get(RseJobRules.pickCaller(math.random))
    local px, pz = playerPosition()
    local distance = px ~= nil and math.sqrt((scene.x - px) ^ 2 + (scene.z - pz) ^ 2) or nil
    local away = distance ~= nil and g_i18n:formatDistance(distance) or nil
    local farmland = g_farmlandManager ~= nil and g_farmlandManager:getFarmlandIdAtWorldPosition(scene.x, scene.z) or 0
    if away ~= nil and farmland ~= nil and farmland > 0 then
        RseText.notify(RseText.get("rse_call_detailsNear", caller, farmland, away))
    elseif away ~= nil then
        RseText.notify(RseText.get("rse_call_details", caller, away))
    end
    if scene.wreck ~= nil and scene.wreck.variant ~= nil and not scene.wreck.def.scenery then
        scene.towReminderMs = RseConfig.TOW_REMINDER_MS
    end
    if scene.crossing ~= nil and scene.crossing.seconds ~= nil then
        RseText.notify(RseText.get("rse_crossing_call", RseCrossingRules.clock(scene.crossing.seconds)), true)
    end
    -- what the load is, while you can still choose what to bring
    if scene.wreck ~= nil and scene.wreck.load ~= nil then
        RseText.notify(RseText.get("rse_load_call_" .. scene.wreck.load.id))
    end
end

-- what you find on arrival
function RseScenes:announceArrival(scene)
    local count = 0
    for _, entry in ipairs(scene.entries) do
        if exists(entry) then
            count = count + 1
        end
    end
    if scene.flock ~= nil then
        RseText.notify(RseText.get("rse_flock_arrived", scene.flock.total))
    elseif scene.wreck ~= nil and scene.wreck.def.treeOnCar then
        RseText.notify(RseText.get("rse_tree_arrived", math.floor(RseConfig.TREE_RESCUE_MS / 60000 + 0.5),
            RseText.money(RsePayRules.scaled(scene.wreck.def.rescueBonus, self.store ~= nil and self.store.settings.payFactor or 1))))
    elseif scene.spill ~= nil then
        RseText.notify(RseText.get("rse_logs_arrived", scene.spill.total))
    elseif scene.wreck ~= nil and scene.wreck.load ~= nil then
        RseText.notify(RseText.get("rse_crash_arrivedLoad", #scene.wreck.bales))
        RseText.notify(RseText.get("rse_load_arrived_" .. scene.wreck.load.id))
    elseif scene.handover ~= nil and scene.line == nil then -- at a power line, the step's hint says what you find
        RseText.notify(RseText.get("rse_crash_arrived", count, RseSurvivors:remaining(scene)))
    elseif count == 1 then
        RseText.notify(RseText.get("rse_call_arrivedOne"))
    elseif count > 1 then
        RseText.notify(RseText.get("rse_call_arrivedMany", count))
    end
    if not scene.lightsOn then
        RseText.notify(RseText.get("rse_call_lightsHint", math.floor(RseConfig.CALL_LIGHTS_BONUS * 100 + 0.5)))
    end
end

local function hasAny(list)
    return type(list) == "table" and next(list) ~= nil
end

-- Does the vehicle really have turn signal lamps? The game sets the hazard state on any vehicle, lamps or not (Lights.setTurnLightState).
local function hasHazardLamps(spec)
    local static = spec.staticLights or {}
    if hasAny(static.turnLightsLeft) or hasAny(static.turnLightsRight) then
        return true
    end
    for _, setup in pairs(spec.realLights or {}) do
        if type(setup) == "table" and (hasAny(setup.turnLightsLeft) or hasAny(setup.turnLightsRight)) then
            return true
        end
    end
    return false
end

-- are warning lights of yours on at the scene right now? Beacons or hazards that the vehicle really has: the game takes the beacon button on a vehicle
-- with no beacons too (Lights.setBeaconLightsVisibility), and that counted (Z)
local function lightsOnAt(scene)
    local range = RseConfig.LIGHTS_RANGE
    for _, vehicle in ipairs(g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        local spec = vehicle.spec_lights
        -- a wreck's own lights earn nothing, nor the county crew's
        if spec ~= nil and vehicle.rootNode ~= nil and RseWrecks.byVehicle[vehicle] == nil and not RseUtilityCrew:owns(vehicle) then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            if (x - scene.x) ^ 2 + (z - scene.z) ^ 2 <= range * range then
                local beacons = spec.beaconLightsActive == true and hasAny(spec.beaconLights)
                local hazards = vehicle.getTurnLightState ~= nil and vehicle:getTurnLightState() == Lights.TURNLIGHT_HAZARD and hasHazardLamps(spec)
                if beacons or hazards then
                    return true
                end
            end
        end
    end
    return false
end

-- warning lights at the scene: kept on there LIGHTS_EARN_MS in all, at any time during the job, they earn the bonus. Until then the call panel shows
-- whether they are on now.
local function checkLights(scene, elapsed)
    if scene.lightsOn then
        scene.lightsLive = false
        return
    end
    scene.lightsLive = lightsOnAt(scene)
    scene.lightsState = scene.lightsState or {}
    if RsePayRules.tickLights(scene.lightsState, elapsed, scene.lightsLive, RseConfig) == "earned" then
        scene.lightsOn = true
        RseLog.debug("scene %d: warning lights bonus earned", scene.id)
        RseText.notify(RseText.get("rse_call_lightsEarned", math.floor(RseConfig.CALL_LIGHTS_BONUS * 100 + 0.5)))
    end
end

-- the road is clear: the pay follows what you did with each animal; what isn't on its way somewhere counts as left behind
function RseScenes:finish(scene)
    if scene.finished then
        return
    end
    scene.finished = true
    removePins(scene)
    local counts = self:counts(scene)
    local roadsideKinds, leftBehind, hauled = {}, {}, {}
    for _, entry in ipairs(scene.entries) do
        if exists(entry) then
            -- hauled: loaded, or on a strap on its way; anything else was only moved out of the road
            if entry.sceneStatus == "loaded" or (entry.sceneStatus == "away" and RseStrap:isStrapped(entry)) then
                table.insert(hauled, entry)
            else
                table.insert(roadsideKinds, entry.kind)
                table.insert(leftBehind, entry)
                entry.left = { leftMs = 0, warned = true, reminders = 0 }
            end
            entry.sceneId = nil
        end
    end
    local payFactor = self.store ~= nil and self.store.settings.payFactor or 1
    scene.reward = RsePayRules.scaled(RsePayRules.callReward(scene.kinds, roadsideKinds, RseConfig), payFactor)
    if scene.lightsOn then
        scene.reward = RsePayRules.withLightsBonus(scene.reward, RseConfig)
        RseText.notify(RseText.get("rse_call_lightsBonus", math.floor(RseConfig.CALL_LIGHTS_BONUS * 100 + 0.5)))
    end
    for _, entry in ipairs(hauled) do
        entry.unearned = RsePayRules.scaled(RsePayRules.unearnedPay(scene.kinds, roadsideKinds, entry.kind, RseConfig), payFactor)
    end
    scene.hauled = hauled
    self.scenes[scene.id] = nil
    RseLog.info("scene %d (%s) cleared: %d at the roadside, %d loaded, %d towed away, %d delivered; call reward $%d", scene.id,
        tostring(scene.label), counts.verge, counts.loaded, counts.away, counts.gone, scene.reward)
    warnLeft(leftBehind)
    if #hauled > 0 then
        RseText.notify(RseText.get("rse_scene_deliver"))
    end
    if self.onEnded ~= nil then
        self.onEnded(scene)
    end
end

-- what the pack actually pays includes the game's economy difficulty; pay taken back must match it
function RseScenes:applyPayFactor(scene, paid)
    if type(paid) ~= "number" or scene.reward == nil or scene.reward <= 0 then
        return
    end
    for _, entry in ipairs(scene.hauled or {}) do
        entry.unearned = math.floor(entry.unearned * paid / scene.reward + 0.5)
    end
end

-- The emergency ended before the job was done (out of time, handed over with nothing done, called off): no pay, and what is left at the scene waits for
-- the county (Cleanup.lua). Dead animals you loaded or towed away stay yours.
function RseScenes:abandon(scene)
    if scene.finished then
        return
    end
    scene.finished = true
    removePins(scene)
    local item = RseCleanup.newItem(scene)
    item.wreck = scene.wreck
    RsePowerLine:leaveBehind(scene, item)
    RseLogSpill:leaveBehind(scene, item, false)
    RseFlock:leaveBehind(scene, item)
    RseSurvivors:leaveBehind(scene, item)
    for _, entry in ipairs(scene.entries) do
        if exists(entry) then
            entry.sceneId = nil
            if entry.sceneStatus ~= "loaded" and entry.sceneStatus ~= "away" then
                table.insert(item.carcasses, entry)
            end
        end
    end
    RseCleanup:add(item)
    self.scenes[scene.id] = nil
    RseLog.info("scene %d (%s) ended before the job was done", scene.id, tostring(scene.label))
    if self.onEnded ~= nil then
        self.onEnded(scene)
    end
end

-- A map target only has x and z, so its marker stands on the ground under a bridge (Z). Within sight of an animal up there it steps aside for a pin on the
-- animal itself; from further off it still shows the way.
local function hideTarget(scene, hide)
    local hotspot = scene.scenario ~= nil and scene.scenario.mapHotspot or nil
    local mission = g_currentMission
    if type(hotspot) ~= "table" or mission.setMapTargetHotspot == nil then
        return
    end
    if hide and mission.currentMapTargetHotspot == hotspot then
        if not scene.targetHidden then
            RseLog.info("scene %d: an animal on a bridge: a pin instead of the map target", scene.id)
        end
        scene.targetHidden = true
        RseLog.try("hide the map target", mission.setMapTargetHotspot, mission, nil)
    elseif not hide and scene.targetHidden then
        scene.targetHidden = nil
        if mission.currentMapTargetHotspot == nil then
            RseLog.try("show the map target", mission.setMapTargetHotspot, mission, hotspot)
        end
    end
end

-- puts the pack's marker on the first animal still in the road, and a pin of our own on each of the others. At a wreck the pack's marker has
-- other things to show: every animal gets a pin of our own.
local function updateMarkers(scene)
    local primary = nil
    local lead = scene.wreck == nil
    local px, pz = playerPosition()
    local onBridgeNearby = false
    for _, entry in ipairs(scene.entries) do
        local inRoad = exists(entry) and not RseRoadClearRule.isClear(entry.sceneStatus)
        local pinned = inRoad
        if inRoad and lead and primary == nil then
            primary = entry
            local x, y, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
            local moved = scene.markerX == nil or math.abs(x - scene.markerX) + math.abs(z - scene.markerZ) > 1
            if moved and scene.scenario ~= nil then
                scene.markerX, scene.markerZ = x, z
                RseEpBridge.moveMarker(scene.scenario, x, y, z)
            end
            local near = px ~= nil and (x - px) ^ 2 + (z - pz) ^ 2 <= RseConfig.PIN_RANGE ^ 2
            onBridgeNearby = near and y - getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) > RseConfig.BRIDGE_HEIGHT
            pinned = onBridgeNearby
        end
        if pinned and type(NavigationMarker) == "table" then
            if entry.pin == nil then
                local ok, pin = RseLog.try("create a pin", NavigationMarker.new)
                entry.pin = ok and pin or nil
            end
            if entry.pin ~= nil then
                local x, y, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
                entry.pin:setWorldPosition(x, y + RseConfig.PIN_HEIGHT, z)
                entry.pin:setVisibility(px ~= nil and (x - px) ^ 2 + (z - pz) ^ 2 <= RseConfig.PIN_RANGE ^ 2)
            end
        else
            removePin(entry)
        end
    end
    if lead then
        hideTarget(scene, onBridgeNearby)
    end
end

-- Z: with an animal left from an earlier job, the red marker led to that animal and not to the new call. Nothing of ours aims it there, so the cause isn't
-- proven. While a job runs, none of our map markers may hold the game's map target: it goes back to the job's.
local function keepTargetOnJob(self)
    local mission = g_currentMission
    local current = mission.currentMapTargetHotspot
    if type(current) ~= "table" or current.rseMarker == nil or mission.setMapTargetHotspot == nil then
        return
    end
    for _, scene in pairs(self.scenes) do
        local hotspot = scene.scenario ~= nil and scene.scenario.mapHotspot or nil
        if type(hotspot) == "table" and not scene.targetHidden then
            RseLog.try("put the map target back", mission.setMapTargetHotspot, mission, hotspot)
            return
        end
    end
end

-- Anything drawn every frame can take the whole GUI down (M1): not behind menus, and one failure switches it off.
function RseScenes:draw()
    if self.drawFailed or next(self.scenes) == nil or (g_gui ~= nil and g_gui:getIsGuiVisible()) then
        return
    end
    for _, scene in pairs(self.scenes) do
        for _, entry in ipairs(scene.entries) do
            if entry.pin ~= nil and not RseLog.try("draw a pin", entry.pin.render, entry.pin) then
                self.drawFailed = true
                return
            end
        end
        if not RseSurvivors:draw(scene) or not RsePowerLine:draw(scene) or not RseLogSpill:draw(scene) or not RseLevelCrossing:draw(scene) then
            self.drawFailed = true
            return
        end
    end
end

-- carcasses left behind: runs the clock of each, keeps a map marker on each one warned about, and the county collects those whose
-- time is up
local function updateLeftBehind(self, dt)
    local px, pz = playerPosition()
    local list = {}
    for _, entry in ipairs(RseCarcasses.entries) do
        if exists(entry) then
            table.insert(list, entry)
        end
    end
    local warnings = {}
    for _, entry in ipairs(list) do
        entry.left = entry.left or { leftMs = 0 }
        local exempt = entry.sceneId ~= nil or entry.resuming == true or entry.crewTakes == true
        local isHeld = self:isLoaded(entry) or RseCarcassDrag.dragged == entry or RseStrap:isStrapped(entry)
        local held = not exempt and isHeld
        local x, _, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
        -- on its way somewhere: an animal on a trailer you parked and walked away from isn't (Z: the markers stayed up after a delivery)
        entry.carried = isHeld and px ~= nil and (x - px) ^ 2 + (z - pz) ^ 2 <= RseConfig.POINT_MARKER_RANGE ^ 2
        local near = px ~= nil and (x - px) ^ 2 + (z - pz) ^ 2 <= RseConfig.LEFT_PLAYER_DISTANCE ^ 2
        local event = RseLeftBehindRule.tick(entry.left, dt, { exempt = exempt, held = held, playerNear = near }, RseConfig)
        local collect = { id = entry.id, x = x, z = z, unearned = entry.unearned }
        if event == "collect" and self.store ~= nil and self.store:apply("collectCarcass", collect) ~= nil then
            RseCarcasses:remove(entry, false)
        else
            if event == "warn" then
                table.insert(warnings, entry)
            end
            if entry.left.warned then
                local title = RseText.get("rse_marker_left", RseText.animal(entry.kind))
                entry.markerInfo = entry.markerInfo or { kind = "dead", entry = entry, title = title,
                    image = Utils.getFilename("icons/hud_fill_" .. entry.kind .. ".dds", RoadsideEmergencies.MOD_DIR) }
                -- while a job runs it keeps quiet, so the only thing calling you is the job
                RseMarkers:show(entry, x, z, { name = title, image = "left", info = entry.markerInfo, quiet = next(self.scenes) ~= nil })
            else
                RseMarkers:hide(entry)
            end
        end
    end
    warnLeft(warnings)
end

-- how far the wreck has come towards the recovery point, 0 to 1
local function towShare(self, scene)
    local x, z = RseWrecks:position(scene.wreck)
    local point = x ~= nil and self.store ~= nil and self.store.points:nearest(x, z, "recovery") or nil
    if point == nil then
        return 0
    end
    local distance = math.sqrt((point.x - x) ^ 2 + (point.z - z) ^ 2)
    scene.towStart = math.max(scene.towStart or distance, distance)
    return scene.towStart > 0 and 1 - distance / scene.towStart or 0
end

-- The pack's bar follows what has really been done (Z: true to the scene). Each part of the job counts the same: the animals, the bales, the wreck.
local function reportProgress(self, scene)
    local scenario = scene.scenario
    if scenario == nil or type(scenario.setProgress) ~= "function" then
        return
    end
    local parts = {}
    local total = #(scene.kinds or {}) + (scene.led or 0) + RseSurvivors:remaining(scene)
    if total > 0 then
        local done = #(scene.kinds or {}) + (scene.led or 0)
        for _, entry in ipairs(scene.entries) do
            if exists(entry) and not RseRoadClearRule.isClear(entry.sceneStatus) then
                done = done - 1
            end
        end
        table.insert(parts, RseProgressRules.share(done, total))
    end
    local wreck = scene.wreck
    if wreck ~= nil then
        if not wreck.def.noVehicle and not wreck.def.scenery then
            local towed = wreck.state == "ready" and not wreck.delivered and towShare(self, scene) or 0
            table.insert(parts, RseProgressRules.wreck(wreck.state, wreck.delivered, towed, wreck.def.tipped, RseConfig))
        end
        if (wreck.balesTotal or 0) + (wreck.balesIn or 0) > 0 then
            table.insert(parts, RseProgressRules.share(wreck.balesIn or 0, wreck.balesTotal))
        end
        if scene.line ~= nil then
            table.insert(parts, RsePowerLine:share(scene))
        end
        if scene.spill ~= nil then
            table.insert(parts, RseLogSpill:share(scene))
        end
        if scene.flock ~= nil then
            table.insert(parts, RseFlock:share(scene))
        end
    end
    local progress = math.max(scene.progress or 0, RseProgressRules.scene(scene.arrived == true, parts, RseConfig))
    if progress ~= scene.progress then
        scene.progress = progress
        scenario.rseProgress = progress
        RseLog.try("report the progress", scenario.setProgress, scenario, progress)
    end
end

-- steady map markers on the drop-off points, only while you have something to bring to one (Z: a marker with nothing to do there looks like a leftover):
-- disposal points while you are with an animal you have loaded, on a strap or in hand; recovery points while a wreck can be towed in or bales brought.
-- Your own points carry their number, as in the settings panel. The shop has no marker of ours (Z): the map already shows it.
local function updatePointMarkers(self)
    if self.store == nil then
        return
    end
    local disposal, recovery = false, false
    for _, entry in ipairs(RseCarcasses.entries) do
        disposal = disposal or entry.carried == true
    end
    for _, scene in pairs(self.scenes) do
        local wreck = scene.wreck
        if wreck ~= nil and ((wreck.state == "ready" and not wreck.delivered) or #wreck.bales > 0 or (scene.line ~= nil and not scene.line.poleIn)) then
            recovery = true
        end
    end
    for _, point in ipairs(self.store.points:list()) do
        local own = RsePoints:numberOf(point) ~= nil
        if own and ((point.kind ~= "recovery" and disposal) or (point.kind ~= "disposal" and recovery)) then
            local title = RseText.get("rse_point_hotspot", RsePoints:numberOf(point), point.name)
            RseMarkers:show("point" .. point.id, point.x, point.z, { steady = true, name = title, image = RsePoints:markerImage(point),
                info = { kind = "point", point = point, title = title, image = Utils.getFilename("icons/map_dropoff.dds", RoadsideEmergencies.MOD_DIR) } })
        else
            RseMarkers:hide("point" .. point.id)
        end
    end
end

-- A few seconds after yes, on its own: what the pager said about the vehicle (Z didn't see it among the messages that come with yes).
local function remindTow(scene, elapsed)
    if scene.towReminderMs == nil then
        return
    end
    scene.towReminderMs = scene.towReminderMs - elapsed
    if scene.towReminderMs > 0 then
        return
    end
    scene.towReminderMs = nil
    if scene.wreck ~= nil and scene.wreck.variant ~= nil then
        RseText.notify(RseWrecks:towText(scene.wreck.variant), scene.wreck.variant.heavy == true)
        RseLog.info("scene %d: told the player again what the vehicle takes", scene.id)
    end
end

function RseScenes:update(dt)
    self.checkMs = self.checkMs + dt
    if self.checkMs < CHECK_INTERVAL_MS then
        return
    end
    local elapsed = self.checkMs
    self.checkMs = 0
    RseWrecks:removeResetCopies()
    for _, scene in pairs(self.scenes) do
        remindTow(scene, elapsed)
        for _, entry in ipairs(scene.entries) do
            if exists(entry) then
                judge(self, scene, entry, elapsed)
            end
        end
        updateMarkers(scene)
        checkLights(scene, elapsed)
        reportProgress(self, scene)
    end
    updateLeftBehind(self, elapsed)
    updatePointMarkers(self)
    keepTargetOnJob(self)
    RseCleanup:update(elapsed)
    if self.resuming ~= nil then
        self.resuming.timerMs = self.resuming.timerMs - elapsed
        if self.resuming.timerMs <= 0 then
            self:cancelResume("the pack did not start it in time")
        end
    end
end

-- the county collects a dead animal now, at the player's word (a click on its map marker): the same bill as when the time runs out
function RseScenes:collectNow(entry)
    if self.store == nil or not exists(entry) then
        return
    end
    local x, _, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
    if self.store:apply("collectCarcass", { id = entry.id, x = x, z = z, unearned = entry.unearned }) ~= nil then
        RseCarcasses:remove(entry, false)
    end
end

-- where the next call happens: anywhere on the road network, or where a saved call was. Kept out: on top of the player or a
-- vehicle, and disposal points (a carcass lying there would be delivered at once, M1).
function RseScenes:nextSpot(onGround)
    if self.resuming ~= nil then
        local data = self.resuming.data
        return { x = data.x, y = data.y, z = data.z, dirX = 1, dirY = 0, dirZ = 0 }
    end
    if self.spotExact ~= nil then
        local exact = self.spotExact
        self.spotExact = nil
        return exact
    end
    local near = self.spotNear
    self.spotNear = nil
    local keepOuts = {}
    if g_localPlayer ~= nil then
        local x, _, z = g_localPlayer:getPosition()
        table.insert(keepOuts, { x = x, z = z, radius = RseConfig.SPOT_PLAYER_CLEAR })
    end
    for _, vehicle in ipairs(g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        if vehicle.rootNode ~= nil then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            table.insert(keepOuts, { x = x, z = z, radius = RseConfig.SPOT_VEHICLE_CLEAR })
        end
    end
    for _, point in ipairs(self.store ~= nil and self.store.points:list() or {}) do
        if point.kind ~= "recovery" then
            table.insert(keepOuts, { x = point.x, z = point.z, radius = RseConfig.POINT_RADIUS + RseConfig.SCATTER_SPAN_MAX })
        end
    end
    local ok, spot = RseLog.try("pick a road spot", RseRoads.randomSpot, keepOuts, near, onGround)
    if ok and spot == nil and near ~= nil then
        ok, spot = RseLog.try("pick a road spot", RseRoads.randomSpot, keepOuts, nil, onGround)
    end
    return ok and spot or nil
end

-- what the savegame keeps of the call in progress, or nil
function RseScenes:saveData()
    if self.resuming ~= nil then
        return self.resuming.data
    end
    local scene = self:get(self:activeId())
    if scene == nil or scene.emergency == nil then
        return nil
    end
    return { id = scene.emergency, label = scene.label, x = scene.x, y = scene.y, z = scene.z, kinds = scene.kinds,
        wreck = scene.wreck ~= nil and RseWrecks:saveData(scene.wreck) or nil, survivors = RseSurvivors:saveData(scene),
        reward = scene.wreck ~= nil and scene.reward or nil, arrived = scene.arrived == true, led = scene.led,
        balesIn = scene.wreck ~= nil and scene.wreck.balesIn or 0, line = RsePowerLine:saveData(scene), logs = RseLogSpill:saveData(scene),
        flock = RseFlock:saveData(scene),
        crossing = RseLevelCrossing:saveData(scene),
        rescueMs = scene.rescueMs, rescueNoted = scene.rescueNoted, rescueEarned = scene.rescueEarned }
end

function RseScenes:isResuming()
    return self.resuming ~= nil
end

-- A saved call: its animals (entries) are back in the world; asks the pack to run that emergency again.
function RseScenes:beginResume(data, entries)
    self.resuming = { data = data, entries = entries, timerMs = RseConfig.RESUME_TIMEOUT_MS }
    for _, entry in ipairs(entries) do
        entry.resuming = true
    end
    local ok, reason = RseEpBridge.resume(RseConfig.POOL_PREFIX .. data.id)
    if not ok then
        self:cancelResume(reason)
    end
end

-- The pack has placed the emergency again: the saved animals and items become its scene. Returns the scene.
function RseScenes:adopt()
    local resuming = self.resuming
    local data = resuming.data
    self.resuming = nil
    local id = self.nextId
    self.nextId = id + 1
    local road = measureRoad(data.x, data.z)
    local scene = { id = id, emergency = data.id, label = data.label, x = data.x, y = data.y, z = data.z, segments = road.segments,
        entries = {}, finished = false, kinds = data.kinds or {}, arrived = data.arrived == true }
    for _, entry in ipairs(resuming.entries) do
        entry.resuming = nil
        if exists(entry) then
            local x, _, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
            entry.sceneId = id
            entry.sceneLastX, entry.sceneLastZ, entry.sceneRestMs = x, z, 0
            table.insert(scene.entries, entry)
        end
    end
    if #scene.kinds == 0 then
        for _, entry in ipairs(scene.entries) do
            table.insert(scene.kinds, entry.kind)
        end
    end
    scene.reward = RsePayRules.callReward(scene.kinds, {}, RseConfig)
    if data.wreck ~= nil then
        local saved = data.wreck
        local position = { x = saved.x or data.x, y = saved.y ~= nil and saved.y + 0.1 or nil, z = saved.z or data.z,
            yaw = saved.ry, rx = saved.rx, rz = saved.rz }
        local def = RseConfig.WRECKS[saved.kind]
        local load = RseWreckRules.loadById(def, saved.load, RseConfig)
        scene.wreck = RseWrecks:spawn(saved.kind, position, saved.state, saved.bales, saved.delivered, load, RseWreckRules.variantByFile(def, saved.file))
        if def.line and data.line ~= nil then
            RseLog.try("bring back the power line", RsePowerLine.restore, RsePowerLine, scene, data.line)
        end
        if def.water then
            RseRiver:noteLast(data.x, data.z)
        end
        if def.flock ~= nil then
            RseFlockPlaces:noteLast(data.x, data.z)
        end
        if def.crossing then
            local ok, found = false, false
            if data.crossing ~= nil then
                ok, found = RseLog.try("bring back the crossing", RseLevelCrossing.restore, RseLevelCrossing, scene, data.crossing)
            end
            if not (ok and found) then
                scene.wreck.failed = true
            end
        end
        if def.logs ~= nil and (data.logs == nil or not RseLog.try("bring back the logs", RseLogSpill.restore, RseLogSpill, scene, data.logs)) then
            scene.wreck.failed = true -- the job can't go on without them: the call is cancelled, with no pay and no penalty
        end
        if def.treeOnCar then
            scene.wreck.waitForTree = scene
            -- a driver already out isn't paid for twice
            scene.rescueMs, scene.rescueNoted, scene.rescueEarned = data.rescueMs, data.rescueNoted, data.rescueEarned
        end
        if def.flock ~= nil then
            if data.flock == nil or not RseLog.try("bring back the flock", RseFlock.restore, RseFlock, scene, data.flock, data.survivors or {}) then
                scene.wreck.failed = true
            end
        else
            for _, animal in ipairs(data.survivors or {}) do
                RseSurvivors:spawn(scene, animal.kind, { animal })
            end
        end
        -- fixed when the job began: bales and animals already brought in still count
        scene.haulPay = haulPayFrom(self, def, data.x, data.z)
        scene.reward = data.reward or RseWreckRules.reward(def, #saved.bales, load, scene.haulPay)
        scene.wreck.balesIn = data.balesIn or 0
        scene.wreck.balesTotal = scene.wreck.balesTotal + scene.wreck.balesIn
        if def.twoParts then
            scene.handover, scene.led = {}, data.led or 0
        end
    end
    self.scenes[id] = scene
    if self.store ~= nil then
        self.store:apply("kitMoveJob", { from = "resume", to = id })
    end
    RseText.notify(RseText.get("rse_scene_resumed"))
    RseLog.info("the call in progress is back: scene %d (%s) at %.1f, %.1f, %d animal(s), full call reward $%d", id, tostring(data.label), data.x,
        data.z, #scene.entries, scene.reward)
    return scene
end

-- The saved call can't come back: its animals still at the scene and its logs wait for the county (Cleanup.lua; the game has put the logs back from the
-- savegame), what is loaded or towed away stays, its items are owed. Nothing else of it is in the world: the rest only came back with the call.
function RseScenes:cancelResume(reason)
    local resuming = self.resuming
    self.resuming = nil
    local data = resuming.data
    local item = RseCleanup.newItem(data)
    for _, entry in ipairs(resuming.entries) do
        entry.resuming = nil
        if exists(entry) then
            local x, _, z = getWorldTranslation(RseCarcasses:bodyNode(entry))
            local status = RseRoadClearRule.status({ x = x, z = z, loaded = self:isLoaded(entry), atRest = false },
                { x = data.x, z = data.z }, RseConfig)
            if status ~= "loaded" and status ~= "away" then
                table.insert(item.carcasses, entry)
            end
        end
    end
    RseCleanup:add(item)
    local logs = {}
    for _, list in ipairs({ data.logs ~= nil and data.logs.pieces or {}, data.line ~= nil and data.line.pieces or {} }) do
        for _, place in ipairs(list) do
            table.insert(logs, { x = place.x, y = place.y, z = place.z })
        end
    end
    RseCleanup:findLater(data.x, data.z, logs)
    RseText.notify(RseText.get("rse_scene_resumeFailed"), true)
    RseLog.info("the call in progress could not come back (%s): %d animal(s) and %d log(s) left for the county", tostring(reason), #item.carcasses, #logs)
    if self.onEnded ~= nil then
        self.onEnded({ id = "resume" })
    end
end

-- the id of the job running now, or nil (one farm, one emergency at a time)
function RseScenes:activeId()
    local id = next(self.scenes)
    return id
end

function RseScenes:activeCount()
    local count = 0
    for _ in pairs(self.scenes) do
        count = count + 1
    end
    return count
end

-- while the map unloads: the carcasses go with RseCarcasses:unload
function RseScenes:unload()
    RseLog.try("clear up what jobs left", RseCleanup.unload, RseCleanup)
    RseLog.try("unload the crossing", RseLevelCrossing.unload, RseLevelCrossing)
    RseLog.try("unload the pager text", RseEpBridge.unload)
    RseLog.try("unload the sounds", RseSound.unload, RseSound)
    RseLog.try("unload the logs", RseLogSpill.unload, RseLogSpill)
    RseLog.try("unload the power line", RsePowerLine.unload, RsePowerLine)
    for _, scene in pairs(self.scenes) do
        removePins(scene)
        RseLog.try("take down the pen", RseFlock.remove, RseFlock, scene)
        RseLog.try("remove the live animals", RseSurvivors.remove, RseSurvivors, scene)
    end
    self.drawFailed = false
    self.scenes = {}
    self.resuming = nil
    self.checkMs = 0
end
