-- Roadside Emergencies: our steps inside the Emergency Pack's emergencies (DESIGN §2.4). The pack builds each checkpoint of a
-- scenario file from its actionClass attribute and finds our classes by their dotted names
-- ("FS25_RoadsideEmergencies.RseStepArrive"), so they must be globals of this mod. They extend the pack's own ScenarioAction,
-- so the pack keeps running the pager, the map marker, the progress bar and the hints, and pays what we tell it (P7b).
--   RseStepArrive    lays the animals in the road once the pack has placed the emergency; done when you are within
--                    `range` metres, in any vehicle or on foot. Attribute animals="cow:1-2" (RseSceneSpec).
--   RseStepClearRoad done when every animal of the scene is off the road: on the verge, loaded, towed away or delivered.
--   RseStepPrepare   done when the wreck has been prepared on foot (or the driver helped out).
--   RseStepUpright   done when the wreck stands on its wheels again.
--   RseStepCrash     a livestock trailer crash, in one step because the two parts can be done in any order: done when both are, or when
--                    another contractor takes the part you left.
--   RseStepDeliver   done when the wreck and any bales have reached a recovery point; only then the job ends (Z).
--   RseStepPower     a downed power line: done when the utility crew has cut the power.
--   RseStepTree      a tree on a car, in one step because its parts can be done in any order: done when the road is clear and the car is in.
-- Only the last step of a chain pays a job out, because completing a step only moves the pack on to the next one (Z, on the tree job: a job handed over from a
-- step in the middle went on to "help the driver" with its scene gone, and nothing could end it). A hand-over goes straight through the steps before the last.

RseEpSteps = {
    defined = false,
    waiting = nil   -- the expiry state of the job not reached yet
}

local function xmlString(xmlFile, path)
    if type(xmlFile.getString) == "function" then
        local ok, value = pcall(xmlFile.getString, xmlFile, path)
        if ok then
            return value
        end
    end
    return nil
end

local function xmlFloat(xmlFile, path, default)
    if type(xmlFile.getFloat) == "function" then
        local ok, value = pcall(xmlFile.getFloat, xmlFile, path, default)
        if ok and value ~= nil then
            return value
        end
    end
    return default
end

local function scenarioOf(action)
    local checkpoint = action.checkpoint
    return checkpoint ~= nil and checkpoint.getScenario ~= nil and checkpoint:getScenario() or nil
end

-- where the pack put the emergency (x, y, z), once it has
local function targetOf(scenario)
    local target = scenario ~= nil and scenario.targetPosition or nil
    if type(target) == "table" and target[1] ~= nil and target[3] ~= nil then
        return target[1], target[2], target[3]
    end
    return nil
end

local function isRunning(action)
    return action.checkpoint ~= nil and action.checkpoint.isActive and not action:isCompleted()
end

local function playerDistance(x, z)
    if g_localPlayer == nil then
        return nil
    end
    local vehicle = g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() or nil
    local px, pz
    if vehicle ~= nil and vehicle.rootNode ~= nil then
        local vx, _, vz = getWorldTranslation(vehicle.rootNode)
        px, pz = vx, vz
    else
        local fx, _, fz = g_localPlayer:getPosition()
        px, pz = fx, fz
    end
    return math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
end

-- Our pay instead of the pack's: its reward grows the faster you finish (thousands for a deer in 0.2.0.1). The pack asks the
-- emergency for its reward when it completes and applies the game's economy difficulty to it; this emergency's own
-- calculateReward (this one object only, nothing global) answers with the scene's call reward (RsePayRules.callReward).
local function installReward(scenario)
    if scenario.rseRewardInstalled then
        return
    end
    scenario.rseRewardInstalled = true
    if type(scenario.calculateReward) ~= "function" then
        RseLog.info("the emergency has no calculateReward; the pack's own pay stays. Names like 'reward': %s",
            RseEpBridge.namesLike(scenario, "reward"))
        return
    end
    scenario.calculateReward = function(target)
        return target.rseReward or RseConfig.CALL_PAY_BASE
    end
end

-- Our progress instead of the pack's, on this one emergency object: the pack counts its own steps, so reaching a scene showed 50% and then the job
-- jumped to the
-- end (Z). Whatever it reports, the bar shows what RseScenes says has been done.
local function installProgress(scenario)
    if scenario.rseProgressInstalled or type(scenario.setProgress) ~= "function" then
        return
    end
    scenario.rseProgressInstalled = true
    local original = scenario.setProgress
    scenario.setProgress = function(target, value)
        return original(target, target.rseProgress or value)
    end
