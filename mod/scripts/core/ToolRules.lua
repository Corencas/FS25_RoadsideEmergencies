-- Roadside Emergencies: which hand tool comes next, when the game won't change it during a job (ToolSwitch.lua). Engine-free.

RseToolRules = {}

-- the tool after `current` in `tools`, going round; direction: above 0 forward, below 0 back
function RseToolRules.next(tools, current, direction)
    local count = #tools
    if count == 0 then
        return nil
    end
    local index = 0
    for i, tool in ipairs(tools) do
        if tool == current then
            index = i
        end
    end
    if index == 0 then
        return tools[1]
    end
    return tools[(index - 1 + (direction < 0 and -1 or 1)) % count + 1]
end

-- From a tool back to bare hands; from bare hands to the tool used last, if you still carry it, or else the first that isn't your hands.
function RseToolRules.toggle(tools, current, hands, last)
    if current ~= nil and current ~= hands then
        return hands
    end
    local fallback = nil
    for _, tool in ipairs(tools) do
        if tool ~= hands then
            if tool == last then
                return tool
            end
            fallback = fallback or tool
        end
    end
    return fallback
end
