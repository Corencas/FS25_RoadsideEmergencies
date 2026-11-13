-- Roadside Emergencies: driving a flock into a pen. Engine-free.
-- Z on the first version: they don't respond directly to what you do, half walk in by themselves, it is too easy, and they turned back at the farmer's truck
-- for no reason. So each one now moves straight away from you, faster the closer you are to it, and those beside it go with it. They know nothing of the pen:
-- where they go is up to you. Near the gate, with others already in, they want to join them. Left alone they graze and close up on those they can see, so
-- bunches out of sight of each other stay apart until you bring them together. Drive fast near them and they scatter. Once in, they stay.
-- Z on the second: the walk is the job, it should last longer, and flow. So they go at a walk unless you crowd them, ease into it and out of it, and turn
-- gently.
-- Z on the third: going round them, they should answer the angle you take. So a pressed one goes away from you through the middle of its bunch as well as
-- straight away, those on the move a little beyond your reach still bend away from you, and a flock you have just pushed walks on a few seconds, so
-- swinging out wide to come round them doesn't stop them dead.
-- Z on the fourth: a honk should draw them together, so they are easier to get going and into the pen, but each honk only a little, and not hold them: who is
-- together keeps changing as they move. So one honk moves each a share of the way in toward those it can see at that moment, and that is all. And they
-- walk a little faster. Then: more honks before they scatter, and more gathering, above all while you drive them: hard to bunch them for the gate.
-- Z on the fifth (0.9.10.0): the honk should see the bigger picture, all of the flock, so there aren't five bunches going their own ways as you drive them.
-- So a honk now calls every one in earshot that isn't with the biggest bunch over to it, the whole way, and the biggest bunch closes up a step as before.
-- And two pinned against the pen by the buggy just stood there: crowded against the pen or the truck, one now gets out along it.
-- An animal: { x, z, yaw, speed, moving, penned, blocked }. Yaw 0 looks along +z.

RseFlockRules = {}

local TWO_PI = 2 * math.pi

local function unit(x, z)
    local length = math.sqrt(x * x + z * z)
    if length < 1e-6 then
        return 0, 0, 0
    end
    return x / length, z / length, length
end

local function rotated(x, z, angle)
    local s, c = math.sin(angle), math.cos(angle)
    return x * c + z * s, z * c - x * s
end

-- the middle of those still loose: x, z, how many
function RseFlockRules.centre(animals)
    local sumX, sumZ, count = 0, 0, 0
    for _, animal in ipairs(animals) do
        if not animal.penned then
            sumX, sumZ, count = sumX + animal.x, sumZ + animal.z, count + 1
        end
    end
    if count == 0 then
        return nil, nil, 0
    end
    return sumX / count, sumZ / count, count
end

-- how far the nearest one still loose is from (x, z), or nil
function RseFlockRules.nearest(animals, x, z)
    local best = nil
    for _, animal in ipairs(animals) do
        if not animal.penned then
            local gap = math.sqrt((animal.x - x) ^ 2 + (animal.z - z) ^ 2)
            best = (best == nil or gap < best) and gap or best
        end
    end
    return best
end

-- how hard you press on one, 0 to 1, from how far you are from it; a vehicle carries further than a person
function RseFlockRules.pressure(distance, onFoot, config)
    if distance == nil then
        return 0
    end
    local outer = onFoot and config.FLOCK_PUSH_FOOT or config.FLOCK_PUSH_VEHICLE
    return math.max(0, math.min(1, (outer - distance) / (outer - config.FLOCK_PUSH_FULL)))
end

-- How much it minds where you are: 1 where you push it, easing off to 0 FLOCK_AWARE further out.
function RseFlockRules.aware(distance, onFoot, config)
    if distance == nil then
        return 0
    end
    local outer = onFoot and config.FLOCK_PUSH_FOOT or config.FLOCK_PUSH_VEHICLE
    return math.max(0, math.min(1, (outer + config.FLOCK_AWARE - distance) / config.FLOCK_AWARE))
end

