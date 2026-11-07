-- Roadside Emergencies: a call planned before the pager asks (U3, P5 in docs/UI_RESEARCH.md; Z at Gate U: you must know before you say yes). Where it is,
-- how many animals, the vehicle and its load, and when the train comes are decided here, and the pager says them, one field a line (RsePagerRules); the
-- scene is then laid out from the same plan (EpSteps.lua, sceneFor), so what the pager said is what you find.
-- A plan is only used by the call it was made for, and only for a while: a call you declined leaves nothing behind that a later call could pick up.

RseCallPlan = {
    plan = nil,
    specs = {}   -- emergency id -> its animals ("deer:1-2"), read once from our own emergencies/<id>.xml
}

-- the calls that need a place found for them: no place, no call
local SPECIAL = { crossing = true, river = true, flock = true, powerline = true, tree = true }

local function emergencyOf(id)
    for _, emergency in ipairs(RseConfig.EMERGENCIES) do
        if emergency.id == id then
            return emergency
        end
    end
    return nil
end

-- the kind of vehicle job, or nil for an animal call
local function wreckKindOf(emergency)
    if emergency.wreck ~= nil then
        return emergency.wreck
    end
    return RseConfig.WRECKS[emergency.id] ~= nil and emergency.id or nil
end

-- the animals an animal call has, as its step in our own XML says (the one place it is written)
local function animalSpec(self, id)
    if self.specs[id] ~= nil then
        return self.specs[id] or nil
    end
    self.specs[id] = false
    local file = Utils.getFilename("emergencies/" .. id .. ".xml", RoadsideEmergencies.MOD_DIR)
    local xmlId = fileExists(file) and loadXMLFile("rseCallSpec", file) or nil
    if xmlId == nil or xmlId == 0 then
        return nil
    end
    for i = 0, 7 do
        local spec = getXMLString(xmlId, string.format("scenario.checkpoints.checkpoint(%d).action#animals", i))
        if spec ~= nil then
            self.specs[id] = spec
            break
        end
    end
    delete(xmlId)
    return self.specs[id] or nil
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

local function pickSpot(id, isWreck)
    if id == "crossing" then
        return RseLevelCrossing:pickSpot()
    elseif id == "river" then
        return RseRiver:pickSpot()
    elseif id == "flock" then
        return RseFlockPlaces:pickSpot()
    elseif id == "powerline" then
        return RsePowerLine:pickSpot()
    elseif id == "tree" then
        return RseLogSpill:pickTreeSpot()
    end
    return RseScenes:nextSpot(isWreck)
end

local function settings()
    return RseScenes.store ~= nil and RseScenes.store.settings or {}
end

-- money as the job will pay it: the pay setting, and the economy difficulty as the pack applies it
local function payRatio()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    return RsePagerRules.payRatio(info ~= nil and info.economicDifficulty or nil, RseScenes.lastPayRatio)
end

local function aboutMoney(amount)
    return RseText.money(RsePagerRules.about(RsePayRules.scaled(amount, settings().payFactor or 1) * payRatio(), RseConfig))
end

local function exactMoney(amount)
    return RseText.money(math.floor(RsePayRules.scaled(amount, settings().payFactor or 1) * payRatio() + 0.5))
end

local function whereField(plan)
    local px, pz = playerPosition()
    if plan.spot == nil or px == nil then
        return nil
    end
    local dx, dz = plan.spot.x - px, plan.spot.z - pz
    local distance = math.sqrt(dx * dx + dz * dz)
    local direction = RsePagerRules.compass(dx, dz)
    if direction == nil or distance < RseConfig.PAGER_NEAR then
        return RseText.get("rse_pager_whereNear")
    end
    return RseText.get("rse_pager_where", RseText.aboutDistance(distance), RseText.get("rse_dir_" .. direction))
end

