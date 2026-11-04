-- Roadside Emergencies: our own file in the savegame folder (roadsideEmergencies.xml): settings, the player's points and
-- every carcass (with how long it has been left lying), every recovery strap on them, the scene kit items out in the world, and
-- the call in progress.
-- Written whenever the game saves (a hook appended to the career save, see install), read when the map loads.
-- Read data goes through RseSaveCodec, so a damaged file drops bad entries instead of breaking the game.

RseSaveLoad = {
    hook = nil
}

local ROOT = "roadsideEmergencies"

local function savePath(directory)
    if type(directory) ~= "string" or directory == "" then
        return nil
    end
    return directory .. "/" .. RseConfig.SAVE_FILENAME
end

-- a downed power line: its state, and three lists of places
local LINE_LISTS = { standing = { "x", "z" }, wire = { "x", "y", "z", "topX", "topY", "topZ" }, piece = { "x", "y", "z" } }
local LINE_LIST_FIELDS = { standing = "standing", wire = "wires", piece = "pieces" }
local LINE_POLE_FIELDS = { "poleX", "poleZ", "poleDirX", "poleDirZ" }

local function writeLine(xmlId, line)
    local base = ROOT .. ".scene.line"
    for _, field in ipairs({ "powerOff", "warned", "penalized", "poleIn" }) do
        setXMLBool(xmlId, base .. "#" .. field, line[field] == true)
    end
    for _, field in ipairs({ "liveMs", "insideMs", "yaw" }) do
        setXMLFloat(xmlId, base .. "#" .. field, line[field] or 0)
    end
    setXMLInt(xmlId, base .. "#wiresIn", math.floor(line.wiresIn or 0))
    for _, field in ipairs(LINE_POLE_FIELDS) do
        if line[field] ~= nil then
            setXMLFloat(xmlId, base .. "#" .. field, line[field])
        end
    end
    if line.splitType ~= nil then
        setXMLInt(xmlId, base .. "#splitType", line.splitType)
    end
    for name, fields in pairs(LINE_LISTS) do
        for i, item in ipairs(line[LINE_LIST_FIELDS[name]] or {}) do
            local key = string.format("%s.%s(%d)", base, name, i - 1)
            for _, field in ipairs(fields) do
                setXMLFloat(xmlId, key .. "#" .. field, item[field])
            end
        end
    end
end

local function readLine(xmlId)
    local base = ROOT .. ".scene.line"
    if not hasXMLProperty(xmlId, base) then
        return nil
    end
    local line = { wiresIn = getXMLInt(xmlId, base .. "#wiresIn"), splitType = getXMLInt(xmlId, base .. "#splitType") }
    for _, field in ipairs(LINE_POLE_FIELDS) do
        line[field] = getXMLFloat(xmlId, base .. "#" .. field)
    end
    for _, field in ipairs({ "powerOff", "warned", "penalized", "poleIn" }) do
        line[field] = getXMLBool(xmlId, base .. "#" .. field)
    end
    for _, field in ipairs({ "liveMs", "insideMs", "yaw" }) do
        line[field] = getXMLFloat(xmlId, base .. "#" .. field)
    end
    for name, fields in pairs(LINE_LISTS) do
        local list = {}
        local n = 0
        while hasXMLProperty(xmlId, string.format("%s.%s(%d)", base, name, n)) do
            local key = string.format("%s.%s(%d)", base, name, n)
            local item = {}
            for _, field in ipairs(fields) do
                item[field] = getXMLFloat(xmlId, key .. "#" .. field)
            end
            table.insert(list, item)
            n = n + 1
        end
        line[LINE_LIST_FIELDS[name]] = list
    end
    return line
end

