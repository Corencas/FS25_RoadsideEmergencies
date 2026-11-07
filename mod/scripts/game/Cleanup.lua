-- Roadside Emergencies: what is left at a scene once its job is over, and the county clearing it away (Z: a job that fails must not clutter the map, and its
-- things go after a bit).
--   However a job ends (done, handed over, out of time, the train first, called off), what is left of it stays where it is for now, because vanishing in front
--     of you is unrealistic (Z). It goes once nobody is within CLEANUP_DISTANCE of the scene, CLEANUP_WAIT_MS at the soonest, and after CLEANUP_MAX_MS
--     anyway (RseLeftBehindRule.crewDue). Meanwhile it is nobody's job: no prompts, pins or markers, and our strap lets go.
--   What goes: the wreck and its bales, the job's logs, dead animals still lying there, live animals, the pen, the power line's poles and wires, the truck.
--   What stays with you: the scene kit (yours to pick up, Z), dead animals you loaded or strapped (they are yours, and the county bills you if you leave them
--     lying, LeftBehindRule), and the logs on your vehicle when you hand a logging job over early (Z).
--   A save in the meantime: of all this, the game keeps only the logs (our wrecks and bales are not saved, and the animals, the pen and the poles are ours),
--     so their places go in our save and are cleared after the load. The same goes for the logs of a saved job that can't come back.

RseCleanup = {
    items = {},  -- { x, z, label, wreck, logs = { node }, carcasses = { entry }, extras = { function }, waitMs, maxMs }
    pending = {} -- since a load: { x, z, logs = { { x, y, z } }, triesLeft, searchMs }, logs to find again before they are cleared
}

local function parts()
    return RsePowerLine.logs
end

-- what is left of a job, at its scene; filled in by each part of the job (leaveBehind), then handed to add
function RseCleanup.newItem(scene)
    return { x = scene.x, z = scene.z, label = tostring(scene.label), logs = {}, carcasses = {}, extras = {} }
end

local function isListed(entry)
    for _, candidate in ipairs(RseCarcasses.entries) do
        if candidate == entry then
            return true
        end
    end
    return false
end

-- waits for you to go, then clears it all. Nothing to clear: nothing waits.
function RseCleanup:add(item)
    for _, entry in ipairs(item.carcasses) do
        entry.crewTakes = true -- nobody's bill (Scenes.lua, updateLeftBehind), and not saved (Carcasses.lua)
    end
    if item.wreck ~= nil then
        RseWrecks:retire(item.wreck)
    end
    if item.wreck == nil and #item.logs == 0 and #item.carcasses == 0 and #item.extras == 0 then
        return
    end
    table.insert(self.items, item)
    RseLog.info("%s: what is left waits for the county: %s, %d log(s), %d dead animal(s)", item.label,
        item.wreck ~= nil and item.wreck.vehicle ~= nil and "the vehicle" or "no vehicle", #item.logs, #item.carcasses)
end

local function clearUp(item)
    if item.wreck ~= nil then
        RseWrecks:remove(item.wreck)
    end
    for _, node in ipairs(item.logs) do
        if parts().nodeExists(node) then
            parts().deleteLog(node)
        end
    end
    for _, entry in ipairs(item.carcasses) do
        if isListed(entry) then -- not taken to a drop-off point meanwhile
            RseCarcasses:remove(entry)
        end
    end
    for _, extra in ipairs(item.extras) do
        extra()
    end
end

-- the loose logs lying where these were saved, one each: the nearest within LOG_SAVED_NEAR. Never one that isn't where a log of the job was.
local function findLogs(saved)
    local L = parts()
    RsePowerLine.foundLogs, RsePowerLine.searchLine = {}, {}
    for _, place in ipairs(saved) do
        L.searchAround(RsePowerLine, place.x, place.y, place.z, RseConfig.LOG_SAVED_NEAR)
    end
    local nodes, found = {}, {}
    for node in pairs(RsePowerLine.foundLogs) do
        local x, y, z = getWorldTranslation(node)
        table.insert(nodes, node)
        table.insert(found, { x = x, y = y, z = z })
    end
    RsePowerLine.foundLogs, RsePowerLine.searchLine = nil, nil
    local match = RseLogRules.matchSaved(found, saved, RseConfig.LOG_SAVED_NEAR)
    local result = {}
    for i, node in ipairs(nodes) do
        if match[i] ~= nil and match[i].inPlace then
            table.insert(result, node)
        end
    end
    return result
end

local function findPending(self, dt)
    for i = #self.pending, 1, -1 do
        local item = self.pending[i]
        item.searchMs = item.searchMs - dt
        if item.searchMs <= 0 then
            item.searchMs = RseConfig.LINE_SEARCH_MS
            item.triesLeft = item.triesLeft - 1
            local ok, nodes = RseLog.try("find the logs a job left", findLogs, item.logs)
            nodes = ok and nodes or {}
            if #nodes >= #item.logs or item.triesLeft <= 0 then
                table.remove(self.pending, i)
                RseLog.info("logs a job left before the load: %d of %d found, cleared once nobody is near", #nodes, #item.logs)
                if #nodes > 0 then
                    table.insert(self.items, { x = item.x, z = item.z, label = "a job before the load", logs = nodes, carcasses = {}, extras = {} })
                end
            end
        end
    end
end

-- from RseScenes:update, job or no job
function RseCleanup:update(dt)
    if #self.pending > 0 then
        findPending(self, dt)
    end
    if #self.items == 0 then
        return
    end
    local px, pz = parts().playerPosition()
    for i = #self.items, 1, -1 do
        local item = self.items[i]
        local far = px == nil or (item.x - px) ^ 2 + (item.z - pz) ^ 2 >= RseConfig.CLEANUP_DISTANCE ^ 2
        if RseLeftBehindRule.crewDue(item, dt, far, RseConfig) then
            table.remove(self.items, i) -- first, so a failure can't repeat every moment
            RseLog.try("the county clears up", clearUp, item)
            RseLog.info("%s: the county has cleared up", item.label)
        end
    end
end

-- logs of a job that are back from the savegame and still to be cleared: found once the game has put them back. logs: { { x, y, z } }
function RseCleanup:findLater(x, z, logs)
    if logs ~= nil and #logs > 0 then
        table.insert(self.pending, { x = x, z = z, logs = logs, triesLeft = RseConfig.LINE_SEARCH_TRIES, searchMs = RseConfig.LINE_SEARCH_MS })
    end
end

-- from our save, as the map loads
function RseCleanup:restore(list)
    self.pending = {}
    for _, item in ipairs(list or {}) do
        self:findLater(item.x, item.z, item.logs)
    end
end

-- What the savegame keeps: the places of the logs, the one thing of a job the game saves itself. Logs not found again since the load are kept too.
function RseCleanup:saveData()
    local list = {}
    for _, item in ipairs(self.items) do
        local logs = {}
        for _, node in ipairs(item.logs) do
            if parts().nodeExists(node) then
                local x, y, z = getWorldTranslation(node)
                table.insert(logs, { x = x, y = y, z = z })
            end
        end
        if #logs > 0 then
            table.insert(list, { x = item.x, z = item.z, logs = logs })
        end
    end
    for _, item in ipairs(self.pending) do
        table.insert(list, { x = item.x, z = item.z, logs = item.logs })
    end
    return list
end

-- while the map unloads: whatever still waits goes now, while everything it needs is still there
function RseCleanup:unload()
    local items = self.items
    self.items, self.pending = {}, {}
    for _, item in ipairs(items) do
        RseLog.try("clear up as the map unloads", clearUp, item)
    end
end
