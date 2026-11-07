describe("RseFlockRules", function()
    local function near(a, b, margin)
        return math.abs(a - b) <= (margin or 1e-6)
    end

    it("feels a vehicle from further off than a person, and never pushes harder than full", function()
        expectEqual(RseFlockRules.pressure(nil, false, RseConfig), 0, "no player")
        expectEqual(RseFlockRules.pressure(RseConfig.FLOCK_PUSH_VEHICLE, false, RseConfig), 0)
        expectTrue(RseFlockRules.pressure(RseConfig.FLOCK_PUSH_VEHICLE - 1, false, RseConfig) > 0, "a vehicle, just inside its zone")
        expectEqual(RseFlockRules.pressure(RseConfig.FLOCK_PUSH_FOOT, true, RseConfig), 0, "a person isn't felt that far")
        expectEqual(RseFlockRules.pressure(0, true, RseConfig), 1)
        expectEqual(RseFlockRules.pressure(RseConfig.FLOCK_PUSH_FULL, false, RseConfig), 1)
    end)

    it("finds the middle of those still loose", function()
        local x, z, count = RseFlockRules.centre({ { x = 0, z = 0 }, { x = 10, z = 0 }, { x = 99, z = 99, penned = true } })
        expectEqual(x, 5)
        expectEqual(z, 0)
        expectEqual(count, 2)
        local _, _, none = RseFlockRules.centre({ { x = 1, z = 1, penned = true } })
        expectEqual(none, 0)
    end)

    it("lays the hurdles in a ring with the gate open", function()
        local pen = RseFlockRules.newPen(100, 200, 0, RseConfig)
        for _, length in ipairs({ RseConfig.FLOCK_HURDLE_LENGTH, 1.2, 2.4 }) do
            local pieces = RseFlockRules.penPieces(pen, RseConfig, length)
            expectTrue(#pieces > 8, "enough to look like a pen: " .. #pieces)
            for i, piece in ipairs(pieces) do
                local distance = math.sqrt((piece.x - 100) ^ 2 + (piece.z - 200) ^ 2)
                expectTrue(near(distance, pen.radius, 1e-6), "on the ring")
                local angle = math.abs(RseHerdRules.angleDiff(0, math.atan2(piece.x - 100, piece.z - 200)))
                expectTrue(angle - length / 2 / pen.radius >= RseConfig.FLOCK_GATE_HALF - 1e-6,
                    "none reaches into the gate: the gap you see is the gap they use")
                if i > 1 then
                    local before = pieces[i - 1]
                    expectTrue(math.sqrt((piece.x - before.x) ^ 2 + (piece.z - before.z) ^ 2) < length,
                        "each overlaps the one before: no gaps in the ring (Z), " .. length .. " m hurdles")
                end
            end
        end
        expectTrue(near(pen.gateX, 100) and pen.gateZ > 200 + pen.radius, "the gate is on the side it faces")
    end)

    it("puts the truck well out from the ring, with room for a flock to pass inside it", function()
        local pen = RseFlockRules.newPen(0, 0, 1, RseConfig)
        local truck = RseFlockRules.truckSpot(pen, RseConfig)
        expectTrue(math.sqrt(truck.x ^ 2 + truck.z ^ 2) >= pen.radius + 10)
    end)

    it("turns the pen's gate toward the flock, but well off to one side", function()
        local list = RseFlockRules.penCandidates(10, 20, RseConfig, function() return 0.3 end)
        expectEqual(#list, #RseConfig.FLOCK_PEN_DISTANCES * RseConfig.FLOCK_PEN_ANGLES)
        for _, candidate in ipairs(list) do
            local gateX, gateZ = math.sin(candidate.gateYaw), math.cos(candidate.gateYaw)
            local toFlockX, toFlockZ = 10 - candidate.x, 20 - candidate.z
            local along = (gateX * toFlockX + gateZ * toFlockZ) / math.sqrt(toFlockX ^ 2 + toFlockZ ^ 2)
            expectTrue(along > 0, "you can see the way in from the flock")
            expectTrue(along < math.cos(RseConfig.FLOCK_GATE_TURN[1]) + 1e-6, "but you can't just push them straight at it")
        end
    end)

    it("pays the job and each animal, and only those in the pen when handed over", function()
        local def = { pay = 1000, payPerAnimal = 100 }
        expectEqual(RseFlockRules.pay(def, 10, 10, false), 2000)
        expectEqual(RseFlockRules.pay(def, 4, 10, true), 400)
        expectEqual(RseFlockRules.pay(def, 0, 10, true), 0)
        expectEqual(RseFlockRules.share(5, 10), 0.5)
        expectEqual(RseFlockRules.share(0, 0), 0)
    end)

    -- a pen at (0, 100) with its gate toward us: the gate is at z = 90
    local function world(extra)
        local pen = RseFlockRules.newPen(0, 100, math.pi, RseConfig)
        local w = { cx = 0, cz = 0, pen = pen, animals = {}, obstacles = {}, inPen = 0, onFoot = false, playerSpeed = 0 }
        for key, value in pairs(extra or {}) do
            w[key] = value
        end
        return w
    end

    local function sheep(x, z)
        return { x = x or 0, z = z or 0, yaw = 0, speed = 0 }
    end

    local function middling()
        return 0.5
    end

    it("leaves a flock alone that nobody presses", function()
        local animal = sheep()
        local vx, vz = RseFlockRules.steer(animal, world({ animals = { animal } }), RseConfig)
        expectEqual(vx, 0)
        expectEqual(vz, 0)
    end)

    it("moves straight away from you, faster the closer you are", function()
        local animal = sheep()
        local vx, vz = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = -10, playerZ = 0 }), RseConfig)
        expectTrue(vx > 0 and near(vz, 0), "straight away: " .. vx .. ", " .. vz)
        local lightWorld = world({ animals = { animal }, playerX = 0, playerZ = -(RseConfig.FLOCK_PUSH_VEHICLE - 1) })
        local _, light = RseFlockRules.steer(animal, lightWorld, RseConfig)
        local hardWorld = world({ animals = { animal }, playerX = 0, playerZ = -(RseConfig.FLOCK_PUSH_FULL + 0.1) })
        local _, hard = RseFlockRules.steer(animal, hardWorld, RseConfig)
        expectTrue(hard > light and light >= RseConfig.FLOCK_WALK)
        expectTrue(hard <= RseConfig.FLOCK_TROT + 1e-6)
    end)

    it("goes away from you even when the pen is the other way: it knows nothing of the pen", function()
        local animal = sheep(0, 40)
        local _, vz = RseFlockRules.steer(animal, world({ animals = { animal }, cz = 40, playerX = 0, playerZ = 50 }), RseConfig)
        expectTrue(vz < 0)
    end)

    it("doesn't feel you from too far, a person less far than a vehicle", function()
        local animal = sheep()
        local _, far = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = -(RseConfig.FLOCK_PUSH_VEHICLE + 1) }), RseConfig)
        expectEqual(far, 0)
        local gap = -(RseConfig.FLOCK_PUSH_FOOT + 1)
        local _, onFoot = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = gap, onFoot = true }), RseConfig)
        expectEqual(onFoot, 0)
        local _, driving = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = gap }), RseConfig)
        expectTrue(driving > 0)
    end)

    it("hears your horn from further off than it feels you", function()
        local animal = sheep()
        local gap = -(RseConfig.FLOCK_PUSH_VEHICLE + 2)
        local _, silent = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = gap }), RseConfig)
        local _, horn = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = gap, horn = true }), RseConfig)
        expectEqual(silent, 0)
        expectTrue(horn > 0)
    end)

    it("goes with those beside it when they are on the move, and not for long after", function()
        local a, b = sheep(0, 0), sheep(2, 0)
        b.flightX, b.flightZ, b.flightSpeed = 2, 0, 2
        local vx = RseFlockRules.steer(a, world({ animals = { a, b } }), RseConfig)
        expectTrue(vx > 0, "with them")
        b.flightX, b.flightSpeed = 0.1, 0.1
        vx = RseFlockRules.steer(a, world({ animals = { a, b } }), RseConfig)
        expectEqual(vx, 0)
    end)

    it("minds where you are a little beyond where it feels you, and not at all further out", function()
        local outer = RseConfig.FLOCK_PUSH_VEHICLE
        expectEqual(RseFlockRules.aware(outer - 1, false, RseConfig), 1)
        local half = RseFlockRules.aware(outer + RseConfig.FLOCK_AWARE / 2, false, RseConfig)
        expectTrue(half > 0.4 and half < 0.6, "easing off: " .. half)
        expectEqual(RseFlockRules.aware(outer + RseConfig.FLOCK_AWARE + 1, false, RseConfig), 0)
        expectEqual(RseFlockRules.aware(nil, false, RseConfig), 0)
        expectTrue(RseFlockRules.aware(RseConfig.FLOCK_PUSH_FOOT + RseConfig.FLOCK_AWARE / 2, true, RseConfig) < 1, "a person, less far")
    end)

    it("going round them, a pressed bunch turns together, away through its middle, and doesn't fan out (Z)", function()
        local function offStraight(groupAway)
            local config = setmetatable({ FLOCK_GROUP_AWAY = groupAway }, { __index = RseConfig })
            -- further apart than it closes up on, so only the way away from you counts
            local apart = RseConfig.FLOCK_SENSE + 1
            local edge, mid, other = sheep(-apart, 0), sheep(0, 0), sheep(apart, 0)
            local vx, vz = RseFlockRules.steer(edge, world({ animals = { edge, mid, other }, playerX = 0, playerZ = -12 }), config)
            return math.abs(math.atan2(vx, vz))
        end
        expectTrue(offStraight(RseConfig.FLOCK_GROUP_AWAY) < offStraight(0) - 0.05, "closer to straight away from you through the middle")
    end)

    it("on the move a little beyond your reach, it bends away from your side", function()
        local a, b = sheep(0, 0), sheep(2, 0)
        b.flightX, b.flightZ, b.flightSpeed = 0, 2, 2
        local gap = RseConfig.FLOCK_PUSH_VEHICLE + 3
        local vx, vz = RseFlockRules.steer(a, world({ animals = { a, b }, playerX = gap, playerZ = 0 }), RseConfig)
        expectTrue(vz > 0 and vx < -0.1, "on with them, and away from your side: " .. vx)
        local far = RseFlockRules.steer(a, world({ animals = { a, b }, playerX = gap + RseConfig.FLOCK_AWARE, playerZ = 0 }), RseConfig)
        expectTrue(near(far, 0), "further out, it takes no notice")
    end)

    it("walks on a little once you swing out wide, turning away from you, then stops", function()
        local animal = sheep(0, 0)
        local w = world({ animals = { animal }, playerX = 0, playerZ = -10 })
        for _ = 1, 60 do
            RseFlockRules.step(animal, 33, w, RseConfig, middling)
        end
        expectTrue(animal.speed > RseConfig.FLOCK_MIN_SPEED, "pushed")
        w.playerX, w.playerZ = animal.x + RseConfig.FLOCK_PUSH_VEHICLE + 4, animal.z
        for _ = 1, 30 do
            RseFlockRules.step(animal, 33, w, RseConfig, middling)
        end
        expectTrue(animal.speed > RseConfig.FLOCK_MIN_SPEED, "still walking a second later")
        expectTrue(math.sin(animal.yaw) < -0.1, "and turning away from your side: " .. animal.yaw)
        for _ = 1, math.ceil((RseConfig.FLOCK_CARRY_MS + 1000) / 33) do
            RseFlockRules.step(animal, 33, w, RseConfig, middling)
        end
        expectTrue(animal.speed < RseConfig.FLOCK_MIN_SPEED, "then it stops")
    end)

    it("goes back to those it can see, even with nobody pressing", function()
        local animal, other = sheep(RseConfig.FLOCK_STRAY + 5, 0), sheep(0, 0)
        local vx = RseFlockRules.steer(animal, world({ animals = { animal, other } }), RseConfig)
        expectTrue(vx < 0, "toward the others")
    end)

    it("stays where it is with none in sight, so bunches wait to be rounded up", function()
        local animal, other = sheep(RseConfig.FLOCK_SEE + 5, 0), sheep(0, 0)
        local vx, vz = RseFlockRules.steer(animal, world({ animals = { animal, other } }), RseConfig)
        expectEqual(vx, 0)
        expectEqual(vz, 0)
    end)

    it("doesn't walk back toward you to rejoin the others: Z saw them turn round for no reason", function()
        local x = RseConfig.FLOCK_STRAY + 5
        local animal, other = sheep(x, 0), sheep(0, 0)
        local vx = RseFlockRules.steer(animal, world({ animals = { animal, other }, playerX = x - (RseConfig.FLOCK_PUSH_VEHICLE + 2), playerZ = 0 }), RseConfig)
        expectTrue(near(vx, 0), "it waits for them: " .. vx)
        local alone = RseFlockRules.steer(animal, world({ animals = { animal, other }, playerX = x + 50, playerZ = 0 }), RseConfig)
        expectTrue(alone < 0, "with you far enough off it goes")
    end)

    it("doesn't step back toward you in a crush", function()
        local a, b = sheep(0, 0), sheep(0, 0.3)
        local _, vz = RseFlockRules.steer(a, world({ animals = { a, b }, playerX = 0, playerZ = -RseConfig.FLOCK_PUSH_VEHICLE + 1 }), RseConfig)
        expectTrue(vz >= -1e-9, "it may stop, not come back: " .. vz)
    end)

    it("doesn't go to the pen by itself, even with half of them in", function()
        local animal = sheep()
        local vx, vz = RseFlockRules.steer(animal, world({ animals = { animal }, inPen = 5 }), RseConfig)
        expectEqual(vx, 0)
        expectEqual(vz, 0)
    end)

    it("joins the others when it is right at the gate, and only with others already in", function()
        local animal = sheep(0, 88)
        local _, alone = RseFlockRules.steer(animal, world({ animals = { animal }, cz = 88 }), RseConfig)
        expectEqual(alone, 0, "the first has to be pushed in")
        local _, with = RseFlockRules.steer(animal, world({ animals = { animal }, cz = 88, inPen = 1 }), RseConfig)
        expectTrue(with > 0, "the rest want to join them")
    end)

    it("keeps them from standing inside each other", function()
        local a, b = sheep(0, 0), sheep(0.3, 0)
        local vx = RseFlockRules.steer(a, world({ animals = { a, b } }), RseConfig)
        expectTrue(vx < 0, "apart")
    end)

    it("hurries with you right on it", function()
        local animal = sheep()
        local _, vz = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = -(RseConfig.FLOCK_PERSONAL - 1) }), RseConfig)
        expectTrue(near(vz, RseConfig.FLOCK_RUN))
    end)

    it("goes along the ring the way it was already tending, so you choose which way round", function()
        local z = 100 + RseConfig.FLOCK_PEN_RADIUS + 0.5 -- behind the pen, far from its gate
        local right = sheep(1, z)
        local vx, vz = RseFlockRules.steer(right, world({ animals = { right }, cx = 1, cz = z, playerX = -3, playerZ = z + 15 }), RseConfig)
        expectTrue(vx > 0 and math.abs(vx) > math.abs(vz), "around it: " .. vx .. ", " .. vz)
        local left = sheep(1, z)
        vx = RseFlockRules.steer(left, world({ animals = { left }, cx = 1, cz = z, playerX = 5, playerZ = z + 15 }), RseConfig)
        expectTrue(vx < 0, "with you on the other side, the other way: " .. vx)
    end)

    it("stands and presses against the ring with you straight behind it", function()
        local z = 100 + RseConfig.FLOCK_PEN_RADIUS + 0.5
        local animal = sheep(0, z)
        local vx, vz = RseFlockRules.steer(animal, world({ animals = { animal }, cx = 0, cz = z, playerX = 0, playerZ = z + 15 }), RseConfig)
        expectTrue(near(vx, 0) and near(vz, 0), vx .. ", " .. vz)
    end)

    it("can't pass through a hurdle however it is pushed", function()
        local z = 100 + RseConfig.FLOCK_PEN_RADIUS + 3
        local animal = sheep(0, z)
        animal.yaw, animal.speed = math.pi, 3
        local w = world({ animals = { animal }, cx = 0, cz = z, playerX = 0, playerZ = z + 8 })
        for _ = 1, 400 do
            w.cz = animal.z
            RseFlockRules.step(animal, 33, w, RseConfig, middling)
            expectTrue(not animal.penned, "it isn't in")
            expectTrue(math.sqrt(animal.x ^ 2 + (animal.z - 100) ^ 2) >= RseConfig.FLOCK_PEN_RADIUS, "it stays outside")
        end
    end)

    it("goes in by the gate", function()
        local animal = sheep(0, 86)
        animal.yaw = 0
        local w = world({ animals = { animal }, cz = 86, playerX = 0, playerZ = 77 })
        local result = nil
        for _ = 1, 300 do
            w.cz = animal.z
            result = result or RseFlockRules.step(animal, 33, w, RseConfig, middling)
        end
        expectEqual(result, "in")
    end)

    it("walks around the farmer's truck and not through it, and doesn't turn back", function()
        local animal = sheep(0.5, -6)
        local w = world({ animals = { animal }, cx = 0.5, cz = -6, playerX = 0.5, playerZ = -15, obstacles = { { x = 0, z = 0, radius = 3 } } })
        local furthest = animal.z
        for _ = 1, 700 do
            w.cx, w.cz = animal.x, animal.z
            RseFlockRules.step(animal, 33, w, RseConfig, middling)
            expectTrue(math.sqrt(animal.x ^ 2 + animal.z ^ 2) >= 3 - 1e-6, "not through it")
            furthest = math.max(furthest, animal.z)
            expectTrue(animal.pressure == 0 or animal.z >= furthest - 0.2, "not back the way it came while you press it")
        end
        expectTrue(animal.z > 0, "past it: " .. animal.z)
    end)

    it("turns to the open side of something in the way, sideways at first, and further round only in a corner (Z)", function()
        for _, side in ipairs({ 1, -1 }) do
            local animal = sheep()
            animal.blocked, animal.openSide = true, side
            local w = world({ animals = { animal }, playerX = 0, playerZ = -10 })
            for _ = 1, math.floor(RseConfig.FLOCK_CORNER_MS / 50) - 2 do
                RseFlockRules.step(animal, 50, w, RseConfig, middling)
            end
            expectTrue(near(animal.yaw, side * RseConfig.FLOCK_SLIDE_MOST, 0.01), "turned: " .. animal.yaw)
            expectTrue(RseConfig.FLOCK_SLIDE_MOST <= math.pi / 2 + 0.05, "sideways at the very most, at first")
            for _ = 1, 60 do
                RseFlockRules.step(animal, 50, w, RseConfig, middling)
            end
            expectTrue(animal.yaw * side > RseConfig.FLOCK_SLIDE_MOST + 0.8, "still stuck: a corner, so on round, back past you: " .. animal.yaw)
            expectTrue(animal.slideHoldMs == RseConfig.FLOCK_CORNER_HOLD_MS, "and once out it keeps going that way a while")
            animal.blocked = false
            RseFlockRules.step(animal, 50, w, RseConfig, middling)
            expectTrue(animal.cornerSide == nil and animal.blockedMs == 0, "out: the next time starts afresh")
        end
    end)

    it("eases a leg off reaching near full stretch, so the knee doesn't snap, and leaves a bent leg alone", function()
        expectEqual(RseGaitRules.softReach(0.5, 1, 0.92), 0.5, "well within reach: as asked")
        expectEqual(RseGaitRules.softReach(0.95, 1, nil), 0.95, "no softening asked for")
        local last, worstStep = RseGaitRules.softReach(0.9, 1, 0.92), 0
        for i = 1, 200 do
            local now = RseGaitRules.softReach(0.9 + i * 0.001, 1, 0.92)
            expectTrue(now < 1 and now >= last, "never all the way, and never back")
            worstStep = math.max(worstStep, now - last)
            last = now
        end
        expectTrue(worstStep <= 0.001 + 1e-9, "no faster than asked: no jump where it starts")
    end)

    it("sends the whole flock the same way along something when it can't tell which side is open", function()
        local w = world()
        local a, b = sheep(), sheep()
        local picks = { 0.2, 0.8 }
        local function random()
            return table.remove(picks, 1)
        end
        local first = RseFlockRules.noteBlocked(w, a, RseConfig, random)
        local second = RseFlockRules.noteBlocked(w, b, RseConfig, random)
        expectEqual(first, second)
    end)

    it("scatters when a vehicle comes in fast, and not for a slow one or a person", function()
        local function try(speed, onFoot, gap)
            local animal = sheep()
            local w = world({ animals = { animal }, playerX = 0, playerZ = -gap, playerSpeed = speed, onFoot = onFoot })
            RseFlockRules.step(animal, 16, w, RseConfig, middling)
            return (animal.spookMs or 0) > 0, w.scattered == true
        end
        local inside = RseConfig.FLOCK_SPOOK_RADIUS - 1
        local fast = RseConfig.FLOCK_SPOOK_SPEED + 1
        local spooked, told = try(fast, false, inside)
        expectTrue(spooked and told, "too fast")
        expectTrue(not (try(RseConfig.FLOCK_SPOOK_SPEED - 1, false, inside)), "slowly")
        expectTrue(not (try(fast, true, inside)), "on foot")
        expectTrue(not (try(fast, false, RseConfig.FLOCK_SPOOK_RADIUS + 1)), "going past further off")
    end)

    it("may break away when you lean on it, without the player being told they scattered it", function()
        local function try(pressure)
            local animal = sheep()
            animal.pressure = pressure
            local w = world({ animals = { animal }, playerX = 0, playerZ = -30 })
            RseFlockRules.step(animal, 16, w, RseConfig, function() return 0 end)
            return (animal.spookMs or 0) > 0, w.scattered == true
        end
        local broke, told = try(RseConfig.FLOCK_BREAK_PRESSURE)
        expectTrue(broke, "pressed hard")
        expectTrue(not told, "and nobody is told they scattered it")
        expectTrue(not (try(RseConfig.FLOCK_BREAK_PRESSURE - 0.1)), "pressed gently")
    end)

    it("takes one honk as a nudge, however long you hold it, and doesn't push again too soon", function()
        local w = {}
        RseFlockRules.hearHorn(w, true, 16, RseConfig)
        expectTrue(w.horn and w.honked, "they hear it")
        for _ = 1, 200 do
            RseFlockRules.hearHorn(w, true, 16, RseConfig)
        end
        expectTrue(not w.horn, "held down, it wears off")
        RseFlockRules.hearHorn(w, false, 16, RseConfig)
        RseFlockRules.hearHorn(w, true, 16, RseConfig)
        expectTrue(not w.horn, "too soon after the last to push")
        expectTrue(w.honked, "but a step together, the last being a few seconds ago")
        expectTrue(not w.hornScare, "one more doesn't frighten them")
        RseFlockRules.hearHorn(w, false, RseConfig.FLOCK_HORN_REST_MS, RseConfig)
        RseFlockRules.hearHorn(w, true, 16, RseConfig)
        expectTrue(w.horn, "with a long enough rest it pushes again")
    end)

    it("never scatters them for honking now and then, only for leaning on it (Z: more than 3)", function()
        local w = {}
        local steps, pushes, last = 0, 0, false
        for frame = 1, 1800 do -- a minute, a short honk every 2 s
            local honking = frame % 60 < 3
            RseFlockRules.hearHorn(w, honking, 33, RseConfig)
            expectTrue(not w.hornScare, "a honk every 2 s never frightens them")
            steps = steps + (w.honked and 1 or 0)
            pushes = pushes + ((w.horn and not last) and 1 or 0)
            last = w.horn
        end
        expectTrue(steps >= 14 and steps <= 21, "a step every few seconds: " .. steps)
        expectTrue(pushes >= 4 and pushes <= 6, "a push only every 12 s: " .. pushes)
        local scared = false
        for frame = 1, 120 do -- quick taps, five a second
            RseFlockRules.hearHorn(w, frame % 6 < 3, 33, RseConfig)
            scared = scared or w.hornScare
        end
        expectTrue(scared, "leaning on it does")
    end)

    it("each honk is one small step in toward the others, and only a tight bunch stays as it is (Z)", function()
        local tight = RseConfig.FLOCK_HORN_TIGHT
        expectEqual(RseFlockRules.hornStep(tight - 0.5, RseConfig), 0, "close in already: no step")
        expectNear(RseFlockRules.hornStep(tight + 4, RseConfig), 4 * RseConfig.FLOCK_HORN_STEP_SHARE, 1e-9, "a share of the way")
        expectEqual(RseFlockRules.hornStep(tight + 100, RseConfig), RseConfig.FLOCK_HORN_STEP_MAX, "and never far")
    end)

    it("a honk moves one at the edge a little in toward the others, then it is over until the next", function()
        local function after(honk)
            local edge = sheep(-4.3, 0)
            local w = world({ animals = { edge, sheep(0, 0), sheep(1, 0), sheep(0, 1) }, playerX = -3, playerZ = -30 })
            for frame = 1, 300 do
                RseFlockRules.hearHorn(w, honk and frame == 1, 33, RseConfig)
                RseFlockRules.step(edge, 33, w, RseConfig, middling)
            end
            return edge
        end
        local honked, quiet = after(true), after(false)
        local expected = RseFlockRules.hornStep(math.sqrt((4.3 + 1 / 3) ^ 2 + (1 / 3) ^ 2), RseConfig)
        local moved = honked.x - quiet.x
        expectTrue(expected > 0.5, "a step worth seeing: " .. expected)
        expectTrue(moved > expected * 0.6 and moved < expected * 1.4, "about one step further in than without: " .. moved .. " against " .. expected)
        expectEqual(honked.huddleLeft, 0, "and over")
    end)

    it("scatters them if you keep honking", function()
        local w = world()
        local animal = sheep()
        w.animals = { animal }
        local scared = false
        for _ = 1, RseConfig.FLOCK_HORN_TOO_MANY + 1 do
            RseFlockRules.think(w, w.animals, { x = 0, z = -10, horn = true }, 16, RseConfig)
            scared = scared or w.hornScare
            RseFlockRules.step(animal, 16, w, RseConfig, middling)
            RseFlockRules.think(w, w.animals, { x = 0, z = -10, horn = false }, 16, RseConfig)
        end
        expectTrue(scared, "too many honks")
        expectTrue(w.scatteredByHorn, "and the player is told")
        expectTrue(animal.spookMs > 0, "they are frightened")
        expectTrue((animal.huddleLeft or 0) == 0 or animal.spookMs > 0, "and don't draw together: a scare is a scare")
    end)

    it("changes its mind gently: no twitching", function()
        local animal = sheep()
        animal.speed, animal.yaw = 1, 0
        local w = world({ animals = { animal }, playerX = 0, playerZ = 10 })
        RseFlockRules.step(animal, 16, w, RseConfig, middling)
        expectTrue(math.abs(animal.yaw) <= RseConfig.FLOCK_TURN * 0.016 + 1e-6, "it turns no faster than it can")
        expectTrue(math.abs(animal.wantZ) < RseConfig.FLOCK_WALK, "and the new way only comes through bit by bit")
    end)

    it("goes at a walk unless you crowd it", function()
        local animal = sheep()
        local _, middling_gap = RseFlockRules.steer(animal, world({ animals = { animal }, playerX = 0, playerZ = -14 }), RseConfig)
        expectTrue(middling_gap < RseConfig.FLOCK_WALK + (RseConfig.FLOCK_TROT - RseConfig.FLOCK_WALK) * 0.35, "at 14 m: " .. middling_gap)
    end)

    it("starts in bunches out of sight of each other, as many sheep as asked for", function()
        for _, total in ipairs({ 1, 3, 4, 8, 9, 10, 16, 40 }) do
            local sum = 0
            for _, group in ipairs(RseFlockRules.startGroups(total, RseConfig, middling)) do
                expectTrue(group.count > 0, "no empty bunch at " .. total)
                sum = sum + group.count
            end
            expectEqual(sum, total)
        end
        expectEqual(#RseFlockRules.startGroups(16, RseConfig, middling), 3)
        expectEqual(#RseFlockRules.startGroups(6, RseConfig, middling), 2)
        expectTrue(RseConfig.FLOCK_GROUP_APART - 2 * RseConfig.FLOCK_SPAN >= RseConfig.FLOCK_SEE, "out of sight, even at their nearest")
    end)

    it("knows which bunches there are, and marks one of each smaller one", function()
        local animals = { sheep(0, 0), sheep(3, 0), sheep(6, 0), sheep(100, 0), sheep(103, 0), sheep(0, 200) }
        animals[6].penned = true
        local w = {}
        local groups = RseFlockRules.markGroups(w, animals, RseConfig)
        expectEqual(#groups, 2)
        expectEqual(groups[1].count, 3, "biggest first")
        expectTrue(near(groups[1].x, 3), "its middle")
        expectTrue(animals[4].stray and not animals[5].stray, "one pin for the smaller bunch")
        expectTrue(not animals[1].stray, "none for the biggest")
    end)

    it("closes the gate with as many hurdles as it takes", function()
        local pen = RseFlockRules.newPen(100, 200, 0, RseConfig)
        local pieces = RseFlockRules.gatePieces(pen, RseConfig, 1.5)
        expectTrue(#pieces >= 1)
        expectTrue(#pieces * 1.5 * RseConfig.FLOCK_HURDLE_SHARE >= 2 * RseConfig.FLOCK_GATE_HALF * pen.radius, "they fill the gap")
        for _, piece in ipairs(pieces) do
            expectTrue(near(math.sqrt((piece.x - 100) ^ 2 + (piece.z - 200) ^ 2), pen.radius), "on the ring")
            expectTrue(math.abs(RseHerdRules.angleDiff(0, math.atan2(piece.x - 100, piece.z - 200))) < RseConfig.FLOCK_GATE_HALF, "in the gate")
        end
    end)

    it("can't be driven off across the map", function()
        local far = RseConfig.FLOCK_LEASH + RseConfig.FLOCK_LEASH_SOFT + 5
        local animal = sheep(0, 100 - far)
        local _, vz = RseFlockRules.steer(animal, world({ animals = { animal }, cz = animal.z, playerX = 0, playerZ = animal.z + 10 }), RseConfig)
        expectTrue(vz >= 0 or near(vz, 0), "it won't go further: " .. vz)
    end)

    it("says so when one reaches the pen, and it stays in", function()
        local animal = sheep(0, 100)
        local result = RseFlockRules.step(animal, 16, world({ animals = { animal } }), RseConfig, middling)
        expectEqual(result, "in")
        expectTrue(animal.penned)
    end)

    it("gives up on being stuck after a while, and says so once", function()
        local animal = sheep()
        animal.blocked = true
        local w = world({ animals = { animal }, playerX = 0, playerZ = -5 })
        local said = 0
        for _ = 1, 20 do
            if RseFlockRules.step(animal, 1000, w, RseConfig, middling) == "stuck" then
                said = said + 1
            end
        end
        expectEqual(said, 1, "after " .. RseConfig.FLOCK_STUCK_MS .. " ms, and not again at once")
    end)

    it("keeps a saved flock, and those in the pen", function()
        local base = { id = "flock", x = 1, y = 2, z = 3, wreck = { kind = "flock", state = "locked", bales = {} } }
        base.flock = { total = "10", x = "5", z = "6", gateYaw = "1.5" }
        base.survivors = { { kind = "sheep", x = "1", y = "2", z = "3", yaw = "0", penned = true, lamb = "true" },
            { kind = "sheep", x = "1", y = "2", z = "3" } }
        local scene = RseSaveCodec.normalize({ scene = base }, RseConfig).scene
        expectEqual(scene.flock.total, 10)
        expectEqual(scene.flock.gateYaw, 1.5)
        expectTrue(scene.survivors[1].penned and scene.survivors[1].lamb)
        expectEqual(scene.survivors[2].penned, false)
        base.flock = { total = "10" }
        expectNil(RseSaveCodec.normalize({ scene = base }, RseConfig).scene.flock, "without a pen there is nothing to bring back")
    end)
end)
