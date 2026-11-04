-- Roadside Emergencies: console commands (prefix rse) for testing and debugging. Listed in the README.

RseConsole = {
    owner = nil
}

local COMMANDS = {
    { "rseHelp", "List the Roadside Emergencies console commands", "consoleHelp" },
    { "rseDebug", "Turn debug logging on or off", "consoleDebug" },
    { "rseStart", "rseStart [emergency]: dispatch calls now (an animal, wreck, rollover, trailer, livestock, powerline or storm; none: a random one)",
        "consoleStart" },
    { "rseCalls", "rseCalls [on|off]: show or switch the calls that come by themselves", "consoleCalls" },
    { "rseScene", "Log the emergency scenes and where each animal is (in the road, at the roadside, loaded)", "consoleScene" },
    { "rseRoad", "Log the road where you stand (lanes found, distance, direction)", "consoleRoad" },
    { "rseJobSize", "rseJobSize [small|normal|large|random]: show or set how much work a call is (how many animals)", "consoleJobSize" },
    { "rseLoad", "rseLoad [small|big|random]: test: which bales a spilled load has", "consoleLoad" },
    { "rseHere", "rseHere [metres]: test: the next call comes from a road this close to you (default 60), for instance on a bridge", "consoleHere" },
    { "rseKit", "Log the scene kit items in the world; rseKit clear removes all of them", "consoleKit" },
    { "rseMarkers", "rseMarkers [on|off]: show or switch the map markers", "consoleMarkers" },
    { "rseCarcass", "rseCarcass [animal] [count]: place dead animals 6 m ahead (deer, boar, pig, sheep, goat, cow, buffalo, horse)", "consoleCarcass" },
    { "rseCarcassClear", "Remove every carcass", "consoleCarcassClear" },
    { "rseLive", "Test: rseLive [animal] puts a loose animal 6 m ahead, and the log says its model and clips; rseLive clear removes them", "consoleLive" },
    { "rseTwister", "Test: spawn the game's twister (spring and summer only); when it ends, a storm call comes from a road nearby", "consoleTwister" },
    { "rseExpireSoon", "rseExpireSoon [seconds]: test: the job you haven't reached goes to another contractor sooner (default in 30 s)", "consoleExpireSoon" },
    { "rseLeftSoon", "rseLeftSoon [seconds]: test: collect and bill the carcasses left lying in that many seconds (default 30)", "consoleLeftSoon" },
    { "rseCarcassBodies", "Show or hide the hidden carcass bodies (debug)", "consoleCarcassBodies" },
    { "rsePoints", "List the disposal and recovery points", "consolePoints" },
    { "rsePointAdd", "rsePointAdd [disposal|recovery|both] [name]: a point where you stand", "consolePointAdd" },
    { "rsePointRemove", "rsePointRemove <id>: remove one of your points", "consolePointRemove" },
    { "rseFee", "rseFee [factor]: show or set the factor on disposal fees and collection bills (0 to 5)", "consoleFee" },
    { "rseState", "Log everything the mod tracks", "consoleState" }
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

-- "1 carcass", "2 carcasses"
local function counted(count, singular, plural)
    return string.format("%d %s", count, count == 1 and singular or plural)
end

-- a point `distance` ahead of the player on foot, and the direction across their view
local function ahead(distance)
    if g_localPlayer == nil or g_localPlayer:getCurrentVehicle() ~= nil then
        return nil
    end
    local x, _, z = g_localPlayer:getPosition()
    local dirX, dirZ = g_localPlayer:getCurrentFacingDirection()
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 0.001 then
        return nil
    end
    dirX, dirZ = dirX / length, dirZ / length
    return { x = x + dirX * distance, z = z + dirZ * distance, rightX = dirZ, rightZ = -dirX, yaw = math.atan2(dirX, dirZ) }
end

function RseConsole:consoleCarcass(kindArg, countArg)
    local def = RseAnimalCatalog.get(kindArg or "deer")
    if def == nil then
        return "Unknown animal. Animals: " .. table.concat(RseAnimalCatalog.kinds(), ", ")
    end
    local frame = ahead(6)
    if frame == nil then
        return "Get out of the vehicle first"
    end
    local count = math.max(1, math.min(tonumber(countArg) or 1, 8))
    local spacing = def.body == RseAnimalCatalog.BODY_LARGE and 2 or 1.2
    local spawned, reason = 0, nil
    for i = 1, count do
        local side = (i - (count + 1) / 2) * spacing
        local entry
        entry, reason = RseCarcasses:spawn(def.kind, frame.x + frame.rightX * side, nil, frame.z + frame.rightZ * side, 0,
            frame.yaw + math.pi / 2, 0)
        if entry == nil then
            break
        end
        spawned = spawned + 1
    end
    if spawned == 0 then
        return "No carcass: " .. tostring(reason)
    end
    return string.format("Placed %s 6 m ahead (%s)", counted(spawned, "dead animal", "dead animals"), RseText.animal(def.kind))
end

function RseConsole:consoleCarcassClear()
    local count = #RseCarcasses.entries
    RseCarcasses:clear()
    return "Removed " .. counted(count, "carcass", "carcasses")
end

function RseConsole:consoleLive(arg)
    if arg == "clear" then
        RseSurvivors:clearTest()
        return "The test animals are gone"
    end
    local def = RseAnimalCatalog.get(arg or "sheep")
    if def == nil or def.subType == nil then
        return "Use a farm animal: sheep, pig, goat, cow, buffalo or horse"
    end
    local frame = ahead(6)
    if frame == nil then
        return "Get out of the vehicle first"
    end
    return counted(RseSurvivors:spawnTest(def.kind, frame.x, frame.z, frame.yaw), "test animal", "test animals") .. " out (see log.txt)"
end

function RseConsole:consoleTwister()
    local environment = g_currentMission.environment
    local weather = environment ~= nil and environment.weather or nil
    if weather == nil or weather.consoleCommandWeatherTwisterSpawn == nil then
        return "The weather has no twister spawn function"
    end
    local ok, result = RseLog.try("spawn a twister", weather.consoleCommandWeatherTwisterSpawn, weather)
    if not ok then
        return "No twister (see log.txt)"
    end
    local twister = weather.twister
    local spawned = type(twister) == "table" and twister.isSpawned == true
    RseLog.info("rseTwister: '%s'; day %s, season %s; twister up: %s", tostring(result), tostring(environment.currentDay),
        tostring(environment.currentSeason), tostring(spawned))
    local season = environment.currentSeason
    if not spawned and Season ~= nil and (season == Season.AUTUMN or season == Season.WINTER) then
        return "Twister: " .. tostring(result) .. ". It is autumn or winter, and the game only has twisters in spring and summer. "
            .. "Try again then. rseStart storm starts the storm job at any time."
    end
    return "Twister: " .. tostring(result)
end

function RseConsole:consoleExpireSoon(secondsArg)
    local state = RseEpSteps.waiting
    if state == nil or RseScenes:activeCount() == 0 then
        return "No job on its way: accept one first, and stay away from it"
    end
    local seconds = math.max(0, tonumber(secondsArg) or 30)
    state.waitMs = math.max(0, RseConfig.JOB_EXPIRE_MS - seconds * 1000)
    return string.format("Another contractor takes over in %d s, unless you get there first", seconds)
end

function RseConsole:consoleLeftSoon(secondsArg)
    local seconds = math.max(0, tonumber(secondsArg) or 30)
    local count = 0
    for _, entry in ipairs(RseCarcasses.entries) do
        if entry.sceneId == nil then
            entry.left = entry.left or {}
            entry.left.leftMs = math.max(0, RseConfig.LEFT_COLLECT_MS - seconds * 1000)
            count = count + 1
        end
    end
    return string.format("%s will be collected in %d s of play with you more than %d m away, if still left lying", counted(count, "carcass", "carcasses"),
        seconds, RseConfig.LEFT_PLAYER_DISTANCE)
end

function RseConsole:consoleCarcassBodies()
    RseCarcasses.showBodies = not RseCarcasses.showBodies
    return RseCarcasses.showBodies and "Carcass bodies shown" or "Carcass bodies hidden"
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
        end
        return "No call: " .. tostring(reason)
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

function RseConsole:consoleScene()
    local count = 0
    for _, scene in pairs(RseScenes.scenes) do
        count = count + 1
        local counts = RseScenes:counts(scene)
        RseLog.info("scene %d (%s) at %.1f, %.1f: %d road segment(s); in the road %d, verge %d, loaded %d, towed away %d, gone %d",
            scene.id, tostring(scene.label), scene.x, scene.z, #scene.segments, counts.onRoad, counts.verge, counts.loaded,
            counts.away, counts.gone)
        if scene.wreck ~= nil then
            RseLog.info("  wreck %s: state %s, delivered %s, %d bale(s), %d live animal(s), pay $%d", scene.wreck.kind, scene.wreck.state,
                tostring(scene.wreck.delivered), #scene.wreck.bales, RseSurvivors:remaining(scene), scene.reward or 0)
        end
        for _, entry in ipairs(scene.entries) do
            local node = RseCarcasses:bodyNode(entry)
            if node ~= nil then
                local x, _, z = getWorldTranslation(node)
                RseLog.info("  carcass %d: %s at %.1f, %.1f, %s, %.1f m from the nearest lane", entry.id, entry.kind, x, z,
                    tostring(entry.sceneStatus), RseRoadClearRule.distanceToRoad(x, z, scene.segments) or -1)
            end
        end
    end
    local waiting = 0
    for _, entry in ipairs(RseCarcasses.entries) do
        if entry.left ~= nil and (entry.left.leftMs or 0) > 0 then
            waiting = waiting + 1
            RseLog.info("carcass %d (%s): left behind; the county collects and bills it in %.0f s (while nobody is within %d m)", entry.id, entry.kind,
                (RseConfig.LEFT_COLLECT_MS - entry.left.leftMs) / 1000, RseConfig.LEFT_PLAYER_DISTANCE)
        end
    end
    return string.format("%s, %s left behind (see log.txt)", counted(count, "scene", "scenes"), counted(waiting, "carcass", "carcasses"))
end

function RseConsole:consoleRoad()
    if g_localPlayer == nil then
        return "No player"
    end
    local x, _, z = g_localPlayer:getPosition()
    local ok, road = RseLog.try("measure the road", RseRoads.around, x, z, RseConfig.ROAD_SEARCH_RADIUS)
    if not ok or road == nil then
        return "Could not measure the road (see log.txt)"
    end
    local distance = RseRoadClearRule.distanceToRoad(x, z, road.segments)
    RseLog.info("road at %.1f, %.1f: %d lane(s), %d segment(s), nearest lane centre %s m, direction %s", x, z, road.lanes,
        #road.segments, distance ~= nil and string.format("%.1f", distance) or "-",
        road.dirX ~= nil and string.format("%.2f, %.2f", road.dirX, road.dirZ) or "-")
    if distance == nil then
        return "No road lane within " .. RseConfig.ROAD_SEARCH_RADIUS .. " m"
    end
    local verdict = distance >= RseConfig.CLEAR_DISTANCE and "off the road" or "in the road"
    return string.format("%s near; the nearest lane center is %.1f m away; a carcass here counts as %s", counted(road.lanes, "lane", "lanes"),
        distance, verdict)
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

function RseConsole:consoleLoad(arg)
    if arg == "small" or arg == "big" then
        RseScenes.forcedLoad = arg
    elseif arg == "random" then
        RseScenes.forcedLoad = nil
    end
    return "Spilled loads: " .. tostring(RseScenes.forcedLoad or "random")
end

function RseConsole:consoleHere(arg)
    if g_localPlayer == nil then
        return "You are not in the world yet"
    end
    local x, _, z = g_localPlayer:getPosition()
    local radius = tonumber(arg) or 60
    RseScenes.spotNear = { x = x, z = z, radius = radius }
    return string.format("The next call comes from a road within %d m of here, at least %d m from you", radius, RseConfig.SPOT_PLAYER_CLEAR)
end

function RseConsole:consoleKit(arg)
    if arg == "clear" then
        local count = #RseKit.entries
        RseKit:clear()
        return "Removed " .. counted(count, "scene kit item", "scene kit items")
    end
    RseKit:logBlockers()
    for _, item in ipairs(RseKit:saveData()) do
        RseLog.info("kit: %s at %.1f, %.1f%s", item.item, item.x, item.z, item.owed and " (to pick up)" or "")
    end
    return string.format("%s, %d to pick up (see log.txt)", counted(#RseKit.entries, "scene kit item", "scene kit items"), RseKit:owedCount())
end

function RseConsole:consoleMarkers(arg)
    if arg == "on" or arg == "off" then
        self.owner.store:apply("setSetting", { key = "markersEnabled", value = arg == "on" })
    elseif arg ~= nil then
        return "Use rseMarkers on or rseMarkers off"
    end
    return "Map markers: " .. (RseMarkers.enabled and "on" or "off")
end

function RseConsole:consoleState()
    RseLog.info("state: %d carcass(es), %d strap(s)%s, %d point(s), fee factor %.2f, bodies: %s, calls %s, %d scene(s), pack busy: %s",
        #RseCarcasses.entries, #RseStrap.straps, RseStrap.holding ~= nil and " (one in hand)" or "", #self.owner.store.points:list(),
        self.owner.store.settings.feeFactor, RseCarcasses.usingFallbackBodies and "straw fallback" or "own bale type",
        self.owner.store.settings.callsEnabled and "on" or "off", RseScenes:activeCount(), tostring(RseEpBridge.isBusy()))
    for _, entry in ipairs(RseCarcasses.entries) do
        local node = RseCarcasses:bodyNode(entry)
        local x, _, z = 0, 0, 0
        if node ~= nil then
            x, _, z = getWorldTranslation(node)
        end
        RseLog.info("carcass %d: %s at %.1f, %.1f%s%s%s", entry.id, entry.kind, x, z, entry.dragged and " dragged" or "",
            RseStrap:isStrapped(entry) and " strapped" or "", RseCarcasses:isMounted(entry) and " held by a machine" or "")
    end
    return "State logged (see log.txt)"
end
