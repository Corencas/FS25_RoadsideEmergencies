-- Roadside Emergencies: checks and cleans the data read from our savegame file. Engine-free.
-- Raw data (as read from XML): { version, settings = { feeFactor, callsEnabled, jobSize, and the rest of RseSettings.ROWS }, points = { { name, kind, x, z } },
-- carcasses = { { kind, x, y, z, rx, ry, rz, leftMs, unearned, scene } } (leftMs: time left lying; unearned: pay taken back if the
-- county collects it; scene: part of the call in progress),
-- straps = { { carcass, vehicle, component, hx, hy, hz, vx, vy, vz, length } } } (carcass: its number in the carcass list;
-- vehicle: the vehicle's unique id; h*: hook point on the carcass body, v*: point on that vehicle component, both local),
-- kit = { { item, x, y, z, yaw, owed, job } } (scene kit items in the world; job: placed for the call in progress),
-- scene = { id, label, x, y, z, kinds, arrived, wreck, reward } (the call in progress, which comes back after loading; kinds: its animals,
-- space-separated; arrived: the player had reached it;
-- wreck: { kind, state, x, y, z, rx, ry, rz, delivered, bales = { { x, y, z, rx, ry, rz } } }, survivors = { { kind, x, y, z, yaw } };
-- reward: a wreck job's pay, fixed when it began; led: live animals already loaded; balesIn: bales already brought in).
-- Bad entries are dropped with a warning instead of breaking the load.

RseSaveCodec = {}

-- a saved power line, or nil: only places with all their numbers
local function normalizeLine(line)
    if type(line) ~= "table" then
        return nil
    end
    local function places(list, fields)
        local result = {}
        for _, item in ipairs(type(list) == "table" and list or {}) do
            local place = {}
            local whole = true
            for _, field in ipairs(fields) do
                place[field] = tonumber(item[field])
                whole = whole and place[field] ~= nil
            end
            if whole then
                table.insert(result, place)
            end
        end
        return result
    end
    return { powerOff = line.powerOff == true, warned = line.warned == true, penalized = line.penalized == true, poleIn = line.poleIn == true,
        liveMs = math.max(0, tonumber(line.liveMs) or 0), insideMs = math.max(0, tonumber(line.insideMs) or 0), yaw = tonumber(line.yaw) or 0,
        wiresIn = math.max(0, math.floor(tonumber(line.wiresIn) or 0)), standing = places(line.standing, { "x", "z" }),
        wires = places(line.wires, { "x", "y", "z", "topX", "topY", "topZ" }), pieces = places(line.pieces, { "x", "y", "z" }),
        poleX = tonumber(line.poleX), poleZ = tonumber(line.poleZ), poleDirX = tonumber(line.poleDirX), poleDirZ = tonumber(line.poleDirZ),
        splitType = tonumber(line.splitType) }
end

function RseSaveCodec.normalize(raw, config)
    local data = { version = config.SAVE_VERSION, settings = {}, points = {}, carcasses = {}, straps = {}, kit = {} }
    local warnings = {}
    if type(raw) ~= "table" then
        data.settings.feeFactor = config.FEE_FACTOR_DEFAULT
        data.settings.callsEnabled = config.CALLS_ENABLED_DEFAULT
        data.settings.jobSize = config.JOB_SIZE_DEFAULT
        RseSettings.fillDefaults(data.settings)
        return data, warnings
    end
    local version = tonumber(raw.version)
    if version ~= nil and version > config.SAVE_VERSION then
        table.insert(warnings, string.format("save file version %d is newer than this mod (%d)", version, config.SAVE_VERSION))
    end
    local settings = type(raw.settings) == "table" and raw.settings or {}
    data.settings.feeFactor = RsePayRules.clampFactor(settings.feeFactor, config)
    if type(settings.callsEnabled) == "boolean" then
        data.settings.callsEnabled = settings.callsEnabled
    else
        data.settings.callsEnabled = config.CALLS_ENABLED_DEFAULT
    end

    data.settings.jobSize = RseSceneSpec.SIZES[settings.jobSize] and settings.jobSize or config.JOB_SIZE_DEFAULT
    data.settings.guideSeen = settings.guideSeen == true
    for _, row in ipairs(RseSettings.ROWS) do
        if not row.legacy then
            data.settings[row.key] = RseSettings.parse(row, settings[row.key])
        end
    end

    for i, point in ipairs(type(raw.points) == "table" and raw.points or {}) do
        local x, z = tonumber(point.x), tonumber(point.z)
        if x ~= nil and z ~= nil then
            local kind = RsePointRegistry.KINDS[point.kind] and point.kind or "both"
            local name = (type(point.name) == "string" and point.name ~= "") and point.name or ("Point " .. i)
            table.insert(data.points, { name = name, kind = kind, x = x, z = z })
        else
            table.insert(warnings, string.format("point %d has no position; dropped", i))
        end
    end

    local scene = type(raw.scene) == "table" and raw.scene or {}
    local sceneX, sceneY, sceneZ = tonumber(scene.x), tonumber(scene.y), tonumber(scene.z)
    local sceneValid = type(scene.id) == "string" and scene.id ~= "" and sceneX ~= nil and sceneY ~= nil and sceneZ ~= nil
    if sceneValid then
        local kinds = {}
        for kind in string.gmatch(type(scene.kinds) == "string" and scene.kinds or "", "%S+") do
            if RseAnimalCatalog.get(kind) ~= nil then
                table.insert(kinds, kind)
            end
        end
        data.scene = { id = scene.id, label = scene.label, x = sceneX, y = sceneY, z = sceneZ, kinds = kinds, arrived = scene.arrived == true }
        if type(scene.wreck) == "table" and config.WRECKS[scene.wreck.kind] ~= nil then
            local wreck = { kind = scene.wreck.kind, state = scene.wreck.state, delivered = scene.wreck.delivered == true, bales = {},
                load = type(scene.wreck.load) == "string" and scene.wreck.load or nil }
            for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
                wreck[field] = tonumber(scene.wreck[field])
            end
            for _, bale in ipairs(type(scene.wreck.bales) == "table" and scene.wreck.bales or {}) do
                if tonumber(bale.x) ~= nil and tonumber(bale.y) ~= nil and tonumber(bale.z) ~= nil then
                    table.insert(wreck.bales, { x = tonumber(bale.x), y = tonumber(bale.y), z = tonumber(bale.z), rx = tonumber(bale.rx) or 0,
                        ry = tonumber(bale.ry) or 0, rz = tonumber(bale.rz) or 0 })
                end
            end
            data.scene.wreck = wreck
            data.scene.line = normalizeLine(scene.line)
            local reward = tonumber(scene.reward)
            data.scene.reward = reward ~= nil and reward > 0 and reward or nil
            data.scene.led = math.max(0, math.floor(tonumber(scene.led) or 0))
            data.scene.balesIn = math.max(0, math.floor(tonumber(scene.balesIn) or 0))
            data.scene.survivors = {}
            for _, animal in ipairs(type(scene.survivors) == "table" and scene.survivors or {}) do
                if RseAnimalCatalog.get(animal.kind) ~= nil and tonumber(animal.x) ~= nil and tonumber(animal.y) ~= nil and tonumber(animal.z) ~= nil then
                    table.insert(data.scene.survivors, { kind = animal.kind, x = tonumber(animal.x), y = tonumber(animal.y), z = tonumber(animal.z),
                        yaw = tonumber(animal.yaw) or 0 })
                end
            end
        end
    end

    local carcassIndex = {} -- number in the raw list -> number in the cleaned list
    for i, carcass in ipairs(type(raw.carcasses) == "table" and raw.carcasses or {}) do
        local entry = RseAnimalCatalog.get(carcass.kind)
        local x, y, z = tonumber(carcass.x), tonumber(carcass.y), tonumber(carcass.z)
        if carcass.scene == true and not sceneValid then
            table.insert(warnings, string.format("carcass %d belonged to a call that is gone; dropped", i))
        elseif entry ~= nil and x ~= nil and y ~= nil and z ~= nil then
            local leftMs = math.max(0, math.min(tonumber(carcass.leftMs) or 0, config.LEFT_COLLECT_MS))
            table.insert(data.carcasses, { leftMs = leftMs, unearned = math.max(0, tonumber(carcass.unearned) or 0), kind = entry.kind,
                x = x, y = y, z = z, rx = tonumber(carcass.rx) or 0,
                ry = tonumber(carcass.ry) or 0, rz = tonumber(carcass.rz) or 0, scene = carcass.scene == true })
            carcassIndex[i] = #data.carcasses
        else
            table.insert(warnings, string.format("carcass %d (%s) is incomplete; dropped", i, tostring(carcass.kind)))
        end
    end

    for i, strap in ipairs(type(raw.straps) == "table" and raw.straps or {}) do
        local index = carcassIndex[tonumber(strap.carcass) or -1]
        local values, complete = {}, true
        for _, field in ipairs({ "hx", "hy", "hz", "vx", "vy", "vz", "length" }) do
            values[field] = tonumber(strap[field])
            complete = complete and values[field] ~= nil
        end
        if index ~= nil and type(strap.vehicle) == "string" and strap.vehicle ~= "" and complete then
            values.carcass = index
            values.vehicle = strap.vehicle
            values.component = math.max(1, math.floor(tonumber(strap.component) or 1))
            values.length = math.max(config.STRAP_MIN_LENGTH, math.min(values.length, config.STRAP_MAX_LENGTH))
            table.insert(data.straps, values)
        else
            table.insert(warnings, string.format("strap %d is incomplete or its carcass is gone; dropped", i))
        end
    end

    local kitItems = {}
    for _, item in ipairs(config.KIT_ITEMS) do
        kitItems[item.id] = true
    end
    for i, item in ipairs(type(raw.kit) == "table" and raw.kit or {}) do
        local x, y, z = tonumber(item.x), tonumber(item.y), tonumber(item.z)
        if kitItems[item.item] and x ~= nil and y ~= nil and z ~= nil then
            -- without its call to come back to, an item placed for it is simply owed
            local job = item.job == true and sceneValid
            table.insert(data.kit, { item = item.item, x = x, y = y, z = z, yaw = tonumber(item.yaw) or 0, job = job,
                owed = item.owed == true or (item.job == true and not sceneValid) })
        else
            table.insert(warnings, string.format("kit item %d (%s) is incomplete; dropped", i, tostring(item.item)))
        end
    end
    return data, warnings
end
