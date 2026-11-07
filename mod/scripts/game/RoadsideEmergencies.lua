-- Roadside Emergencies: entry point. Wires the core (Store, rules) to the game adapters and owns the mod's life cycle:
-- loadMap, update, deleteMap. Hooks are listed in docs/HOOKS.md.

RoadsideEmergencies = {
    MOD_NAME = g_currentModName,
    MOD_DIR = g_currentModDirectory,
    store = nil,
    moneyTypePay = nil,
    moneyTypeFee = nil,
    moneyTypeCollection = nil,
    moneyTypePenalty = nil,
    pendingCarcasses = nil,
    pendingDelayMs = 0,
    packChecked = false
}

-- The strap key joins the local player's own key registration. Like the save hook, it always wraps the stored original
-- (no stacking when another savegame loads) and deleteMap restores it.
local function installInputHook()
    if PlayerInputComponent == nil or type(PlayerInputComponent.registerActionEvents) ~= "function" then
        return false
    end
    RseToolSwitch:install()
    if PlayerInputComponent.rseOriginalRegisterActionEvents == nil then
        PlayerInputComponent.rseOriginalRegisterActionEvents = PlayerInputComponent.registerActionEvents
    end
    PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.rseOriginalRegisterActionEvents,
        function(component)
            if component.player ~= nil and component.player.isOwner then
                RseStrap:registerActionEvents()
                RseKit:registerActionEvents()
            end
        end)
    RoadsideEmergencies.inputHook = PlayerInputComponent.registerActionEvents
    return true
end

local function uninstallInputHook()
    if PlayerInputComponent ~= nil and PlayerInputComponent.registerActionEvents == RoadsideEmergencies.inputHook then
        PlayerInputComponent.registerActionEvents = PlayerInputComponent.rseOriginalRegisterActionEvents
    end
    RoadsideEmergencies.inputHook = nil
end

-- the player's key registration may run before loadMap, so the hook goes in as soon as the scripts load
installInputHook()

