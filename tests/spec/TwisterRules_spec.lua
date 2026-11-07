describe("RseTwisterRules", function()
    it("wanders at a steady speed in long curves, and comes back at the end of its leash", function()
        local seed = 12345
        local function random()
            seed = seed * 16807 % 2147483647
            return seed / 2147483647
        end
        local state = {}
        local furthest, travelled = 0, 0
        local lastX, lastZ = 0, 0
        for _ = 1, 60 * 60 * 30 do -- an hour at 30 frames a second
            RseTwisterRules.wander(state, 33, RseConfig, random)
            local dx, dz = state.x - lastX, state.z - lastZ
            travelled = travelled + math.sqrt(dx * dx + dz * dz)
            lastX, lastZ = state.x, state.z
            furthest = math.max(furthest, math.sqrt(state.x * state.x + state.z * state.z))
        end
        expectTrue(furthest > RseConfig.TWISTER_WANDER_RADIUS * 0.5, "it really goes somewhere")
        expectTrue(furthest < RseConfig.TWISTER_WANDER_RADIUS + 30, "and stays near")
        local expected = RseConfig.TWISTER_WANDER_SPEED * 0.033 * 60 * 60 * 30
        expectTrue(math.abs(travelled - expected) < expected * 0.001, "at a steady speed")
    end)

    it("keeps its area across a reload, unless it is plainly another twister", function()
        local x, z = RseTwisterRules.base({ x = 100, z = 100 }, 150, 120, RseConfig)
        expectEqual(x, 100)
        expectEqual(z, 100)
        x, z = RseTwisterRules.base({ x = 100, z = 100 }, 900, 900, RseConfig)
        expectEqual(x, 900)
        expectEqual(z, 900)
        x, z = RseTwisterRules.base(nil, 5, 6, RseConfig)
        expectEqual(x, 5)
        expectEqual(z, 6)
    end)
end)
