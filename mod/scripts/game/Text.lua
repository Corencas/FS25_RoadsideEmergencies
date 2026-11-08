-- Roadside Emergencies: player-facing texts (translations/translation_en.xml, translation_de.xml).

RseText = {
    keySource = nil -- how key names are read: "game" or "defaults", logged once
}

-- The key bound to one of our actions, as the game names it, or our default key if the game can't say. Texts carry {key:RSE_STRAP} instead of a letter,
-- so a rebound key reads right (Z, Gate U).
function RseText.keyName(actionName)
    local display = g_inputDisplayManager
    local key = nil
    if type(display) == "table" and type(display.getKeyboardInputActionKey) == "function" then
        local ok, name = pcall(display.getKeyboardInputActionKey, display, actionName)
        key = ok and type(name) == "string" and name ~= "" and name or nil
    end
    local source = key ~= nil and "game" or "defaults"
    if RseText.keySource ~= source then
        RseText.keySource = source
        RseLog.info("key names in texts come from the %s", source == "game" and "game's bindings" or "default keys (the game gave none)")
    end
    return key or RseConfig.KEY_DEFAULTS[actionName] or actionName
end

-- an amount of money as the game writes one in a sentence (its own "buy this building for ..." dialog): the player's currency, with separators
function RseText.money(amount)
    local ok, text = pcall(g_i18n.formatMoney, g_i18n, amount or 0, 0, true)
    return ok and text or tostring(math.floor((amount or 0) + 0.5))
end

-- a mass in tonnes, as the game writes a bale's: "3 t", "80 kg", in every unit setting, because the game does
function RseText.mass(tonnes)
    local ok, text = pcall(g_i18n.formatMass, g_i18n, tonnes or 0)
    return ok and text or string.format("%g t", tonnes or 0)
end

-- a distance in metres, as the game writes one: feet in an imperial game
function RseText.distance(metres)
    local ok, text = pcall(g_i18n.formatDistance, g_i18n, metres or 0)
    return ok and text or string.format("%.0f m", metres or 0)
end

-- An "about" distance (the pager's Where): rounded in the units the player reads, so it doesn't look exact (Z's pager said "about 1527 m"). Metres to 50
-- under a kilometre and to 100 above; feet to 100 under 3,000 and to 500 above. The game's own formatter writes it (the units setting as U0 read it).
function RseText.aboutDistance(metres)
    local miles = false
    if g_gameSettings ~= nil and GameSettings ~= nil and GameSettings.SETTING ~= nil and GameSettings.SETTING.USE_MILES ~= nil then
        local ok, value = pcall(g_gameSettings.getValue, g_gameSettings, GameSettings.SETTING.USE_MILES)
        miles = ok and value == true
    end
    local value = metres or 0
    if miles then
        local feet = value * 3.28084
        local step = feet < 3000 and 100 or 500
        value = math.max(step, math.floor(feet / step + 0.5) * step) / 3.28084
    else
        local step = value < 1000 and 50 or 100
        value = math.max(step, math.floor(value / step + 0.5) * step)
    end
    return RseText.distance(value)
end

-- the texts with {...} in them, as written, once the pack's copies have been filled in (EpBridge.lua, fillHints): RseText.get reads these, so a key you
-- change later still shows
RseText.templates = {}

-- the {key:ACTION}, {mass:N} (tonnes) and {distance:N} (metres) in a text, filled in as the game writes them
local function expand(text)
    if type(text) ~= "string" or string.find(text, "{", 1, true) == nil then
        return text
    end
    text = string.gsub(text, "{key:([%w_]+)}", function(name)
        return RseText.keyName(name)
    end)
    text = string.gsub(text, "{mass:([%d%.]+)}", function(value)
        return RseText.mass(tonumber(value))
    end)
    text = string.gsub(text, "{distance:([%d%.]+)}", function(value)
        return RseText.distance(tonumber(value))
    end)
    return text
end

RseText.expand = expand

-- the text for key, formatted with any extra arguments
function RseText.get(key, ...)
    local text = expand(RseText.templates[key] or g_i18n:getText(key))
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

-- a line of ours in the F1 help, always starting with "RSE: " and kept short (Z: lines are cut off at about 20 characters)
function RseText.action(key, ...)
    return RseTheme.F1_PREFIX .. RseText.get(key, ...)
end

-- the animal's short name, for an F1 line: "boar", "buffalo"
function RseText.animalShort(kind)
    return RseText.get("rse_animalShort_" .. tostring(kind))
end

-- the animal's name on its own, capitalized: "Deer", "Water buffalo" (Z: the box you see looking at one)
function RseText.animalName(kind)
    return RseText.get("rse_animalName_" .. tostring(kind))
end

-- the animal counted, for the fill display and the pager: "Deer" or "Cow" for one, "Deer" or "Cows" for more (Z: "3 Deer", not "3pieces"). A language
-- whose rule (rse_plural_rule, RsePlural) has a form for 2 to 4 has rse_unit_<animal>_few as well; one that doesn't falls back to _many.
function RseText.animalUnit(kind, count)
    local base = "rse_unit_" .. tostring(kind)
    local form = RsePlural.form(g_i18n:getText("rse_plural_rule"), count or 0)
    if form == "few" and not g_i18n:hasText(base .. "_few") then
        form = "many"
    end
    return RseText.get(base .. "_" .. form)
end

-- the animals named on their own, with no number before them (the call panel's title, "Cows on the road"): the form after a number, except in a
-- language where the plain plural differs (Russian "5 коров", but "Коровы на дороге"), which has rse_unit_<animal>_plural for it
function RseText.animalTitle(kind, count)
    local plural = "rse_unit_" .. tostring(kind) .. "_plural"
    if (count or 0) > 1 and g_i18n:hasText(plural) then
        return RseText.get(plural)
    end
    return RseText.animalUnit(kind, count)
end

-- "1 minute", "5 minutes"
function RseText.minutes(count)
    if count == 1 then
        return RseText.get("rse_unit_minute")
    end
    return RseText.get("rse_unit_minutes", count)
end

-- a short message at the top of the screen; a warning carries the warning mark as well as the game's warning colour (Z: the colour alone looks like our
-- orange titles)
function RseText.notify(text, isProblem)
    if isProblem and type(text) == "string" then
        text = RseText.get("rse_warning") .. " " .. text
    end
    local mission = g_currentMission
    if mission == nil or mission.addIngameNotification == nil or FSBaseMission == nil then
        return
    end
    local kind = isProblem and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_OK
    RseLog.try("addIngameNotification", mission.addIngameNotification, mission, kind or FSBaseMission.INGAME_NOTIFICATION_OK, text)
end