end

-- Our location instead of the pack's: anywhere on the road network, or where a saved call was (RseScenes:nextSpot). FS25's pack
-- chooses before our step loads and doesn't ask the emergency's start strategy, and its onTargetPositionDetermined leaves the
-- position as it was (0.2.0.7's log), so the position is written here too, before anything has been laid out.
local function moveToOurSpot(scenario, onGround)
    if scenario.rseMoved then
        return
    end
    scenario.rseMoved = true
    local spot = RseScenes:nextSpot(onGround)
    if spot == nil then
        RseLog.info("no free road spot found; the emergency stays where the pack put it")
        return
    end
    local packX, _, packZ = targetOf(scenario)
    local ai = g_currentMission.aiSystem
    if ai ~= nil and ai.removeObstacle ~= nil and scenario.rootNode ~= nil then
        RseLog.try("remove the old obstacle", ai.removeObstacle, ai, scenario.rootNode)
    end
    if type(scenario.onTargetPositionDetermined) == "function" then
        RseLog.try("tell the emergency its position", scenario.onTargetPositionDetermined, scenario, spot.x, spot.y, spot.z)
    end
    scenario.targetPosition = { spot.x, spot.y, spot.z }
    if scenario.rootNode ~= nil then
        setWorldTranslation(scenario.rootNode, spot.x, spot.y, spot.z)
    end
    RseEpBridge.moveMarker(scenario, spot.x, spot.y, spot.z)
    RseLog.info("call location: %.1f, %.1f (the pack had picked %.1f, %.1f)", spot.x, spot.z, packX or 0, packZ or 0)
end

-- the scene of this emergency; lays it out from `spec` when it doesn't exist yet and the position is known; a saved call takes
-- back its animals instead
local function sceneFor(scenario, spec, emergency, wreckKind)
    if scenario == nil then
        return nil
    end
    local scene = RseScenes:get(scenario.rseSceneId)
    if scene == nil and scenario.rseSceneId == nil and (spec ~= nil or wreckKind ~= nil) then
        if targetOf(scenario) ~= nil then
            -- the call was planned before the pager (CallPlan.lua): the place, the animals and the load it promised
            local plan = not RseScenes:isResuming() and RseCallPlan:take(emergency) or nil
            -- wrecks stay off bridges: there is no room to right one up there, and its load would go over the side
            if plan ~= nil then
                RseScenes.spotExact, RseScenes.plannedKinds, RseScenes.plannedLoad = plan.spot, plan.kinds, plan.load
            elseif wreckKind == "crossing" and not RseScenes:isResuming() then
                RseScenes.spotExact = RseLevelCrossing:pickSpot()
            elseif wreckKind == "river" and not RseScenes:isResuming() then
                RseScenes.spotExact = RseRiver:pickSpot()
            elseif wreckKind == "flock" and not RseScenes:isResuming() then
                local ok, spot = RseLog.try("find a place for the flock", RseFlockPlaces.pickSpot, RseFlockPlaces)
                RseScenes.spotExact = ok and spot or nil
            elseif wreckKind == "powerline" and not RseScenes:isResuming() then
                local ok, spot = RseLog.try("find room for a power line", RsePowerLine.pickSpot, RsePowerLine)
                RseScenes.spotExact = ok and spot or nil
            end
            moveToOurSpot(scenario, wreckKind ~= nil)
            local x, y, z = targetOf(scenario)
            local created, reason
            if RseScenes:isResuming() then
                created = RseScenes:adopt()
            else
                if wreckKind ~= nil then
                    created = RseScenes:createWreck(x, y, z, wreckKind, emergency)
                else
                    created, reason = RseScenes:create(x, y, z, spec, emergency)
                end
                if created ~= nil then
                    RseScenes:announce(created)
                end
            end
            -- remember the attempt either way, so a failed scene isn't retried every frame
            scenario.rseSceneId = created ~= nil and created.id or false
            scenario.rseReward = created ~= nil and created.reward or nil
            if created ~= nil then
                created.scenario = scenario
            end
            installReward(scenario)
            installProgress(scenario)
            scenario.rseProgress = 0
            if created == nil then
                RseLog.info("emergency scene could not be laid out: %s", tostring(reason))
            end
            scene = created
        end
    end
    return scene
end

-- the emergency ended (completed, declined midway or cancelled): our scene goes with it unless it was finished
local function endScene(scenario)
    local scene = scenario ~= nil and RseScenes:get(scenario.rseSceneId) or nil
    if scene ~= nil then
        RseScenes:abandon(scene)
    end
end

local function defineSteps(base)
    RseStepArrive = {}
    local arriveMt = Class(RseStepArrive, base)

    -- the step is done (reached, or handed over first): the clock for another contractor stops
    local function reached(self)
        if RseEpSteps.waiting == self.rseExpiry then
            RseEpSteps.waiting = nil
        end
        self.checkpoint:setActionCompleted(true)
    end

    function RseStepArrive.new(checkpoint, customMt)
        local self = RseStepArrive:superClass().new(checkpoint, customMt or arriveMt)
        self.rseRange = 20
        self.rseAnimals = nil
        return self
    end

    function RseStepArrive:loadFromXML(xmlFile, baseKey, baseDirectory, rootNode)
        if not RseStepArrive:superClass().loadFromXML(self, xmlFile, baseKey, baseDirectory, rootNode) then
            return false
        end
        self.rseRange = xmlFloat(xmlFile, baseKey .. "#range", self.rseRange)
        self.rseAnimals = xmlString(xmlFile, baseKey .. "#animals")
        self.rseEmergency = xmlString(xmlFile, baseKey .. "#emergency")
        self.rseWreck = xmlString(xmlFile, baseKey .. "#wreck")
        return true
    end

    function RseStepArrive:onUpdate(dt)
        RseStepArrive:superClass().onUpdate(self, dt)
        if not isRunning(self) then
            return
        end
        local scenario = scenarioOf(self)
        local scene = sceneFor(scenario, self.rseAnimals, self.rseEmergency, self.rseWreck)
        if scene ~= nil and scene.wreck ~= nil then
            RseWrecks:update(scene.wreck, dt)
            if RseScenes:checkWreckGone(scene) then
                return
            end
            RsePowerLine:update(scene, dt)
            RseLogSpill:update(scene, dt)
            if RseLevelCrossing:update(scene) then
                return
            end
            if scene.wreck.failed then
                RseText.notify(RseText.get("rse_call_cancelled"), true)
                RseEpBridge.cancel()
                return
            end
        end
        if scene ~= nil and scene.handOverNow then
            reached(self) -- handed over before you got there, with something done: the last step settles it
            return
        end
        -- a saved call you had already reached: you may be far away with the wreck by now, and no other contractor takes it from you
        if scene ~= nil and scene.arrived then
            reached(self)
            return
        end
        local x, _, z = targetOf(scenario)
        local distance = x ~= nil and playerDistance(x, z) or nil
        if distance ~= nil and distance <= self.rseRange then
            RseLog.debug("arrived at the emergency (%.0f m)", distance)
            if scene ~= nil then
                scene.arrived = true
                RseScenes:announceArrival(scene)
            end
            reached(self)
            return
        end
        -- not there yet: the job goes to another contractor in the end (no pay, and a small charge)
        self.rseExpiry = self.rseExpiry or {}
        RseEpSteps.waiting = self.rseExpiry
        local event = RseJobRules.tickExpiry(self.rseExpiry, dt, RseConfig)
        if event == "warn" then
            RseText.notify(RseText.get("rse_call_expiring", RseText.minutes(math.ceil(RseConfig.JOB_EXPIRE_WARN_MS / 60000))), true)
        elseif event == "expire" and not self.rseExpired then
            self.rseExpired = true
            RseLog.info("nobody reached the emergency in time: another contractor took over")
            local fee = scene ~= nil and RseScenes:chargePenalty(scene) or 0
            RseText.notify(fee > 0 and RseText.get("rse_call_expiredFee", RseText.money(fee)) or RseText.get("rse_call_expired"), true)
            RseEpBridge.cancel()
        end
    end

    function RseStepArrive:canBeCompleted()
        return self.checkpoint ~= nil and self.checkpoint.isActive
    end

    function RseStepArrive:delete()
        if RseEpSteps.waiting == self.rseExpiry then
            RseEpSteps.waiting = nil
        end
        endScene(scenarioOf(self))
        RseStepArrive:superClass().delete(self)
    end

    RseStepClearRoad = {}
    local clearMt = Class(RseStepClearRoad, base)

    function RseStepClearRoad.new(checkpoint, customMt)
        local self = RseStepClearRoad:superClass().new(checkpoint, customMt or clearMt)
        self.rseAnimals = nil
        return self
    end

    function RseStepClearRoad:loadFromXML(xmlFile, baseKey, baseDirectory, rootNode)
        if not RseStepClearRoad:superClass().loadFromXML(self, xmlFile, baseKey, baseDirectory, rootNode) then
            return false
        end
        self.rseAnimals = xmlString(xmlFile, baseKey .. "#animals")
        return true
    end

    function RseStepClearRoad:onUpdate(dt)
        RseStepClearRoad:superClass().onUpdate(self, dt)
        if not isRunning(self) then
            return
        end
        local scenario = scenarioOf(self)
        local scene = sceneFor(scenario, self.rseAnimals)
        if scene == nil then
            if scenario ~= nil and (scenario.rseSceneId == false or targetOf(scenario) ~= nil) then
                -- nothing of ours lies there (a restored emergency, or the scene failed): don't leave the player stuck
                installReward(scenario)
                RseLog.info("emergency without animals in the road; step completed")
                self.checkpoint:setActionCompleted(true)
            end
            return
        end
        if RseScenes:isClear(scene) then
            RseScenes:finish(scene)
            scenario.rseReward = scene.reward
            scenario.rseProgress = 1
            local okPay, paid = false, nil
            if type(scenario.getReward) == "function" then
                okPay, paid = RseLog.try("getReward", scenario.getReward, scenario)
            end
            RseLog.info("road clear: call reward $%s; with the economy difficulty the pack pays $%s", tostring(scenario.rseReward),
                okPay and type(paid) == "number" and string.format("%.0f", paid) or "?")
            RseScenes:applyPayFactor(scene, okPay and paid or nil)
            self.checkpoint:setActionCompleted(true)
        end
    end

    function RseStepClearRoad:canBeCompleted()
        return self.checkpoint ~= nil and self.checkpoint.isActive
    end

    function RseStepClearRoad:delete()
        endScene(scenarioOf(self))
        RseStepClearRoad:superClass().delete(self)
    end
end

-- defines the wreck steps on the pack's class
local function defineWreckSteps(base)
    local function sceneOf(action)
        local scenario = scenarioOf(action)
        return scenario ~= nil and RseScenes:get(scenario.rseSceneId) or nil, scenario
    end

    local function wreckStep(name, onRunning)
        local class = {}
        local mt = Class(class, base)

        function class.new(checkpoint, customMt)
            return class:superClass().new(checkpoint, customMt or mt)
        end

        function class:onUpdate(dt)
            class:superClass().onUpdate(self, dt)
            if not isRunning(self) then
                return
            end
            local scene, scenario = sceneOf(self)
            if scene == nil or scene.wreck == nil then
                -- A step with nothing to run can never finish, and with no scene the settings panel can't end it either, so it ends here, whatever led to it.
                if scenario ~= nil and scenario.rseReward ~= nil then
                    self.checkpoint:setActionCompleted(true)
                elseif scenario ~= nil and not self.rseStuck then
                    self.rseStuck = true
                    RseLog.problem("the step %s has no scene: the emergency is cancelled", name)
                    RseText.notify(RseText.get("rse_call_cancelled"), true)
                    RseEpBridge.cancel()
                end
                return
            end
            RseWrecks:update(scene.wreck, dt)
            if RseScenes:checkWreckGone(scene) then
                return
            end
            RsePowerLine:update(scene, dt)
            RseLogSpill:update(scene, dt)
            if RseLevelCrossing:update(scene) then
                return
            end
            onRunning(self, scene, scenario, dt)
        end

        function class:canBeCompleted()
            return self.checkpoint ~= nil and self.checkpoint.isActive
        end

        function class:delete()
            endScene(scenarioOf(self))
            class:superClass().delete(self)
        end

        RseLog.debug("wreck step %s defined", name)
        return class
    end

    -- the job is over: the pack pays what the scene says
    local function payOut(action, scene, scenario)
        scenario.rseReward = scene.reward
        scenario.rseProgress = 1
        local okPay, paid = false, nil
        if type(scenario.getReward) == "function" then
            okPay, paid = RseLog.try("getReward", scenario.getReward, scenario)
        end
        RseLog.info("wreck job done: pay $%s; with the economy difficulty the pack pays $%s", tostring(scene.reward),
            okPay and type(paid) == "number" and string.format("%.0f", paid) or "?")
        RseScenes:applyPayFactor(scene, okPay and paid or nil)
        action.checkpoint:setActionCompleted(true)
    end

    RseStepPrepare = wreckStep("prepare", function(action, scene)
        if scene.handOverNow or scene.wreck.state ~= "locked" then
            action.checkpoint:setActionCompleted(true)
        end
    end)

    -- a tree on a car: the last step, so a hand-over ends it here
    RseStepTree = wreckStep("tree", function(action, scene, scenario, dt)
        if scene.handOverNow then
            RseScenes:finishLogs(scene)
            payOut(action, scene, scenario)
        elseif RseScenes:updateTree(scene, scenario, dt) then
            RseScenes:finishTree(scene)
            payOut(action, scene, scenario)
        end
    end)

    -- a flock: the pack's marker shows the way to the pen
    RseStepFlock = wreckStep("flock", function(action, scene, scenario)
        if not action.rseMarkerMoved and scene.flock ~= nil then
            action.rseMarkerMoved = true
            local pen = scene.flock.pen
            RseEpBridge.moveMarker(scenario, pen.x, getTerrainHeightAtWorldPos(g_terrainNode, pen.x, 0, pen.z), pen.z)
        end
        if scene.handOverNow or RseFlock:isDone(scene) then
            RseScenes:finishFlock(scene)
            payOut(action, scene, scenario)
        end
    end)

    RseStepPower = wreckStep("power", function(action, scene, _, dt)
        if scene.handOverNow or scene.line == nil or RsePowerLine:updatePower(scene, dt) then
            action.checkpoint:setActionCompleted(true)
        end
    end)

    RseStepCrash = wreckStep("crash", function(action, scene, scenario, dt)
        if RseScenes:updateCrash(scene, scenario, dt) then
            RseScenes:finishCrash(scene)
            payOut(action, scene, scenario)
        end
    end)

    -- the logs are the job
    RseStepLogs = wreckStep("logs", function(action, scene, scenario)
        if scene.handOverNow or RseLogSpill:isDone(scene) then
            RseScenes:finishLogs(scene)
            payOut(action, scene, scenario)
        end
    end)

    -- off the tracks, the pack's marker shows the way to the nearest recovery point; it pays when the vehicle is there
    RseStepCrossing = wreckStep("crossing", function(action, scene, scenario, dt)
        if not action.rseMarkerMoved and scene.crossing ~= nil and scene.crossing.clear then
            action.rseMarkerMoved = true
            local point = RseScenes.store ~= nil and RseScenes.store.points:nearest(scene.x, scene.z, "recovery") or nil
            if point ~= nil then
                RseEpBridge.moveMarker(scenario, point.x, getTerrainHeightAtWorldPos(g_terrainNode, point.x, 0, point.z), point.z)
            end
        end
        if RseWrecks:checkDelivered(scene.wreck, dt) then
            RseScenes:finishWreck(scene)
            payOut(action, scene, scenario)
        end
    end)

    RseStepUpright = wreckStep("upright", function(action, scene)
        if scene.handOverNow then
            action.checkpoint:setActionCompleted(true)
        elseif scene.wreck.state == "ready" then
            RseText.notify(RseText.get("rse_wreck_upright"))
            action.checkpoint:setActionCompleted(true)
        end
    end)

    RseStepDeliver = wreckStep("deliver", function(action, scene, scenario, dt)
        -- the pack's marker now shows the way to the nearest recovery point
        if not action.rseMarkerMoved then
            action.rseMarkerMoved = true
            local point = RseScenes.store ~= nil and RseScenes.store.points:nearest(scene.x, scene.z, "recovery") or nil
            if point ~= nil then
                RseEpBridge.moveMarker(scenario, point.x, getTerrainHeightAtWorldPos(g_terrainNode, point.x, 0, point.z), point.z)
            end
        end
        if scene.handOverNow then
            RseScenes:finishPartial(scene)
            payOut(action, scene, scenario)
        elseif RseWrecks:checkDelivered(scene.wreck, dt) then
            RseScenes:finishWreck(scene)
            payOut(action, scene, scenario)
        end
    end)
end

-- defines the step classes on the pack's classes; true once they exist. Safe to call again.
function RseEpSteps.define()
    if RseEpSteps.defined then
        return true
    end
    local env = _G[RseConfig.EP_ENV_NAME]
    if type(env) ~= "table" or type(env.ScenarioAction) ~= "table" then
        return false
    end
    local ok = RseLog.try("define emergency steps", defineSteps, env.ScenarioAction)
    ok = ok and RseLog.try("define wreck steps", defineWreckSteps, env.ScenarioAction)
    RseEpSteps.defined = ok == true
    return RseEpSteps.defined
end

-- the pack's scripts load before mods, so the classes can exist before any scenario file is read
RseEpSteps.define()
