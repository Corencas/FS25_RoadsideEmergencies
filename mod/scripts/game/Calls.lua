-- Roadside Emergencies: county dispatch calls the player now and then (living-world trigger, DESIGN F20). RseCallPlanner
-- decides when and what from play time, the hour and the season; this file feeds it the game state and asks the pack for
-- the call (RseEpBridge.request). The player answers Yes/No in the pack's pager; No costs nothing.

RseCalls = {
    state = nil
}

local function isAutumn()
    local environment = g_currentMission.environment
    return environment ~= nil and Season ~= nil and Season.AUTUMN ~= nil and environment.currentSeason == Season.AUTUMN
end

function RseCalls:init()
    self.state = RseCallPlanner.newState(RseConfig)
    self.crossingWaitMs = nil
    self.fleetNow, self.fleetMs = nil, 0
    RseTwisterTravel:reset()
    RseToolSwitch:reset()
    RseRiver:reset()
    RseFlockPlaces:reset()
    RseLog.try("hook the twister", RseTwisterTravel.hook, RseTwisterTravel)
end

-- Asks the pack for this call, planned first (CallPlan.lua): the pager says what happened, where, what it takes, a vehicle of yours that can, the time and
-- the pay (Z: you must know before you say yes). A call that needs a special place and has none doesn't come.
local function askPack(id)
    local ok, plan, why = RseLog.try("plan the call", RseCallPlan.make, RseCallPlan, id)
    if ok and plan == nil and why ~= nil then
        return false, why
    end
    plan = ok and plan or nil
    return RseEpBridge.request(RseConfig.POOL_PREFIX .. id, "rse_ep_" .. id .. "_description", plan ~= nil and plan.text or nil,
        plan ~= nil and plan.short or nil)
end

-- A tool that lifts a bale: the game's bale grabs and bale loaders, the forks and spears that go on a front loader, telehandler, wheel loader or skid steer,
-- and a forklift. The same part on a trailer only holds a load down, so that doesn't count.
local LIFT_JOINTS = { "frontloader", "telehandler", "wheelLoader", "skidSteer" }

local function liftsBales(vehicle)
    if vehicle.spec_baleGrab ~= nil or vehicle.spec_baleLoader ~= nil or vehicle.spec_universalAutoload ~= nil then
        return true
    end
    if vehicle.spec_dynamicMountAttacher == nil then
        return false
    end
    if vehicle.spec_motorized ~= nil then
        return true
    end
    if vehicle.getInputAttacherJoints == nil or AttacherJoints == nil or AttacherJoints.jointTypeNameToInt == nil then
        return false
    end
    for _, joint in ipairs(vehicle:getInputAttacherJoints() or {}) do
        for _, name in ipairs(LIFT_JOINTS) do
            if joint.jointType ~= nil and joint.jointType == AttacherJoints.jointTypeNameToInt[name] then
                return true
            end
        end
    end
    return false
end

-- Can this livestock trailer carry what a crash's loose animals are? A horse trailer can't take cattle (Z). If the game won't say, it counts, as it
-- always did, and the log says why.
local function carriesCrashAnimals(vehicle)
    local ok, carries = RseLog.try("see what a livestock trailer carries", RseSurvivors.carriesAny, vehicle, RseConfig.WRECKS.livestock.kinds)
    return not ok or carries == true
end

local function machineOf(vehicle)
    local belts = vehicle.spec_tensionBelts
    local named, name = false, nil
    if vehicle.getFullName ~= nil then
        named, name = pcall(vehicle.getFullName, vehicle)
    end
    return {
        name = named and type(name) == "string" and name or nil, -- for the pager's "You have"

        motorized = vehicle.spec_motorized ~= nil,
        mass = vehicle.getTotalMass ~= nil and vehicle:getTotalMass(true) or 0,
        lifts = liftsBales(vehicle),
        carries = vehicle.spec_trailer ~= nil or vehicle.spec_baleLoader ~= nil or vehicle.spec_universalAutoload ~= nil
            or (belts ~= nil and belts.hasTensionBelts == true),
        livestockTrailer = vehicle.spec_livestockTrailer ~= nil and carriesCrashAnimals(vehicle)
    }
end

-- every vehicle you own or lease; not those that belong to a job or a contract
local function scanFleet()
    local machines = {}
    local mission = g_currentMission
    local farm = mission.getFarmId ~= nil and mission:getFarmId() or 1
    for _, vehicle in ipairs(mission.vehicleSystem ~= nil and mission.vehicleSystem.vehicles or {}) do
        if vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farm and vehicle.propertyState ~= VehiclePropertyState.MISSION
            and not RseWrecks.everWreck[vehicle] then
            table.insert(machines, machineOf(vehicle))
        end
    end
    return RseJobRules.fleetFrom(machines, RseConfig)
end

-- What the farm has right now. It can't be read? Then dispatch assumes nothing: a call it can't be sure of doesn't come.
function RseCalls:fleet()
    if self.fleetNow == nil or (self.fleetMs or 0) <= 0 then
        self.fleetMs = RseConfig.FLEET_CHECK_MS
        local ok, fleet = RseLog.try("look over the farm's vehicles", scanFleet)
        self.fleetNow = ok and fleet or RseJobRules.fleetFrom({}, RseConfig)
    end
    return self.fleetNow
end

-- the calls dispatch would not make to this farm, whatever the settings say: { id = true }
function RseCalls:outOfReach()
    return RseJobRules.unavailable(RseConfig.EMERGENCIES, self:fleet(), RseConfig)
end

