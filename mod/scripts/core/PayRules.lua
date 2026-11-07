-- Roadside Emergencies: what the county pays. Engine-free.
-- When an emergency's road is clear the Emergency Pack pays the call reward (callReward, our amount in place of the pack's).
-- Delivering a carcass at a disposal point: the county pays for the haul-off (haulPay), and the site charges its fee
-- (disposalFee); the pay is the larger, so hauling is worth it (DESIGN F5, Z).

RsePayRules = {}

local function amount(base, perKg, massKg, factor)
    local mass = math.max(0, tonumber(massKg) or 0)
    local f = math.max(0, tonumber(factor) or 1)
    return math.floor((base + perKg * mass) * f + 0.5)
end

-- whole dollars the county pays for hauling one carcass away: a base amount plus an amount per kilogram, times the setting
function RsePayRules.haulPay(massKg, factor, config)
    return amount(config.HAUL_PAY_BASE, config.HAUL_PAY_PER_KG, massKg, factor)
end

-- whole dollars the disposal site charges for one carcass, worked out the same way; never negative
function RsePayRules.disposalFee(massKg, factor, config)
    return amount(config.FEE_BASE, config.FEE_PER_KG, massKg, factor)
end

-- whole dollars the county charges for collecting a carcass left behind, on top of the disposal fee
function RsePayRules.collectionCharge(massKg, factor, config)
    return amount(config.COLLECTION_BASE, config.COLLECTION_PER_KG, massKg, factor)
end

-- Whole dollars for clearing a road. kinds: all its animals; roadsideKinds: those only moved to the roadside, which pay very little
-- (Z: that takes under a minute); the base amount is shared in proportion. Unknown kinds count as nothing.
function RsePayRules.callReward(kinds, roadsideKinds, config)
    local atRoadside = {}
    for _, kind in ipairs(roadsideKinds or {}) do
        atRoadside[kind] = (atRoadside[kind] or 0) + 1
    end
    local hauled, roadside, total = 0, 0, 0
    for _, kind in ipairs(kinds or {}) do
        if (atRoadside[kind] or 0) > 0 then
            atRoadside[kind] = atRoadside[kind] - 1
            roadside = roadside + 1
            total = total + config.CALL_PAY_ROADSIDE_PER_ANIMAL
        else
            hauled = hauled + 1
            local entry = RseAnimalCatalog.get(kind)
            if entry ~= nil then
                total = total + config.CALL_PAY_PER_ANIMAL + config.CALL_PAY_PER_KG * entry.massKg
            end
        end
    end
    local count = hauled + roadside
    if count == 0 then
        return config.CALL_PAY_BASE
    end
    total = total + (config.CALL_PAY_BASE * hauled + config.CALL_PAY_ROADSIDE_BASE * roadside) / count
    return math.floor(total + 0.5)
end

-- The part of the call reward paid for hauling this animal: what the reward would have been less if it had only gone to the roadside.
-- The county takes it back if it has to collect the animal after all, so towing one off, unhooking it and leaving it ends the same as
-- leaving it at the roadside (Z: fair enough to discourage that).
function RsePayRules.unearnedPay(kinds, roadsideKinds, kind, config)
    local more = {}
    for _, other in ipairs(roadsideKinds or {}) do
        table.insert(more, other)
    end
    table.insert(more, kind)
    return RsePayRules.callReward(kinds, roadsideKinds, config) - RsePayRules.callReward(kinds, more, config)
end

-- an amount of pay with the income setting
function RsePayRules.scaled(amountOfPay, factor)
    return math.floor(amountOfPay * (tonumber(factor) or 1) + 0.5)
end

-- the call reward with the extra pay for warning lights at the scene
function RsePayRules.withLightsBonus(reward, config)
    return math.floor(reward * (1 + config.CALL_LIGHTS_BONUS) + 0.5)
end

-- The warning lights bonus is earned by lights kept on at the scene, LIGHTS_EARN_MS in all (Z: pressing the button and pressing it off again earned it).
-- on: lights of yours are on there right now. state: { ms, earned }, updated here. Returns "earned" the moment it is.
function RsePayRules.tickLights(state, dt, on, config)
    if state.earned or not on then
        return nil
    end
    state.ms = (state.ms or 0) + dt
    if state.ms >= config.LIGHTS_EARN_MS then
        state.earned = true
        return "earned"
    end
    return nil
end

-- What a job you said yes to costs if it ends with no pay: a small part of that pay, with the pay setting, in steps of $5 (Z).
function RsePayRules.penalty(reward, factor, config)
    local pay = RsePayRules.scaled(tonumber(reward) or 0, factor)
    return math.floor(pay * config.JOB_PENALTY_SHARE / 5 + 0.5) * 5
end

-- the fee setting kept inside its allowed range
function RsePayRules.clampFactor(factor, config)
    local f = tonumber(factor) or config.FEE_FACTOR_DEFAULT
    return math.min(config.FEE_FACTOR_MAX, math.max(config.FEE_FACTOR_MIN, f))
end
