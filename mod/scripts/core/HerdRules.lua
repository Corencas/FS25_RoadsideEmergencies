-- Roadside Emergencies: how the loose animals at a livestock trailer crash move (DESIGN F16). Engine-free.
-- They wander off slowly, a few steps at a time with pauses to look around; they shy away when you come close; once caught, they follow
-- you. They turn back at a limit, so one can always be found again (Z: the player wrangles them, nobody loses them for good).
-- An animal: { x, z, yaw, moving, speed, walkMs, pauseMs, targetYaw, dodging }. Yaw 0 looks along +z.

RseHerdRules = {}

local TWO_PI = 2 * math.pi

local function between(range, random)
    return range[1] + (range[2] - range[1]) * random()
end

local function distance(ax, az, bx, bz)
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- the shortest turn from a to b, -pi to pi
function RseHerdRules.angleDiff(a, b)
    local diff = (b - a) % TWO_PI
    if diff > math.pi then
        diff = diff - TWO_PI
    end
    return diff
end

local function yawFromTo(fromX, fromZ, toX, toZ)
    return math.atan2(toX - fromX, toZ - fromZ)
end

local function turn(animal, target, rate, dt)
    local diff = RseHerdRules.angleDiff(animal.yaw, target)
    local most = rate * dt / 1000
    animal.yaw = animal.yaw + math.max(-most, math.min(most, diff))
end

-- something in the way, or nothing to do: stops at once
local function halt(animal)
    animal.moving, animal.speed = false, 0
end

-- eases towards `target` metres per second and moves on at the speed it has; it starts and stops like an animal, not a switch
local function go(animal, target, rate, dt)
    local most = rate * dt / 1000
    local speed = animal.speed or 0
    speed = speed + math.max(-most, math.min(most, target - speed))
    animal.speed = speed
    animal.moving = speed > 0.02
    local step = speed * dt / 1000
    animal.x = animal.x + math.sin(animal.yaw) * step
    animal.z = animal.z + math.cos(animal.yaw) * step
end

-- where the next few steps go: away from where it started, roughly; back again once it has gone far enough
local function wanderYaw(animal, world, config, random)
    local fromHome = distance(animal.x, animal.z, world.homeX, world.homeZ)
    if fromHome >= config.HERD_LEASH then
        return yawFromTo(animal.x, animal.z, world.homeX, world.homeZ)
    end
    if fromHome < 0.5 then
        return random() * TWO_PI
    end
    return yawFromTo(world.homeX, world.homeZ, animal.x, animal.z) + (random() - 0.5) * 2 * config.HERD_SPREAD
end

-- something in the way: stops, picks a new direction and turns; picks another if that one is blocked too, so it can't stay stuck
local function dodge(animal, blocked, random)
    if not blocked then
        animal.dodging = false
    elseif not animal.dodging or math.abs(RseHerdRules.angleDiff(animal.yaw, animal.targetYaw or animal.yaw)) < 0.1 then
        animal.dodging = true
        animal.targetYaw = animal.yaw + (random() < 0.5 and -1 or 1) * (math.pi / 2 + random())
    end
end

-- One step of time. world: { homeX, homeZ, playerX, playerZ, playerStill, led, blocked } (playerX nil: no player; blocked: something right ahead of it).
-- Returns "broke" when an animal on a lead has fallen too far behind you.
function RseHerdRules.step(animal, dt, world, config, random)
    local toPlayer = world.playerX ~= nil and distance(animal.x, animal.z, world.playerX, world.playerZ) or nil
    if world.led then
        if toPlayer == nil or toPlayer > config.HERD_LEAD_BREAK then
            halt(animal)
            return "broke"
        end
        if toPlayer > config.HERD_LEAD_LENGTH then
            turn(animal, yawFromTo(animal.x, animal.z, world.playerX, world.playerZ), config.HERD_LEAD_TURN, dt)
            go(animal, math.min((toPlayer - config.HERD_LEAD_LENGTH) * config.HERD_LEAD_CATCH_UP, config.HERD_LEAD_SPEED_MAX), config.HERD_LEAD_ACCEL, dt)
        else
            go(animal, 0, config.HERD_LEAD_ACCEL, dt)
        end
        return nil
    end
    dodge(animal, world.blocked, random)
    if toPlayer ~= nil and toPlayer < config.HERD_SPOOK_RADIUS and not world.playerStill then
        animal.walkMs, animal.pauseMs = 0, 0
        local away = yawFromTo(world.playerX, world.playerZ, animal.x, animal.z)
        turn(animal, animal.dodging and animal.targetYaw or away, config.HERD_LEAD_TURN, dt)
        if world.blocked then
            halt(animal)
        else
            go(animal, config.HERD_SPOOK_SPEED, config.HERD_ACCEL, dt)
        end
        return nil
    end
    if (animal.walkMs or 0) > 0 then
        animal.walkMs = animal.walkMs - dt
        turn(animal, animal.targetYaw or animal.yaw, config.HERD_TURN_SPEED, dt)
        if world.blocked then
            halt(animal)
        else
            go(animal, config.HERD_WANDER_SPEED, config.HERD_ACCEL, dt)
        end
        if animal.walkMs <= 0 then
            animal.pauseMs = between(config.HERD_PAUSE_MS, random)
        end
        return nil
    end
    if world.blocked then
        halt(animal)
    else
        go(animal, 0, config.HERD_ACCEL, dt)
    end
    animal.pauseMs = (animal.pauseMs or 0) - dt
    if animal.pauseMs <= 0 then
        animal.walkMs = between(config.HERD_WALK_MS, random)
        animal.targetYaw = wanderYaw(animal, world, config, random)
    end
    return nil
end