local function whatField(plan)
    if plan.kinds ~= nil and #plan.kinds > 0 then
        return RseText.get("rse_pager_animals", #plan.kinds, RseText.animalUnit(plan.kinds[1], #plan.kinds))
    end
    if plan.variant ~= nil then
        local name = RseWrecks:nameOf(plan.variant)
        if name ~= nil then
            return RseText.get(plan.variant.heavy and "rse_pager_vehicleHeavy" or "rse_pager_vehicle", name)
        end
    end
    return nil
end

local function loadField(plan)
    if plan.load == nil then
        return nil
    end
    return RseText.get("rse_pager_load_" .. plan.load.id)
end

-- what the job takes, and which of your vehicles can do it: { needKey, machineNeed } pairs
local function needsOf(plan, emergency)
    local list = {}
    local kind = plan.kind
    if kind == nil then
        local heavy = false
        for _, animal in ipairs(plan.kinds or {}) do
            heavy = heavy or not RseAnimalCatalog.isDraggable(animal, RseConfig.DRAG_MAX_MASS_KG)
        end
        table.insert(list, heavy and { "rse_pager_need_pull", "pull" } or { "rse_pager_need_hands" })
        return list
    end
    if kind == "flock" then
        table.insert(list, { "rse_pager_need_flock" })
        return list
    end
    if kind == "logging" then
        table.insert(list, { "rse_pager_need_logs", "pull" })
        return list
    end
    if kind == "crossing" then
        table.insert(list, { "rse_pager_need_line" })
    end
    if plan.variant ~= nil then
        table.insert(list, plan.variant.heavy and { "rse_pager_need_heavy", "heavy" } or { "rse_pager_need_tow", "pull" })
    end
    if emergency.needs == "livestock" then
        table.insert(list, { "rse_pager_need_livestock", "livestock" })
    end
    if emergency.needs == "carry" then
        table.insert(list, { "rse_pager_need_carry", "carry" })
    end
    if plan.load ~= nil and plan.load.needsLift then
        table.insert(list, { "rse_pager_need_lift", "lift" })
    end
    return list
end

local function takesFields(plan, emergency)
    local needs, words, names, seen = needsOf(plan, emergency), {}, {}, {}
    local fleet = RseCalls ~= nil and RseCalls:fleet() or nil
    for _, need in ipairs(needs) do
        table.insert(words, RseText.get(need[1]))
        local name = need[2] ~= nil and fleet ~= nil and RsePagerRules.bestMachine(fleet.machines, need[2], RseConfig) or nil
        if name ~= nil and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    local takes = #words > 0 and RseText.get("rse_pager_takes", table.concat(words, RseText.get("rse_pager_and"))) or nil
    local have = #names > 0 and RseText.get("rse_pager_youHave", table.concat(names, ", ")) or nil
    return takes, have
end

local function timeField(plan)
    if plan.seconds ~= nil then
        return RseText.get("rse_pager_train", RseText.minutes(math.max(1, math.floor(plan.seconds / 60 + 0.5))))
    end
    return RseText.get("rse_pager_time", RseText.minutes(math.floor(RseConfig.JOB_EXPIRE_MS / 60000 + 0.5)))
end

local function payField(plan)
    if plan.kind == nil then
        return RseText.get("rse_pager_pay", aboutMoney(RsePayRules.callReward(plan.kinds or {}, {}, RseConfig)))
    end
    local def = RseConfig.WRECKS[plan.kind]
    local haul = 0
    if plan.spot ~= nil and not def.noVehicle and not def.scenery then
        haul = RseScenes:haulPayAt(def, plan.spot.x, plan.spot.z)
    end
    local each, item = nil, nil
    if def.spills and plan.load ~= nil then
        each, item = RseWreckRules.balePay(plan.load, not def.noVehicle), "bale"
    elseif def.payPerSurvivor ~= nil then
        each, item = def.payPerSurvivor, "animal"
    elseif def.wirePay ~= nil then
        each, item = def.wirePay, "wire"
    elseif def.payPerLog ~= nil then
        each, item = def.payPerLog, "log"
    elseif def.payPerAnimal ~= nil then
        each, item = def.payPerAnimal, "sheep"
    end
    if each ~= nil then
        return RseText.get("rse_pager_payEach", aboutMoney(def.pay + haul), exactMoney(each), RseText.get("rse_pager_item_" .. item))
    end
    return RseText.get("rse_pager_pay", aboutMoney(def.pay + haul))
end

-- the pager's text for the plan, and a short line to show on the screen if the pager turns out not to carry it
local function compose(plan, emergency)
    local description = RseText.get("rse_ep_" .. plan.id .. "_description")
    local takes, have = takesFields(plan, emergency)
    local what, load = whatField(plan), loadField(plan)
    -- a field with nothing to say is nil, and a list with a gap stops there: so each goes in only if it is there
    local fields, short = {}, {}
    local function add(list, field)
        if field ~= nil then
            table.insert(list, field)
        end
    end
    for _, field in ipairs({ "where", "what", "load", "takes", "have", "time", "pay" }) do
        if field == "where" then
            add(fields, whereField(plan))
        elseif field == "what" then
            add(fields, what)
            add(short, what)
        elseif field == "load" then
            add(fields, load)
            add(short, load)
        elseif field == "takes" then
            add(fields, takes)
            add(short, takes)
        elseif field == "have" then
            add(fields, have)
        elseif field == "time" then
            add(fields, timeField(plan))
        else
            add(fields, payField(plan))
        end
    end
    return RsePagerRules.compose(description, fields), #short > 0 and table.concat(short, " ") or nil
end

-- Plans the call `id` and writes its pager text. Returns the plan, or nil and why the call can't come (a call that needs a special place found none).
function RseCallPlan:make(id)
    self.plan = nil
    local emergency = emergencyOf(id)
    if emergency == nil then
        return nil, "no such call"
    end
    local kind = wreckKindOf(emergency)
    local plan = { id = id, kind = kind, madeMs = g_time or 0 }
    if emergency.wreck ~= nil then
        RseWrecks:planCall(id)
        plan.variant = RseWrecks.planned ~= nil and RseWrecks.planned.variant or nil
    end
    local ok, spot = RseLog.try("plan where the call is", pickSpot, id, kind ~= nil)
    plan.spot = ok and spot or nil
    if plan.spot == nil and SPECIAL[id] then
        return nil, "no place for it"
    end
    if kind == nil then
        local spec = animalSpec(self, id)
        if spec ~= nil then
            plan.kinds = RseSceneSpec.pick(RseSceneSpec.parse(spec), math.random, settings().jobSize)
        end
    elseif RseConfig.WRECKS[kind].spills then
        plan.load = RseWreckRules.pickLoad(RseConfig.WRECKS[kind], math.random(), RseConfig, RseCalls ~= nil and RseCalls:fleet() or nil)
    end
    if id == "crossing" and RseLevelCrossing.pending ~= nil then
        plan.seconds = RseLevelCrossing.pending.seconds
    end
    plan.text, plan.short = compose(plan, emergency)
    self.plan = plan
    return plan
end

-- the plan for this call, once: nil if it was made for another call or too long ago
function RseCallPlan:take(emergency)
    local plan = self.plan
    self.plan = nil
    if plan == nil or plan.id ~= emergency or (g_time or 0) - plan.madeMs > RseConfig.PLAN_MAX_MS then
        return nil
    end
    return plan
end

function RseCallPlan:unload()
    self.plan, self.specs = nil, {}
end
