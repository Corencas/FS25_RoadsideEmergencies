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

-- logs what it finds. Returns true when the pack is present.
function RseEpBridge.check(modName)
    local instance = rolePlay()
    if instance == nil then
        RseLog.info("Emergency Pack not found: emergencies need the free Emergency Pack DLC (carcass handling still works)")
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

-- Z: the pack has to be impossible to miss, and a notice at load went unseen. So: a dialog the player has to answer, on every load without the pack.
function RseEpBridge.tellMissing()
    local text = RseText.get("rse_ep_missing")
    if type(InfoDialog) ~= "table" or type(InfoDialog.show) ~= "function" or not RseLog.try("show the missing pack dialog", InfoDialog.show, text) then
        RseText.notify(text, true)
    end
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
    RseLog.try("fill in the hints' keys", RseEpBridge.fillHints)
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

-- The pack reads an emergency's description from its text key as it loads the emergency for the pager. So for one call, our own text says more: the fields
-- of the call's plan (CallPlan.lua), one a line under what happened. U0 showed the pager keeps line breaks. Every mod has its own g_i18n, so the pack
-- doesn't see ours. The tables that can hold our text: our own, the game's, and the game's for our mod. Which one the pack reads isn't readable, so every
-- one that already holds the key; no other text is touched.
local function tablesHolding(key)
    local root = _G.g_i18n
    local environments = type(root) == "table" and root.modEnvironments or nil
    local holders = { g_i18n, root, type(environments) == "table" and environments[RoadsideEmergencies.MOD_NAME] or nil }
    local found, seen = {}, {}
    for i = 1, 3 do
        local texts = type(holders[i]) == "table" and holders[i].texts or nil
        if type(texts) == "table" and not seen[texts] and type(texts[key]) == "string" then
            seen[texts] = true
            table.insert(found, texts)
        end
    end
    return found
end

-- The pack reads each step's hint from our texts itself, so a {key:...} in one reached the screen as it was written (Z: "{key:RSE_STRAP}" on the hint
-- line). Before the pack loads a call, every hint of ours with {...} in it is filled in, in each text table that holds it, from the text as written (kept in
-- RseText.templates), so a key changed since shows too.
local function fillHints()
    local own = g_i18n ~= nil and g_i18n.texts or nil
    if type(own) ~= "table" then
        return
    end
    for key, text in pairs(own) do
        if type(key) == "string" and string.find(key, "^rse_") and string.find(key, "hint", 1, true) and type(text) == "string" then
            local template = RseText.templates[key]
            if template == nil and string.find(text, "{", 1, true) then
                template = text
                RseText.templates[key] = template
            end
            if template ~= nil then
                local filled = RseText.expand(template)
                for _, texts in ipairs(tablesHolding(key)) do
                    texts[key] = filled
                end
            end
        end
    end
end

RseEpBridge.fillHints = fillHints

local function restorePagerText()
    for _, entry in ipairs(RseEpBridge.pagerChanged or {}) do
        entry.texts[entry.key] = entry.base
    end
    RseEpBridge.pagerChanged = nil
end

local function setPagerText(key, text)
    restorePagerText()
    local changed = {}
    for _, texts in ipairs(tablesHolding(key)) do
        table.insert(changed, { texts = texts, key = key, base = texts[key] })
        texts[key] = text
    end
    RseEpBridge.pagerChanged = changed
    RseEpBridge.pagerBase = changed[1] ~= nil and changed[1].base or nil
end

function RseEpBridge.unload()
    restorePagerText()
    RseEpBridge.pagerText, RseEpBridge.pagerShort, RseEpBridge.pagerBase, RseEpBridge.pagerCheckMs = nil, nil, nil, nil
end

-- A moment after a call: our text goes back to what it was, and did the fields reach the emergency the pager asks about? If they did, the emergency's own copy
-- goes back to the short description too, so what the pack shows after the pager is one line again. If not, the player still has to know before saying yes,
-- so the vehicle and what it takes go on the screen, and the log names the fields to look at.
function RseEpBridge.checkPager(dt)
    if RseEpBridge.pagerCheckMs == nil then
        return
    end
    RseEpBridge.pagerCheckMs = RseEpBridge.pagerCheckMs - dt
    if RseEpBridge.pagerCheckMs > 0 then
        return
    end
    RseEpBridge.pagerCheckMs = nil
    restorePagerText()
    local full, short, base = RseEpBridge.pagerText, RseEpBridge.pagerShort, RseEpBridge.pagerBase
    RseEpBridge.pagerText, RseEpBridge.pagerShort, RseEpBridge.pagerBase = nil, nil, nil
    local instance = rolePlay()
    local farm = farmId()
    local pending = instance ~= nil and type(instance.pendingScenarios) == "table" and instance.pendingScenarios[farm] or nil
    local scenario = pending or (instance ~= nil and type(instance.runningScenarios) == "table" and instance.runningScenarios[farm]) or nil
    local text = type(scenario) == "table" and scenario.description or nil
    if type(text) == "string" and string.find(text, full, 1, true) ~= nil then
        RseLog.info("the pager has the call's fields: %s", (full:gsub("\n", " | ")))
        if base ~= nil then
            scenario.description = base
        end
    else
        RseLog.info("the pager's text wasn't where we looked, so what it takes goes on the screen. "
            .. "Emergency, fields like 'descr': %s. Game's text table, fields like 'text': %s",
            type(scenario) == "table" and RseEpBridge.namesLike(scenario, "descr") or "no emergency found", RseEpBridge.namesLike(_G.g_i18n, "text"))
        if short ~= nil then
            RseText.notify(short, true)
        end
    end
end

-- Asks the pack to page the player with an emergency from `poolName`. Returns true when asked, or false and a reason.
-- pagerKey, pagerText: the emergency's description key, and the whole text the pager shows this time (nil: its own); pagerShort: what to show on the screen
-- instead if the pager turns out not to carry it.
function RseEpBridge.request(poolName, pagerKey, pagerText, pagerShort)
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
    restorePagerText()
    RseLog.try("fill in the hints' keys", fillHints)
    RseEpBridge.pagerText, RseEpBridge.pagerShort, RseEpBridge.pagerBase, RseEpBridge.pagerCheckMs = nil, nil, nil, nil
    if pagerText ~= nil and pagerKey ~= nil then
        RseLog.try("write the pager's text", setPagerText, pagerKey, pagerText)
        RseEpBridge.pagerText, RseEpBridge.pagerShort, RseEpBridge.pagerCheckMs = pagerText, pagerShort, RseConfig.PAGER_CHECK_MS
    end
    local ok = RseLog.try("ask the Emergency Pack for a call", instance.messageCenter.publish, instance.messageCenter,
        messages.SCENARIO_TOGGLE, farmId(), poolName, true)
    if not ok then
        RseEpBridge.unload()
        return false, "the pack refused (see log)"
    end
    RseLog.info("asked the Emergency Pack for an emergency from pool '%s'", poolName)
    return true
end
