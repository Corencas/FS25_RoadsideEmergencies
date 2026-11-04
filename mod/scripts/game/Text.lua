-- Roadside Emergencies: player-facing texts (translations/translation_en.xml, translation_de.xml).

RseText = {}

-- the text for key, formatted with any extra arguments
function RseText.get(key, ...)
    local text = g_i18n:getText(key)
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then
            return formatted
        end
    end
    return text
end

-- the animal's name, e.g. "cow"
function RseText.animal(kind)
    local entry = RseAnimalCatalog.get(kind)
    return entry ~= nil and g_i18n:getText(entry.textKey) or tostring(kind)
end

-- "1 minute", "5 minutes"
function RseText.minutes(count)
    if count == 1 then
        return RseText.get("rse_unit_minute")
    end
    return RseText.get("rse_unit_minutes", count)
end

-- a short message at the top of the screen
function RseText.notify(text, isProblem)
    local mission = g_currentMission
    if mission == nil or mission.addIngameNotification == nil or FSBaseMission == nil then
        return
    end
    local kind = isProblem and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_OK
    RseLog.try("addIngameNotification", mission.addIngameNotification, mission, kind or FSBaseMission.INGAME_NOTIFICATION_OK, text)
end
