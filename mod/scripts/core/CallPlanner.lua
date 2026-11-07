-- Roadside Emergencies: when county dispatch calls, and for what (the living-world trigger, DESIGN F20). Engine-free.
-- The Emergency Pack's own pager only calls farms that own pack vehicles (P9), so we ask for our calls ourselves.
-- Every CALL_CHECK_MS of play a call comes with chance CALL_CHANCE, but never within CALL_GAP_MS of the last one and never
-- while the farm already has an emergency. Which emergency: weighted (config.EMERGENCIES); deer and boar are likelier at
-- dusk and dawn, deer also in autumn. Big jobs (group wreck) come no closer than CALL_BIG_GAP_MS, however short the gap is set.

RseCallPlanner = {}

function RseCallPlanner.newState(config)
    return { sinceLastMs = math.huge, sinceBigMs = math.huge, untilFirstMs = config.CALL_FIRST_MS, untilCheckMs = config.CALL_CHECK_MS }
end

-- after a call (asked for, or an emergency just ended): the gap starts again
function RseCallPlanner.reset(state)
    state.sinceLastMs = 0
end

-- a call went out: the gap starts again, and the wait for the next big job if this was one
function RseCallPlanner.noteCall(state, id, config)
    RseCallPlanner.reset(state)
    for _, emergency in ipairs(config.EMERGENCIES) do
        if emergency.id == id and emergency.group == "wreck" then
            state.sinceBigMs = 0
        end
    end
end

function RseCallPlanner.isDuskOrDawn(hour, config)
    for _, h in ipairs(config.DUSK_DAWN_HOURS) do
        if h == hour then
            return true
        end
    end
    return false
end

-- context: { hour, isAutumn, disabled = { id = true }, noBig = true while big jobs have to wait }. Returns { { id, weight }, ... } (weights > 0 only).
function RseCallPlanner.weights(context, config)
    local list = {}
    local dusk = context.hour ~= nil and RseCallPlanner.isDuskOrDawn(context.hour, config)
    for _, emergency in ipairs(config.EMERGENCIES) do
        if not (context.disabled ~= nil and context.disabled[emergency.id]) and not (context.noBig and emergency.group == "wreck") then
            local weight = emergency.weight
            if dusk and emergency.duskFactor ~= nil then
                weight = weight * emergency.duskFactor
            end
            if context.isAutumn and emergency.autumnFactor ~= nil then
                weight = weight * emergency.autumnFactor
            end
            if weight > 0 then
                table.insert(list, { id = emergency.id, weight = weight })
            end
        end
    end
    return list
end

-- roll in [0, 1): the emergency it lands on, or nil for an empty list
function RseCallPlanner.pick(list, roll)
    local total = 0
    for _, item in ipairs(list) do
        total = total + item.weight
    end
    if total <= 0 then
        return nil
    end
    local target = roll * total
    for _, item in ipairs(list) do
        target = target - item.weight
        if target < 0 then
            return item.id
        end
    end
    return list[#list].id
end

-- Called every frame with the frame time. context: { enabled, busy, hour, isAutumn, disabled }.
-- Returns the id of the emergency to ask for, or nil.
function RseCallPlanner.tick(state, dt, context, config, random)
    state.sinceLastMs = state.sinceLastMs + dt
    state.sinceBigMs = state.sinceBigMs + dt
    state.untilFirstMs = state.untilFirstMs - dt
    state.untilCheckMs = state.untilCheckMs - dt
    if state.untilCheckMs > 0 then
        return nil
    end
    state.untilCheckMs = config.CALL_CHECK_MS
    if not context.enabled or context.busy or state.untilFirstMs > 0 or state.sinceLastMs < config.CALL_GAP_MS then
        return nil
    end
    if random() >= config.CALL_CHANCE then
        return nil
    end
    context.noBig = state.sinceBigMs < config.CALL_BIG_GAP_MS
    local id = RseCallPlanner.pick(RseCallPlanner.weights(context, config), random())
    if id ~= nil then
        RseCallPlanner.noteCall(state, id, config)
    end
    return id
end
