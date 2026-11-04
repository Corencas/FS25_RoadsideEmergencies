-- Roadside Emergencies: the settings panel, drawn on the screen like the scene kit strip (H on foot opens it). While it is open it has an input context of
-- its own, as the game's text boxes do, so the arrow keys work it instead of turning the camera, and the player stands still: Up and Down choose a row, Left
-- and Right change it, Enter confirms, H or Esc closes. It also adds and removes your own drop-off points, returns the settings to default, and hands the
-- job in progress to another contractor at any moment.
-- It also shows the guide (core/Guide.lua), a page at a time with the same keys: by itself once in a new savegame, and from its first row whenever you want it.
-- A panel of our own rather than a tab in the game's menu: patching that menu is what broke it in 0.1.0.0, and a panel can't. It draws only while open, not
-- behind menus, and one failure switches it off for the session. Opening and closing wait for the next update, away from the input being handled, and it
-- closes by itself after a long time without input, so that no failure can leave the player without controls.

RseSettingsPanel = {
    isOpen = false,
    wantsOpen = false,
    wantsClose = false,
    wantsGuide = false,
    guide = false,       -- showing the guide rather than the settings
    guideFromPanel = false,
    page = 1,
    introMs = nil,
    index = 1,
    idleMs = 0,
    clockMs = 0,
    held = {},       -- arrow axis -> { sign, nextMs, lastMs }: one step per press, then repeating while held
    store = nil,
    drawFailed = false
}

local CONTEXT_NAME = "RSE_SETTINGS_PANEL"
local REPEAT_DELAY_MS, REPEAT_RATE_MS, RELEASED_AFTER_MS = 400, 140, 100

-- the guide, the settings (RseSettings.ROWS), then the actions; the last one only while a job is running
local ACTIONS = {
    { action = "addPoint", textKey = "rse_set_addPoint" },
    { action = "removePoint", textKey = "rse_set_removePoint" },
    { action = "defaults", textKey = "rse_set_defaults" }
}
local HAND_OVER = { action = "handOver", textKey = "rse_set_handOver" }
local GUIDE = { action = "guide", textKey = "rse_set_guide" }

local function rows()
    local list = { GUIDE }
    for _, row in ipairs(RseSettings.ROWS) do
        table.insert(list, row)
    end
    for _, row in ipairs(ACTIONS) do
        table.insert(list, row)
    end
    if RseScenes:canHandOver() then
        table.insert(list, HAND_OVER)
    end
    return list
end

function RseSettingsPanel:init(store)
    self.store = store
    self.isOpen, self.wantsOpen, self.wantsClose, self.wantsGuide, self.guide = false, false, false, false, false
    self.index, self.page = 1, 1
    self.introMs = RseConfig.GUIDE_INTRO_DELAY_MS
    self.drawFailed = false
end

local function enterInput(self)
    g_inputBinding:setContext(CONTEXT_NAME, true, false)
    local function listen(action, callback, always)
        local _, eventId = g_inputBinding:registerActionEvent(action, self, callback, false, true, always == true, true)
        if eventId ~= nil then
            g_inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end
    -- the arrows fire every frame while held, the way the game's own menus register these two actions (Gui.lua)
    listen(InputAction.MENU_AXIS_UP_DOWN, self.onUpDown, true)
    listen(InputAction.MENU_AXIS_LEFT_RIGHT, self.onLeftRight, true)
    listen(InputAction.MENU_ACCEPT, self.onAccept)
    listen(InputAction.MENU_BACK, self.onClose)
    listen(InputAction.RSE_SETTINGS, self.onClose)
end

local function leaveInput()
    g_inputBinding:revertContext(true)
end

-- H on foot, from the player's own keys
function RseSettingsPanel:requestOpen()
    self.wantsOpen = true
end

