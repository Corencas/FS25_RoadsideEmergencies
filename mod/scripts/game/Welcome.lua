-- Roadside Emergencies: the welcome dialog (P3 in docs/UI_RESEARCH.md; mockup docs/mockups/welcome_dialog.html). Once per player, not per savegame: what
-- the mod is in three short lines, that it needs the Emergency Pack, and where to report a bug in the beta. It pauses the game while it is open (Z, Gate U).
-- The game's MessageDialog and dialog parts with our layout (gui/rseWelcomeDialog.xml), proven by U0. The game can't open a link (openWebFile returns nothing
-- and no browser shows, in U0 and U1), so the address is written out, here and in the guide (Z).
-- rseWelcome shows it again.

RseWelcome = {
    dialog = nil,
    paused = false,
    failed = false
}

RseWelcomeDialog = {}

local function defineDialog()
    if RseWelcomeDialog.mt ~= nil then
        return true
    end
    if MessageDialog == nil then
        return false
    end
    RseWelcomeDialog.mt = Class(RseWelcomeDialog, MessageDialog)

    function RseWelcomeDialog.new(target, customMt)
        return MessageDialog.new(target, customMt or RseWelcomeDialog.mt)
    end

    function RseWelcomeDialog:onOpen()
        RseWelcomeDialog:superClass().onOpen(self)
        RseLog.try("fill the welcome dialog", RseWelcome.fill, RseWelcome, self)
    end

    function RseWelcomeDialog:onClose()
        RseWelcomeDialog:superClass().onClose(self)
        RseWelcome:closed()
    end

    function RseWelcomeDialog:onClickStart()
        self:close()
    end

    function RseWelcomeDialog:onClickGuide()
        self:close()
        RseSettingsPanel:openGuide()
    end

    return true
end

local function setText(element, text)
    if element ~= nil and element.setText ~= nil then
        element:setText(text)
    end
end

local function setColor(element, color)
    if element ~= nil and element.setTextColor ~= nil then
        element:setTextColor(color[1], color[2], color[3], color[4])
    end
end

local function setImage(element, file)
    if element ~= nil and element.setImageFilename ~= nil then
        element:setImageFilename(Utils.getFilename(file, RoadsideEmergencies.MOD_DIR))
    end
end

-- texts from the translations, the icon, the stripe and the colours from RseTheme
function RseWelcome:fill(dialog)
    setImage(dialog.welcomeIcon, "icon_roadsideEmergencies.dds")
    setImage(dialog.welcomeStripe, "icons/ui_stripe.dds")
    setText(dialog.welcomeTitle, RseText.get("rse_welcome_title"))
    setColor(dialog.welcomeTitle, RseTheme.ACCENT)
    setText(dialog.welcomeSubtitle, RseText.get("rse_welcome_subtitle"))
    setColor(dialog.welcomeSubtitle, RseTheme.TEXT_MUTED)
    setText(dialog.welcomeBody, RseText.get("rse_welcome_body"))
    setText(dialog.welcomePack, RseText.get("rse_welcome_pack"))
    setColor(dialog.welcomePack, RseTheme.TEXT_MUTED)
    setText(dialog.welcomeBeta, RseText.get("rse_welcome_beta"))
    setColor(dialog.welcomeBeta, RseTheme.TEXT_MUTED)
    setText(dialog.welcomeStart, RseText.get("rse_welcome_start"))
    setText(dialog.welcomeGuide, RseText.get("rse_welcome_guide"))
end

local function isSinglePlayer()
    local info = g_currentMission ~= nil and g_currentMission.missionDynamicInfo or nil
    return info ~= nil and info.isMultiplayer == false
end

local function setPaused(paused)
    local mission = g_currentMission
    if mission ~= nil and mission.setManualPause ~= nil then
        mission:setManualPause(paused)
        return true
    end
    return false
end

-- a new player, with the Emergency Pack there (without it, the game's mod list and our own notice say what is missing)
function RseWelcome:shouldShow(packFound)
    return not self.failed and packFound and RsePlayerFile:welcomeSeen() ~= true
end

function RseWelcome:show()
    if not defineDialog() then
        self.failed = true
        RseLog.info("welcome: the game has no MessageDialog here, so no welcome")
        return false
    end
    if self.dialog == nil then
        local dialog = RseWelcomeDialog.new()
        local ok, gui = RseLog.try("load the welcome dialog", g_gui.loadGui, g_gui,
            Utils.getFilename("gui/rseWelcomeDialog.xml", RoadsideEmergencies.MOD_DIR), "RseWelcomeDialog", dialog)
        if not ok or gui == nil then
            self.failed = true
            return false
        end
        self.dialog = dialog
    end
    if not RseLog.try("show the welcome dialog", g_gui.showDialog, g_gui, "RseWelcomeDialog") then
        self.failed = true
        return false
    end
    self.paused = isSinglePlayer() and RseLog.try("pause for the welcome", setPaused, true) or false
    RseLog.info("welcome: shown%s", self.paused and ", the game paused" or "")
    return true
end

-- the dialog has closed, by any button or Esc: the game goes on, and the player has seen it
function RseWelcome:closed()
    if self.paused then
        self.paused = false
        RseLog.try("unpause after the welcome", setPaused, false)
    end
    RsePlayerFile:setWelcomeSeen()
end

function RseWelcome:unload()
    if self.dialog ~= nil and g_gui ~= nil and g_gui.currentDialogName == "RseWelcomeDialog" then
        RseLog.try("close the welcome dialog", g_gui.closeDialogByName, g_gui, "RseWelcomeDialog")
    end
    self.dialog, self.paused, self.failed = nil, false, false
end
