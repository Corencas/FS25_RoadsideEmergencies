-- Roadside Emergencies: the link to the Emergency Pack (pdlc_emergencyPack): checks that the pack is there and read our
-- emergency folder (modDesc emergencyPack, API version 1), and asks it for one of our emergencies. The pack's own pager only
-- calls farms that own pack vehicles (P9), so our calls go through the pack's toggle message with one of our pools, the way
-- its own pager and console command start one (P7b); its pager then asks the player Yes/No.

RseEpBridge = {}

local function rolePlay()
    local instance = g_currentMission ~= nil and g_currentMission.rolePlay or nil
    return type(instance) == "table" and instance or nil
end

local function farmId()
    local mission = g_currentMission
    return mission.getFarmId ~= nil and mission:getFarmId() or 1
end

-- our scenarios in the pack's list
local function ourReferences(instance, modName)
    local list = {}
    for _, info in ipairs(type(instance.scenarioReferences) == "table" and instance.scenarioReferences or {}) do
        if type(info) == "table" and type(info.path) == "string" and string.find(info.path, modName, 1, true) ~= nil then
            table.insert(list, info)
        end
    end
    return list
end

-- logs what it finds; tells the player once if the pack is missing. Returns true when the pack is present.
function RseEpBridge.check(modName)
    local instance = rolePlay()
    if instance == nil then
        RseLog.info("Emergency Pack not found: emergencies need the free Emergency Pack DLC (carcass handling still works)")
        RseText.notify(RseText.get("rse_ep_missing"), true)
        return false
    end
    local thirdParty = type(instance.thirdPartyMods) == "table" and instance.thirdPartyMods or {}
    local registered = false
    for _, dir in ipairs(type(thirdParty.scenarioDirectories) == "table" and thirdParty.scenarioDirectories or {}) do
        if type(dir.path) == "string" and string.find(dir.path, modName, 1, true) ~= nil then
            registered = true
        end
    end
    local pools = {}
    for name, pool in pairs(type(instance.scenarioPools) == "table" and instance.scenarioPools or {}) do
        if type(name) == "string" and string.sub(name, 1, #RseConfig.POOL_PREFIX) == RseConfig.POOL_PREFIX then
            table.insert(pools, string.format("%s(%d)", name, type(pool) == "table" and #pool or 0))
        end
    end
    table.sort(pools)
    RseLog.info("Emergency Pack found (add-on API %s-%s); our emergency folder registered: %s; our scenarios: %d; steps defined: %s; pools: %s",
        tostring(thirdParty.minAPIVersion), tostring(thirdParty.maxAPIVersion), tostring(registered),
        #ourReferences(instance, modName), tostring(RseEpSteps.defined), table.concat(pools, " "))
    return true
end

-- Names (only) of the fields and functions of a pack object and its classes that contain `pattern`, for the log when
-- something we expect is missing (runtime inspection, approved: names only).
function RseEpBridge.namesLike(object, pattern)
    local names, seen = {}, {}
    local current, depth = object, 0
    while type(current) == "table" and depth < 6 do
        for key in pairs(current) do
            if type(key) == "string" and not seen[key] and string.find(string.lower(key), pattern, 1, true) ~= nil then
                seen[key] = true
                table.insert(names, key)
            end
        end
        local mt = getmetatable(current)
        current = type(mt) == "table" and mt.__index or nil
        depth = depth + 1
    end
    table.sort(names)
    return table.concat(names, " ")
end

-- the farm already has an emergency running (ours or the pack's)
function RseEpBridge.isBusy()
    local instance = rolePlay()
    return instance ~= nil and type(instance.runningScenarios) == "table" and instance.runningScenarios[farmId()] ~= nil
end

-- ends the farm's running emergency without pay (another contractor took over); its steps then clean up after themselves
function RseEpBridge.cancel()
    local instance = rolePlay()
    if instance == nil or type(instance.stopScenarioForFarm) ~= "function" then
        return false
    end
    return (RseLog.try("stop the emergency", instance.stopScenarioForFarm, instance, farmId()))
end

-- moves the pack's marker of this emergency (map marker and the pin in the world); doesn't change where the emergency is
function RseEpBridge.moveMarker(scenario, x, y, z)
    if type(scenario.updateMarker) == "function" then
        RseLog.try("move the marker", scenario.updateMarker, scenario, true, { x, y, z }, true)
    end
    local hotspot = scenario.mapHotspot
    if type(hotspot) == "table" and hotspot.setWorldPosition ~= nil then
        RseLog.try("move the marker position", hotspot.setWorldPosition, hotspot, x, z)
    end
end

-- Runs an emergency from `poolName` without the pager, for a saved call coming back after loading: what the pack does itself once
-- the player has answered Yes (P7b, FS25 names checked at runtime). Returns true when started, or false and a reason.
function RseEpBridge.resume(poolName)
    local instance = rolePlay()
    if instance == nil then
        return false, "no Emergency Pack"
    end
    if RseEpBridge.isBusy() then
        return false, "busy"
    end
    local pool = type(instance.scenarioPools) == "table" and instance.scenarioPools[poolName] or nil
    local info = type(pool) == "table" and pool[1] or nil
    if type(info) ~= "table" or info.id == nil or type(instance.pendingScenarios) ~= "table" then
        return false, "no emergency in pool " .. tostring(poolName)
    end
    local farm = farmId()
    local ok, scenario = RseLog.try("load the saved emergency", instance.loadScenarioByInfoId, instance, info.id, farm)
    if not ok or scenario == nil then
        return false, "the pack did not load it"
    end
    instance.pendingScenarios[farm] = scenario
    if not RseLog.try("start the saved emergency", instance.startStopScenarioForFarm, instance, farm, info.id, true) then
        return false, "the pack did not start it"
    end
    RseLog.info("asked the Emergency Pack to run the saved emergency from pool '%s' again", poolName)
    return true
end

-- Asks the pack to page the player with an emergency from `poolName`. Returns true when asked, or false and a reason.
function RseEpBridge.request(poolName)
    local instance = rolePlay()
    local env = _G[RseConfig.EP_ENV_NAME]
    if instance == nil or type(env) ~= "table" then
        return false, "no Emergency Pack"
    end
    if RseEpBridge.isBusy() then
        return false, "busy"
    end
    local pool = type(instance.scenarioPools) == "table" and instance.scenarioPools[poolName] or nil
    if type(pool) ~= "table" or #pool == 0 then
        return false, "no pool " .. tostring(poolName)
    end
    local messages = env.ScenarioMessageType
    if type(messages) ~= "table" or messages.SCENARIO_TOGGLE == nil or instance.messageCenter == nil then
        return false, "the pack's toggle message is missing"
    end
    local ok = RseLog.try("ask the Emergency Pack for a call", instance.messageCenter.publish, instance.messageCenter,
        messages.SCENARIO_TOGGLE, farmId(), poolName, true)
    if not ok then
        return false, "the pack refused (see log)"
    end
    RseLog.info("asked the Emergency Pack for an emergency from pool '%s'", poolName)
    return true
end
