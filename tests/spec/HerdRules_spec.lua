describe("RseHerdRules", function()
    local function fixed(value)
        return function()
            return value
        end
    end

    local function newAnimal(x, z)
        return { x = x, z = z, yaw = 0, moving = false, speed = 0 }
    end

    local function run(animal, seconds, world, random)
        local result = nil
        for _ = 1, seconds * 10 do
            result = RseHerdRules.step(animal, 100, world, RseConfig, random) or result
        end
        return result
    end

    local function fromHome(animal)
        return math.sqrt(animal.x * animal.x + animal.z * animal.z)
    end

    it("turns the short way round", function()
        expectNear(RseHerdRules.angleDiff(0, 3 * math.pi / 2), -math.pi / 2, 0.001)
        expectNear(RseHerdRules.angleDiff(3, -3), 2 * math.pi - 6, 0.001)
    end)

    it("wanders away from where it started, slowly", function()
        local animal = newAnimal(2, 0)
        run(animal, 60, { homeX = 0, homeZ = 0 }, fixed(0.5))
        expectTrue(fromHome(animal) > 5, "it has gone somewhere")
        expectTrue(fromHome(animal) < 2 + 60 * RseConfig.HERD_WANDER_SPEED, "at a walk at most")
    end)

    it("eases into a walk and out of it", function()
        local animal = newAnimal(2, 0)
        animal.walkMs = 5000
        animal.targetYaw = 0
        RseHerdRules.step(animal, 100, { homeX = 0, homeZ = 0 }, RseConfig, fixed(0.5))
        expectTrue(animal.speed > 0 and animal.speed < RseConfig.HERD_WANDER_SPEED, "getting going")
        run(animal, 2, { homeX = 0, homeZ = 0 }, fixed(0.5))
        expectNear(animal.speed, RseConfig.HERD_WANDER_SPEED, 0.001, "walking")
        animal.walkMs = 0
        animal.pauseMs = 100000
        RseHerdRules.step(animal, 100, { homeX = 0, homeZ = 0 }, RseConfig, fixed(0.5))
        expectTrue(animal.speed > 0 and animal.speed < RseConfig.HERD_WANDER_SPEED, "slowing down")
    end)

    it("stops now and then", function()
        local animal = newAnimal(2, 0)
        local stopped, moved = 0, 0
        for _ = 1, 600 do
            RseHerdRules.step(animal, 100, { homeX = 0, homeZ = 0 }, RseConfig, fixed(0.5))
            if animal.moving then
                moved = moved + 1
            else
                stopped = stopped + 1
            end
        end
        expectTrue(stopped > 0 and moved > 0, "both")
    end)

    it("doesn't go past the limit for long", function()
        local animal = newAnimal(RseConfig.HERD_LEASH + 1, 0)
        run(animal, 300, { homeX = 0, homeZ = 0 }, fixed(0.5))
        expectTrue(fromHome(animal) < RseConfig.HERD_LEASH + 10, "it came back")
    end)

    it("shies away from you", function()
        local animal = newAnimal(3, 0)
        animal.yaw = -math.pi / 2
        run(animal, 2, { homeX = 0, homeZ = 0, playerX = 0, playerZ = 0 }, fixed(0.5))
        expectTrue(animal.x > 3, "it moved off")
        expectNear(animal.speed, RseConfig.HERD_SPOOK_SPEED, 0.001)
    end)

    it("doesn't mind someone standing still, so you can watch it graze", function()
        local animal = newAnimal(3, 0)
        animal.pauseMs = 100000
        run(animal, 2, { homeX = 0, homeZ = 0, playerX = 0, playerZ = 0, playerStill = true }, fixed(0.5))
        expectEqual(animal.x, 3)
        expectEqual(animal.speed, 0)
    end)

    it("can be caught on foot: it shies away more slowly than you walk", function()
        expectTrue(RseConfig.HERD_SPOOK_SPEED < 1.4, "a person walks about 1.4 m/s")
    end)

    it("stands still when something is right ahead of it, and turns", function()
        local animal = newAnimal(5, 0)
        animal.walkMs = 5000
        animal.targetYaw = 0
        local yaw = animal.yaw
        run(animal, 2, { homeX = 0, homeZ = 0, blocked = true }, fixed(0.5))
        expectEqual(animal.x, 5)
        expectEqual(animal.z, 0)
        expectTrue(animal.yaw ~= yaw, "turned")
    end)

    it("keeps looking for a way out when every direction is blocked", function()
        local animal = newAnimal(5, 0)
        animal.walkMs = 600000
        animal.targetYaw = 0
        run(animal, 20, { homeX = 0, homeZ = 0, blocked = true }, fixed(0.5))
        local yaw = animal.yaw
        run(animal, 20, { homeX = 0, homeZ = 0, blocked = true }, fixed(0.5))
        expectTrue(animal.yaw ~= yaw, "still turning")
        expectEqual(animal.x, 5, "not walking")
    end)

    it("follows you on a lead and stays close", function()
        local animal = newAnimal(10, 0)
        run(animal, 20, { homeX = 0, homeZ = 0, playerX = 0, playerZ = 0, led = true }, fixed(0.5))
        expectTrue(fromHome(animal) < RseConfig.HERD_LEAD_LENGTH + 0.5, "close behind you")
        expectTrue(fromHome(animal) >= RseConfig.HERD_LEAD_LENGTH - 0.5, "not on top of you")
    end)

    it("gets away when you go too far ahead", function()
        local animal = newAnimal(RseConfig.HERD_LEAD_BREAK + 5, 0)
        expectEqual(RseHerdRules.step(animal, 100, { homeX = 0, homeZ = 0, playerX = 0, playerZ = 0, led = true }, RseConfig, fixed(0.5)), "broke")
        expectEqual(RseHerdRules.step(animal, 100, { homeX = 0, homeZ = 0, led = true }, RseConfig, fixed(0.5)), "broke", "no player")
    end)
end)
