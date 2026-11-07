-- Roadside Emergencies: the county crew at a downed power line (Z, 2026-11-07). Once you reach the scene, a crew truck appears out of sight along the road,
-- drives up with its hazards on and a driver at the wheel, parks short of the scene at the side of its lane, and the crew cuts the power (CrewRules.lua says
-- where, how fast and when). After the job it stays until you have gone.
-- It is driven the way the game's own AI helpers drive: the game's AIVehicleUtil.driveToPoint (steering, motor, brakes through the real wheels), on a
-- vehicle kept active with the game's forceIsActive flag, since nobody sits in it. The game's Drivable only drives a vehicle a player controls, so nothing
-- fights it. Like a wreck, it is the game's kind of contract vehicle: not saved, not in your list, and it can't be entered.
-- If no truck can come (no road long enough, it doesn't load, it never gets moving), the power goes off on the old timer (LineRules.tickPower), and the
-- log says why.

RseUtilityCrew = {
    crews = {},        -- scene id -> crew
    byVehicle = {},    -- vehicle -> crew
    leaving = {}       -- crews whose job is over, waiting for you to go
}

local function aiNode(vehicle)
    if vehicle.getAIRootNode ~= nil then
        local ok, node = pcall(vehicle.getAIRootNode, vehicle)
        if ok and node ~= nil then
            return node
        end
    end
    return vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node or vehicle.rootNode
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

-- the camera's forward direction on the ground, to come from out of sight
local function cameraForward()
    local camera = type(getCamera) == "function" and getCamera() or nil
    if camera == nil or camera == 0 then
        return 0, 0
    end
    local fx, _, fz = localDirectionToWorld(camera, 0, 0, -1)
    return fx, fz
end

-- The way to the scene: the road back from it, cut short of it by CREW_STOP_BEFORE, the last stretch eased over to the side of the lane, away from the
-- other lanes. Nil when there is no lane there.
local function buildRoute(scene)
    local route, dirX, dirZ = RseRoads.routeBack(scene.x, scene.z, RseConfig.CREW_ROUTE_MAX, RseConfig.CREW_ROUTE_STEP)
    if route == nil or #route < 3 then
        return nil
    end
    local cut = 0
    while #route > 2 and cut < RseConfig.CREW_STOP_BEFORE - 0.5 do -- the half metre: five 5 m steps can add up to a hair under 25
        local a, b = route[#route - 1], route[#route]
        cut = cut + math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
        table.remove(route)
    end
    local stop = route[#route]
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 1e-6 then
        return route
    end
    dirX, dirZ = dirX / length, dirZ / length
    local side = RseCrewRules.shoulderSide(stop.x, stop.z, dirX, dirZ, RseConfig.CREW_SHOULDER, function(x, z)
        return RseRoads.laneDistance(x, z, RseConfig.CREW_SHOULDER * 3)
    end)
    local along = 0
    for i = #route, 2, -1 do
        local a, b = route[i - 1], route[i]
        local sx, sz = b.x - a.x, b.z - a.z
        local segment = math.sqrt(sx * sx + sz * sz)
        if segment > 1e-6 then
            local share = math.max(0, 1 - along / RseConfig.CREW_SHOULDER_ALONG)
            local offset = side * RseConfig.CREW_SHOULDER * share
            -- the right-hand side of the way it goes is (-dirZ, dirX)
            b.x, b.z = b.x - sz / segment * offset, b.z + sx / segment * offset
        end
        along = along + segment
        if along > RseConfig.CREW_SHOULDER_ALONG then
            break
        end
    end
    return route
end

-- the driver, dressed like one of the map's people, as a wreck's (P9b)
local function seatDriver(crew)
    local vehicle = crew.vehicle
    if vehicle.setVehicleCharacter == nil or g_npcManager == nil or g_npcManager.getNPCByName == nil then
        return
    end
    local ok, npc = RseLog.try("find an NPC", g_npcManager.getNPCByName, g_npcManager, "FARMER")
    if ok and npc ~= nil and npc.playerStyle ~= nil and RseLog.try("seat the crew's driver", vehicle.setVehicleCharacter, vehicle, npc.playerStyle) then
        crew.showDriverInMs = RseConfig.CREW_DRIVER_SHOW_MS
    end
end

function RseUtilityCrew:onLoaded(vehicles, loadingState, crew)
    if loadingState ~= VehicleLoadingState.OK or vehicles == nil or vehicles[1] == nil then
        RseLog.problem("the county crew's truck did not load (state %s): the timer cuts the power", tostring(loadingState))
        crew.state.phase = "failed"
        return
    end
    if crew.removed then
        RseLog.try("delete a crew truck no longer needed", vehicles[1].delete, vehicles[1])
        return
    end
    crew.vehicle = vehicles[1]
    self.byVehicle[crew.vehicle] = crew
    crew.state.phase = "driving"
    seatDriver(crew)
    local vehicle = crew.vehicle
    if vehicle.spec_lights ~= nil then
        RseLog.try("the crew's hazards", vehicle.setTurnLightState, vehicle, Lights.TURNLIGHT_HAZARD, true, true)
        if vehicle.setLightsTypesMask ~= nil then
            RseLog.try("the crew's headlights", vehicle.setLightsTypesMask, vehicle, 1, true, true)
        end
    end
    RseLog.info("the county crew is on its way: %.0f m of road", RseCrewRules.lengthFrom(crew.route, 1))
end

-- Sends a crew to a power line you have reached. Returns true if a truck is on its way; false and the timer cuts the power otherwise.
function RseUtilityCrew:dispatch(scene)
    if self.crews[scene.id] ~= nil then
        return true
    end
    local route = buildRoute(scene)
    if route == nil then
        RseLog.info("county crew: no lane at the scene, so no truck; the timer cuts the power")
        return false
    end
    local px, pz = playerPosition()
    local fx, fz = cameraForward()
    local first = RseCrewRules.spawnIndex(route, px, pz, fx, fz, RseConfig)
    if first == nil then
        RseLog.info("county crew: only %.0f m of road to come along, so no truck; the timer cuts the power", RseCrewRules.lengthFrom(route, 1))
        return false
    end
    local trimmed = {}
    for i = first, #route do
        table.insert(trimmed, route[i])
    end
    local a, b = trimmed[1], trimmed[2]
    local crew = { scene = scene, route = trimmed, index = 1, state = { phase = "loading" }, aheadMs = 0 }
    self.crews[scene.id] = crew
    local data = VehicleLoadingData.new()
    data:setFilename(Utils.getFilename(RseConfig.CREW_VEHICLE, RoadsideEmergencies.MOD_DIR))
    data:setPosition(a.x, nil, a.z, RseConfig.WRECK_HEIGHT)
    data:setRotation(0, math.atan2(b.x - a.x, b.z - a.z), 0)
    data:setPropertyState(VehiclePropertyState.MISSION)
    data:setOwnerFarmId(g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or 1)
    data:setIsSaved(false)
    data:load(self.onLoaded, self, crew)
    return true
end

-- what the power line needs to know: { underway, done, secondsLeft }, or nil when no crew was sent
function RseUtilityCrew:status(scene)
    local crew = self.crews[scene.id]
    if crew == nil then
        return nil
    end
    local phase = crew.state.phase
    return { underway = phase == "loading" or phase == "driving" or phase == "parked", done = phase == "done",
        secondsLeft = RseCrewRules.secondsLeft(crew.state, crew.distanceLeft or RseCrewRules.lengthFrom(crew.route, 1), RseConfig) }
end

function RseUtilityCrew:owns(vehicle)
    return vehicle ~= nil and self.byVehicle[vehicle] ~= nil
end

function RseUtilityCrew:onAheadRaycast(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 and self.rayCrew ~= nil then
        self.rayCrew.blocked = true
    end
    return false
end

-- something right in front: traffic, you, cones, the wreck. A ray from just ahead of the bumper, every CREW_AHEAD_CHECK_MS.
local function checkAhead(self, crew, node, dt)
    crew.aheadMs = crew.aheadMs - dt
    if crew.aheadMs > 0 then
        return
    end
    crew.aheadMs = RseConfig.CREW_AHEAD_CHECK_MS
    local vehicle = crew.vehicle
    local root = vehicle.rootNode or node -- the vehicle's size is measured from its root
    local size = vehicle.size or {}
    local front = (size.length or 5) / 2 + (size.lengthOffset or 0) + 0.3
    local x, y, z = localToWorld(root, 0, 1, front)
    local dx, dy, dz = localDirectionToWorld(root, 0, 0, 1)
    local mask = 0
    for _, name in ipairs({ "VEHICLE", "TRAFFIC_VEHICLE", "DYNAMIC_OBJECT", "PLAYER", "TREE" }) do
        mask = mask + (CollisionFlag[name] or 0)
    end
    crew.blocked = false
    self.rayCrew = crew
    raycastClosest(x, y, z, dx, dy, dz, RseConfig.CREW_AHEAD, "onAheadRaycast", self, mask)
    self.rayCrew = nil
end

local function holdStill(vehicle, dt)
    AIVehicleUtil.driveToPoint(vehicle, dt, 0, false, true, 0, 1, 0, true)
end

local function drive(self, crew, dt)
    local vehicle = crew.vehicle
    vehicle.forceIsActive = true
    if vehicle.getIsMotorStarted ~= nil and not vehicle:getIsMotorStarted() and vehicle.startMotor ~= nil then
        vehicle:startMotor(true)
    end
    if crew.showDriverInMs ~= nil then
        crew.showDriverInMs = crew.showDriverInMs - dt
        if crew.showDriverInMs <= 0 then
            crew.showDriverInMs = nil
            local character = vehicle.spec_enterable ~= nil and vehicle.spec_enterable.vehicleCharacter or nil
            if character ~= nil and character.setCharacterVisibility ~= nil then
                RseLog.try("the crew's driver", character.setCharacterVisibility, character, true)
            end
        end
    end
    local state = crew.state
    if state.phase ~= "driving" then
        holdStill(vehicle, dt)
        if state.phase == "parked" then
            if RseCrewRules.tick(state, dt, { distanceLeft = 0, speed = 0 }, RseConfig) == "done" then
                RseLog.info("county crew: the power is cut")
            end
        end
        return
    end
    local node = aiNode(vehicle)
    local x, y, z = getWorldTranslation(node)
    local point, index = RseCrewRules.target(crew.route, crew.index, x, z, RseConfig)
    crew.index = index
    local nextPoint = crew.route[math.min(#crew.route, index + 1)]
    crew.distanceLeft = math.sqrt((nextPoint.x - x) ^ 2 + (nextPoint.z - z) ^ 2) + RseCrewRules.lengthFrom(crew.route, index + 1)
    checkAhead(self, crew, node, dt)
    local lx, _, lz = worldToLocal(node, point.x, y, point.z)
    AIVehicleUtil.driveToPoint(vehicle, dt, 1, not crew.blocked, true, lx, lz, RseCrewRules.speedFor(crew.distanceLeft, RseConfig), false)
    local speed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    local event = RseCrewRules.tick(state, dt, { distanceLeft = crew.distanceLeft, speed = speed }, RseConfig)
    if event == "parked" then
        RseLog.info("county crew: parked %.0f m from the scene%s", math.sqrt((crew.scene.x - x) ^ 2 + (crew.scene.z - z) ^ 2),
            crew.distanceLeft > RseConfig.CREW_STOP_REACH and ", held up on the way" or "")
        RseText.notify(RseText.get("rse_crew_arrived"))
    elseif event == "failed" then
        RseLog.info("county crew: the truck never got moving; the timer cuts the power")
    end
end

local function removeCrew(self, crew)
    crew.removed = true
    local vehicle = crew.vehicle
    crew.vehicle = nil
    if vehicle ~= nil then
        self.byVehicle[vehicle] = nil
        if not vehicle.isDeleted then
            RseLog.try("remove the crew truck", vehicle.delete, vehicle)
        end
    end
end

-- every frame, on the server
function RseUtilityCrew:update(dt)
    for _, crew in pairs(self.crews) do
        if crew.vehicle ~= nil and not crew.vehicle.isDeleted then
            if not RseLog.try("drive the county crew", drive, self, crew, dt) then
                crew.state.phase = "failed"
                removeCrew(self, crew)
            end
        end
    end
    local px, pz = playerPosition()
    for i = #self.leaving, 1, -1 do
        local crew = self.leaving[i]
        crew.leftMs = crew.leftMs + dt
        local vehicle = crew.vehicle
        local far = vehicle == nil or vehicle.isDeleted or px == nil
        if not far then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            far = (x - px) ^ 2 + (z - pz) ^ 2 >= RseConfig.CREW_LEAVE_DISTANCE ^ 2
            if not far then
                RseLog.try("hold the crew truck", holdStill, vehicle, dt)
            end
        end
        if far or crew.leftMs >= RseConfig.CREW_LEAVE_MAX_MS then
            removeCrew(self, crew)
            table.remove(self.leaving, i)
        end
    end
end

-- the job is over: the crew truck stays until you have gone
function RseUtilityCrew:release(scene)
    local crew = self.crews[scene.id]
    if crew == nil then
        return
    end
    self.crews[scene.id] = nil
    if crew.vehicle == nil then
        crew.removed = true -- still loading: it goes as soon as it is there
        return
    end
    crew.leftMs = 0
    table.insert(self.leaving, crew)
end

function RseUtilityCrew:unload()
    for _, crew in pairs(self.crews) do
        removeCrew(self, crew)
    end
    for _, crew in ipairs(self.leaving) do
        removeCrew(self, crew)
    end
    self.crews, self.byVehicle, self.leaving, self.rayCrew = {}, {}, {}, nil
end
