-- Roadside Emergencies: the utility crew at a power line (Z, 2026-11-07): a truck with a driver that comes along the road from out of sight, parks short of
-- the scene and cuts the power. Engine-free: where it starts, which way it steers, how fast, and when it has arrived and is done. UtilityCrew.lua drives the
-- real vehicle with the game's own AIVehicleUtil.driveToPoint, as the game's AI helpers do.
--
-- A route is a list of points { x, z } from the far end to where the truck stops, roughly CREW_ROUTE_STEP apart, along the lanes of the map's AI roads.

RseCrewRules = {}

-- the length of the route from point i to its end
function RseCrewRules.lengthFrom(route, i)
    local length = 0
    for k = math.max(1, i), #route - 1 do
        length = length + math.sqrt((route[k + 1].x - route[k].x) ^ 2 + (route[k + 1].z - route[k].z) ^ 2)
    end
    return length
end

-- Can the player see this spot? fx, fz: the camera's forward direction on the ground. Far enough away counts as unseen, and so does anything well to the
-- side or behind.
function RseCrewRules.inView(px, pz, fx, fz, x, z, config)
    local dx, dz = x - px, z - pz
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance >= config.CREW_UNSEEN_DISTANCE then
        return false
    end
    if distance < 1 then
        return true
    end
    local forward = math.sqrt(fx * fx + fz * fz)
    if forward < 1e-6 then
        return true
    end
    return (dx * fx + dz * fz) / (distance * forward) > math.cos(config.CREW_VIEW_HALF_ANGLE)
end

-- Where on the route the truck appears: the point nearest the scene that is at least CREW_SPAWN_MIN along the road, CREW_SPAWN_CLEAR from the player and out
-- of sight; failing that, the far end. Nil when the route is too short to come from anywhere.
function RseCrewRules.spawnIndex(route, px, pz, fx, fz, config)
    if #route < 2 then
        return nil
    end
    local along = 0
    for i = #route - 1, 1, -1 do
        along = along + math.sqrt((route[i + 1].x - route[i].x) ^ 2 + (route[i + 1].z - route[i].z) ^ 2)
        if along >= config.CREW_SPAWN_MIN then
            local p = route[i]
            local clear = px == nil or (p.x - px) ^ 2 + (p.z - pz) ^ 2 >= config.CREW_SPAWN_CLEAR ^ 2
            if clear and (px == nil or not RseCrewRules.inView(px, pz, fx, fz, p.x, p.z, config)) then
                return i
            end
        end
    end
    if RseCrewRules.lengthFrom(route, 1) < config.CREW_SPAWN_SHORTEST then
        return nil
    end
    return 1
end

-- Pure pursuit: the point the truck steers at, CREW_LOOK_AHEAD along the route from where it is. index: the route point it last passed. Points within reach
-- and points it has already gone past (a long frame) are skipped. Returns the point and the new index.
function RseCrewRules.target(route, index, x, z, config)
    local i = math.max(1, index)
    while i < #route do
        local a, b = route[i], route[i + 1]
        local near = (b.x - x) ^ 2 + (b.z - z) ^ 2 <= config.CREW_LOOK_AHEAD ^ 2
        local passed = (b.x - a.x) * (x - b.x) + (b.z - a.z) * (z - b.z) > 0
        if not near and not passed then
            break
        end
        i = i + 1
    end
    local point = route[math.min(#route, i + 1)]
    return point, i
end

-- how fast to go with this far left to drive, in km/h: slower towards the end
function RseCrewRules.speedFor(distanceLeft, config)
    if distanceLeft <= config.CREW_CREEP_DISTANCE then
        return config.CREW_CREEP_SPEED
    elseif distanceLeft <= config.CREW_SLOW_DISTANCE then
        return config.CREW_SLOW_SPEED
    end
    return config.CREW_SPEED
end

-- The crew, every update. state: { phase = "driving" | "parked" | "done", heldMs, workMs, waitedMs, moved }, updated here.
-- input: { distanceLeft (metres to the stop), speed (km/h), blocked (something right ahead) }.
-- Returns nil, "parked" (it stopped: at the end, or held up by traffic, the player or the scene), "done" (the power is off), or "failed" (it never got moving).
function RseCrewRules.tick(state, dt, input, config)
    if state.phase == "driving" then
        state.waitedMs = (state.waitedMs or 0) + dt
        if input.speed >= config.CREW_MOVING_SPEED then
            state.moved = true
        end
        if input.distanceLeft <= config.CREW_STOP_REACH then
            state.phase, state.workMs = "parked", 0
            return "parked"
        end
        if input.speed < config.CREW_MOVING_SPEED then
            state.heldMs = (state.heldMs or 0) + dt
        else
            state.heldMs = 0
        end
        if state.moved and state.heldMs >= config.CREW_HELD_MS then
            state.phase, state.workMs = "parked", 0 -- held up for good: it parks where it is, and the crew walks the rest
            return "parked"
        end
        if not state.moved and state.waitedMs >= config.CREW_START_MS then
            state.phase = "failed"
            return "failed"
        end
        return nil
    elseif state.phase == "parked" then
        state.workMs = (state.workMs or 0) + dt
        if state.workMs >= config.CREW_WORK_MS then
            state.phase = "done"
            return "done"
        end
    end
    return nil
end

-- about how long until the power is off, in seconds, for the call panel
function RseCrewRules.secondsLeft(state, distanceLeft, config)
    if state.phase == "driving" then
        return math.ceil((distanceLeft or 0) / config.CREW_ETA_SPEED + config.CREW_WORK_MS / 1000)
    elseif state.phase == "parked" then
        return math.max(1, math.ceil((config.CREW_WORK_MS - (state.workMs or 0)) / 1000))
    end
    return 0
end

-- which side of the lane the truck pulls over to: away from the other lanes. right: the lane's right-hand side (-dirZ, dirX); nearest(x, z): how far the
-- closest lane centre is from a point. Returns 1 for the right, -1 for the left.
function RseCrewRules.shoulderSide(x, z, dirX, dirZ, offset, nearest)
    local rightX, rightZ = -dirZ, dirX
    local right = nearest(x + rightX * offset, z + rightZ * offset)
    local left = nearest(x - rightX * offset, z - rightZ * offset)
    return right >= left and 1 or -1
end
