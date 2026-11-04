-- Roadside Emergencies: hand tools during a job. While a job runs, the game refuses to change the tool you hold: the key presses arrive, and nothing happens
-- (Z, with the chainsaw at a power line). The reason isn't readable, so this works from what it can see: when a press changed nothing during one of our jobs,
-- and your hands are empty, the tool changes here instead. Away from a job the game does it all.

RseToolSwitch = {
    last = nil         -- the tool held last that wasn't bare hands
}

local function toolName(tool)
    return tool ~= nil and tostring(tool.configFileNameClean or tool.configFileName) or "none"
end

local function handsOf(tools)
    for _, tool in ipairs(tools) do
        if tool.spec_hands ~= nil then
            return tool
        end
    end
    return nil
end

-- A press has been handled by the game. name: which key; before: the tool held until then; direction: which way a cycle goes.
local function afterPress(self, name, component, before, direction)
    local player = component.player
    if player == nil or not player.isOwner then
        return
    end
    local tools = player.carriedHandTools or {}
    local hands = handsOf(tools)
    local now = player.currentHandTool
    if before ~= nil and before ~= hands then
        self.last = before
    end
    if name == "flashlight" or now ~= before then
        RseLog.debug("tool key %s: %s, now %s", name, toolName(before), toolName(now))
        return
    end
    if RseScenes:activeCount() == 0 then
        RseLog.debug("tool key %s: %s stays, no job running", name, toolName(before))
        return
    end
    -- something in your hands stays there until you put it down, as always
    if before ~= nil and before.getIsHoldingItem ~= nil and before:getIsHoldingItem() then
        return
    end
    local target
    if name == "toggle" then
        target = RseToolRules.toggle(tools, before, hands, self.last)
    else
        target = RseToolRules.next(tools, before, direction)
    end
    if target == nil or target == before then
        return
    end
    player:setCurrentHandTool(target, true)
    RseLog.debug("tool key %s: the game refused during a job, so %s -> %s: holding %s", name, toolName(before), toolName(target),
        toolName(player.currentHandTool))
end

local function passOn(self, name, component, before, direction, ...)
    RseLog.try("change the tool", afterPress, self, name, component, before, direction)
    return ...
end

-- The game's handlers are wrapped before the player registers its keys, and hand back what they returned.
function RseToolSwitch:install()
    if PlayerInputComponent == nil then
        return
    end
    for name, handler in pairs({ cycle = "onInputCycleHandTool", toggle = "onInputToggleHandTool", flashlight = "onInputToggleFlashlight" }) do
        local key = "rseOriginal_" .. handler
        if PlayerInputComponent[key] == nil then
            PlayerInputComponent[key] = PlayerInputComponent[handler]
        end
        if type(PlayerInputComponent[key]) == "function" then
            PlayerInputComponent[handler] = function(component, actionName, inputValue, ...)
                local player = component.player
                local before = player ~= nil and player.currentHandTool or nil
                return passOn(self, name, component, before, tonumber(inputValue) or 1,
                    PlayerInputComponent[key](component, actionName, inputValue, ...))
            end
        else
            RseLog.info("the game has no %s", handler)
        end
    end
end

-- a new savegame
function RseToolSwitch:reset()
    self.last = nil
end
