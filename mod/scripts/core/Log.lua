-- Roadside Emergencies: log lines with the mod's prefix. Debug lines only while debug logging is on (rseDebug).

RseLog = {
    debugEnabled = false
}

local function write(level, fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then
        text = tostring(fmt)
    end
    print(RseConfig.LOG_PREFIX .. level .. text)
end

function RseLog.info(fmt, ...)
    write("", fmt, ...)
end

function RseLog.debug(fmt, ...)
    if RseLog.debugEnabled then
        write("debug: ", fmt, ...)
    end
end

function RseLog.problem(fmt, ...)
    write("problem: ", fmt, ...)
end

-- Runs fn protected: a failure is logged and never takes the game down. Returns ok, then fn's results.
function RseLog.try(label, fn, ...)
    local result = { pcall(fn, ...) }
    if not result[1] then
        RseLog.problem("%s failed: %s", label, tostring(result[2]))
    end
    return unpack(result)
end
