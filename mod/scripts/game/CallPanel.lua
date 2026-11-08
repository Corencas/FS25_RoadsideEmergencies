-- Roadside Emergencies: the call panel (P4 in docs/UI_RESEARCH.md; mockup docs/mockups/call_hud.html, look B). While a job runs, a panel at the right of the
-- screen says what it is, how far and which way to go, the clock that applies, the job's steps (done, now, to do), whether the warning lights bonus is on,
-- and about what it pays. The steps come from RsePanelRules, from the same state as the progress bar.
-- Drawn by us like the kit strip: it looks at the scene a few times a second and draws every frame, hides behind the game's menus and dialogs, the map,
-- our settings panel and a hidden HUD, and one failure switches it off for the session. The game's font has no ticks or warning signs, so the marks are
-- pictures (icons/ui_*.dds), each with a word beside it: never colour alone. A setting turns it off.

RseCallPanel = {
    store = nil,
    view = nil,        -- what to draw, built every PANEL_UPDATE_MS
    updateMs = 0,
    failed = false
}

-- sizes in pixels at 1920 x 1080
local WIDTH, RIGHT, TOP, PAD = 430, 34, 330, 16
local STRIPE, HEAD, CLOCK, ROW, GAP, FOOT = 6, 44, 34, 32, 6, 34
local MARK, SMALL_MARK, ARROW = 20, 16, 18
local HEAD_SIZE, LABEL_SIZE, ROW_SIZE, STATE_SIZE = 0.0175, 0.0125, 0.0145, 0.0115
local DIVIDER = { 1, 1, 1, 0.12 }
local WHITE = { 1, 1, 1, 1 }

local MARKS = { done = "icons/ui_done.dds", now = "icons/ui_now.dds", todo = "icons/ui_todo.dds", optional = "icons/ui_todo.dds" }
local WRECK_WHAT = { powerline = "car", river = "car", tree = "car", trailer = "trailer", livestock = "trailer" }

function RseCallPanel:init(store)
    self.store = store
    self.view, self.updateMs, self.failed = nil, 0, false
end

-- capitals as the mockup has them, from the game's own function (it knows umlauts); the text as it is if that gives nothing
local function upper(text)
    if type(utf8ToUpper) == "function" then
        local result = utf8ToUpper(text)
        if type(result) == "string" then
            return result
        end
    end
    return text
end

local function playerPosition()
    if g_localPlayer == nil then
        return nil
    end
    local vehicle = g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil
    if vehicle ~= nil and vehicle.rootNode ~= nil then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        return x, z
    end
    local x, _, z = g_localPlayer:getPosition()
    return x, z
end

local function recoveryPoint(self, scene)
    return self.store ~= nil and self.store.points:nearest(scene.x, scene.z, "recovery") or nil
end

