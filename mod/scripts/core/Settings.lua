-- Roadside Emergencies: the settings a player can change in the panel (SettingsPanel.lua, H on foot). Engine-free. Each row cycles through
-- its values; everything is saved with the savegame. Three of them have their own save fields since M1 and M2 (legacy).

RseSettings = {
    ROWS = {
        { key = "callsEnabled", textKey = "rse_set_calls", kind = "onOff", values = { true, false }, default = true, legacy = true },
        { key = "callFrequency", textKey = "rse_set_frequency", kind = "frequency", values = { "rare", "normal", "often" }, default = "normal" },
        { key = "pagerSound", textKey = "rse_set_pagerSound", kind = "onOff", values = { true, false }, default = true },
        { key = "animalCalls", textKey = "rse_set_animalCalls", kind = "onOff", values = { true, false }, default = true },
        { key = "wreckCalls", textKey = "rse_set_wreckCalls", kind = "onOff", values = { true, false }, default = true },
        { key = "jobSize", textKey = "rse_set_jobSize", kind = "size", values = { "small", "normal", "large", "random" }, default = "normal", legacy = true },
        { key = "payFactor", textKey = "rse_set_pay", kind = "percent", values = { 0.5, 0.75, 1, 1.25, 1.5, 2 }, default = 1 },
        { key = "feeFactor", textKey = "rse_set_fees", kind = "percent", values = { 0, 0.5, 1, 1.5, 2 }, default = 1, legacy = true },
        { key = "leftMinutes", textKey = "rse_set_left", kind = "minutes", values = { 15, 30, 45, 60 }, default = 30 },
        { key = "expireMinutes", textKey = "rse_set_expire", kind = "minutes", values = { 10, 20, 30, 60 }, default = 20 },
        { key = "markersEnabled", textKey = "rse_set_markers", kind = "onOff", values = { true, false }, default = true },
        { key = "panelEnabled", textKey = "rse_set_panel", kind = "onOff", values = { true, false }, default = true }
    }
}

function RseSettings.row(key)
    for _, row in ipairs(RseSettings.ROWS) do
        if row.key == key then
            return row
        end
    end
    return nil
end

-- the value after `current` in the row's list, starting over at the end; the first one if `current` isn't in the list
function RseSettings.nextValue(row, current)
    for i, value in ipairs(row.values) do
        if value == current then
            return row.values[i % #row.values + 1]
        end
    end
    return row.values[1]
end

-- the value before `current` in the row's list, going round; the first one if `current` isn't in the list
function RseSettings.previousValue(row, current)
    for i, value in ipairs(row.values) do
        if value == current then
            return row.values[(i - 2) % #row.values + 1]
        end
    end
    return row.values[1]
end

function RseSettings.isValid(row, value)
    for _, candidate in ipairs(row.values) do
        if candidate == value then
            return true
        end
    end
    return false
end

-- a value read from a savegame (often as a string): the row's own value if it matches, else the default
function RseSettings.parse(row, raw)
    for _, candidate in ipairs(row.values) do
        if candidate == raw or tostring(candidate) == tostring(raw) then
            return candidate
        end
    end
    return row.default
end

-- puts the defaults into a settings table
function RseSettings.fillDefaults(settings)
    for _, row in ipairs(RseSettings.ROWS) do
        if settings[row.key] == nil then
            settings[row.key] = row.default
        end
    end
    return settings
end

-- the settings that are times live in the config, where the rules read them
function RseSettings.applyTimes(settings, config)
    config.LEFT_COLLECT_MS = (settings.leftMinutes or 30) * 60000
    config.JOB_EXPIRE_MS = (settings.expireMinutes or 20) * 60000
    config.CALL_GAP_MS = config.CALL_GAPS[settings.callFrequency] or config.CALL_GAPS.normal
end