function RseSaveLoad.write(directory, store, carcasses, straps, kit, scene)
    local path = savePath(directory)
    if path == nil then
        return false
    end
    local xmlId = createXMLFile("rseSave", path, ROOT)
    if xmlId == nil or xmlId == 0 then
        RseLog.problem("could not create %s", path)
        return false
    end
    setXMLInt(xmlId, ROOT .. "#version", RseConfig.SAVE_VERSION)
    setXMLFloat(xmlId, ROOT .. ".settings#feeFactor", store.settings.feeFactor)
    setXMLBool(xmlId, ROOT .. ".settings#calls", store.settings.callsEnabled)
    setXMLString(xmlId, ROOT .. ".settings#jobSize", store.settings.jobSize)
    setXMLBool(xmlId, ROOT .. ".settings#guideSeen", store.settings.guideSeen == true)
    for _, row in ipairs(RseSettings.ROWS) do
        if not row.legacy then
            setXMLString(xmlId, ROOT .. ".settings#" .. row.key, tostring(store.settings[row.key]))
        end
    end
    for i, point in ipairs(store.points:playerPoints()) do
        local key = string.format("%s.points.point(%d)", ROOT, i - 1)
        setXMLString(xmlId, key .. "#name", point.name)
        setXMLString(xmlId, key .. "#kind", point.kind)
        setXMLFloat(xmlId, key .. "#x", point.x)
        setXMLFloat(xmlId, key .. "#z", point.z)
    end
    for i, carcass in ipairs(carcasses) do
        local key = string.format("%s.carcasses.carcass(%d)", ROOT, i - 1)
        setXMLString(xmlId, key .. "#kind", carcass.kind)
        for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
            setXMLFloat(xmlId, key .. "#" .. field, carcass[field])
        end
        setXMLInt(xmlId, key .. "#leftMs", math.floor(carcass.leftMs or 0))
        setXMLInt(xmlId, key .. "#unearned", math.floor(carcass.unearned or 0))
        setXMLBool(xmlId, key .. "#scene", carcass.scene == true)
    end
    for i, strap in ipairs(straps or {}) do
        local key = string.format("%s.straps.strap(%d)", ROOT, i - 1)
        setXMLInt(xmlId, key .. "#carcass", strap.carcass)
        setXMLString(xmlId, key .. "#vehicle", strap.vehicle)
        setXMLInt(xmlId, key .. "#component", strap.component)
        for _, field in ipairs({ "hx", "hy", "hz", "vx", "vy", "vz", "length" }) do
            setXMLFloat(xmlId, key .. "#" .. field, strap[field])
        end
    end
    for i, item in ipairs(kit or {}) do
        local key = string.format("%s.kit.item(%d)", ROOT, i - 1)
        setXMLString(xmlId, key .. "#item", item.item)
        for _, field in ipairs({ "x", "y", "z", "yaw" }) do
            setXMLFloat(xmlId, key .. "#" .. field, item[field])
        end
        setXMLBool(xmlId, key .. "#owed", item.owed)
        setXMLBool(xmlId, key .. "#job", item.job == true)
    end
    if scene ~= nil then
        setXMLString(xmlId, ROOT .. ".scene#id", scene.id)
        setXMLString(xmlId, ROOT .. ".scene#label", tostring(scene.label))
        setXMLString(xmlId, ROOT .. ".scene#kinds", table.concat(scene.kinds or {}, " "))
        setXMLBool(xmlId, ROOT .. ".scene#arrived", scene.arrived == true)
        for _, field in ipairs({ "x", "y", "z" }) do
            setXMLFloat(xmlId, ROOT .. ".scene#" .. field, scene[field])
        end
        if scene.wreck ~= nil then
            setXMLInt(xmlId, ROOT .. ".scene#reward", math.floor(scene.reward or 0))
            setXMLInt(xmlId, ROOT .. ".scene#led", math.floor(scene.led or 0))
            setXMLInt(xmlId, ROOT .. ".scene#balesIn", math.floor(scene.balesIn or 0))
            setXMLString(xmlId, ROOT .. ".scene.wreck#kind", scene.wreck.kind)
            setXMLString(xmlId, ROOT .. ".scene.wreck#state", scene.wreck.state)
            setXMLBool(xmlId, ROOT .. ".scene.wreck#delivered", scene.wreck.delivered == true)
            if scene.wreck.load ~= nil then
                setXMLString(xmlId, ROOT .. ".scene.wreck#load", scene.wreck.load)
            end
            for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
                if scene.wreck[field] ~= nil then
                    setXMLFloat(xmlId, ROOT .. ".scene.wreck#" .. field, scene.wreck[field])
                end
            end
            for i, animal in ipairs(scene.survivors or {}) do
                local key = string.format("%s.scene.survivor(%d)", ROOT, i - 1)
                setXMLString(xmlId, key .. "#kind", animal.kind)
                for _, field in ipairs({ "x", "y", "z", "yaw" }) do
                    setXMLFloat(xmlId, key .. "#" .. field, animal[field])
                end
            end
            if scene.line ~= nil then
                writeLine(xmlId, scene.line)
            end
            for i, bale in ipairs(scene.wreck.bales or {}) do
                local key = string.format("%s.scene.wreck.bale(%d)", ROOT, i - 1)
                for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
                    setXMLFloat(xmlId, key .. "#" .. field, bale[field])
                end
            end
        end
    end
    saveXMLFile(xmlId)
    delete(xmlId)
    RseLog.debug("saved %d point(s) and %d carcass(es) to %s", #store.points:playerPoints(), #carcasses, path)
    return true
end

-- the raw data in the savegame folder, or nil (new game, or nothing saved yet)
function RseSaveLoad.read(directory)
    local path = savePath(directory)
    if path == nil or not fileExists(path) then
        return nil
    end
    local xmlId = loadXMLFile("rseSave", path)
    if xmlId == nil or xmlId == 0 then
        RseLog.problem("could not read %s", path)
        return nil
    end
    local raw = { version = getXMLInt(xmlId, ROOT .. "#version"), points = {}, carcasses = {}, straps = {}, kit = {},
        settings = { feeFactor = getXMLFloat(xmlId, ROOT .. ".settings#feeFactor"), callsEnabled = getXMLBool(xmlId, ROOT .. ".settings#calls"),
            jobSize = getXMLString(xmlId, ROOT .. ".settings#jobSize"), guideSeen = getXMLBool(xmlId, ROOT .. ".settings#guideSeen") } }
    local i = 0
    while true do
        local key = string.format("%s.points.point(%d)", ROOT, i)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        table.insert(raw.points, { name = getXMLString(xmlId, key .. "#name"), kind = getXMLString(xmlId, key .. "#kind"),
            x = getXMLFloat(xmlId, key .. "#x"), z = getXMLFloat(xmlId, key .. "#z") })
        i = i + 1
    end
    for _, row in ipairs(RseSettings.ROWS) do
        if not row.legacy then
            raw.settings[row.key] = getXMLString(xmlId, ROOT .. ".settings#" .. row.key)
        end
    end
    i = 0
    while true do
        local key = string.format("%s.carcasses.carcass(%d)", ROOT, i)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local carcass = { kind = getXMLString(xmlId, key .. "#kind") }
        for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
            carcass[field] = getXMLFloat(xmlId, key .. "#" .. field)
        end
        carcass.leftMs = getXMLInt(xmlId, key .. "#leftMs")
        carcass.unearned = getXMLInt(xmlId, key .. "#unearned")
        carcass.scene = getXMLBool(xmlId, key .. "#scene")
        table.insert(raw.carcasses, carcass)
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("%s.straps.strap(%d)", ROOT, i)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local strap = { carcass = getXMLInt(xmlId, key .. "#carcass"), vehicle = getXMLString(xmlId, key .. "#vehicle"),
            component = getXMLInt(xmlId, key .. "#component") }
        for _, field in ipairs({ "hx", "hy", "hz", "vx", "vy", "vz", "length" }) do
            strap[field] = getXMLFloat(xmlId, key .. "#" .. field)
        end
        table.insert(raw.straps, strap)
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("%s.kit.item(%d)", ROOT, i)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local item = { item = getXMLString(xmlId, key .. "#item"), owed = getXMLBool(xmlId, key .. "#owed"), job = getXMLBool(xmlId, key .. "#job") }
        for _, field in ipairs({ "x", "y", "z", "yaw" }) do
            item[field] = getXMLFloat(xmlId, key .. "#" .. field)
        end
        table.insert(raw.kit, item)
        i = i + 1
    end
    if hasXMLProperty(xmlId, ROOT .. ".scene") then
        raw.scene = { id = getXMLString(xmlId, ROOT .. ".scene#id"), label = getXMLString(xmlId, ROOT .. ".scene#label"),
            kinds = getXMLString(xmlId, ROOT .. ".scene#kinds"), arrived = getXMLBool(xmlId, ROOT .. ".scene#arrived") }
        for _, field in ipairs({ "x", "y", "z" }) do
            raw.scene[field] = getXMLFloat(xmlId, ROOT .. ".scene#" .. field)
        end
        if hasXMLProperty(xmlId, ROOT .. ".scene.wreck") then
            local wreck = { kind = getXMLString(xmlId, ROOT .. ".scene.wreck#kind"), state = getXMLString(xmlId, ROOT .. ".scene.wreck#state"),
                delivered = getXMLBool(xmlId, ROOT .. ".scene.wreck#delivered"), load = getXMLString(xmlId, ROOT .. ".scene.wreck#load"), bales = {} }
            for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
                wreck[field] = getXMLFloat(xmlId, ROOT .. ".scene.wreck#" .. field)
            end
            local n = 0
            while true do
                local key = string.format("%s.scene.wreck.bale(%d)", ROOT, n)
                if not hasXMLProperty(xmlId, key) then
                    break
                end
                local bale = {}
                for _, field in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
                    bale[field] = getXMLFloat(xmlId, key .. "#" .. field)
                end
                table.insert(wreck.bales, bale)
                n = n + 1
            end
            raw.scene.wreck = wreck
            raw.scene.line = readLine(xmlId)
            raw.scene.reward = getXMLInt(xmlId, ROOT .. ".scene#reward")
            raw.scene.led = getXMLInt(xmlId, ROOT .. ".scene#led")
            raw.scene.balesIn = getXMLInt(xmlId, ROOT .. ".scene#balesIn")
            raw.scene.survivors = {}
            n = 0
            while true do
                local key = string.format("%s.scene.survivor(%d)", ROOT, n)
                if not hasXMLProperty(xmlId, key) then
                    break
                end
                local animal = { kind = getXMLString(xmlId, key .. "#kind") }
                for _, field in ipairs({ "x", "y", "z", "yaw" }) do
                    animal[field] = getXMLFloat(xmlId, key .. "#" .. field)
                end
                table.insert(raw.scene.survivors, animal)
                n = n + 1
            end
        end
    end
    delete(xmlId)
    return raw
end

-- Appends onSave(target, ...) to the career save (FSCareerMissionInfo.saveToXMLFile; FSBaseMission.saveSavegame if that is
-- missing). It always wraps the stored original, so loading another savegame never stacks the hook; uninstall restores it.
-- Returns the hooked function's name for the log, or nil.
function RseSaveLoad.install(onSave)
    local target, className, name = nil, nil, nil
    if FSCareerMissionInfo ~= nil and type(FSCareerMissionInfo.saveToXMLFile) == "function" then
        target, className, name = FSCareerMissionInfo, "FSCareerMissionInfo", "saveToXMLFile"
    elseif FSBaseMission ~= nil and type(FSBaseMission.saveSavegame) == "function" then
        target, className, name = FSBaseMission, "FSBaseMission", "saveSavegame"
    end
    if target == nil then
        RseLog.problem("no savegame function found: carcasses and points won't be saved")
        return nil
    end
    local originalKey = "rseOriginal_" .. name
    if target[originalKey] == nil then
        target[originalKey] = target[name]
    end
    target[name] = Utils.appendedFunction(target[originalKey], function(object)
        RseLog.try("save Roadside Emergencies data", onSave, object)
    end)
    RseSaveLoad.hook = { target = target, name = name, wrapped = target[name] }
    return className .. "." .. name
end

function RseSaveLoad.uninstall()
    local hook = RseSaveLoad.hook
    if hook ~= nil and hook.target[hook.name] == hook.wrapped then
        hook.target[hook.name] = hook.target["rseOriginal_" .. hook.name]
    end
    RseSaveLoad.hook = nil
end
