-- Roadside Emergencies: the rules of wreck jobs. Engine-free. A wreck goes locked -> (tipped ->) ready -> delivered: a wreck lying on
-- its side has to be righted first. Wrecks and spilled loads must reach a recovery point before the job ends: leaving them at the
-- side of the road makes no sense (Z), so unlike animal jobs there is no roadside ending, and the pay comes at delivery.

RseWreckRules = {}

-- the state a wreck starts in, or comes back in from a savegame
function RseWreckRules.newState(saved)
    if saved == "tipped" or saved == "ready" or saved == "held" then
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
function RseWreckRules.pickLoad(def, roll, config, fleet)
    if not def.spills then
        return nil
    end
    local loads, weights = {}, {}
    for _, load in ipairs(config.WRECK_LOADS) do
        -- no big bales for a farm with nothing to lift them
        if fleet == nil or fleet.canLift or not load.needsLift then
            table.insert(loads, load)
            table.insert(weights, load.weight)
        end
    end
    return loads[RseSpotRules.pickWeighted(weights, roll)]
end

-- could this farm recover this vehicle? fleet: RseJobRules.fleetFrom's; nil: nobody has looked, so anything goes
function RseWreckRules.canRecover(variant, fleet)
    if fleet == nil then
        return true
    end
    if variant.heavy then
        return fleet.canPullHeavy
    end
    return fleet.canPull
end

function RseWreckRules.anyVariantFor(def, fleet)
    for _, variant in ipairs(def.variants or {}) do
        if RseWreckRules.canRecover(variant, fleet) then
            return true
        end
    end
    return false
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