function RoadsideEmergencies:loadMap()
    self.store = RseStore.new(RseConfig)
    self.store:subscribe(function(kind, data, result)
        self:onChange(kind, data, result)
    end)
    if MoneyType ~= nil and MoneyType.register ~= nil then
        self.moneyTypeFee = MoneyType.register("other", "rse_finance_disposalFee", self.MOD_NAME)
        self.moneyTypePay = MoneyType.register("other", "rse_finance_haulPay", self.MOD_NAME)
        self.moneyTypeCollection = MoneyType.register("other", "rse_finance_collection", self.MOD_NAME)
        self.moneyTypePenalty = MoneyType.register("other", "rse_finance_penalty", self.MOD_NAME)
    end
    installInputHook()
    local saveHook = RseSaveLoad.install(function(object)
        self:onSave(object)
    end)

    RseCarcasses:init(self.store, self.MOD_DIR, self.MOD_NAME)
    RsePoints:init(self.store)
    RseScenes:unload()
    RseScenes.store = self.store
    RseKit:init(self.store)
    RseSettingsPanel:init(self.store)
    RseCallPanel:init(self.store)
    RseScenes.onEnded = function(scene)
        RseKit:onJobEnded(scene.id)
        if RseCalls.state ~= nil then
            RseCallPlanner.reset(RseCalls.state)
        end
    end
    RseCalls:init()
    RseEpSteps.define()
    RseConsole:register(self)

    -- saved settings and points now; carcasses once the world is running (update)
    local directory = g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.savegameDirectory or nil
    local raw = RseSaveLoad.read(directory)
    local player = RsePlayerFile:read()
    local hadSave = raw ~= nil
    if raw == nil and player.settings ~= nil then
        raw = { settings = player.settings } -- a new savegame starts with your last settings (Z, Gate U)
        RseLog.info("a new savegame: it starts with your last settings")
    end
    local data, warnings = RseSaveCodec.normalize(raw, RseConfig)
    RseSavedLogs:restore(data.ownLogs, hadSave) -- before the game loads its trees
    RseCleanup:restore(data.cleanup)
    for _, warning in ipairs(warnings) do
        RseLog.info("savegame: %s", warning)
    end
    self.store:apply("setFeeFactor", { factor = data.settings.feeFactor })
    self.store:apply("setCallsEnabled", { enabled = data.settings.callsEnabled })
    self.store:apply("setJobSize", { size = data.settings.jobSize })
    self.store:apply("setGuideSeen", { seen = data.settings.guideSeen })
    for _, row in ipairs(RseSettings.ROWS) do
        if not row.legacy then
            self.store:apply("setSetting", { key = row.key, value = data.settings[row.key] })
        end
    end
    for _, point in ipairs(data.points) do
        self.store:apply("addPoint", { name = point.name, kind = point.kind, x = point.x, z = point.z, source = "player" })
    end
    RsePoints:refreshHotspots()
    self.pendingCarcasses = data.carcasses
    self.pendingStraps = data.straps
    self.pendingKit = data.kit
    self.pendingScene = data.scene
    RseTwisterTravel.savedBase = data.twister
    self.pendingDelayMs = RseConfig.PLACE_DELAY_MS

    RseLog.info("loaded version %s (game %s); save hook: %s; strap key: %s; body types registered: %d; %d saved carcass(es) to place; calls %s",
        tostring(g_modManager ~= nil and g_modManager:getModByName(self.MOD_NAME) ~= nil and g_modManager:getModByName(self.MOD_NAME).version),
        tostring(g_gameVersionDisplay), tostring(saveHook), InputAction.RSE_STRAP ~= nil and "ready" or "missing",
        RseCarcasses.bodyTypesRegistered, #data.carcasses, data.settings.callsEnabled and "on" or "off")
end

function RoadsideEmergencies:onSave(object)
    local directory = type(object) == "table" and object.savegameDirectory or nil
    if directory == nil and g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        directory = g_currentMission.missionInfo.savegameDirectory
    end
    local carcasses, indexOf = RseCarcasses:saveData()
    RseSaveLoad.write(directory, self.store, carcasses, RseStrap:saveData(indexOf), RseKit:saveData(), RseScenes:saveData(), RseTwisterTravel:saveData(),
        RseSavedLogs:saveData(), RseCleanup:saveData())
    RseLog.try("write the player file", RsePlayerFile.write, RsePlayerFile, self.store.settings)
end

-- game-side work for Store changes (money and messages)
function RoadsideEmergencies:onChange(kind, data, result)
    if kind == "setSetting" then
        RseSettings.applyTimes(self.store.settings, RseConfig)
        RseMarkers:setEnabled(self.store.settings.markersEnabled)
        return
    elseif kind == "removePoint" then
        RseMarkers:hide("point" .. result.id)
        return
    elseif kind == "collectCarcass" then
        local mission = g_currentMission
        local farmId = mission.getFarmId ~= nil and mission:getFarmId() or 1
        if result.total > 0 then
            RseLog.try("addMoney(collection bill)", mission.addMoney, mission, -result.total, farmId, self.moneyTypeCollection or MoneyType.OTHER, true, true)
        end
        if result.unearned > 0 then
            RseText.notify(RseText.get("rse_collectedUnearned", RseText.animal(result.record.kind), RseText.money(result.total),
                RseText.money(result.unearned)), true)
        else
            RseText.notify(RseText.get("rse_collected", RseText.animal(result.record.kind), RseText.money(result.total)), true)
        end
        RseLog.info("the county collected carcass %d (%s) left at %.0f, %.0f: fee $%d + charge $%d + pay taken back $%d", result.record.id,
            result.record.kind, data.x, data.z, result.fee, result.charge, result.unearned)
    elseif kind == "deliverCarcass" then
        local mission = g_currentMission
        local farmId = mission.getFarmId ~= nil and mission:getFarmId() or 1
        if result.pay > 0 then
            RseLog.try("addMoney(haul-off pay)", mission.addMoney, mission, result.pay, farmId, self.moneyTypePay or MoneyType.OTHER, true, true)
        end
        if result.fee > 0 then
            RseLog.try("addMoney(disposal fee)", mission.addMoney, mission, -result.fee, farmId, self.moneyTypeFee or MoneyType.OTHER, true, true)
        end
        RseText.notify(RseText.get("rse_delivered", RseText.animal(result.record.kind), result.pointName or "", RseText.money(result.pay),
            RseText.money(result.fee)))
        RseLog.info("delivered carcass %d (%s) at '%s': pay $%d, fee $%d", result.record.id, result.record.kind, tostring(result.pointName),
            result.pay, result.fee)
    end
end

function RoadsideEmergencies:update(dt)
    if self.store == nil then
        return
    end
    if not self.packChecked then
        self.packChecked = true
        self.packMissing = not RseEpBridge.check(self.MOD_NAME)
        self.packFound = not self.packMissing
        self.packNoticeMs = RseConfig.PACK_NOTICE_DELAY_MS
        RseWrecks:logVehicles()
    end
    if self.packMissing then
        self.packNoticeMs = self.packNoticeMs - dt
        if self.packNoticeMs <= 0 and g_localPlayer ~= nil and not (g_gui ~= nil and g_gui:getIsGuiVisible()) then
            self.packMissing = false
            RseEpBridge.tellMissing()
        end
    end
    if self.pendingCarcasses ~= nil then
        self.pendingDelayMs = self.pendingDelayMs - dt
        if self.pendingDelayMs <= 0 then
            local placed, byIndex, sceneEntries = 0, {}, {}
            for i, carcass in ipairs(self.pendingCarcasses) do
                local entry = RseCarcasses:spawn(carcass.kind, carcass.x, carcass.y, carcass.z, carcass.rx, carcass.ry, carcass.rz)
                if entry ~= nil then
                    placed = placed + 1
                    byIndex[i] = entry
                    if carcass.scene then
                        table.insert(sceneEntries, entry)
                    end
                    entry.left = RseLeftBehindRule.restore(carcass.leftMs, RseConfig)
                    entry.unearned = carcass.unearned
                end
            end
            if #self.pendingCarcasses > 0 then
                RseLog.info("placed %d of %d saved carcass(es)", placed, #self.pendingCarcasses)
                self.beltRefreshMs = RseConfig.BELT_REFRESH_DELAY_MS
            end
            if self.pendingStraps ~= nil and #self.pendingStraps > 0 then
                RseLog.info("put back %d of %d saved strap(s)", RseStrap:restore(self.pendingStraps, byIndex), #self.pendingStraps)
            end
            if self.pendingKit ~= nil and #self.pendingKit > 0 then
                RseLog.info("put back %d of %d saved scene kit item(s); %d still to collect", RseKit:restore(self.pendingKit),
                    #self.pendingKit, RseKit:owedCount())
            end
            if self.pendingScene ~= nil then
                RseScenes:beginResume(self.pendingScene, sceneEntries)
            end
            self.pendingCarcasses = nil
            self.pendingStraps = nil
            self.pendingKit = nil
            self.pendingScene = nil
        end
    end
    if self.beltRefreshMs ~= nil and g_currentMission:getIsServer() then
        self.beltRefreshMs = self.beltRefreshMs - dt
        if self.beltRefreshMs <= 0 then
            self.beltRefreshMs = nil
            local vehicles, held = RseCarcasses:refastenBeltsNearCarcasses()
            if vehicles > 0 then
                RseLog.info("fastened the tension belts of %d vehicle(s) carrying saved carcasses again; %d carcass(es) now held by belts",
                    vehicles, held)
            end
        end
    end
    RseSettingsPanel:update(dt)
    RseMapClicks:update()
    RseCarcassDrag.update()
    RseCarcasses:update(dt)
    RseStrap:update(dt)
    RseKit:update(dt)
    RseCallPanel:update(dt)
    if g_currentMission:getIsServer() then
        RseUtilityCrew:update(dt)
        RseScenes:update(dt)
        RseSurvivors:update(dt)
        RseCalls:update(dt, self.store)
    end
end

function RoadsideEmergencies:draw()
    RseKit:draw()
    RseScenes:draw()
    RseCallPanel:draw()
    RseSettingsPanel:draw()
end

function RoadsideEmergencies:deleteMap()
    RseStrap:forget()
    RseCarcassDrag.dragged = nil
    RseScenes:unload()
    RseSurvivors:unload()
    RseMapClicks:unload()
    RseKit:unload()
    RseMarkers:unload()
    RseSettingsPanel:unload()
    RseWrecks:unload()
    RseCarcasses:unload()
    RsePoints:unload()
    RseSavedLogs:unload()
    RseWelcome:unload()
    RseCallPlan:unload()
    RseCallPanel:unload()
    RseUtilityCrew:unload()
    RseDraw.unload()
    RseConsole:unregister()
    RseSaveLoad.uninstall()
    uninstallInputHook()
    self.store = nil
end

addModEventListener(RoadsideEmergencies)
