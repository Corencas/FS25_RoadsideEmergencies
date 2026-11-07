describe("RseCrossingRules", function()
    local lap = 397 -- Riverbend Springs: 8,823 m at 80 km/h

    it("gives you the drive at a fair speed and the time to get a line on", function()
        local near = RseCrossingRules.allowance(0, lap, RseConfig)
        expectEqual(near, RseConfig.CROSSING_WORK_SECONDS)
        expectNear(RseCrossingRules.allowance(1000, lap, RseConfig), 1000 / RseConfig.CROSSING_DRIVE_SPEED + RseConfig.CROSSING_WORK_SECONDS, 1e-6)
        expectEqual(RseCrossingRules.allowance(5000, lap, RseConfig), lap - RseConfig.CROSSING_LAP_MARGIN, "never more than a lap")
    end)

    it("knows how far the train still has to go, across the start of the track", function()
        expectNear(RseCrossingRules.ahead(0.5, 0.25, 1000), 250, 1e-6)
        expectNear(RseCrossingRules.ahead(0.1, 0.9, 1000), 200, 1e-6, "round the end")
        expectNear(RseCrossingRules.ahead(0.25, 0.5, 1000), 750, 1e-6, "just gone by: nearly a whole lap")
    end)

    it("only calls from a crossing that is within reach and fits into a lap", function()
        local near = { index = 1, distance = 500, seconds = 0 }
        local middle = { index = 2, distance = 2000, seconds = 0 }
        local far = { index = 3, distance = RseConfig.CROSSING_MAX_DISTANCE + 1, seconds = 0 }
        local list = RseCrossingRules.candidates({ near, middle, far }, lap, RseConfig)
        expectEqual(#list, 2)
        expectEqual(#RseCrossingRules.candidates({ near, middle }, 200, RseConfig), 0, "a short lap gives neither enough time")
        expectEqual(#RseCrossingRules.candidates({ near }, 300, RseConfig), 1, "the near one fits, at 2 min plus the drive")
    end)

    it("chooses any crossing, and not the same one twice while there is another", function()
        local list = { { index = 1 }, { index = 2 }, { index = 3 } }
        expectEqual(RseCrossingRules.choose(list, nil, 0), 1)
        expectEqual(RseCrossingRules.choose(list, nil, 0.999), 3)
        expectEqual(RseCrossingRules.choose(list, 1, 0), 2, "not the last one")
        expectEqual(RseCrossingRules.choose({ { index = 1 } }, 1, 0.5), 1, "the last one if it is all there is")
        expectNil(RseCrossingRules.choose({}, nil, 0.5))
    end)

    it("calls when the train is the right time from the crossing chosen, however far it is", function()
        for _, distance in ipairs({ 100, 1000, 1800 }) do
            local allowed = RseCrossingRules.allowance(distance, lap, RseConfig)
            expectTrue(RseCrossingRules.isMoment({ distance = distance, seconds = allowed + 1 }, lap, RseConfig), "right on time")
            expectTrue(not RseCrossingRules.isMoment({ distance = distance, seconds = allowed - 1 }, lap, RseConfig), "too late for you to make it")
            expectTrue(not RseCrossingRules.isMoment({ distance = distance, seconds = allowed + RseConfig.CROSSING_SLACK + 1 }, lap, RseConfig), "too early")
        end
        expectTrue(RseCrossingRules.allowance(1800, lap, RseConfig) > RseCrossingRules.allowance(100, lap, RseConfig), "further away, more time")
        expectTrue(not RseCrossingRules.isMoment(nil, lap, RseConfig), "no crossing")
    end)

    it("keeps the chosen crossing after a short wait at the pager, and finds another after a long one", function()
        local allowed = RseCrossingRules.allowance(800, lap, RseConfig)
        local chosen = { index = 1, distance = 800, seconds = allowed - RseConfig.CROSSING_PAGER_GRACE + 1 }
        local other = { index = 2, distance = 1500, seconds = 390 }
        expectEqual(RseCrossingRules.pick({ chosen, other }, 1, lap, RseConfig, 0), chosen, "a short wait")
        chosen.seconds = allowed - RseConfig.CROSSING_PAGER_GRACE - 1
        expectEqual(RseCrossingRules.pick({ chosen, other }, 1, lap, RseConfig, 0), other, "a long wait: one that still leaves enough")
        local short = RseCrossingRules.pick({ { index = 1, distance = 200, seconds = 10 }, { index = 2, distance = 800, seconds = 30 } }, 1, lap, RseConfig, 0)
        expectEqual(short.distance, 200, "none leaves enough: the least short of time")
        expectNil(RseCrossingRules.pick({}, nil, lap, RseConfig, 0))
    end)

    it("knows which way is away from the track", function()
        local x, z = RseCrossingRules.awayFromTrack(5, 3, 5, 0, 1, 0)
        expectEqual(x, 0)
        expectEqual(z, 1)
        x, z = RseCrossingRules.awayFromTrack(5, -3, 5, 0, 1, 0)
        expectEqual(z, -1, "the other side")
        expectTrue(x == 0)
    end)

    it("sees a vehicle in the train's way, whichever way the track runs", function()
        local half = 2.5
        expectTrue(RseCrossingRules.isOnTracks(0, 1, 0, 0, 1, 0, half, RseConfig), "beside the rails, but its length reaches them")
        expectTrue(not RseCrossingRules.isOnTracks(0, half + RseConfig.CROSSING_TRAIN_HALF + 1, 0, 0, 1, 0, half, RseConfig), "clear")
        expectTrue(RseCrossingRules.isOnTracks(50, 0, 0, 0, 1, 0, half, RseConfig), "further along the track is still on it")
        expectTrue(not RseCrossingRules.isOnTracks(10, 0, 0, 0, 0, 1, half, RseConfig), "the track runs the other way")
    end)

    it("lets go just before the train, then says whether it was hit, once", function()
        local state = {}
        expectNil(RseCrossingRules.tick(state, 500, true, RseConfig))
        expectEqual(RseCrossingRules.tick(state, RseConfig.CROSSING_RELEASE_M, true, RseConfig), "release")
        expectNil(RseCrossingRules.tick(state, RseConfig.CROSSING_RELEASE_M - 5, true, RseConfig), "once")
        expectEqual(RseCrossingRules.tick(state, RseConfig.CROSSING_HIT_M, true, RseConfig), "hit")
        expectNil(RseCrossingRules.tick(state, 5, true, RseConfig), "and that is the end of it")
    end)

    it("says the train has gone by when the vehicle is clear, and doesn't let go of anything", function()
        local state = {}
        expectNil(RseCrossingRules.tick(state, RseConfig.CROSSING_RELEASE_M, false, RseConfig))
        expectEqual(RseCrossingRules.tick(state, RseConfig.CROSSING_HIT_M, false, RseConfig), "passed")
    end)

    it("doesn't miss the train in a long frame", function()
        local state = {}
        expectNil(RseCrossingRules.tick(state, 300, true, RseConfig))
        expectEqual(RseCrossingRules.tick(state, 8700, true, RseConfig), "hit", "it went past between two looks")
    end)

    it("shows the time like a clock", function()
        expectEqual(RseCrossingRules.clock(185), "3:05")
        expectEqual(RseCrossingRules.clock(59.2), "1:00")
        expectEqual(RseCrossingRules.clock(-3), "0:00")
    end)

    it("has a call, with a vehicle held until a line is on it", function()
        local def = RseConfig.WRECKS.crossing
        expectTrue(def.held and def.crossing and #def.variants > 1)
        expectEqual(RseWreckRules.newState("held"), "held")
        expectEqual(RseProgressRules.wreck("held", false, 0, false, RseConfig), 0, "nothing done yet")
        local data = RseSaveCodec.normalize({ scene = { id = "crossing", x = 1, y = 2, z = 3, wreck = { kind = "crossing", state = "held", bales = {} },
            crossing = { index = "2", passed = "true" } } }, RseConfig)
        expectEqual(data.scene.crossing.index, 2)
        expectEqual(data.scene.crossing.passed, true)
        expectEqual(data.scene.wreck.state, "held")
        expectNil(RseSaveCodec.normalize({ scene = { id = "crossing", x = 1, y = 2, z = 3, wreck = { kind = "crossing", state = "held", bales = {} },
            crossing = { passed = true } } }, RseConfig).scene.crossing, "no crossing named")
    end)
end)
