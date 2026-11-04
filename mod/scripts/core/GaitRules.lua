-- Roadside Emergencies: a walk worked out by numbers, because the livestock models have bones but no walking clips a mod can reach (M4 round 1).
-- Engine-free. Four beats, the order walking mammals use: back left, front left, back right, front right. Each foot spends GAIT_DUTY of the cycle on
-- the ground, then swings forward through the air. The foot's path comes first, and the joints follow it (solveLeg: inverse kinematics, in the side
-- view of the animal). On the ground the foot moves back under the body exactly as fast as the body moves forward, so it stays where it landed and
-- doesn't slide. Angles are radians about the animal's left-right axis: positive moves what lies below the joint backward.

RseGaitRules = {
    PHASES = { hindLeft = 0, frontLeft = 0.25, hindRight = 0.5, frontRight = 0.75 }
}

-- where a leg is at `phase` (0 to 1): swing -1 reaching forward to 1 far back, and lift 0 on the ground to 1 folded highest
function RseGaitRules.leg(phase, duty)
    if phase < duty then
        return 2 * phase / duty - 1, 0
    end
    -- in the air: a curve that leaves and lands at the speed the foot has on the ground, so there is no snap where it lifts or lands
    local t = (phase - duty) / (1 - duty)
    local speedAtEnds = 2 * (1 - duty) / duty
    local t2, t3 = t * t, t * t * t
    local along = (2 * t3 - 3 * t2 + 1) + (t3 - 2 * t2 + t) * speedAtEnds + (2 * t3 - 3 * t2) + (t3 - t2) * speedAtEnds
    local lift = math.sin(math.pi * t)
    return along, lift * lift
end

-- Cycles per second and half a foot's reach in metres, for walking at `speed` m/s on legs `legLength` m long. A bigger animal takes slower, longer
-- steps. Over the time a foot is down, GAIT_DUTY / cycles, the body moves that foot's whole reach, which is what keeps it from sliding.
function RseGaitRules.stride(speed, legLength, config)
    local leg = math.max(legLength, 0.1)
    local cycles = (config.GAIT_CYCLES_BASE + speed * config.GAIT_CYCLES_PER_SPEED) * math.sqrt(config.GAIT_REFERENCE_LEG / leg)
    cycles = math.max(config.GAIT_CYCLES_MIN, math.min(config.GAIT_CYCLES_MAX, cycles))
    return cycles, math.min(speed * config.GAIT_DUTY / (2 * cycles), leg * config.GAIT_STRIDE_MAX)
end

-- which way a limb points in the side view: 0 straight down, positive forward. A turn by +a about the left-right axis takes a off it.
local function pointing(z, y)
    return math.atan2(z, -y)
end

-- A leg at rest, for solveLeg. points: its first four joints from the top (hip or shoulder, knee or elbow, hock or wrist, fetlock), each { z, y } in
-- the animal's own space, forward and up. isFront says which way the middle joint bends if the rest pose doesn't show it.
function RseGaitRules.restLeg(points, isFront)
    local a, b, c, d = points[1], points[2], points[3], points[4]
    local rest = {
        hipZ = a[1], hipY = a[2],
        upper = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2),
        lower = math.sqrt((c[1] - b[1]) ^ 2 + (c[2] - b[2]) ^ 2),
        cannonZ = d[1] - c[1], cannonY = d[2] - c[2],
        footZ = d[1], footY = d[2],
        upperAngle = pointing(b[1] - a[1], b[2] - a[2]),
        lowerAngle = pointing(c[1] - b[1], c[2] - b[2])
    }
    local toHock = pointing(c[1] - a[1], c[2] - a[2])
    local bend = rest.upperAngle - toHock
    if math.abs(bend) < 0.02 then
        rest.side = isFront and -1 or 1 -- a straight leg: elbows bend back, knees forward
    else
        rest.side = bend > 0 and 1 or -1
    end
    return rest
end

-- The turn of each of the four joints, from rest, that puts the fetlock `offsetZ` forward and `offsetY` up from where it rests, with the cannon bone
-- turned by `cannon` and the hoof by `hoof`. Out of reach, the leg goes as far as it can. Returns the four angles.
function RseGaitRules.solveLeg(rest, offsetZ, offsetY, cannon, hoof)
    local c, s = math.cos(cannon), math.sin(cannon)
    -- the hock or wrist has to be where the turned cannon bone reaches the fetlock's new place
    local hockZ = rest.footZ + offsetZ - (rest.cannonY * s + rest.cannonZ * c)
    local hockY = rest.footY + offsetY - (rest.cannonY * c - rest.cannonZ * s)
    local dz, dy = hockZ - rest.hipZ, hockY - rest.hipY
    local reach = math.sqrt(dz * dz + dy * dy)
    reach = math.max(math.abs(rest.upper - rest.lower) + 0.001, math.min(rest.upper + rest.lower - 0.001, reach))
    local cosAtHip = (rest.upper * rest.upper + reach * reach - rest.lower * rest.lower) / (2 * rest.upper * reach)
    local upperAngle = pointing(dz, dy) + rest.side * math.acos(math.max(-1, math.min(1, cosAtHip)))
    local kneeZ = rest.hipZ + math.sin(upperAngle) * rest.upper
    local kneeY = rest.hipY - math.cos(upperAngle) * rest.upper
    local hipTurn = rest.upperAngle - upperAngle
    local lowerTurn = rest.lowerAngle - pointing(hockZ - kneeZ, hockY - kneeY)
    return hipTurn, lowerTurn - hipTurn, cannon - lowerTurn, hoof - cannon
end

-- the turn by `angle` about a unit axis, as a quaternion x, y, z, w
function RseGaitRules.axisAngle(ax, ay, az, angle)
    local half = angle / 2
    local s = math.sin(half)
    return ax * s, ay * s, az * s, math.cos(half)
end

-- first turn a, then b within it
function RseGaitRules.multiply(ax, ay, az, aw, bx, by, bz, bw)
    return aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz
end
