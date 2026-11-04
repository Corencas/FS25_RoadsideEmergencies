-- Roadside Emergencies: the rules of wreck jobs. Engine-free. A wreck goes locked -> (tipped ->) ready -> delivered: a wreck lying on
-- its side has to be righted first. Wrecks and spilled loads must reach a recovery point before the job ends: leaving them at the
-- side of the road makes no sense (Z), so unlike animal jobs there is no roadside ending, and the pay comes at delivery.

RseWreckRules = {}

-- the state a wreck starts in, or comes back in from a savegame
function RseWreckRules.newState(saved)
    if saved == "tipped" or saved == "ready" then
        return saved
    end
    return "locked"
end

-- prepared on foot: pinned wrecks are let go. Returns the next state.
function RseWreckRules.afterPrepare(state, def)
    if state ~= "locked" then
        return state
    end
    return def.tipped and "tipped" or "ready"
end

-- upY: how upright it stands, 1 on its wheels, 0 on its side, -1 on its roof
function RseWreckRules.isUpright(upY, config)
    return upY ~= nil and upY >= config.WRECK_UPRIGHT
end

-- which load a job has this time (roll: 0 to 1); nil for a job that spills nothing
function RseWreckRules.pickLoad(def, roll, config)
    if not def.spills then
        return nil
    end
    local weights = {}
    for i, load in ipairs(config.WRECK_LOADS) do
        weights[i] = load.weight
    end
    return config.WRECK_LOADS[RseSpotRules.pickWeighted(weights, roll)]
end