-- the guide opens by itself once in a savegame, the first time you are on foot with nothing else on the screen
local function checkIntro(self, dt)
    if self.store == nil or self.store.settings.guideSeen or self.isOpen or self.wantsOpen or self.drawFailed then
        return
    end
    self.introMs = (self.introMs or RseConfig.GUIDE_INTRO_DELAY_MS) - dt
    if self.introMs > 0 or g_localPlayer == nil or g_localPlayer:getCurrentVehicle() ~= nil or (g_gui ~= nil and g_gui:getIsGuiVisible()) then
        return
    end
    self.store:apply("setGuideSeen", { seen = true })
    self.wantsOpen, self.wantsGuide = true, true
end

function RseSettingsPanel:update(dt)
    self.clockMs = self.clockMs + dt
    checkIntro(self, dt)
    if self.wantsClose then
        self.wantsClose = false
        if self.isOpen then
            self.isOpen = false
            RseLog.try("leave the settings panel", leaveInput)
        end
    elseif self.wantsOpen then
        self.wantsOpen = false
        if not self.isOpen and self.store ~= nil and not self.drawFailed then
            self.isOpen = RseLog.try("open the settings panel", enterInput, self) == true
            self.index, self.idleMs, self.held = 1, 0, {}
            self.guide, self.guideFromPanel, self.page = self.wantsGuide, false, 1
            self.wantsGuide = false
        end
    elseif self.isOpen then
        self.idleMs = self.idleMs + dt
        if self.idleMs >= RseConfig.PANEL_IDLE_MS then
            self.wantsClose = true
        end
    end
end

