-- Roadside Emergencies: console commands (prefix rse). Listed in the README.

RseConsole = {
    owner = nil
}

local COMMANDS = {
    { "rseHelp", "List the Roadside Emergencies console commands", "consoleHelp" },
    { "rseDebug", "Turn debug logging on or off", "consoleDebug" },
    { "rseStart", "rseStart [emergency]: dispatch a call now (deer, boar, pig, sheep, goat, cow, horse, buffalo, wreck, rollover, trailer, livestock, "
        .. "powerline, logging, crossing, river, tree, flock or storm; none: any)", "consoleStart" },
    { "rseCalls", "rseCalls [on|off]: show or switch the calls that come by themselves", "consoleCalls" },
    { "rseJobSize", "rseJobSize [small|normal|large|random]: show or set how much work a call is (how many animals)", "consoleJobSize" },
    { "rseMarkers", "rseMarkers [on|off]: show or switch the map markers", "consoleMarkers" },
    { "rsePoints", "List the disposal and recovery points", "consolePoints" },
    { "rsePointAdd", "rsePointAdd [disposal|recovery|both] [name]: a point where you stand", "consolePointAdd" },
    { "rsePointRemove", "rsePointRemove <id>: remove one of your points", "consolePointRemove" },
    { "rseFee", "rseFee [factor]: show or set the factor on disposal fees and collection bills (0 to 5)", "consoleFee" },
    { "rseWelcome", "Show the welcome dialog again", "consoleWelcome" }
}

function RseConsole:register(owner)
    self.owner = owner
    for _, command in ipairs(COMMANDS) do
        addConsoleCommand(command[1], command[2], command[3], self)
    end
end

function RseConsole:unregister()
    for _, command in ipairs(COMMANDS) do
        removeConsoleCommand(command[1])
    end
end

function RseConsole:consoleHelp()
    for _, command in ipairs(COMMANDS) do
        RseLog.info("%-17s %s", command[1], command[2])
    end
    return "Roadside Emergencies commands listed in log.txt"
end

function RseConsole:consoleDebug()
    RseLog.debugEnabled = not RseLog.debugEnabled
    return "Debug logging " .. (RseLog.debugEnabled and "on" or "off")
end

-- "1 point", "2 points"
local function counted(count, singular, plural)
    return string.format("%d %s", count, count == 1 and singular or plural)
end

function RseConsole:consolePoints()
    local px, pz = nil, nil
    if g_localPlayer ~= nil then
        local x, _, z = g_localPlayer:getPosition()
        px, pz = x, z
    end
    for _, point in ipairs(self.owner.store.points:list()) do
        local distance = px ~= nil and math.sqrt((point.x - px) ^ 2 + (point.z - pz) ^ 2) or -1
        RseLog.info("point %d: %s (%s, %s) at %.1f, %.1f, %.0f m from you", point.id, point.name, point.kind, point.source,
            point.x, point.z, distance)
    end
    return counted(#self.owner.store.points:list(), "point", "points") .. " listed in log.txt"
end

function RseConsole:consolePointAdd(kindArg, ...)
    if g_localPlayer == nil then
        return "No player"
    end
    local kind = kindArg or "disposal"
    if not RsePointRegistry.KINDS[kind] then
        return "Kind must be disposal, recovery or both"
    end
    local name = table.concat({ ... }, " ")
    if name == "" then
        name = RseText.get("rse_point_player", #self.owner.store.points:playerPoints() + 1)
    end
    local x, _, z = g_localPlayer:getPosition()
    local id, reason = self.owner.store:apply("addPoint", { name = name, kind = kind, x = x, z = z, source = "player" })
    if id == nil then
        return "Not added: " .. tostring(reason)
    end
    RsePoints:refreshHotspots()
    return string.format("Point %d '%s' (%s) added where you stand", id, name, kind)
end

function RseConsole:consolePointRemove(idArg)
    local point, reason = self.owner.store:apply("removePoint", { id = tonumber(idArg) })
    if point == nil then
        return "Not removed: " .. tostring(reason)
    end
    RsePoints:refreshHotspots()
    return string.format("Point '%s' removed", point.name)
end

function RseConsole:consoleFee(factorArg)
    local store = self.owner.store
    if factorArg == nil then
        return string.format("Fee factor %.2f (a cow: disposal fee $%d)", store.settings.feeFactor,
            RsePayRules.disposalFee(RseAnimalCatalog.get("cow").massKg, store.settings.feeFactor, RseConfig))
    end
    return string.format("Fee factor set to %.2f", store:apply("setFeeFactor", { factor = factorArg }))
end

function RseConsole:consoleStart(idArg)
    local id = nil
    if idArg ~= nil then
        local known = {}
        for _, emergency in ipairs(RseConfig.EMERGENCIES) do
            table.insert(known, emergency.id)
            if emergency.id == string.lower(idArg) then
                id = emergency.id
            end
        end
        if id == nil then
            return "Unknown emergency. Emergencies: " .. table.concat(known, ", ")
        end
    end
    local ok, reason, picked = RseCalls:request(self.owner.store, id)
    if not ok then
        if reason == "busy" then
            return "You already have an emergency running (finish it, or cancel it in the pack's menu)"
        elseif reason == "kit" then
            return string.format("No new job: pick up your cones and barricades from the last one first (%d left)", RseKit:owedCount())
        elseif reason == "searching" then
            return string.format("No call yet: the mod is still searching this map for places for the %s call. That takes a minute or two after loading, "
                .. "so try again then", id)
        end
        return "No call: " .. tostring(reason)
    end
    if reason == "wait" then
        return "The crossing call comes when the train is the right time away, within about one lap of the track: a few minutes. Keep playing"
    end
    if RseCalls:outOfReach()[picked] then
        return string.format("County dispatch is calling (%s), only because you asked: your farm couldn't finish this one, so it would never come by itself",
            tostring(picked))
    end
    return string.format("County dispatch is calling (%s): answer the pager", tostring(picked))
end

function RseConsole:consoleCalls(arg)
    local store = self.owner.store
    if arg == "on" or arg == "off" then
        store:apply("setCallsEnabled", { enabled = arg == "on" })
    elseif arg ~= nil then
        return "Use rseCalls on or rseCalls off"
    end
    return "Calls from county dispatch: " .. (store.settings.callsEnabled and "on" or "off")
end

function RseConsole:consoleJobSize(arg)
    if arg ~= nil then
        local size, reason = self.owner.store:apply("setJobSize", { size = arg })
        if size == nil then
            return "Not set: " .. tostring(reason)
        end
    end
    return "Job size: " .. self.owner.store.settings.jobSize
end

function RseConsole:consoleMarkers(arg)
    if arg == "on" or arg == "off" then
        self.owner.store:apply("setSetting", { key = "markersEnabled", value = arg == "on" })
    elseif arg ~= nil then
        return "Use rseMarkers on or rseMarkers off"
    end
    return "Map markers: " .. (RseMarkers.enabled and "on" or "off")
end

function RseConsole:consoleWelcome()
    RsePlayerFile:forgetWelcome()
    local ok, shown = RseLog.try("the welcome dialog", RseWelcome.show, RseWelcome)
    return ok and shown and "Welcome dialog shown" or "The welcome dialog could not be shown: see log.txt"
end
