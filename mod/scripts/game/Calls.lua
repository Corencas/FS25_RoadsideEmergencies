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
    RseTwisterTravel:reset()
    RseToolSwitch:reset()
    RseLog.try("hook the twister", RseTwisterTravel.hook, RseTwisterTravel)
end

-- what the farm's vehicles can do: anything motorized can pull with a strap
local function fleetOf()
    local fleet = { canPull = false }
    local mission = g_currentMission
    local farm = mission.getFarmId ~= nil and mission:getFarmId() or 1
    for _, vehicle in ipairs(mission.vehicleSystem ~= nil and mission.vehicleSystem.vehicles or {}) do
        if vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farm and vehicle.propertyState ~= VehiclePropertyState.MISSION then
            fleet.canPull = fleet.canPull or vehicle.spec_motorized ~= nil
        end
    end
    return fleet
end

-- the context the planner needs right now
function RseCalls:context(store)
    local environment = g_currentMission.environment
    local disabled = RseJobRules.unavailable(RseConfig.EMERGENCIES, fleetOf())
    for _, emergency in ipairs(RseConfig.EMERGENCIES) do
        local allowed = store.settings.animalCalls
        if emergency.group == "wreck" then
            allowed = store.settings.wreckCalls
        end
        if not allowed then
            disabled[emergency.id] = true
        end
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
    local ok, reason = RseEpBridge.request(RseConfig.POOL_PREFIX .. id)
    if ok and self.state ~= nil then
        RseCallPlanner.reset(self.state)
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
        if store.settings.callsEnabled and store.settings.wreckCalls and self.twisterX ~= nil and not self:context(store).busy then
            RseScenes.spotNear = { x = self.twisterX, z = self.twisterZ, radius = RseConfig.STORM_ROAD_RANGE }
            local ok, reason = RseEpBridge.request(RseConfig.POOL_PREFIX .. "storm")
            RseLog.info("a twister ended at %.0f, %.0f: storm call %s", self.twisterX, self.twisterZ, ok and "placed" or tostring(reason))
            if ok then
                RseCallPlanner.reset(self.state)
            else
                RseScenes.spotNear = nil
            end
        end
    end
end

function RseCalls:update(dt, store)
    if self.state == nil or not g_currentMission:getIsServer() then
        return
    end
    watchTwister(self, store, dt)
    local id = RseCallPlanner.tick(self.state, dt, self:context(store), RseConfig, math.random)
    if id ~= nil then
        local ok, reason = RseEpBridge.request(RseConfig.POOL_PREFIX .. id)
        if not ok then
            RseLog.debug("dispatch call for '%s' not placed: %s", id, tostring(reason))
        end
    end
end