-- everything the rules need, read from the scene and the modules that keep its parts
local function gather(self, scene)
    local facts = { arrived = scene.arrived == true }
    local waiting = RseEpSteps ~= nil and RseEpSteps.waiting or nil
    if not facts.arrived and waiting ~= nil then
        facts.expireLeftMs = math.max(0, RseConfig.JOB_EXPIRE_MS - (waiting.waitMs or 0))
    end
    local left, total = RseScenes:animalsLeft(scene)
    if total > 0 then
        facts.animals = { left = left, total = total }
    end
    local wreck = scene.wreck
    if wreck == nil then
        return facts
    end
    local def = wreck.def
    if not def.noVehicle and not def.scenery then
        facts.wreck = { state = wreck.state, delivered = wreck.delivered == true, tipped = def.tipped == true, driver = def.driver == true,
            what = WRECK_WHAT[wreck.kind] }
        local x, z = RseWrecks:position(wreck)
        local point = recoveryPoint(self, scene)
        if x ~= nil and point ~= nil then
            facts.pointDistance = math.sqrt((point.x - x) ^ 2 + (point.z - z) ^ 2)
        end
    end
    if (wreck.balesTotal or 0) > 0 then
        facts.bales = { left = wreck.balesLeft or #wreck.bales, total = wreck.balesTotal }
    end
    if def.kinds ~= nil then
        local loose = RseSurvivors:remaining(scene)
        facts.survivors = { left = loose, total = loose + (scene.led or 0) }
    end
    if scene.flock ~= nil then
        facts.flock = { left = math.max(0, scene.flock.total - RseFlock:pennedCount(scene)) }
    end
    local line = scene.line
    if line ~= nil then
        local off = line.state.powerOff == true
        local crew = RseUtilityCrew ~= nil and RseUtilityCrew:status(scene) or nil
        local payFactor = self.store ~= nil and self.store.settings.payFactor or 1
        facts.line = { powerOff = off, secondsLeft = not off and RseLineRules.secondsLeft(line.state, RseConfig, crew) or nil,
            wiresLeft = RsePowerLine:wiresLeft(line), poleIn = line.poleIn == true,
            polePay = math.floor(RsePayRules.scaled(line.def.polePay or 0, payFactor) * (scene.payRatio or 1) + 0.5) }
    end
    if scene.spill ~= nil then
        facts.logs = { left = RseLogSpill:left(scene) }
    end
    if def.treeOnCar then
        local bonusOpen = facts.arrived and not scene.rescueNoted and wreck.state == "locked"
        facts.tree = { doorFree = scene.doorFree == true, rescueLeftMs = bonusOpen and math.max(0, RseConfig.TREE_RESCUE_MS - (scene.rescueMs or 0)) or nil }
    end
    if scene.crossing ~= nil then
        facts.crossing = { seconds = scene.crossing.seconds, clear = scene.crossing.clear == true }
    end
    if scene.handover ~= nil and scene.handover.partDone then
        facts.handoverLeftMs = math.max(0, RseConfig.CRASH_HANDOVER_MS - (scene.handover.waitMs or 0))
    end
    return facts
end

-- What the pack really pays for our amount: it applies the game's economy difficulty (in the FS22 pack, getReward multiplies calculateReward, which
-- answers with our amount on our emergencies). Asked once per job with a round number and put back at once; until the pack has our reward in place, 1.
local function packRatio(scene)
    if scene.payRatio ~= nil then
        return scene.payRatio
    end
    local scenario = scene.scenario
    if scenario == nil or not scenario.rseRewardInstalled or type(scenario.getReward) ~= "function" then
        return 1
    end
    local before = scenario.rseReward
    scenario.rseReward = 1000
    local ok, paid = pcall(scenario.getReward, scenario)
    scenario.rseReward = before
    scene.payRatio = (ok and type(paid) == "number" and paid > 0) and paid / 1000 or 1
    if ok and type(paid) == "number" and paid > 0 then
        RseScenes.lastPayRatio = scene.payRatio -- the pager's next "about" uses it
    end
    return scene.payRatio
end

-- about what the whole job pays once it is all done, as the job will work it out: the pay setting, the lights bonus and the economy difficulty
local function estimate(self, scene)
    local payFactor = self.store ~= nil and self.store.settings.payFactor or 1
    local wreck = scene.wreck
    local amount
    if wreck == nil then
        amount = RsePayRules.scaled(RsePayRules.callReward(scene.kinds or {}, {}, RseConfig), payFactor)
    elseif scene.handover ~= nil then
        local line = scene.line
        local done = { trailer = true, animals = true, kinds = scene.kinds, roadsideKinds = {}, led = (scene.led or 0) + RseSurvivors:remaining(scene),
            bales = wreck.balesTotal or 0, haulPay = scene.haulPay, payPerBale = RseWreckRules.balePay(wreck.load, true),
            linePay = line ~= nil and RseLineRules.pay(line.def, line.poleIn, line.wiresTotal) or 0 } -- the pole only once it is in: it is optional
        local reward = RseWreckRules.crashReward(wreck.def, done, RseConfig)
        amount = RsePayRules.scaled(RseLineRules.afterPenalty(reward, line ~= nil and line.state or nil, RseConfig), payFactor)
    else
        amount = RsePayRules.scaled(scene.reward or 0, payFactor)
    end
    if scene.lightsOn then
        amount = RsePayRules.withLightsBonus(amount, RseConfig)
    end
    return math.floor(amount * packRatio(scene) + 0.5)