-- the context the planner needs right now
function RseCalls:context(store)
    local environment = g_currentMission.environment
    local disabled = self:outOfReach()
    for _, emergency in ipairs(RseConfig.EMERGENCIES) do
        local allowed = store.settings.animalCalls
        if emergency.group == "wreck" then
            allowed = store.settings.wreckCalls
        end
        if not allowed then
            disabled[emergency.id] = true
        end
    end
    if not RseLevelCrossing:canOffer(false, self.lastDt) then
        disabled.crossing = true
    end
    if not RseRiver:canOffer() then
        disabled.river = true
    end
    if not RseFlockPlaces:canOffer() then
        disabled.flock = true
    end
    return {
        enabled = store.settings.callsEnabled,
        -- no new job before the cones are in
        busy = RseEpBridge.isBusy() or RseScenes:activeCount() > 0 or RseScenes:isResuming() or RseKit:owedCount() > 0,
        hour = environment ~= nil and environment.currentHour or nil,
        isAutumn = isAutumn(),
        disabled = disabled
    }
end

-- asks for the emergency with this id (an animal: "deer", "cow", ...) or for a weighted pick when id is nil
function RseCalls:request(store, id)
    if RseKit:owedCount() > 0 then
        return false, "kit"
    end
    if RseScenes:isResuming() then
        return false, "busy"
    end
    if id == nil then
        id = RseCallPlanner.pick(RseCallPlanner.weights(self:context(store), RseConfig), math.random())
    end
    if id == nil then
        return false, "no emergency switched on"
    end
    if id == "crossing" then
        if RseEpBridge.isBusy() then
            return false, "busy"
        end
        if not RseLevelCrossing:canOffer(true) then
            return false, "no crossing within reach, or the train is rented"
        end
        self.crossingWaitMs = RseConfig.CROSSING_WAIT_MS
        RseLevelCrossing:chooseNext()
        if self.state ~= nil then
            RseCallPlanner.noteCall(self.state, id, RseConfig)
        end
        return true, "wait", id
    end
    -- the scan takes a minute or two after a load (50 to 95 seconds on save 19), and a reviewer types rseStart straight away
    if (id == "river" and RseRiver:isSearching()) or (id == "flock" and RseFlockPlaces:isSearching()) then
        return false, "searching"
    end
    if id == "river" and not RseRiver:canOffer() then
        return false, "this map has no shallow water with a gentle bank beside a road"
    end
    if id == "flock" and not RseFlockPlaces:canOffer() then
        return false, "this map has no road through open country with a meadow beside it for a pen"
    end
    local ok, reason = askPack(id)
    if ok and self.state ~= nil then
        RseCallPlanner.noteCall(self.state, id, RseConfig)
    end
    return ok, reason, id
end

-- A twister that has just ended brings a storm call from a road nearby (DESIGN F17): position and state are readable (P9b).
local function watchTwister(self, store, dt)
    local environment = g_currentMission.environment
    local weather = environment ~= nil and environment.weather or nil
    local twister = weather ~= nil and weather.twister or nil
    if type(twister) ~= "table" then
        return
    end
    if twister.isSpawned and (twister.fadeValue or 1) > 0 then
        RseTwisterTravel:update(twister, dt)
        local x, z = RseTwisterTravel:position()
        self.twisterX, self.twisterZ = x or twister.sendPosX, z or twister.sendPosZ
        self.twisterSeen = true
    elseif self.twisterSeen then
        self.twisterSeen = false
        RseTwisterTravel:finish()
        local wanted = store.settings.callsEnabled and store.settings.wreckCalls and self.twisterX ~= nil
        if wanted and not self:context(store).busy and not self:outOfReach().storm then
            RseScenes.spotNear = { x = self.twisterX, z = self.twisterZ, radius = RseConfig.STORM_ROAD_RANGE }
            local ok, reason = askPack("storm")
            RseLog.info("a twister ended at %.0f, %.0f: storm call %s", self.twisterX, self.twisterZ, ok and "placed" or tostring(reason))
            if ok then
                RseCallPlanner.noteCall(self.state, "storm", RseConfig)
            else
                RseScenes.spotNear = nil
            end
        end
    end
end

-- The crossing call waits until the train is the right time away from the crossing chosen for it (RseCrossingRules.isMoment): at most about a lap.
local function waitForCrossing(self, store, dt)
    self.crossingWaitMs = self.crossingWaitMs - dt
    local context = self:context(store)
    if self.crossingWaitMs <= 0 or context.busy or context.disabled.crossing then
        self.crossingWaitMs = nil
        RseLog.debug("the crossing call won't come now")
    elseif RseLevelCrossing:isMoment() then
        self.crossingWaitMs = nil
        local ok, reason = askPack("crossing")
        if not ok then
            RseLog.debug("dispatch call for the crossing not placed: %s", tostring(reason))
        end
    end
end

function RseCalls:update(dt, store)
    if self.state == nil or not g_currentMission:getIsServer() then
        return
    end
    self.lastDt = dt
    self.fleetMs = (self.fleetMs or 0) - dt
    RseRiver:update()
    RseFlockPlaces:update()
    RseEpBridge.checkPager(dt)
    RseEpBridge.ring(dt, store ~= nil and store.settings.pagerSound ~= false)
    watchTwister(self, store, dt)
    if self.crossingWaitMs ~= nil then
        RseLog.try("wait for the crossing call", waitForCrossing, self, store, dt)
        return
    end
    local id = RseCallPlanner.tick(self.state, dt, self:context(store), RseConfig, math.random)
    if id == "crossing" then
        self.crossingWaitMs = RseConfig.CROSSING_WAIT_MS
        RseLevelCrossing:chooseNext()
    elseif id ~= nil then
        local ok, reason = askPack(id)
        if not ok then
            RseLog.debug("dispatch call for '%s' not placed: %s", id, tostring(reason))
        end
    end
end
