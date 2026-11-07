describe("RseCrewRules", function()
    -- a straight road along +x, a point every 5 m, ending where the truck stops
    local function straight(length)
        local route = {}
        for x = 0, length, 5 do
            table.insert(route, { x = x, z = 0 })
        end
        return route
    end

    it("measures the road to the end", function()
        expectNear(RseCrewRules.lengthFrom(straight(600), 1), 600, 1e-6)
        expectNear(RseCrewRules.lengthFrom(straight(600), 120), 5, 1e-6, "the last stretch")
    end)

    it("comes from out of sight, at least the least distance along the road", function()
        local route = straight(600)
        -- the player at the stop, looking down the road towards where the truck comes from (-x): it must come from beyond what can be seen
        local i = RseCrewRules.spawnIndex(route, 600, 0, -1, 0, RseConfig)
        expectTrue(i ~= nil)
        expectTrue(600 - route[i].x >= RseConfig.CREW_UNSEEN_DISTANCE - 5, "further than can be seen: " .. tostring(600 - route[i].x))
        -- looking the other way: the nearest spot past the least distance will do
        i = RseCrewRules.spawnIndex(route, 600, 0, 1, 0, RseConfig)
        expectNear(600 - route[i].x, RseConfig.CREW_SPAWN_MIN, 5, "as near as allowed")
    end)

    it("never appears right by the player", function()
        local route = straight(600)
        -- the player stands on the road 300 m back, looking away
        local i = RseCrewRules.spawnIndex(route, 300, 0, 0, 1, RseConfig)
        expectTrue(math.abs(route[i].x - 300) >= RseConfig.CREW_SPAWN_CLEAR - 5, "clear of the player: " .. route[i].x)
    end)

    it("falls back to the far end, and to nothing on a road too short to come along", function()
        expectEqual(RseCrewRules.spawnIndex(straight(200), 200, 0, 1, 0, RseConfig), 1, "shorter than the least distance: the far end")
        expectNil(RseCrewRules.spawnIndex(straight(40), 40, 0, 1, 0, RseConfig), "too short: no truck")
    end)

    it("steers at a point ahead along the road", function()
        local route = straight(100)
        local point, index = RseCrewRules.target(route, 1, 0, 0, RseConfig)
        expectTrue(point.x > 0 and point.x <= RseConfig.CREW_LOOK_AHEAD + 5, "a little ahead: " .. point.x)
        point, index = RseCrewRules.target(route, index, 98, 0, RseConfig)
        expectEqual(point.x, 100, "the end")
        expectEqual(index, #route)
    end)

    it("slows down towards the end", function()
        expectEqual(RseCrewRules.speedFor(500, RseConfig), RseConfig.CREW_SPEED)
        expectEqual(RseCrewRules.speedFor(RseConfig.CREW_SLOW_DISTANCE, RseConfig), RseConfig.CREW_SLOW_SPEED)
        expectEqual(RseCrewRules.speedFor(5, RseConfig), RseConfig.CREW_CREEP_SPEED)
    end)

    it("parks at the end, works, and is done", function()
        local state = { phase = "driving" }
        expectNil(RseCrewRules.tick(state, 1000, { distanceLeft = 300, speed = 50 }, RseConfig))
        expectEqual(RseCrewRules.tick(state, 1000, { distanceLeft = 2, speed = 3 }, RseConfig), "parked")
        expectEqual(RseCrewRules.secondsLeft(state, 0, RseConfig), RseConfig.CREW_WORK_MS / 1000)
        expectNil(RseCrewRules.tick(state, RseConfig.CREW_WORK_MS - 1, { distanceLeft = 2, speed = 0 }, RseConfig))
        expectEqual(RseCrewRules.tick(state, 1, { distanceLeft = 2, speed = 0 }, RseConfig), "done")
    end)

    it("parks where it is when held up for good once under way (a queue at the scene)", function()
        local state = { phase = "driving" }
        RseCrewRules.tick(state, 1000, { distanceLeft = 200, speed = 40 }, RseConfig)
        expectNil(RseCrewRules.tick(state, RseConfig.CREW_HELD_MS - 1, { distanceLeft = 80, speed = 0 }, RseConfig))
        expectEqual(RseCrewRules.tick(state, 1, { distanceLeft = 80, speed = 0 }, RseConfig), "parked")
    end)

    it("gives up when it never gets moving, so the timer cuts the power", function()
        local state = { phase = "driving" }
        expectNil(RseCrewRules.tick(state, RseConfig.CREW_START_MS - 1, { distanceLeft = 300, speed = 0 }, RseConfig))
        expectEqual(RseCrewRules.tick(state, 1, { distanceLeft = 300, speed = 0 }, RseConfig), "failed")
    end)

    it("tells the panel about how long it will be", function()
        local state = { phase = "driving" }
        expectEqual(RseCrewRules.secondsLeft(state, 330, RseConfig), math.ceil(330 / RseConfig.CREW_ETA_SPEED + RseConfig.CREW_WORK_MS / 1000))
    end)

    it("pulls over away from the other lanes", function()
        -- driving along +x; its right-hand side by (-dirZ, dirX) is +z. The other lane lies at z = -3.5, so the truck pulls over to +z
        local function nearest(_, z)
            return math.min(math.abs(z), math.abs(z + 3.5))
        end
        expectEqual(RseCrewRules.shoulderSide(0, 0, 1, 0, 2.2, nearest), 1)
        local function nearestOther(_, z)
            return math.min(math.abs(z), math.abs(z - 3.5))
        end
        expectEqual(RseCrewRules.shoulderSide(0, 0, 1, 0, 2.2, nearestOther), -1, "the other lane on the right: it pulls over left")
    end)
end)
