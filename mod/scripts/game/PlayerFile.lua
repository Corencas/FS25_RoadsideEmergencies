-- Roadside Emergencies: what belongs to you as a player rather than to one savegame, in the game's modSettings folder, where mods keep such files:
-- your last settings, which a new savegame starts with (P10, Z at Gate U), and whether you have seen the welcome dialog.
-- Written at every save (and when the welcome closes); read as a map loads.

RsePlayerFile = {
    data = nil -- { settings = raw settings or nil, welcomeSeen }
}

local ROOT = "roadsideEmergenciesPlayer"

local function folder()
    return getUserProfileAppPath() .. "modSettings/" .. RoadsideEmergencies.MOD_NAME
end

local function path()
    return folder() .. "/player.xml"
end

function RsePlayerFile:read()
    self.data = { settings = nil, welcomeSeen = false }
    local file = path()
    if not fileExists(file) then
        return self.data
    end
    local xmlId = loadXMLFile("rsePlayer", file)
    if xmlId == nil or xmlId == 0 then
        RseLog.problem("could not read %s", file)
        return self.data
    end
    self.data.welcomeSeen = getXMLBool(xmlId, ROOT .. ".welcome#seen") == true
    if hasXMLProperty(xmlId, ROOT .. ".settings") then
        self.data.settings = RseSaveLoad.readSettings(xmlId, ROOT .. ".settings")
    end
    delete(xmlId)
    return self.data
end

-- settings: the store's settings, or nil to keep what the file has
function RsePlayerFile:write(settings)
    self.data = self.data or { welcomeSeen = false }
    if settings ~= nil then
        self.data.current = settings
    end
    createFolder(getUserProfileAppPath() .. "modSettings")
    createFolder(folder())
    local xmlId = createXMLFile("rsePlayer", path(), ROOT)
    if xmlId == nil or xmlId == 0 then
        RseLog.problem("could not write %s", path())
        return false
    end
    setXMLBool(xmlId, ROOT .. ".welcome#seen", self.data.welcomeSeen == true)
    local current = self.data.current or self.data.settings -- before the first save: what the file had
    if current ~= nil then
        RseSaveLoad.writeSettings(xmlId, ROOT .. ".settings", current)
    end
    saveXMLFile(xmlId)
    delete(xmlId)
    return true
end

function RsePlayerFile:welcomeSeen()
    return self.data ~= nil and self.data.welcomeSeen == true
end

function RsePlayerFile:setWelcomeSeen()
    self.data = self.data or { welcomeSeen = false }
    if self.data.welcomeSeen then
        return
    end
    self.data.welcomeSeen = true
    RseLog.try("write the player file", self.write, self, nil)
end

-- shows the welcome again (rseWelcome): forgets that it was seen
function RsePlayerFile:forgetWelcome()
    self.data = self.data or {}
    self.data.welcomeSeen = false
end