-- a load by its name, as a savegame or the test command has it. A save from before there was a choice gets the big one.
function RseWreckRules.loadById(def, id, config)
    if not def.spills then
        return nil
    end
    for _, load in ipairs(config.WRECK_LOADS) do
        if load.id == id then
            return load
        end
    end
    return config.WRECK_LOADS[#config.WRECK_LOADS]
end

-- how many bales a spilled load has: the job size setting picks from the range, as for animals
function RseWreckRules.baleCount(load, random, size, def)
    if load == nil then
        return 0
    end
    local range = load.count
    local limit = def ~= nil and def.loadLimit ~= nil and def.loadLimit[load.id] or nil
    if limit ~= nil then
        range = { min = math.min(range.min, limit), max = math.min(range.max, limit) }
    end
    return RseSceneSpec.count(range, random, size)
end

-- what one bale pays: more when the bales are all you bring in (Z)
function RseWreckRules.balePay(load, withTrailer)
    if load == nil then
        return 0
    end
    return withTrailer and load.pay or (load.payAlone or load.pay)
end

-- whole dollars for hauling a wreck this many metres; nothing to haul, nothing to pay
function RseWreckRules.haulPay(def, distance, config)
    if def.noVehicle or distance == nil then
        return 0
    end
    return math.floor(distance / 1000 * config.WRECK_PAY_PER_KM + 0.5)
end

-- whole dollars for the job, paid when everything has reached a recovery point
function RseWreckRules.reward(def, baleCount, load, haulPay)
    return math.floor(def.pay + (haulPay or 0) + RseWreckRules.balePay(load, not def.noVehicle) * (baleCount or 0) + 0.5)
end

-- whole dollars for a load handed over part of the way: each bale that came in still pays (Z)
function RseWreckRules.partialReward(load, baleCount)
    return math.floor(RseWreckRules.balePay(load, false) * (baleCount or 0) + 0.5)
end

-- Is this strap towing? Only once the vehicle on it is being driven with the strap tight. Until then the strap leaves the wreck alone, so you can reel it
-- onto a rollback or into another position first (Z). Reeling by hand ends it, and so does standing still for a while. input: { speed (km/h), slack, reeling }.
-- state: { towing, drivenMs, stillMs }, updated here.
function RseWreckRules.isTowing(state, dt, input, config)
    if input.reeling then
        state.towing, state.drivenMs, state.stillMs = false, 0, 0
        return false
    end
    if input.speed >= config.TOW_START_SPEED then
        state.stillMs = 0
        state.drivenMs = input.slack <= config.TOW_SLACK_FREE and (state.drivenMs or 0) + dt or 0
        if state.drivenMs >= config.TOW_START_MS then
            state.towing = true
        end
    else
        state.drivenMs = 0
        state.stillMs = (state.stillMs or 0) + dt
        if state.stillMs >= config.TOW_END_MS then
            state.towing = false
        end
    end
    return state.towing == true
end

-- How hard a wreck on a strap brakes, 0 to 1. slack: metres before the strap goes tight; closing: metres per second the two ends are coming together. A tight
-- strap rolls free. A slack one brakes, or the wreck rolls on into the vehicle in front when that stops (Z).
-- How far a wreck's steered wheels turn toward what pulls it, from -1 to 1. localX and localZ: where it is, seen from the wreck.
-- Pulled by its front, the wheels point at it. Pulled slowly by its rear, they turn the same way, as when you back up, so its tail swings toward the line.
-- Really towing by its rear, they stay straight: at speed that steering would throw it about.
function RseWreckRules.towSteer(localX, localZ, towing, config)
    if towing and localZ <= 0 then
        return 0
    end
    return math.max(-1, math.min(1, math.atan2(localX, math.abs(localZ)) / config.TOW_STEER_ANGLE))
end

-- A trailer can't steer, and its axle can't move sideways, so a pull at an angle could only turn it about the axle, never move it over (Z, on a rollback).
-- While you reel, its wheels give way along the line, as if it stood on dollies, so it rolls where the line runs. dx and dz: from the wheel to the pull, in the
-- wreck's axes. Returns the wheel's angle in radians: a wheel rolls both ways, so it only has to lie along the line, whichever end the pull comes from.
function RseWreckRules.freeWheelAngle(dx, dz, reeling, config)
    if not reeling then
        return 0
    end
    local angle = math.atan2(dz < 0 and -dx or dx, math.abs(dz))
    return math.max(-config.TOW_WHEEL_SWING, math.min(config.TOW_WHEEL_SWING, angle))
end

function RseWreckRules.towBrake(slack, closing, config)
    if slack <= config.TOW_SLACK_FREE then
        return 0
    end
    if closing >= config.TOW_CLOSING then
        return 1
    end
    return math.min(1, (slack - config.TOW_SLACK_FREE) / (config.TOW_SLACK_FULL - config.TOW_SLACK_FREE))
end

-- A crash with two parts (Z): the trailer and its load are each paid for, whichever you do, with a bonus when you do both. done: { trailer, animals (the whole
-- load dealt with), haulPay (with the trailer), payPerBale, kinds (dead animals off the road),
-- roadsideKinds (those of them only moved to the roadside), led (live ones loaded), bales (brought in), linePay (a power line's pole and wires) }.
-- Returns the whole pay and the bonus in it.
function RseWreckRules.crashReward(def, done, config)
    local subtotal = done.trailer and def.pay + (done.haulPay or 0) or 0
    if done.kinds ~= nil and #done.kinds > 0 then
        subtotal = subtotal + RsePayRules.callReward(done.kinds, done.roadsideKinds, config)
    end
    subtotal = subtotal + (def.payPerSurvivor or 0) * (done.led or 0) + (done.payPerBale or 0) * (done.bales or 0) + (done.linePay or 0)
    local bonus = 0
    if done.trailer and done.animals then
        bonus = math.floor(subtotal * (def.bothBonus or 0) + 0.5)
    end
    return math.floor(subtotal + bonus + 0.5), bonus
end

-- When a crash job ends. input: { trailer, animals, progress, now } (parts done; progress: something moved on since the last call; now: the player
-- hands the rest over). state: { partDone, waitMs, warned }, updated here. Returns nil, "partDone" (once), "warn", "handover" or "finish".
function RseWreckRules.tickHandover(state, dt, input, config)
    if input.trailer and input.animals then
        return "finish"
    end
    if input.now then
        return "handover"
    end
    if not input.trailer and not input.animals then
        return nil
    end
    if not state.partDone then
        state.partDone, state.waitMs, state.warned = true, 0, false
        return "partDone"
    end
    if input.progress then
        state.waitMs, state.warned = 0, false
    end
    state.waitMs = state.waitMs + dt
    local left = config.CRASH_HANDOVER_MS - state.waitMs
    if left <= 0 then
        return "handover"
    end
    if left <= config.CRASH_HANDOVER_WARN_MS and not state.warned then
        state.warned = true
        return "warn"
    end
    return nil
end