-- The vehicle for this call, from the def's variants, by their weight: only those isAvailable says the game has (all of them without it), and not the
-- one used last while there is another. nil if nothing is left.
function RseWreckRules.pickVariant(def, roll, last, isAvailable)
    local usable, fresh = {}, {}
    for _, variant in ipairs(def.variants or {}) do
        if isAvailable == nil or isAvailable(variant.file, variant) then
            table.insert(usable, variant)
            if variant.file ~= last then
                table.insert(fresh, variant)
            end
        end
    end
    local list = #fresh > 0 and fresh or usable
    if #list == 0 then
        return nil
    end
    local total = 0
    for _, variant in ipairs(list) do
        total = total + (variant.weight or 1)
    end
    local target = roll * total
    for _, variant in ipairs(list) do
        target = target - (variant.weight or 1)
        if target < 0 then
            return variant
        end
    end
    return list[#list]
end

-- the variant a saved job had; the first one if the save doesn't say or the vehicle is no longer on the list
function RseWreckRules.variantByFile(def, file)
    for _, variant in ipairs(def.variants or {}) do
        if variant.file == file then
            return variant
        end
    end
    return def.variants ~= nil and def.variants[1] or nil
end

-- how many bales a spilled load has: the job size setting picks from the range, as for animals. holder: the vehicle's variant, or the def if it has none
function RseWreckRules.baleCount(load, random, size, holder)
    if load == nil then
        return 0
    end
    local range = load.count
    local limit = holder ~= nil and holder.loadLimit ~= nil and holder.loadLimit[load.id] or nil
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
    if def.noVehicle or def.scenery or distance == nil then
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
-- onto a rollback or into another position first (Z). Reeling by hand ends it, and so does standing still for a while, the wreck riding on the vehicle, or
-- backing
-- toward it: a strap doesn't push. input: { speed (km/h), slack, reeling, carried, pushing }. state: { towing, drivenMs, stillMs }, updated here.
function RseWreckRules.isTowing(state, dt, input, config)
    if input.reeling or input.carried or input.pushing then
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
-- strap rolls free. A slack one brakes, or the wreck rolls on into the vehicle in front when that stops (Z). How far a wreck's steered wheels turn, from -1
-- to 1. localX and localZ: where the pull comes from, seen from the wreck. Pulled by its front, the wheels point from their own axle (axleZ, in the wreck's
-- axes) at it, which is the way that axle has to go; maxAngle: as far as they turn, in radians. Pulled by its rear, the front wheels stay straight: they are
-- the far axle, and the wreck follows on them (isNearAxle).
function RseWreckRules.towSteer(localX, localZ, config, axleZ, maxAngle)
    if localZ <= 0 then
        return 0
    end
    if axleZ ~= nil then
        local angle = math.atan2(localX, math.max(localZ - axleZ, 0.5))
        return math.max(-1, math.min(1, angle / (maxAngle or config.TOW_STEER_ANGLE)))
    end
    return math.max(-1, math.min(1, math.atan2(localX, localZ) / config.TOW_STEER_ANGLE))
end

-- A share meant for one frame of TOW_FRAME_MS, for a frame of dt, so that the feel doesn't change with the frame rate. Over any number of frames it comes to
-- the same.
function RseWreckRules.frameShare(share, dt, config)
    return 1 - (1 - share) ^ ((dt or config.TOW_FRAME_MS) / config.TOW_FRAME_MS)
end

-- Where a wreck's axles are, from its wheels' places along it. Wheels this close together are one group, and then no wheel is at the near end.
-- Returns { middleZ, single, meanZ, frontZ, rearZ }; with no wheels, meanZ is nil.
function RseWreckRules.axleLayout(zs, config)
    if #zs == 0 then
        return { middleZ = 0, single = true }
    end
    local lowest, highest, sum = math.huge, -math.huge, 0
    for _, z in ipairs(zs) do
        lowest, highest, sum = math.min(lowest, z), math.max(highest, z), sum + z
    end
    local middle = (lowest + highest) / 2
    local frontSum, frontCount, rearSum, rearCount = 0, 0, 0, 0
    for _, z in ipairs(zs) do
        if z >= middle then
            frontSum, frontCount = frontSum + z, frontCount + 1
        else
            rearSum, rearCount = rearSum + z, rearCount + 1
        end
    end
    local mean = sum / #zs
    return { middleZ = middle, single = highest - lowest < config.TOW_AXLE_SPAN, meanZ = mean,
        frontZ = frontCount > 0 and frontSum / frontCount or mean, rearZ = rearCount > 0 and rearSum / rearCount or mean }
end

-- The axle a wreck follows on when towed from hookZ, in its own axes: the group at the far end. A truck's two rear axles count as one, between them.
function RseWreckRules.farAxleZ(layout, hookZ)
    if layout.single then
        return layout.meanZ
    end
    return hookZ >= layout.middleZ and layout.rearZ or layout.frontZ
end

-- How fast a towed vehicle has to turn so that its far axle runs straight, as a trailer's does: how fast the hinge moves sideways, seen from the wreck, over
-- the distance from that axle to the hook. Positive turns +z toward +x. nil when the axle is too close to the hook to say.
function RseWreckRules.followYaw(sideways, hookZ, farZ, config)
    local arm = hookZ - (farZ or hookZ)
    if math.abs(arm) < config.TOW_FOLLOW_MIN_ARM then
        return nil
    end
    return sideways / arm
end

-- One frame of following. A model of this found (scratchpad sim_follow): letting the near wheels run free, or only damping the sway, lets the wreck's sideways
-- momentum through the hitch, and that throws the towing vehicle about. So the yaw goes toward what the geometry says, turning about the hook so that the hook
-- doesn't jump, and the hook's speed sideways is matched to the hinge's on the wreck's own body. Only the sideways part: the wreck's weight still pulls.
-- input: { yaw, wantYaw (nil: leave the yaw), vx, vz (of its body), armX, armZ (from its centre of mass to the hook), hookVX, hookVZ, hingeVX, hingeVZ,
-- sideX, sideZ (the towing vehicle's own sideways) }. All in world axes, as the engine reports them. Returns yaw, vx, vz.
function RseWreckRules.follow(input, yawShare, sideShare)
    local yaw, vx, vz = input.yaw, input.vx, input.vz
    if input.wantYaw ~= nil then
        local change = (input.wantYaw - yaw) * yawShare
        yaw = yaw + change
        vx, vz = vx - change * input.armZ, vz + change * input.armX
    end
    local length = math.sqrt(input.sideX * input.sideX + input.sideZ * input.sideZ)
    if length > 1e-6 then
        local sideX, sideZ = input.sideX / length, input.sideZ / length
        local off = ((input.hingeVX - input.hookVX) * sideX + (input.hingeVZ - input.hookVZ) * sideZ) * sideShare
        vx, vz = vx + off * sideX, vz + off * sideZ
    end
    return yaw, vx, vz
end

-- Following relies on the engine's yaw having the sign this file assumes, and with the wrong sign it would spin the wreck. So the engine's yaw is compared all
-- along with the one the wreck's own point speeds show. False once they have disagreed for a while. state: { badMs }, updated here.
function RseWreckRules.yawAgrees(state, engineYaw, shownYaw, dt, config)
    local rate = config.TOW_YAW_CHECK_RATE
    if engineYaw * shownYaw < 0 and math.abs(engineYaw) > rate and math.abs(shownYaw) > rate then
        state.badMs = (state.badMs or 0) + dt
    else
        state.badMs = 0
    end
    return state.badMs < config.TOW_YAW_CHECK_MS
end

-- Which of a wreck's wheels run free on a strap: those at the end being pulled, reeled or towed. They go where the line goes, and the far axle stays
-- straight, so the wreck follows on it like a trailer: that end comes straight to the hitch (Z: it has to be pulled toward where the winch is hooked up, and
-- with both axles fixed it just rolls along its own heading).
function RseWreckRules.isNearAxle(wheelZ, hitchZ, middleZ)
    return (wheelZ >= middleZ) == (hitchZ >= middleZ)
end

-- Where the wreck's end belongs while really towing, measured from the strap's point on the vehicle (px, pz, in the vehicle's axes): on its centre line,
-- just past
-- its end. side: -1 behind it, 1 in front. tugLength: the vehicle's length, nil if the strap isn't on its main body. Returns x, z, and how far along its
-- end is.
function RseWreckRules.hitchPoint(px, pz, side, tugLength, tugOffset, wreckWidth, config)
    local gap = math.max(config.TOW_GAP, (wreckWidth or 0) / 2 + config.TOW_GAP_SIDE)
    local endZ = pz
    if tugLength ~= nil and tugLength > 0 then
        endZ = (tugOffset or 0) + side * tugLength / 2
    end
    return -px, endZ + side * gap - pz, endZ - pz
end

-- the hinge moves there bit by bit, dragging the wreck into line. Returns true if it moved.
function RseWreckRules.moveAnchor(anchor, x, z, step)
    local dx, dz = x - anchor.x, z - anchor.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance < 0.001 then
        return false
    end
    local share = math.min(1, step / distance)
    anchor.x, anchor.z = anchor.x + dx * share, anchor.z + dz * share
    return true
end

-- how far the wreck has run up on the hinge: 0 with it pulling, up to twice the travel with the vehicle slowing down. along: the hook's place along the
-- vehicle.
function RseWreckRules.hitchSlack(along, anchorZ, side, config)
    return math.max(0, config.TOW_TRAVEL - (along - anchorZ) * side)
end

-- Is the wreck riding on the vehicle, as on a rollback? Its middle is over that vehicle's own footprint. lx, lz: where it is, in the vehicle's axes.
function RseWreckRules.isCarried(lx, lz, tugLength, tugOffset, tugWidth)
    if tugLength == nil or tugWidth == nil then
        return false
    end
    return math.abs(lx) <= tugWidth / 2 and math.abs(lz - (tugOffset or 0)) <= tugLength / 2
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