-- the selected row; the last row can go away while the panel is open
local function currentRow(self, list)
    self.index = math.max(1, math.min(self.index, #list))
    return list[self.index]
end

-- closing the guide goes back to the settings if that is where it was opened from
function RseSettingsPanel:onClose()
    self.idleMs = 0
    if self.guide and self.guideFromPanel then
        self.guide = false
    else
        self.wantsClose = true
    end
end

-- this frame's value of an arrow axis: the direction to step in, or nil. A new press steps at once; holding it repeats after a moment.
local function arrowStep(self, axis, inputValue)
    local sign = (inputValue or 0) > 0 and 1 or (inputValue or 0) < 0 and -1 or 0
    local state = self.held[axis] or { sign = 0, nextMs = 0, lastMs = 0 }
    self.held[axis] = state
    if sign == 0 then
        state.sign = 0
        return nil
    end
    local fresh = sign ~= state.sign or self.clockMs - state.lastMs > RELEASED_AFTER_MS
    state.lastMs = self.clockMs
    state.sign = sign
    if fresh then
        state.nextMs = self.clockMs + REPEAT_DELAY_MS
    elseif self.clockMs >= state.nextMs then
        state.nextMs = self.clockMs + REPEAT_RATE_MS
    else
        return nil
    end
    self.idleMs = 0
    return sign
end

-- Up is positive on this axis (the game's key list)
function RseSettingsPanel:onUpDown(_, inputValue)
    local sign = arrowStep(self, "upDown", inputValue)
    if sign == nil then
        return
    end
    if self.guide then
        self.page = RseGuide.turn(self.page, -sign)
        return
    end
    local list = rows()
    currentRow(self, list)
    if sign > 0 then
        self.index = (self.index - 2) % #list + 1
    else
        self.index = self.index % #list + 1
    end
end

local function playerGround()
    if g_localPlayer == nil then
        return nil
    end
    local x, _, z = g_localPlayer:getPosition()
    return x, z
end

-- your own drop-off point nearest to you, or nil
local function nearestOwnPoint(self)
    local x, z = playerGround()
    if x == nil then
        return nil
    end
    local best, bestDistance = nil, math.huge
    for _, point in ipairs(self.store.points:playerPoints()) do
        local distance = (point.x - x) ^ 2 + (point.z - z) ^ 2
        if distance < bestDistance then
            best, bestDistance = point, distance
        end
    end
    return best
end

local function addPoint(self)
    local x, z = playerGround()
    if x == nil then
        return
    end
    local name = RseText.get("rse_point_player", #self.store.points:playerPoints() + 1)
    if self.store:apply("addPoint", { name = name, kind = "both", x = x, z = z, source = "player" }) ~= nil then
        RseText.notify(RseText.get("rse_point_added", name))
    end
end

local function removePoint(self)
    local best = nearestOwnPoint(self)
    if best == nil then
        RseText.notify(RseText.get("rse_point_noneOwn"), true)
    elseif self.store:apply("removePoint", { id = best.id }) ~= nil then
        RseText.notify(RseText.get("rse_point_removed", best.name))
    end
end

local function returnToDefaults(self)
    for _, row in ipairs(RseSettings.ROWS) do
        self.store:apply("setSetting", { key = row.key, value = row.default })
    end
    RseText.notify(RseText.get("rse_set_defaultsDone"))
end

-- Left and Right change a setting; they do nothing on an action, which should never happen by accident
function RseSettingsPanel:onLeftRight(_, inputValue)
    local sign = arrowStep(self, "leftRight", inputValue)
    if sign ~= nil and self.guide then
        self.page = RseGuide.turn(self.page, sign)
        return
    end
    local row = currentRow(self, rows())
    if sign == nil or row.action ~= nil then
        return
    end
    local value = self.store.settings[row.key]
    value = sign > 0 and RseSettings.nextValue(row, value) or RseSettings.previousValue(row, value)
    self.store:apply("setSetting", { key = row.key, value = value })
end

-- Enter does the action, or moves a setting on
function RseSettingsPanel:onAccept()
    self.idleMs = 0
    if self.guide then
        if self.page < #RseGuide.PAGES then
            self.page = RseGuide.turn(self.page, 1)
        else
            self:onClose()
        end
        return
    end
    local row = currentRow(self, rows())
    if row.action == "guide" then
        self.guide, self.guideFromPanel, self.page = true, true, 1
    elseif row.action == "handOver" then
        RseScenes:handOver()
        self.wantsClose = true
    elseif row.action == "addPoint" then
        addPoint(self)
    elseif row.action == "removePoint" then
        removePoint(self)
    elseif row.action == "defaults" then
        returnToDefaults(self)
    else
        self.store:apply("setSetting", { key = row.key, value = RseSettings.nextValue(row, self.store.settings[row.key]) })
    end
end

-- what a row's right-hand side reads
local function valueText(self, row)
    if row.action == "removePoint" then
        local point = nearestOwnPoint(self)
        if point == nil then
            return RseText.get("rse_set_none")
        end
        return string.format("%d: %s", RsePoints:numberOf(point) or 0, point.name)
    elseif row.action == "handOver" then
        return RseText.get(RseScenes:handOverPays() and "rse_set_handOverPaid" or "rse_set_handOverNone")
    elseif row.action ~= nil then
        return ""
    end
    local value = self.store.settings[row.key]
    if row.kind == "onOff" then
        return RseText.get(value and "rse_set_on" or "rse_set_off")
    elseif row.kind == "size" then
        return RseText.get("rse_set_size_" .. tostring(value))
    elseif row.kind == "percent" then
        return string.format("%d %%", math.floor((value or 0) * 100 + 0.5))
    elseif row.kind == "minutes" then
        return RseText.minutes(value or 0)
    end
    return ""
end

-- sizes in pixels at 1920 x 1080
local PANEL_WIDTH, ROW_HEIGHT, TITLE_HEIGHT, HELP_HEIGHT, MARGIN = 680, 34, 46, 34, 18
local TEXT_SIZE, TITLE_SIZE, HELP_SIZE = 0.0135, 0.017, 0.0115

local function drawPanel(self)
    local sx, sy = (1 / 1920) * ((16 / 9) / g_screenAspectRatio), 1 / 1080
    local list = rows()
    currentRow(self, list)
    local width, height = PANEL_WIDTH * sx, (TITLE_HEIGHT + #list * ROW_HEIGHT + HELP_HEIGHT + MARGIN) * sy
    local left, bottom = 0.5 - width / 2, 0.5 - height / 2
    drawFilledRect(left, bottom, width, height, 0, 0, 0, 0.78)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    local y = bottom + height - TITLE_HEIGHT * sy
    renderText(left + MARGIN * sx, y + 12 * sy, TITLE_SIZE, RseText.get("rse_set_title"))
    setTextBold(false)
    for i, row in ipairs(list) do
        y = y - ROW_HEIGHT * sy
        local selected = i == self.index
        if selected then
            drawFilledRect(left, y, width, ROW_HEIGHT * sy, 0.36, 0.72, 0.1, 0.55)
        end
        setTextColor(1, 1, 1, selected and 1 or 0.8)
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(left + MARGIN * sx, y + 10 * sy, TEXT_SIZE, RseText.get(row.textKey))
        local value = valueText(self, row)
        if value ~= "" then
            if selected and row.action == nil then
                value = "< " .. value .. " >"
            end
            setTextAlignment(RenderText.ALIGN_RIGHT)
            renderText(left + width - MARGIN * sx, y + 10 * sy, TEXT_SIZE, value)
        end
    end
    setTextColor(1, 1, 1, 0.7)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(left + MARGIN * sx, bottom + (MARGIN + 2) * sy, HELP_SIZE, RseText.get("rse_set_help"))
    setTextColor(1, 1, 1, 1)
end

-- sizes in pixels at 1920 x 1080
local GUIDE_WIDTH, GUIDE_HEIGHT, GUIDE_GAP = 860, 520, 16
local GUIDE_TEXT_SIZE, GUIDE_HEADING_SIZE = 0.0155, 0.0175

-- one page of the guide. Lines wrap downward from where they start.
local function drawGuide(self)
    local sx, sy = (1 / 1920) * ((16 / 9) / g_screenAspectRatio), 1 / 1080
    local width, height = GUIDE_WIDTH * sx, GUIDE_HEIGHT * sy
    local left, bottom = 0.5 - width / 2, 0.5 - height / 2
    local x = left + MARGIN * sx
    local page = RseGuide.PAGES[self.page]
    drawFilledRect(left, bottom, width, height, 0, 0, 0, 0.78)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(true)
    local y = bottom + height - TITLE_HEIGHT * sy
    renderText(x, y + 12 * sy, TITLE_SIZE, RseText.get("rse_guide_title"))
    setTextBold(false)
    y = y - ROW_HEIGHT * sy
    drawFilledRect(left, y, width, ROW_HEIGHT * sy, 0.36, 0.72, 0.1, 0.55)
    renderText(x, y + 9 * sy, GUIDE_HEADING_SIZE, RseText.get(page.title))
    y = y - MARGIN * sy
    setTextWrapWidth(width - 2 * MARGIN * sx)
    for _, key in ipairs(page.lines) do
        local text = RseText.get(key)
        renderText(x, y - GUIDE_TEXT_SIZE, GUIDE_TEXT_SIZE, text)
        y = y - getTextHeight(GUIDE_TEXT_SIZE, text) - GUIDE_GAP * sy
    end
    setTextWrapWidth(0)
    setTextColor(1, 1, 1, 0.7)
    renderText(x, bottom + (MARGIN + 2) * sy, HELP_SIZE, RseText.get("rse_guide_help"))
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(left + width - MARGIN * sx, bottom + (MARGIN + 2) * sy, HELP_SIZE, RseText.get("rse_guide_page", self.page, #RseGuide.PAGES))
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

function RseSettingsPanel:draw()
    if not self.isOpen or self.drawFailed or (g_gui ~= nil and g_gui:getIsGuiVisible()) then
        return
    end
    if not RseLog.try("settings panel", self.guide and drawGuide or drawPanel, self) then
        setTextWrapWidth(0)
        self.drawFailed = true
        self.wantsClose = true
    end
end

function RseSettingsPanel:unload()
    if self.isOpen then
        RseLog.try("leave the settings panel", leaveInput)
    end
    self.isOpen, self.wantsOpen, self.wantsClose = false, false, false
    self.store = nil
end