-- A honk, and holding it down is still one honk: every few seconds it brings each bunch a step closer together (honked, for one frame), and now and then it
-- pushes them on as well (horn, for FLOCK_HORN_MS), but not more often than FLOCK_HORN_REST_MS, so honking is no way to drive a flock. Lean on it, many
-- honks in a few seconds, and it frightens them: they scatter (hornScare, for one frame). Honks the flock took no notice of never count against you: the
-- old rule restarted its rest on each one, so a patient honk every 10 s scattered them on the fourth (Z: more than 3).
function RseFlockRules.hearHorn(world, honking, dt, config)
    world.clockMs = (world.clockMs or 0) + dt
    world.hornMs = math.max(0, (world.hornMs or 0) - dt)
    world.hornScare, world.honked = false, false
    if honking and not world.hornWas then
        local now = world.clockMs
        local recent = {}
        for _, at in ipairs(world.honks or {}) do
            if now - at < config.FLOCK_HORN_SCARE_MS then
                recent[#recent + 1] = at
            end
        end
        recent[#recent + 1] = now
        if #recent >= config.FLOCK_HORN_TOO_MANY then
            world.hornScare, recent = true, {}
        else
            if world.pushedAt == nil or now - world.pushedAt >= config.FLOCK_HORN_REST_MS then
                world.hornMs, world.pushedAt = config.FLOCK_HORN_MS, now
            end
            if world.steppedAt == nil or now - world.steppedAt >= config.FLOCK_HORN_STEP_GAP_MS then
                world.honked, world.steppedAt = true, now
            end
        end
        world.honks = recent
    end
    world.hornWas = honking
    world.horn = world.hornMs > 0
end

-- Every frame, before the animals move. player: { x, z, onFoot, speed, horn }, speed in metres per second, or nil. Returns how many are still loose.
function RseFlockRules.think(world, animals, player, dt, config)
    world.animals = animals
    local cx, cz, loose = RseFlockRules.centre(animals)
    world.inPen = #animals - loose
    if loose > 0 then
        world.cx, world.cz = cx, cz
    end
    if player ~= nil then
        world.playerX, world.playerZ = player.x, player.z
        world.onFoot, world.playerSpeed = player.onFoot == true, player.speed or 0
    else
        world.playerX, world.playerZ, world.onFoot, world.playerSpeed = nil, nil, false, 0
    end
    RseFlockRules.hearHorn(world, player ~= nil and player.horn == true, dt, config)
    if world.honked and world.playerX ~= nil then
        RseFlockRules.callTogether(world, animals, config)
    end
    RseFlockRules.followMain(world)
    if world.slideSide ~= nil then
        world.slideMs = world.slideMs - dt
        world.slideSideMs = world.slideSideMs + dt
        if world.slideMs <= 0 then
            world.slideSide = nil
        elseif world.slideSideMs >= config.FLOCK_SLIDE_SWAP_MS then
            world.slideSide, world.slideSideMs = -world.slideSide, 0
        end
    end
    return loose
end

-- The pen: a ring of hurdles with a gate facing (gateYaw is the direction from its middle to the gate). Returns { x, z, radius, gateYaw, gateX, gateZ }.
function RseFlockRules.newPen(x, z, gateYaw, config)
    local radius = config.FLOCK_PEN_RADIUS
    return { x = x, z = z, radius = radius, gateYaw = gateYaw, gateX = x + math.sin(gateYaw) * (radius + 1), gateZ = z + math.cos(gateYaw) * (radius + 1) }
end

-- Where the hurdles stand: { { x, z, yaw }, ... }. A hurdle's length runs along its own X axis, so a yaw equal to its angle on the ring lays it along the ring.
-- The first and last end where the gate does, so the gap you see is the gap they can use, and in between they overlap a little: no gaps (Z). length: of
-- one hurdle, in metres, if it has been measured.
function RseFlockRules.penPieces(pen, config, length)
    length = length or config.FLOCK_HURDLE_LENGTH
    local pieces = {}
    local halfGate = config.FLOCK_GATE_HALF + length / 2 / pen.radius
    local span = TWO_PI - 2 * halfGate
    local count = math.ceil(span * pen.radius / (length * config.FLOCK_HURDLE_SHARE))
    for i = 0, count do
        local angle = pen.gateYaw + halfGate + span * i / count
        table.insert(pieces, { x = pen.x + math.sin(angle) * pen.radius, z = pen.z + math.cos(angle) * pen.radius, yaw = angle })
    end
    return pieces
end

-- Where the farmer's truck stands: off to one side of the gate, well out from the ring, so a flock going round the pen has room to pass inside it.
function RseFlockRules.truckSpot(pen, config)
    local angle = pen.gateYaw + config.FLOCK_GATE_HALF + config.FLOCK_TRUCK_ANGLE
    local away = pen.radius + config.FLOCK_TRUCK_AWAY
    return { x = pen.x + math.sin(angle) * away, z = pen.z + math.cos(angle) * away, yaw = angle + math.pi / 2 }
end

-- what closes the pen once they are all in: as many hurdles as it takes to fill the gate, the same way round the ring as the rest
function RseFlockRules.gatePieces(pen, config, length)
    length = length or config.FLOCK_HURDLE_LENGTH
    local arc = 2 * config.FLOCK_GATE_HALF
    local count = math.max(1, math.ceil(arc * pen.radius / (length * config.FLOCK_HURDLE_SHARE)))
    local pieces = {}
    for i = 1, count do
        local angle = pen.gateYaw - config.FLOCK_GATE_HALF + arc * (i - 0.5) / count
        table.insert(pieces, { x = pen.x + math.sin(angle) * pen.radius, z = pen.z + math.cos(angle) * pen.radius, yaw = angle })
    end
    return pieces
end

-- How the flock starts: in bunches along the road, the biggest in the middle. Returns { { count, along }, ... }, along: metres along the road from the scene.
function RseFlockRules.startGroups(total, config, random)
    local away = config.FLOCK_GROUP_APART
    if total >= config.FLOCK_GROUP_THREE then
        local main = math.ceil(total * 0.45)
        local second = math.ceil((total - main) / 2)
        return { { count = main, along = 0 }, { count = second, along = away }, { count = total - main - second, along = -away } }
    elseif total >= 4 then
        local main = math.ceil(total / 2)
        return { { count = main, along = 0 }, { count = total - main, along = random() < 0.5 and away or -away } }
    end
    return { { count = total, along = 0 } }
end

-- The bunches the loose ones are in now: biggest first, and of two the same size the one nearer (px, pz), if given. { { x, z, count, lead, members }, ... }
function RseFlockRules.bunches(animals, config, px, pz)
    local groups, placed = {}, {}
    local link = config.FLOCK_GROUP_LINK ^ 2
    for _, first in ipairs(animals) do
        if not first.penned and not placed[first] then
            local group = { x = 0, z = 0, count = 0, lead = first, members = {} }
            local open = { first }
            placed[first] = true
            while #open > 0 do
                local one = table.remove(open)
                group.x, group.z, group.count = group.x + one.x, group.z + one.z, group.count + 1
                table.insert(group.members, one)
                for _, other in ipairs(animals) do
                    if not other.penned and not placed[other] and (other.x - one.x) ^ 2 + (other.z - one.z) ^ 2 <= link then
                        placed[other] = true
                        table.insert(open, other)
                    end
                end
            end
            group.x, group.z = group.x / group.count, group.z / group.count
            group.away = px ~= nil and (group.x - px) ^ 2 + (group.z - pz) ^ 2 or 0
            table.insert(groups, group)
        end
    end
    table.sort(groups, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.away < b.away
    end)
    return groups
end

-- The bunches they are in now (bunches). The first of each smaller one is marked (stray), so you can see where it is, and world.groups keeps the list.
function RseFlockRules.markGroups(world, animals, config)
    local groups = RseFlockRules.bunches(animals, config, world.playerX, world.playerZ)
    for i, group in ipairs(groups) do
        for _, one in ipairs(group.members) do
            one.stray = false
        end
        group.lead.stray = i > 1
    end
    world.groups = groups
    return groups
end

-- A honk calls the flock together (Z: it should see the bigger picture, so there aren't five bunches as you drive them to the pen): every one within
-- FLOCK_HORN_CALL_RADIUS of you that isn't with the biggest bunch heads for that bunch, the whole way (rejoinPull), and the biggest bunch closes up a step as
-- before (hornStep). world.mainList keeps that bunch, so the others go where it is now while you drive it.
function RseFlockRules.callTogether(world, animals, config)
    local groups = RseFlockRules.bunches(animals, config, world.playerX, world.playerZ)
    world.mainList = nil
    if #groups < 2 then
        return
    end
    world.mainList = groups[1].members
    local reach = config.FLOCK_HORN_CALL_RADIUS ^ 2
    for i = 2, #groups do
        for _, one in ipairs(groups[i].members) do
            if (one.x - world.playerX) ^ 2 + (one.z - world.playerZ) ^ 2 <= reach and (one.spookMs or 0) <= 0 then
                one.joinMs = config.FLOCK_HORN_JOIN_MS
            end
        end
    end
end

-- where the bunch a honk called them to is now: world.mainX, world.mainZ, or nil once it is all in the pen
function RseFlockRules.followMain(world)
    if world.mainList == nil then
        return
    end
    local sumX, sumZ, count = 0, 0, 0
    for _, one in ipairs(world.mainList) do
        if not one.penned then
            sumX, sumZ, count = sumX + one.x, sumZ + one.z, count + 1
        end
    end
    if count == 0 then
        world.mainList, world.mainX, world.mainZ = nil, nil, nil
    else
        world.mainX, world.mainZ = sumX / count, sumZ / count
    end
end

function RseFlockRules.isInside(x, z, pen, config)
    return (x - pen.x) ^ 2 + (z - pen.z) ^ 2 <= (pen.radius - config.FLOCK_IN_MARGIN) ^ 2
end

local function isAtGate(rx, rz, pen, config)
    return math.abs(RseHerdRules.angleDiff(pen.gateYaw, math.atan2(rx, rz))) <= config.FLOCK_GATE_HALF
end

-- Where to try for a pen around (x, z), best first: { { x, z, gateYaw } }. Its gate looks toward (x, z) but well off to one side, so the flock has to be
-- brought round to it: from the road you can see the way in, but you can't just push them straight at it. random(): 0 to 1, so it isn't always the same.
function RseFlockRules.penCandidates(x, z, config, random)
    local list = {}
    local start = random() * TWO_PI
    for _, distance in ipairs(config.FLOCK_PEN_DISTANCES) do
        for i = 0, config.FLOCK_PEN_ANGLES - 1 do
            local angle = start + TWO_PI * i / config.FLOCK_PEN_ANGLES
            local range = config.FLOCK_GATE_TURN
            local turn = (random() < 0.5 and -1 or 1) * (range[1] + random() * (range[2] - range[1]))
            table.insert(list, { x = x + math.sin(angle) * distance, z = z + math.cos(angle) * distance, gateYaw = angle + math.pi + turn })
        end
    end
    return list
end

-- The lane in front of the gate that has to be clear of trees: the opening and FLOCK_TREE_GAP either side, out to FLOCK_GATE_ROOM past the gate.
local function treeLane(pen, config)
    return pen.radius * math.sin(config.FLOCK_GATE_HALF) + config.FLOCK_TREE_GAP, pen.radius + 1 + config.FLOCK_GATE_ROOM
end

-- How far from the middle of a pen trees have to be looked for: past the fence by FLOCK_TREE_GAP, and to the far corners of the lane in front of the gate.
function RseFlockRules.treeReach(config)
    local pen = RseFlockRules.newPen(0, 0, 0, config)
    local half, length = treeLane(pen, config)
    return math.max(pen.radius + config.FLOCK_TREE_GAP, math.sqrt(half * half + length * length))
end

-- Is a pen clear of trees (Z: a small tree inside the pen, the woods against its fence, and trees beside the opening)? trunks: { { x, z }, ... } where each
-- tree stands. None inside the ring or within FLOCK_TREE_GAP of it, all the way round, and none in the lane in front of the gate. Returns true or false,
-- and how far the nearest trunk is from the middle (nil if none was given).
function RseFlockRules.isClearOfTrees(pen, trunks, config)
    local half, length = treeLane(pen, config)
    local alongX, alongZ = math.sin(pen.gateYaw), math.cos(pen.gateYaw)
    local nearest, clear = nil, true
    for _, trunk in ipairs(trunks) do
        local dx, dz = trunk.x - pen.x, trunk.z - pen.z
        local distance = math.sqrt(dx * dx + dz * dz)
        if nearest == nil or distance < nearest then
            nearest = distance
        end
        local along, across = dx * alongX + dz * alongZ, math.abs(dx * alongZ - dz * alongX)
        if distance < pen.radius + config.FLOCK_TREE_GAP or (along > 0 and along <= length and across <= half) then
            clear = false
        end
    end
    return clear, nearest
end

-- what the job pays: all of them in, the job and each animal; handed over early, only those in the pen
function RseFlockRules.pay(def, inPen, total, handedOver)
    if handedOver then
        return def.payPerAnimal * inPen
    end
    return def.pay + def.payPerAnimal * total
end

function RseFlockRules.share(inPen, total)
    if total <= 0 then
        return 0
    end
    return math.min(1, inPen / total)
end

-- Which way along something it is pushed into almost head on: side +1 is along (-normalZ, normalX). The way it was already tending if it was, else away from
-- you when you are right behind it and off to one side, else the way the flock is going round things, else either. It keeps that side while it is pinned
-- (animal.pinSide, for FLOCK_PIN_KEEP_MS after the last time), so it doesn't dither between the two.
local function pinSide(animal, world, normalX, normalZ, vx, vz, config)
    if animal.pinSide ~= nil and (animal.pinSideMs or 0) > 0 then
        animal.pinSideMs = config.FLOCK_PIN_KEEP_MS
        return animal.pinSide
    end
    local tangentX, tangentZ = -normalZ, normalX
    local speed = math.sqrt(vx * vx + vz * vz)
    local leaning = vx * tangentX + vz * tangentZ
    local side
    if math.abs(leaning) > speed * config.FLOCK_PIN_LEAN then
        side = leaning > 0 and 1 or -1
    elseif world.playerX ~= nil and (animal.x - world.playerX) ^ 2 + (animal.z - world.playerZ) ^ 2 < config.FLOCK_PUSH_FULL ^ 2
        and math.abs((animal.x - world.playerX) * tangentX + (animal.z - world.playerZ) * tangentZ) >= config.FLOCK_PIN_OFFSET then
        side = (animal.x - world.playerX) * tangentX + (animal.z - world.playerZ) * tangentZ > 0 and 1 or -1
    else
        if world.slideSide == nil then
            world.slideSide, world.slideSideMs = (animal.wobbleTarget or 0) >= 0 and 1 or -1, 0
        end
        world.slideMs = config.FLOCK_SLIDE_KEEP_MS
        side = world.slideSide
    end
    animal.pinSide, animal.pinSideMs = side, config.FLOCK_PIN_KEEP_MS
    return side
end

-- Against something it can't go through: what is left of its way is along it, in the direction it was already tending, so you decide which way round it goes.
-- Pushed at it almost head on from further off, it stands and presses until you move to one side. But crowded there, you within FLOCK_PUSH_FULL, it is
-- pinned, and doesn't just stand (Z: two pinned against the pen by the buggy stood still): it gets out along it, to one side (pinSide). Marks the animal as
-- going along something the flock knows about (animal.alongKnown), so its look-ahead doesn't turn it a second time.
local function slideAlong(animal, world, normalX, normalZ, vx, vz, config)
    local into = vx * normalX + vz * normalZ
    if into >= 0 then
        return vx, vz
    end
    animal.alongKnown = true
    local dirX, dirZ, along = unit(vx - into * normalX, vz - into * normalZ)
    local speed = math.sqrt(vx * vx + vz * vz)
    local sure = math.min(1, along / (speed * config.FLOCK_ALONG_SURE))
    local crowded = world.playerX ~= nil and (animal.x - world.playerX) ^ 2 + (animal.z - world.playerZ) ^ 2 < config.FLOCK_PUSH_FULL ^ 2
    if sure < 1 and (crowded or (animal.pinSideMs or 0) > 0) then
        local side = pinSide(animal, world, normalX, normalZ, vx, vz, config)
        local kept = speed * config.FLOCK_ALONG_SHARE
        return -normalZ * side * kept, normalX * side * kept
    end
    -- further off, headed straight at it, it stands and presses until you move to one side: you decide which way round it goes
    local kept = along + (speed - along) * config.FLOCK_ALONG_SHARE * sure
    return dirX * kept, dirZ * kept
end

local function alongRing(animal, world, vx, vz, config)
    local pen = world.pen
    local rx, rz = animal.x - pen.x, animal.z - pen.z
    local fromMiddle = math.sqrt(rx * rx + rz * rz)
    if fromMiddle <= pen.radius or fromMiddle > pen.radius + config.FLOCK_PEN_AVOID or isAtGate(rx, rz, pen, config) then
        return vx, vz
    end
    return slideAlong(animal, world, rx / fromMiddle, rz / fromMiddle, vx, vz, config)
end

-- the farmer's truck: it walks around that as well, before it gets there, and keeps going the way it was going
local function aroundObstacles(animal, world, vx, vz, config)
    for _, obstacle in ipairs(world.obstacles or {}) do
        local normalX, normalZ, from = unit(animal.x - obstacle.x, animal.z - obstacle.z)
        if from > 0 and from <= obstacle.radius + config.FLOCK_OBSTACLE_AVOID then
            vx, vz = slideAlong(animal, world, normalX, normalZ, vx, vz, config)
        end
    end
    return vx, vz
end

-- However it got there, it doesn't walk through a hurdle or the truck.
local function keepOut(animal, lastX, lastZ, world, config)
    local pen = world.pen
    local rx, rz = animal.x - pen.x, animal.z - pen.z
    local from = math.sqrt(rx * rx + rz * rz)
    local edge = pen.radius + config.FLOCK_RING_EDGE
    if from < edge and from > 1e-3 and (lastX - pen.x) ^ 2 + (lastZ - pen.z) ^ 2 >= pen.radius ^ 2 and not isAtGate(rx, rz, pen, config) then
        animal.x, animal.z = pen.x + rx / from * edge, pen.z + rz / from * edge
    end
    for _, obstacle in ipairs(world.obstacles or {}) do
        local normalX, normalZ, away = unit(animal.x - obstacle.x, animal.z - obstacle.z)
        if away > 0 and away < obstacle.radius then
            animal.x, animal.z = obstacle.x + normalX * obstacle.radius, obstacle.z + normalZ * obstacle.radius
        end
    end
end

-- With others already in the pen and this one near the gate: where it wants to go to join them. Otherwise nil.
local function joinPoint(animal, world, config)
    local pen = world.pen
    if (world.inPen or 0) == 0 or (animal.x - pen.gateX) ^ 2 + (animal.z - pen.gateZ) ^ 2 > config.FLOCK_GATE_DRAW ^ 2 then
        return nil
    end
    if isAtGate(animal.x - pen.x, animal.z - pen.z, pen, config) then
        return pen.x, pen.z
    end
    return pen.gateX, pen.gateZ
end

-- A long way from the pen, it starts to turn back however you press, so nobody loses a flock across the map.
local function leashed(dirX, dirZ, animal, pen, config)
    local homeX, homeZ, far = unit(pen.x - animal.x, pen.z - animal.z)
    if far <= config.FLOCK_LEASH then
        return dirX, dirZ
    end
    local share = math.min(1, (far - config.FLOCK_LEASH) / config.FLOCK_LEASH_SOFT)
    return dirX * (1 - share) + homeX * share, dirZ * (1 - share) + homeZ * share
end

-- A honk: how far in toward the middle of those it can see right now it steps, in metres. Only the part further out than FLOCK_HORN_TIGHT counts, so a
-- tight bunch stays as it is, and a step is never more than FLOCK_HORN_STEP_MAX. Each honk is one step, and the next is worked out afresh.
function RseFlockRules.hornStep(fromMiddle, config)
    return math.min(config.FLOCK_HORN_STEP_MAX, math.max(0, fromMiddle - config.FLOCK_HORN_TIGHT) * config.FLOCK_HORN_STEP_SHARE)
end

-- Until it has walked that step in (animal.huddleLeft, metres; animal.huddleMs is only a cap, in case it can't), it closes in on where the middle of those it
-- sees is now, in metres per second, whatever else it is doing. Not while frightened: a scare is a scare. It never walks it back toward you: steer takes that
-- out, as for everything else.
local function huddlePull(animal, stepping, seen, seenX, seenZ, config)
    if not stepping or seen == 0 then
        return 0, 0
    end
    local toX, toZ, gap = unit(seenX / seen - animal.x, seenZ / seen - animal.z)
    animal.huddleX, animal.huddleZ = toX, toZ
    local pull = config.FLOCK_HORN_GATHER * math.max(0, math.min(1, (gap - config.FLOCK_HORN_TIGHT) / config.FLOCK_HORN_RAMP))
    return toX * pull, toZ * pull
end

-- Called by a honk to the biggest bunch (callTogether): it heads for where that bunch is now, at FLOCK_REJOIN, until it is with them (FLOCK_HORN_JOINED)
-- or has tried for FLOCK_HORN_JOIN_MS. Not while frightened. Pressed, it still goes away from you as well, and never back toward you (steer).
local function rejoinPull(animal, world, config)
    if (animal.joinMs or 0) <= 0 or world.mainX == nil or (animal.spookMs or 0) > 0 then
        return 0, 0
    end
    local toX, toZ, gap = unit(world.mainX - animal.x, world.mainZ - animal.z)
    if gap <= config.FLOCK_HORN_JOINED then
        animal.joinMs = 0
        return 0, 0
    end
    return toX * config.FLOCK_REJOIN, toZ * config.FLOCK_REJOIN
end

-- Where one animal wants to go, in metres per second. world: { animals, pen, obstacles, inPen, playerX, playerZ, onFoot, horn }.
function RseFlockRules.steer(animal, world, config)
    local awayX, awayZ, gap = 0, 0, nil
    if world.playerX ~= nil then
        awayX, awayZ, gap = unit(animal.x - world.playerX, animal.z - world.playerZ)
    end
    local seenX, seenZ, seen = 0, 0, 0
    local besideX, besideZ, beside = 0, 0, 0
    local moveX, moveZ, movers = 0, 0, 0
    local apartX, apartZ = 0, 0
    for _, other in ipairs(world.animals) do
        if other ~= animal and not other.penned then
            local offX, offZ, apart = unit(animal.x - other.x, animal.z - other.z)
            if apart < config.FLOCK_SEE then
                seenX, seenZ, seen = seenX + other.x, seenZ + other.z, seen + 1
            end
            if apart < config.FLOCK_SENSE then
                besideX, besideZ, beside = besideX + other.x, besideZ + other.z, beside + 1
                if (other.flightSpeed or 0) > 0 then
                    moveX, moveZ, movers = moveX + other.flightX, moveZ + other.flightZ, movers + 1
                end
            end
            if apart > 0 and apart < config.FLOCK_SPACING then
                local push = config.FLOCK_SEPARATE * (config.FLOCK_SPACING - apart) / config.FLOCK_SPACING
                apartX, apartZ = apartX + offX * push, apartZ + offZ * push
            end
        end
    end
    local pressure = RseFlockRules.pressure(gap, world.onFoot, config)
    if world.horn and gap ~= nil and gap < config.FLOCK_HORN_RADIUS then
        pressure = math.max(pressure, config.FLOCK_HORN_PRESSURE)
    end
    if world.honked and gap ~= nil and gap < config.FLOCK_HORN_HUDDLE_RADIUS and (animal.spookMs or 0) <= 0 and seen > 0 then
        local _, _, fromMiddle = unit(seenX / seen - animal.x, seenZ / seen - animal.z)
        animal.huddleLeft = RseFlockRules.hornStep(fromMiddle, config)
        animal.huddleMs = config.FLOCK_HORN_STEP_MS
    end
    animal.pressure = pressure
    local stepping = (animal.huddleLeft or 0) > 0 and (animal.huddleMs or 0) > 0 and (animal.spookMs or 0) <= 0
    local joinX, joinZ = joinPoint(animal, world, config)
    local vx, vz, inFlight = 0, 0, false
    if (animal.spookMs or 0) > 0 and gap ~= nil then
        -- frightened: each its own way, and no thought for the others
        local dirX, dirZ = rotated(awayX, awayZ, animal.spookAngle or 0)
        vx, vz, inFlight = dirX * config.FLOCK_RUN, dirZ * config.FLOCK_RUN, true
    elseif pressure > 0 then
        local dirX, dirZ = awayX, awayZ
        if seen > 0 then
            -- and away from you through the middle of its bunch: as you go round them, they turn together
            local groupX, groupZ = unit((seenX + animal.x) / (seen + 1) - world.playerX, (seenZ + animal.z) / (seen + 1) - world.playerZ)
            dirX, dirZ = dirX + groupX * config.FLOCK_GROUP_AWAY, dirZ + groupZ * config.FLOCK_GROUP_AWAY
        end
        if beside > 0 then
            local closeX, closeZ, closeGap = unit(besideX / beside - animal.x, besideZ / beside - animal.z)
            local weight = config.FLOCK_CLOSE_UP * math.min(1, closeGap / config.FLOCK_TIGHT)
            dirX, dirZ = dirX + closeX * weight, dirZ + closeZ * weight
        end
        if movers > 0 then
            local headX, headZ = unit(moveX, moveZ)
            dirX, dirZ = dirX + headX * config.FLOCK_ALIGN, dirZ + headZ * config.FLOCK_ALIGN
        end
        if joinX ~= nil then
            local homeX, homeZ = unit(joinX - animal.x, joinZ - animal.z)
            dirX, dirZ = dirX + homeX * config.FLOCK_DRAW_WEIGHT, dirZ + homeZ * config.FLOCK_DRAW_WEIGHT
        end
        dirX, dirZ = unit(leashed(dirX, dirZ, animal, world.pen, config))
        dirX, dirZ = rotated(dirX, dirZ, (animal.wobble or 0) * (stepping and 1 - config.FLOCK_HORN_STEADY or 1))
        -- at a walk unless you crowd it
        local speed = config.FLOCK_WALK + (config.FLOCK_TROT - config.FLOCK_WALK) * pressure * pressure
        if gap < config.FLOCK_PERSONAL then
            speed = config.FLOCK_RUN
        end
        vx, vz, inFlight = dirX * speed, dirZ * speed, true
    else
        local follow = movers > 0 and config.FLOCK_FOLLOW / movers or 0
        local followX, followZ = moveX * follow, moveZ * follow
        local aware = RseFlockRules.aware(gap, world.onFoot, config) * config.FLOCK_AWARE_TURN
        if followX * followX + followZ * followZ >= config.FLOCK_FOLLOW_MIN ^ 2 then
            -- those beside it are on the move: it goes with them, bending away from your side
            local dirX, dirZ, speed = unit(followX, followZ)
            dirX, dirZ = unit(dirX + awayX * aware, dirZ + awayZ * aware)
            vx, vz, inFlight = dirX * speed, dirZ * speed, true
        elseif (animal.carryMs or 0) > 0 and aware > 0 then
            -- just pushed: it walks on a little, slowing, and turning away from where you are now
            local dirX, dirZ = unit(animal.carryX + awayX * aware, animal.carryZ + awayZ * aware)
            local speed = config.FLOCK_WALK * animal.carryMs / config.FLOCK_CARRY_MS
            vx, vz, inFlight = dirX * speed, dirZ * speed, true
        elseif joinX ~= nil then
            local homeX, homeZ = unit(joinX - animal.x, joinZ - animal.z)
            vx, vz = homeX * config.FLOCK_JOIN_SPEED, homeZ * config.FLOCK_JOIN_SPEED
        elseif seen > 0 then
            -- it keeps to those it can see; with none in sight it stays where it is until you bring it back
            local toX, toZ, fromThem = unit(seenX / seen - animal.x, seenZ / seen - animal.z)
            if fromThem > config.FLOCK_STRAY then
                vx, vz = toX * config.FLOCK_REJOIN, toZ * config.FLOCK_REJOIN
            elseif fromThem > config.FLOCK_TIGHT then
                local pull = config.FLOCK_COHESION * (fromThem - config.FLOCK_TIGHT) / (config.FLOCK_STRAY - config.FLOCK_TIGHT)
                vx, vz = toX * pull, toZ * pull
            end
        end
    end
    if inFlight then
        animal.flightX, animal.flightZ, animal.flightSpeed = vx, vz, math.sqrt(vx * vx + vz * vz)
    else
        animal.flightSpeed = 0
    end
    local huddleX, huddleZ = huddlePull(animal, stepping, seen, seenX, seenZ, config)
    local rejoinX, rejoinZ = rejoinPull(animal, world, config)
    vx, vz = vx + apartX + huddleX + rejoinX, vz + apartZ + huddleZ + rejoinZ
    -- Nothing but you makes it walk back toward you: not a crush, and not wanting to rejoin the others, which would have it run back in and out of your reach
    -- (Z saw them turn round for no reason).
    if gap ~= nil and gap < (world.onFoot and config.FLOCK_PUSH_FOOT or config.FLOCK_PUSH_VEHICLE) + config.FLOCK_CALM_MARGIN then
        local back = vx * -awayX + vz * -awayZ
        if back > 0 then
            local called = (animal.joinMs or 0) > 0 and (animal.spookMs or 0) <= 0
            local speed = math.sqrt(vx * vx + vz * vz)
            vx, vz = vx + back * awayX, vz + back * awayZ
            if called then
                -- called to the others on your far side: it goes round you at its pace, and doesn't stop dead
                local sideX, sideZ, left = unit(vx, vz)
                if left < 1e-3 then
                    sideX, sideZ = -awayZ, awayX
                end
                vx, vz = sideX * speed, sideZ * speed
            end
        end
    end
    animal.alongKnown = false
    vx, vz = alongRing(animal, world, vx, vz, config)
    return aroundObstacles(animal, world, vx, vz, config)
end

-- A vehicle coming in fast frightens those near it. Nothing else does: on foot, or slowly, you can work as close as you like.
local function checkSpook(animal, world, dt, config, random)
    animal.spookMs = (animal.spookMs or 0) - dt
    if world.hornScare and world.playerX ~= nil and (animal.x - world.playerX) ^ 2 + (animal.z - world.playerZ) ^ 2 < config.FLOCK_HORN_RADIUS ^ 2 then
        animal.spookAngle = (random() * 2 - 1) * config.FLOCK_SPOOK_SPREAD
        animal.spookMs = config.FLOCK_SPOOK_MS
        animal.huddleMs, animal.huddleLeft, animal.joinMs = 0, 0, 0
        world.scatteredByHorn = true
        return
    end
    if world.onFoot or world.playerX == nil or (world.playerSpeed or 0) <= config.FLOCK_SPOOK_SPEED then
        return
    end
    if (animal.x - world.playerX) ^ 2 + (animal.z - world.playerZ) ^ 2 < config.FLOCK_SPOOK_RADIUS ^ 2 then
        if animal.spookMs <= 0 then
            animal.spookAngle = (random() * 2 - 1) * config.FLOCK_SPOOK_SPREAD
            world.scattered = true
        end
        animal.spookMs = config.FLOCK_SPOOK_MS
        animal.huddleMs, animal.huddleLeft, animal.joinMs = 0, 0, 0
    end
end

-- No two of them quite alike: each wanders a little off the line, so a flock doesn't go through a gate like water. And one pressed hard may break away, so it
-- pays to keep your distance and not lean on them.
local function checkTemper(animal, dt, config, random)
    animal.wobbleMs = (animal.wobbleMs or 0) - dt
    if animal.wobbleMs <= 0 then
        animal.wobbleMs = config.FLOCK_WOBBLE_MS * (0.5 + random())
        animal.wobbleTarget = (random() * 2 - 1) * config.FLOCK_WOBBLE
    end
    animal.wobble = (animal.wobble or 0) + (animal.wobbleTarget - (animal.wobble or 0)) * math.min(1, dt / config.FLOCK_WOBBLE_EASE_MS)
    local hardPressed = (animal.pressure or 0) >= config.FLOCK_BREAK_PRESSURE and (animal.spookMs or 0) <= 0
    if hardPressed and random() < config.FLOCK_BREAK_CHANCE * dt / 1000 then
        local range = config.FLOCK_BREAK_ANGLE
        animal.spookAngle = (random() < 0.5 and -1 or 1) * (range[1] + random() * (range[2] - range[1]))
        animal.spookMs = config.FLOCK_BREAK_MS
    end
end

-- One of them has met something: it goes along it, on the side that is open (animal.openSide, from looking both ways). With no telling, the flock all goes to
-- one side, or half go left and half right and it stands at the wall for ever, and tries the other side if that gets it nowhere. Returns the side.
function RseFlockRules.noteBlocked(world, animal, config, random)
    if world.slideSide == nil then
        world.slideSide, world.slideSideMs = animal.openSide or (random() < 0.5 and -1 or 1), 0
    end
    world.slideMs = config.FLOCK_SLIDE_KEEP_MS
    return animal.openSide or world.slideSide
end

-- One step of time for one animal still loose. Returns "in" when it has reached the pen, "stuck" when it has been trying to move for a long time and can't.
function RseFlockRules.step(animal, dt, world, config, random)
    animal.huddleMs = math.max(0, (animal.huddleMs or 0) - dt)
    animal.joinMs = math.max(0, (animal.joinMs or 0) - dt)
    checkSpook(animal, world, dt, config, random)
    checkTemper(animal, dt, config, random)
    local wantX, wantZ = RseFlockRules.steer(animal, world, config)
    if (animal.pressure or 0) > 0 and (animal.spookMs or 0) <= 0 and (animal.flightSpeed or 0) > 0 then
        animal.carryMs = config.FLOCK_CARRY_MS
        animal.carryX, animal.carryZ = unit(animal.flightX, animal.flightZ)
    else
        animal.carryMs = math.max(0, (animal.carryMs or 0) - dt)
    end
    -- a change of mind comes through gently: no twitching
    local ease = math.min(1, dt / config.FLOCK_STEER_MS)
    local vx = (animal.wantX or 0) + (wantX - (animal.wantX or 0)) * ease
    local vz = (animal.wantZ or 0) + (wantZ - (animal.wantZ or 0)) * ease
    animal.wantX, animal.wantZ = vx, vz
    local speed = math.min(config.FLOCK_RUN, math.sqrt(vx * vx + vz * vz))
    local wanting = speed >= config.FLOCK_MIN_SPEED
    local lastX, lastZ = animal.x, animal.z
    animal.pinSideMs = math.max(0, (animal.pinSideMs or 0) - dt)
    -- which way it was looking when it found something in the way (the look-ahead looks along its heading)
    if animal.blocked then
        animal.blockedYaw = animal.blockedYaw or animal.yaw
    else
        animal.blockedYaw = nil
    end
    if wanting then
        local target = math.atan2(vx, vz)
        if animal.blocked and animal.alongKnown then
            -- going along the pen or the truck, which the flock knows about, and something still in the way: it turns to where it is going, and if it
            -- stays blocked, the other way along is the way out
            animal.blockedMs = (animal.blockedMs or 0) + dt
            animal.slideHoldMs = 0
            if animal.blockedMs >= config.FLOCK_CORNER_MS and animal.pinSide ~= nil then
                animal.pinSide, animal.blockedMs = -animal.pinSide, 0
            end
        elseif animal.blocked and math.abs(RseHerdRules.angleDiff(animal.blockedYaw, target)) > math.pi / 2 then
            -- what is in front of it isn't where it wants to go (the others are behind it): it just turns round. Turning it further round the thing in
            -- front, as below, pointed it back into the fence (Z: sheep stood at a field fence until the stuck rule moved them to the flock)
            animal.blockedMs, animal.cornerSide, animal.slideHoldMs = 0, nil, 0
        elseif animal.blocked then
            local side = RseFlockRules.noteBlocked(world, animal, config, random)
            animal.blockedMs = (animal.blockedMs or 0) + dt
            local most = config.FLOCK_SLIDE_MOST
            if animal.blockedMs >= config.FLOCK_CORNER_MS then
                -- in a corner: it keeps turning the way it started, back past you if that is the only way out (Z: stuck on fences and corners)
                animal.cornerSide = animal.cornerSide or side
                side, most = animal.cornerSide, config.FLOCK_CORNER_MOST
            end
            animal.slideAngle = side * math.min(most, config.FLOCK_SLIDE + animal.blockedMs / 1000 * config.FLOCK_SLIDE_GROW)
            animal.slideHoldMs = math.abs(animal.slideAngle) > config.FLOCK_SLIDE_MOST and config.FLOCK_CORNER_HOLD_MS or config.FLOCK_SLIDE_HOLD_MS
            target = target + animal.slideAngle
        else
            animal.blockedMs, animal.cornerSide = 0, nil
            if (animal.slideHoldMs or 0) > 0 then
                -- past it, it keeps going that way a moment, or it would walk straight back into it
                animal.slideHoldMs = animal.slideHoldMs - dt
                target = target + (animal.slideAngle or 0)
            end
        end
        RseHerdRules.turn(animal, target, config.FLOCK_TURN, dt)
        -- it comes round before it picks up speed, and doesn't run sideways
        local facing = math.cos(RseHerdRules.angleDiff(animal.yaw, target))
        local goal = (animal.blocked and 0 or speed) * math.max(config.FLOCK_TURN_SLOW, facing)
        RseHerdRules.go(animal, goal, goal > (animal.speed or 0) and config.FLOCK_ACCEL or config.FLOCK_DECEL, dt)
    else
        -- nobody is pressing it: it stands and grazes, and takes a few steps now and then, staying with the others
        animal.idleMs = (animal.idleMs or random() * config.FLOCK_IDLE_MS) - dt
        if animal.idleMs <= 0 then
            animal.idleMs = config.FLOCK_IDLE_MS * (0.5 + random())
            animal.idleYaw = random() * TWO_PI
            animal.idleWalkMs = config.FLOCK_IDLE_WALK_MS
        end
        animal.idleWalkMs = (animal.idleWalkMs or 0) - dt
        if animal.idleWalkMs > 0 then
            -- facing a fence it still turns away to wander; it only walks once the way is clear
            RseHerdRules.turn(animal, animal.idleYaw or animal.yaw, config.HERD_TURN_SPEED, dt)
            RseHerdRules.go(animal, animal.blocked and 0 or config.HERD_WANDER_SPEED, animal.blocked and config.FLOCK_DECEL or config.HERD_ACCEL, dt)
        else
            RseHerdRules.go(animal, 0, config.FLOCK_DECEL, dt)
        end
    end
    keepOut(animal, lastX, lastZ, world, config)
    if (animal.huddleLeft or 0) > 0 and animal.huddleX ~= nil then
        -- the step a honk asked for counts down with how far it really came in
        local came = (animal.x - lastX) * animal.huddleX + (animal.z - lastZ) * animal.huddleZ
        animal.huddleLeft = (animal.huddleMs or 0) > 0 and math.max(0, animal.huddleLeft - math.max(0, came)) or 0
    end
    if RseFlockRules.isInside(animal.x, animal.z, world.pen, config) then
        animal.penned = true
        animal.stray = false
        animal.flightSpeed = 0
        return "in"
    end
    -- trying to go somewhere and getting nowhere
    if wanting and animal.speed < config.FLOCK_MIN_SPEED then
        animal.stuckMs = (animal.stuckMs or 0) + dt
        if animal.stuckMs >= config.FLOCK_STUCK_MS then
            animal.stuckMs = 0
            return "stuck"
        end
    else
        animal.stuckMs = 0
    end
    return nil
end
