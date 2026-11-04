-- Roadside Emergencies: a downed power line (DESIGN 2.3c). A car has hit a utility pole: the pole lies across the road, wires hang from the poles on either
-- side, and the driver is still in the car. The wires may be live until the utility crew has cut the power, so you stay back until then. Two parts in any order
-- after that, like a crash: the car goes to a recovery point; the wires are rolled up on foot and the pole goes to a recovery point, cut up if it has to fit on
-- something. Engine-free.

RseLineRules = {}

-- what the pole and the wires pay, for what has been done of them
function RseLineRules.pay(def, poleIn, wiresIn)
    return (poleIn and def.polePay or 0) + (def.wirePay or 0) * (wiresIn or 0)
end

-- what is left of the pay after staying too long near live wires
function RseLineRules.afterPenalty(reward, state, config)
    if state ~= nil and state.penalized then
        return math.floor(reward * (1 - config.LINE_DANGER_CUT) + 0.5)
    end
    return reward
end

-- how long until the crew has cut the power, in whole seconds
function RseLineRules.secondsLeft(state, config)
    return math.max(1, math.ceil((config.LINE_POWER_CUT_MS - (state.liveMs or 0)) / 1000))
end

-- The pole counts as brought in only when nothing of it is left and nothing is still being looked for, or asked for from the game.
function RseLineRules.poleIsIn(line)
    return line.hadPole == true and not line.poleIn and line.pending == nil and #line.pieces == 0 and line.searchMs == nil and line.lostMs == nil
end

-- where a saved job's pole was asked for, or a place for a new one. Older saves only know where its pieces lay; x, z: the scene.
function RseLineRules.savedPoleSpot(data, x, z)
    local yaw = data.yaw or 0
    local dirX, dirZ = data.poleDirX or math.cos(yaw), data.poleDirZ or -math.sin(yaw)
    if data.poleX ~= nil and data.poleZ ~= nil then
        return { x = data.poleX, z = data.poleZ, dirX = dirX, dirZ = dirZ }
    end
    local first = data.pieces ~= nil and data.pieces[1] or nil
    return { x = first ~= nil and first.x or x, z = first ~= nil and first.z or z, dirX = dirX, dirZ = dirZ }
end

-- The clock on the live wires. inside: the player is in the danger zone. state: { liveMs, insideMs, warned, penalized, powerOff }, updated here.
-- Returns nil, "warn" (just went in), "cut" (stayed too long) or "off" (the crew has cut the power).
function RseLineRules.tickPower(state, dt, inside, config)
    if state.powerOff then
        return nil
    end
    state.liveMs = (state.liveMs or 0) + dt
    if state.liveMs >= config.LINE_POWER_CUT_MS then
        state.powerOff = true
        return "off"
    end
    if not inside then
        return nil
    end
    state.insideMs = (state.insideMs or 0) + dt
    if not state.warned then
        state.warned = true
        return "warn"
    end
    if not state.penalized and state.insideMs >= config.LINE_DANGER_GRACE_MS then
        state.penalized = true
        return "cut"
    end
    return nil
end

-- Where the wire is after n pieces of a coil, n may be a fraction: loops lying flat, each a little smaller and higher.
-- Returns dx, dy, dz from the coil's middle.
function RseLineRules.coilPoint(n, config)
    local ring = math.floor(n / config.LINE_COIL_POINTS)
    local angle = n / config.LINE_COIL_POINTS * 2 * math.pi
    local radius = config.LINE_COIL_RADIUS - ring * config.LINE_COIL_STEP
    return math.sin(angle) * radius, ring * config.LINE_COIL_RISE, math.cos(angle) * radius
end

-- Which side of the road the poles stand on: 1 or -1, the side where a pole at that distance would stand further from any lane.
-- Across is to the left of (dirX, dirZ).
function RseLineRules.roadside(x, z, dirX, dirZ, segments, config)
    local side = config.LINE_STANDING_SIDE
    local plus = RseRoadClearRule.distanceToRoad(x - dirZ * side, z + dirX * side, segments) or 0
    local minus = RseRoadClearRule.distanceToRoad(x + dirZ * side, z - dirX * side, segments) or 0
    return plus >= minus and 1 or -1
end

-- Where everything goes around (x, z), on a road running along (dirX, dirZ), a unit vector. side: from roadside.
-- Returns { pole = { x, z, dirX, dirZ }, standing = { { x, z }, ... }, wires = { { x, z, pole }, ... } }: the fallen pole from its foot at the roadside across
-- the lane, the two poles still standing, and the wires from those to the road.
function RseLineRules.layout(x, z, dirX, dirZ, side, wireCount, config)
    local acrossX, acrossZ = -dirZ * side, dirX * side
    local function at(along, across)
        return x + dirX * along + acrossX * across, z + dirZ * along + acrossZ * across
    end
    local footX, footZ = at(config.LINE_POLE_ALONG, config.LINE_POLE_FOOT_SIDE)
    local skew = config.LINE_POLE_SKEW
    local poleDirX, poleDirZ = -acrossX + dirX * skew, -acrossZ + dirZ * skew
    local length = math.sqrt(poleDirX * poleDirX + poleDirZ * poleDirZ)
    local result = { pole = { x = footX, z = footZ, dirX = poleDirX / length, dirZ = poleDirZ / length }, standing = {}, wires = {} }
    for i, along in ipairs(config.LINE_STANDING_ALONG) do
        local px, pz = at(along, config.LINE_STANDING_SIDE)
        result.standing[i] = { x = px, z = pz }
    end
    for i = 1, wireCount do
        local spot = config.LINE_WIRE_SPOTS[(i - 1) % #config.LINE_WIRE_SPOTS + 1]
        local wx, wz = at(spot[1], spot[2])
        result.wires[i] = { x = wx, z = wz, pole = spot[1] < 0 and 1 or 2 }
    end
    return result
end