end

local function title(scene)
    if scene.wreck ~= nil then
        return RseText.get("rse_panel_title_" .. scene.wreck.kind)
    end
    local kinds = scene.kinds or {}
    if #kinds > 0 then
        return RseText.get("rse_panel_title_animals", RseText.animalTitle(kinds[1], #kinds))
    end
    return RseText.get("rse_panel_title_call")
end

-- the right-hand side of a step: done, what an optional one adds, how many are left, how far, or now
local function stateText(step)
    if step.state == "done" then
        return RseText.get("rse_panel_done")
    elseif step.state == "optional" then
        return (step.extraPay or 0) > 0 and RseText.get("rse_panel_extra", RseText.money(step.extraPay)) or RseText.get("rse_panel_optional")
    elseif step.count ~= nil and step.count > 0 then
        return RseText.get("rse_panel_left", step.count)
    elseif step.distance ~= nil then
        return RseText.distance(step.distance)
    elseif step.state == "now" then
        return RseText.get("rse_panel_now")
    end
    return ""
end

local function build(self, scene)
    local facts = gather(self, scene)
    local steps = RsePanelRules.steps(facts)
    local view = { title = title(scene), clock = RsePanelRules.clock(facts, RseConfig), lightsOn = scene.lightsOn == true, pay = estimate(self, scene),
        lightsLive = scene.lightsLive == true, steps = {},
        lightsLeftMs = math.max(0, RseConfig.LIGHTS_EARN_MS - (scene.lightsState ~= nil and scene.lightsState.ms or 0)) }
    for _, step in ipairs(steps) do
        table.insert(view.steps, { text = RseText.get(step.key), state = step.state, right = stateText(step) })
    end
    -- where to go next: the scene until you are there, then the recovery point when that is the next thing, else the scene again if you have wandered off
    if not facts.arrived then
        view.targetX, view.targetZ = scene.x, scene.z
    elseif RsePanelRules.goesToPoint(RsePanelRules.current(steps)) then
        local point = recoveryPoint(self, scene)
        if point ~= nil then
            view.targetX, view.targetZ = point.x, point.z
        end
    else
        local px, pz = playerPosition()
        if px ~= nil and (px - scene.x) ^ 2 + (pz - scene.z) ^ 2 > RseConfig.PANEL_NEAR ^ 2 then
            view.targetX, view.targetZ = scene.x, scene.z
        end
    end
    return view
end

function RseCallPanel:enabled()
    return not self.failed and self.store ~= nil and self.store.settings.panelEnabled ~= false
end

function RseCallPanel:update(dt)
    self.updateMs = self.updateMs - dt
    if self.updateMs > 0 then
        return
    end
    self.updateMs = RseConfig.PANEL_UPDATE_MS
    local scene = RseScenes:get(RseScenes:activeId())
    if scene == nil or scene.finished or not self:enabled() then
        self.view = nil
        return
    end
    local ok, view = RseLog.try("build the call panel", build, self, scene)
    if not ok then
        self.failed, self.view = true, nil
        return
    end
    self.view = view
end

-- is it on the screen this frame? The crossing's own clock steps aside for it (LevelCrossing.lua).
function RseCallPanel:visible()
    if self.view == nil or self.failed or (g_gui ~= nil and g_gui:getIsGuiVisible()) or RseSettingsPanel.isOpen then
        return false
    end
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if hud ~= nil and type(hud.getIsVisible) == "function" and not hud:getIsVisible() then
        return false
    end
    return true
end

-- how far to the target, and which way to turn: from the camera, so the arrow matches what you see
local function way(view)
    if view.targetX == nil then
        return nil, nil
    end
    local px, pz = playerPosition()
    if px == nil then
        return nil, nil
    end
    local distance = math.sqrt((view.targetX - px) ^ 2 + (view.targetZ - pz) ^ 2)
    local bearing = nil
    local camera = type(getCamera) == "function" and getCamera() or nil
    if camera ~= nil and camera ~= 0 then
        local cx, _, cz = getWorldTranslation(camera)
        local ax, _, az = localDirectionToWorld(camera, 0, 0, -1)
        local rx, _, rz = localDirectionToWorld(camera, 1, 0, 0)
        bearing = RsePanelRules.bearing(ax, az, rx, rz, view.targetX - cx, view.targetZ - cz)
    end
    return distance, bearing
end

-- a text size that fits the room: a long title or a German step shrinks a little rather than run into the right-hand side (set bold first)
local function fitted(size, text, room)
    if type(getTextWidth) ~= "function" or room <= 0 then
        return size
    end
    local width = getTextWidth(size, text)
    if width <= room then
        return size
    end
    return math.max(size * 0.75, size * room / width)
end

local function divider(left, y, width, sy)
    RseDraw.rect(DIVIDER, left, y, width, sy)
end

local function drawPanel(self)
    local view = self.view
    local sx, sy = (1 / 1920) * ((16 / 9) / g_screenAspectRatio), 1 / 1080
    local width, pad = WIDTH * sx, PAD * sx
    local left = 1 - RIGHT * sx - width
    local right = left + width - pad
    local height = (STRIPE + HEAD + (view.clock ~= nil and CLOCK or 0) + #view.steps * ROW + 2 * GAP + FOOT) * sy
    local top = 1 - TOP * sy
    RseDraw.rect(RseTheme.PANEL, left, top - height, width, height)
    RseDraw.stripeAt(left, top - STRIPE * sy, width, STRIPE * sy)

    -- what it is, and how far
    local y = top - (STRIPE + HEAD) * sy
    setTextBold(true)
    local titleRoom = width - 2 * pad
    local distance, bearing = way(view)
    if distance ~= nil then
        local textRight = right
        if bearing ~= nil and RseDraw.image("icons/ui_arrow.dds", right - ARROW * sx, y + 13 * sy, ARROW * sx, ARROW * sy, RseTheme.ACCENT, -bearing) then
            textRight = right - (ARROW + 6) * sx
        end
        local distanceText = RseText.distance(distance)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        RseDraw.textColor(RseTheme.TEXT)
        renderText(textRight, y + 14 * sy, HEAD_SIZE, distanceText)
        titleRoom = textRight - (left + pad) - (type(getTextWidth) == "function" and getTextWidth(HEAD_SIZE, distanceText) or 0) - 12 * sx
    end
    local titleText = upper(view.title)
    setTextAlignment(RenderText.ALIGN_LEFT)
    RseDraw.textColor(RseTheme.ACCENT)
    renderText(left + pad, y + 14 * sy, fitted(HEAD_SIZE, titleText, titleRoom), titleText)
    setTextBold(false)

    -- the clock: red, with the warning sign and a word, when it can cost you the job
    local clock = view.clock
    if clock ~= nil then
        divider(left, y, width, sy)
        y = y - CLOCK * sy
        local labelX = left + pad
        local label = RseText.get(clock.key)
        if clock.urgent then
            RseDraw.rect(RseTheme.URGENT_FILL, left, y, width, CLOCK * sy)
            if RseDraw.image("icons/ui_warning.dds", labelX, y + (CLOCK - MARK) / 2 * sy, MARK * sx, MARK * sy, WHITE) then
                labelX = labelX + (MARK + 8) * sx
            end
            label = RseText.get("rse_panel_hurry", label)
            RseDraw.textColor(RseTheme.TEXT)
        else
            RseDraw.textColor(RseTheme.TEXT_MUTED)
        end
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(labelX, y + 11 * sy, LABEL_SIZE, label)
        setTextBold(true)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        RseDraw.textColor(RseTheme.TEXT)
        renderText(right, y + 9 * sy, HEAD_SIZE, RsePanelRules.clockText(clock.seconds))
        setTextBold(false)
    end

    -- the steps
    divider(left, y, width, sy)
    y = y - GAP * sy
    for _, step in ipairs(view.steps) do
        y = y - ROW * sy
        RseDraw.image(MARKS[step.state], left + pad, y + (ROW - MARK) / 2 * sy, MARK * sx, MARK * sy, WHITE)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(step.state == "now")
        if step.state == "done" then
            RseDraw.textColor(RseTheme.TEXT_MUTED)
        else
            RseDraw.textColor(RseTheme.TEXT, step.state == "now" and 1 or 0.85)
        end
        local textX = left + pad + (MARK + 10) * sx
        local rightText = upper(step.right)
        local rightWidth = 0
        if rightText ~= "" and type(getTextWidth) == "function" then
            setTextBold(true)
            rightWidth = getTextWidth(STATE_SIZE, rightText)
            setTextBold(step.state == "now")
        end
        renderText(textX, y + 10 * sy, fitted(ROW_SIZE, step.text, right - textX - rightWidth - 10 * sx), step.text)
        if rightText ~= "" then
            setTextBold(true)
            setTextAlignment(RenderText.ALIGN_RIGHT)
            RseDraw.textColor(step.state == "now" and RseTheme.ACCENT or RseTheme.TEXT_MUTED)
            renderText(right, y + 11 * sy, STATE_SIZE, rightText)
        end
        setTextBold(false)
    end
    y = y - GAP * sy

    -- the lights bonus and the pay
    divider(left, y, width, sy)
    y = y - FOOT * sy
    -- the lights: earned (a tick, and it stays), on now and counting (the orange mark), or off (a ring)
    local percent = math.floor(RseConfig.CALL_LIGHTS_BONUS * 100 + 0.5)
    local mark, lights = MARKS.todo, RseText.get("rse_panel_lightsOff", percent)
    if view.lightsOn then
        mark, lights = MARKS.done, RseText.get("rse_panel_lightsEarned", percent)
    elseif view.lightsLive then
        mark, lights = MARKS.now, RseText.get("rse_panel_lightsCounting", percent, RsePanelRules.clockText(view.lightsLeftMs / 1000))
    end
    RseDraw.image(mark, left + pad, y + (FOOT - SMALL_MARK) / 2 * sy, SMALL_MARK * sx, SMALL_MARK * sy, WHITE)
    setTextAlignment(RenderText.ALIGN_LEFT)
    RseDraw.textColor((view.lightsOn or view.lightsLive) and RseTheme.TEXT or RseTheme.TEXT_MUTED)
    renderText(left + pad + (SMALL_MARK + 8) * sx, y + 11 * sy, LABEL_SIZE, lights)
    if view.pay ~= nil and view.pay > 0 then
        setTextAlignment(RenderText.ALIGN_RIGHT)
        RseDraw.textColor(RseTheme.TEXT_MUTED)
        renderText(right, y + 11 * sy, LABEL_SIZE, RseText.get("rse_panel_pay", RseText.money(view.pay)))
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

function RseCallPanel:draw()
    if not self:visible() then
        return
    end
    if not RseLog.try("draw the call panel", drawPanel, self) then
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(1, 1, 1, 1)
        self.failed, self.view = true, nil
    end
end

function RseCallPanel:unload()
    self.store, self.view, self.updateMs, self.failed = nil, nil, 0, false
end
