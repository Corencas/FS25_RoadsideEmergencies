describe("RseWreckRules", function()
    local function largest(_, b)
        return b
    end

    it("goes from locked to ready, or to tipped first for one on its side", function()
        expectEqual(RseWreckRules.newState(nil), "locked")
        expectEqual(RseWreckRules.afterPrepare("locked", { tipped = false }), "ready")
        expectEqual(RseWreckRules.afterPrepare("locked", { tipped = true }), "tipped")
        expectEqual(RseWreckRules.afterPrepare("ready", { tipped = true }), "ready", "only once")
    end)

    it("keeps the state of a saved wreck, and locks anything it doesn't know", function()
        expectEqual(RseWreckRules.newState("tipped"), "tipped")
        expectEqual(RseWreckRules.newState("ready"), "ready")
        expectEqual(RseWreckRules.newState("nonsense"), "locked")
    end)

    it("knows when it stands on its wheels", function()
        expectTrue(RseWreckRules.isUpright(0.95, RseConfig))
        expectTrue(not RseWreckRules.isUpright(0.1, RseConfig), "on its side")
        expectTrue(not RseWreckRules.isUpright(-1, RseConfig), "on its roof")
        expectTrue(not RseWreckRules.isUpright(nil, RseConfig))
    end)

    it("turns the wheels toward the pull from either end, except when really towing by the rear", function()
        expectEqual(RseWreckRules.towSteer(0, 5, false, RseConfig), 0, "straight ahead")
        expectEqual(RseWreckRules.towSteer(5, 5, false, RseConfig), 1, "front, to one side")
        expectEqual(RseWreckRules.towSteer(-5, 5, false, RseConfig), -1, "front, to the other")
        expectEqual(RseWreckRules.towSteer(5, -5, false, RseConfig), 1, "rear, as when you back up")
        expectEqual(RseWreckRules.towSteer(-5, -5, false, RseConfig), -1, "rear, to the other side")
        expectEqual(RseWreckRules.towSteer(5, 5, true, RseConfig), 1, "towing by the front")
        expectEqual(RseWreckRules.towSteer(5, -5, true, RseConfig), 0, "towing by the rear")
        local slight = RseWreckRules.towSteer(0.3, 5, false, RseConfig)
        expectTrue(slight > 0 and slight < 1, "a small angle, a small turn")
    end)

    it("lets a trailer's wheels lie along the line while you reel, from either end", function()
        expectEqual(RseWreckRules.freeWheelAngle(3, 3, false, RseConfig), 0, "not reeling: straight")
        expectEqual(RseWreckRules.freeWheelAngle(0, 5, true, RseConfig), 0, "pulled straight ahead")
        expectEqual(RseWreckRules.freeWheelAngle(0, -5, true, RseConfig), 0, "pulled straight back")
        local ahead = RseWreckRules.freeWheelAngle(1, 4, true, RseConfig)
        expectTrue(ahead > 0.24 and ahead < 0.25, "ahead and to one side: along the line")
        local behind = RseWreckRules.freeWheelAngle(1, -4, true, RseConfig)
        expectTrue(behind < -0.24 and behind > -0.25, "behind and to the same side: the same line, the other way")
        expectEqual(RseWreckRules.freeWheelAngle(5, 0, true, RseConfig), RseConfig.TOW_WHEEL_SWING, "from the side: no further than this")
        expectEqual(RseWreckRules.freeWheelAngle(-5, 0, true, RseConfig), -RseConfig.TOW_WHEEL_SWING)
    end)

    it("pays more per bale when the bales are all you bring in", function()
        local load = { pay = 45, payAlone = 75 }
        expectEqual(RseWreckRules.balePay(load, true), 45, "with the trailer")
        expectEqual(RseWreckRules.balePay(load, false), 75, "alone")
        expectEqual(RseWreckRules.balePay({ pay = 45 }, false), 45, "a load with one price")
        expectEqual(RseWreckRules.balePay(nil, false), 0)
        local trailer, storm = RseConfig.WRECKS.trailer, RseConfig.WRECKS.storm
        expectEqual(RseWreckRules.reward(trailer, 2, load, 0), trailer.pay + 90, "a trailer job counts on the trailer")
        expectEqual(RseWreckRules.reward(storm, 2, load, 0), storm.pay + 150, "a storm job has none")
        expectEqual(RseWreckRules.partialReward(load, 2), 150, "handed over on a storm job")
    end)

    it("spills no more big bales off a trailer than it can carry, and doesn't limit a storm", function()
        local big
        for _, load in ipairs(RseConfig.WRECK_LOADS) do
            if load.id == "big" then
                big = load
            end
        end
        local trailer, storm = RseConfig.WRECKS.trailer, RseConfig.WRECKS.storm
        expectEqual(RseWreckRules.baleCount(big, largest, "large", trailer), trailer.loadLimit.big)
        expectEqual(RseWreckRules.baleCount(big, largest, "small", trailer), big.count.min)
        expectEqual(RseWreckRules.baleCount(big, largest, "large", storm), big.count.max)
        for _, load in ipairs(RseConfig.WRECK_LOADS) do
            if load.id ~= "big" then
                expectEqual(RseWreckRules.baleCount(load, largest, "large", trailer), load.count.max, "small bales fit")
            end
        end
    end)

    it("scales the bales of a spilled load with the job size", function()
        for _, load in ipairs(RseConfig.WRECK_LOADS) do
            expectEqual(RseWreckRules.baleCount(load, largest, "small"), load.count.min)
            expectEqual(RseWreckRules.baleCount(load, largest, "large"), load.count.max)
        end
        expectEqual(RseWreckRules.baleCount(nil, largest, "large"), 0, "a truck spills nothing")
    end)

    it("picks a load only for a job that spills one", function()
        local def = RseConfig.WRECKS.trailer
        expectEqual(RseWreckRules.pickLoad(def, 0, RseConfig).id, "small", "most calls are small bales")
        expectEqual(RseWreckRules.pickLoad(def, 0.99, RseConfig).id, "big")
        expectEqual(RseWreckRules.pickLoad(RseConfig.WRECKS.truck, 0, RseConfig), nil)
    end)

    it("finds a saved load, and gives an old save the big one", function()
        local def = RseConfig.WRECKS.storm
        expectEqual(RseWreckRules.loadById(def, "small", RseConfig).id, "small")
        expectEqual(RseWreckRules.loadById(def, nil, RseConfig).id, "big")
        expectEqual(RseWreckRules.loadById(RseConfig.WRECKS.truck, "small", RseConfig), nil)
    end)

    it("pays by the job, the haul and the bale", function()
        expectEqual(RseWreckRules.reward({ pay = 1800 }, 0), 1800)
        expectEqual(RseWreckRules.reward({ pay = 1800 }, 0, nil, 400), 2200)
        expectEqual(RseWreckRules.reward({ pay = 1500 }, 7, { pay = 60 }), 1920)
    end)

    it("pays the haul by distance, only for a vehicle", function()
        expectEqual(RseWreckRules.haulPay({ pay = 1 }, 1500, { WRECK_PAY_PER_KM = 500 }), 750)
        expectEqual(RseWreckRules.haulPay({ noVehicle = true }, 1500, { WRECK_PAY_PER_KM = 500 }), 0)
        expectEqual(RseWreckRules.haulPay({ pay = 1 }, nil, { WRECK_PAY_PER_KM = 500 }), 0)
    end)

    it("pays for the bales that came in when the rest is handed over", function()
        expectEqual(RseWreckRules.partialReward({ pay = 45 }, 3), 135)
        expectEqual(RseWreckRules.partialReward(nil, 3), 0)
    end)

    describe("a wreck on a strap", function()
        local config = { TOW_SLACK_FREE = 0.05, TOW_SLACK_FULL = 0.45, TOW_CLOSING = 0.1, TOW_START_SPEED = 5, TOW_START_MS = 2000, TOW_END_MS = 5000 }

        it("isn't towing just because it is hooked up", function()
            local state = {}
            expectTrue(not RseWreckRules.isTowing(state, 60000, { speed = 0, slack = 0 }, config), "parked, however long")
        end)

        it("tows once the vehicle is driven with the strap tight for a while", function()
            local state = {}
            expectTrue(not RseWreckRules.isTowing(state, 1000, { speed = 20, slack = 0 }, config), "not yet")
            expectTrue(RseWreckRules.isTowing(state, 1000, { speed = 20, slack = 0 }, config))
        end)

        it("doesn't count driving on a slack strap", function()
            local state = {}
            RseWreckRules.isTowing(state, 1500, { speed = 20, slack = 0 }, config)
            RseWreckRules.isTowing(state, 100, { speed = 20, slack = 1 }, config)
            expectTrue(not RseWreckRules.isTowing(state, 1500, { speed = 20, slack = 0 }, config), "the clock started again")
        end)

        it("keeps towing through a short stop, and stops after a long one", function()
            local state = {}
            RseWreckRules.isTowing(state, 2000, { speed = 20, slack = 0 }, config)
            expectTrue(RseWreckRules.isTowing(state, 4000, { speed = 0, slack = 0.3 }, config), "a short stop")
            expectTrue(not RseWreckRules.isTowing(state, 1000, { speed = 0, slack = 0.3 }, config), "a long one")
        end)

        it("stops towing the moment you reel by hand", function()
            local state = {}
            RseWreckRules.isTowing(state, 2000, { speed = 20, slack = 0 }, config)
            expectTrue(not RseWreckRules.isTowing(state, 16, { speed = 20, slack = 0, reeling = true }, config))
        end)

        it("rolls free while the strap is tight", function()
            expectEqual(RseWreckRules.towBrake(0, 0, config), 0)
            expectEqual(RseWreckRules.towBrake(-0.1, 2, config), 0, "tight, however fast")
        end)

        it("brakes at once when it is coming up on the vehicle in front", function()
            expectEqual(RseWreckRules.towBrake(0.1, 1, config), 1)
        end)

        it("holds harder the more slack there is, at a standstill", function()
            expectEqual(RseWreckRules.towBrake(0.25, 0, config), 0.5)
            expectEqual(RseWreckRules.towBrake(2, 0, config), 1)
        end)
    end)

    describe("a crash with two parts", function()
        local def = { pay = 1500, payPerSurvivor = 75, bothBonus = 0.25 }

        it("pays the trailer alone", function()
            local pay, bonus = RseWreckRules.crashReward(def, { trailer = true, kinds = {}, led = 0 }, RseConfig)
            expectEqual(pay, 1500)
            expectEqual(bonus, 0)
        end)

        it("pays the animals alone: the dead as on a call, and each live one loaded", function()
            local pay, bonus = RseWreckRules.crashReward(def, { animals = true, kinds = { "sheep" }, roadsideKinds = {}, led = 2 }, RseConfig)
            expectEqual(pay, RsePayRules.callReward({ "sheep" }, {}, RseConfig) + 150)
            expectEqual(bonus, 0)
        end)

        it("pays both, with the bonus on top", function()
            local animals = RsePayRules.callReward({ "sheep" }, {}, RseConfig) + 150
            local pay, bonus = RseWreckRules.crashReward(def, { trailer = true, animals = true, kinds = { "sheep" }, roadsideKinds = {}, led = 2 }, RseConfig)
            expectEqual(bonus, math.floor((1500 + animals) * 0.25 + 0.5))
            expectEqual(pay, 1500 + animals + bonus)
        end)

        it("pays bales as a part, with the bonus for both", function()
            local bales = { pay = 1500, bothBonus = 0.25 }
            expectEqual((RseWreckRules.crashReward(bales, { bales = 4, payPerBale = 60 }, RseConfig)), 240, "the bales alone")
            expectEqual((RseWreckRules.crashReward(bales, { trailer = true, payPerBale = 60 }, RseConfig)), 1500, "the trailer alone")
            local pay, bonus = RseWreckRules.crashReward(bales, { trailer = true, animals = true, bales = 4, payPerBale = 60 }, RseConfig)
            expectEqual(bonus, 435)
            expectEqual(pay, 2175)
        end)

        it("pays the haul with the trailer, not without it", function()
            local bales = { pay = 1500, bothBonus = 0.25 }
            expectEqual((RseWreckRules.crashReward(bales, { trailer = true, haulPay = 500 }, RseConfig)), 2000)
            expectEqual((RseWreckRules.crashReward(bales, { bales = 2, payPerBale = 60, haulPay = 500 }, RseConfig)), 120)
        end)

        it("gives no bonus while some animals are still out", function()
            local _, bonus = RseWreckRules.crashReward(def, { trailer = true, animals = false, kinds = { "sheep" }, roadsideKinds = {}, led = 1 }, RseConfig)
            expectEqual(bonus, 0)
        end)

        local config = { CRASH_HANDOVER_MS = 1000, CRASH_HANDOVER_WARN_MS = 200 }

        it("waits while nothing is done, however long it takes", function()
            expectNil(RseWreckRules.tickHandover({}, 1000000, {}, config))
        end)

        it("finishes at once when both are done", function()
            expectEqual(RseWreckRules.tickHandover({}, 1, { trailer = true, animals = true }, config), "finish")
        end)

        it("says so when one part is done, warns, then hands the rest over", function()
            local state = {}
            expectEqual(RseWreckRules.tickHandover(state, 1, { trailer = true }, config), "partDone")
            expectNil(RseWreckRules.tickHandover(state, 700, { trailer = true }, config))
            expectEqual(RseWreckRules.tickHandover(state, 100, { trailer = true }, config), "warn")
            expectNil(RseWreckRules.tickHandover(state, 100, { trailer = true }, config), "only once")
            expectEqual(RseWreckRules.tickHandover(state, 100, { trailer = true }, config), "handover")
        end)

        it("gives you more time while you are getting on with it", function()
            local state = {}
            RseWreckRules.tickHandover(state, 1, { animals = true }, config)
            RseWreckRules.tickHandover(state, 900, { animals = true }, config)
            expectNil(RseWreckRules.tickHandover(state, 1, { animals = true, progress = true }, config))
            expectNil(RseWreckRules.tickHandover(state, 700, { animals = true }, config))
        end)

        it("lets you hand the rest over yourself at any moment", function()
            expectEqual(RseWreckRules.tickHandover({}, 1, { now = true }, config), "handover", "nothing done: a wreck stuck in water")
            local state = {}
            RseWreckRules.tickHandover(state, 1, { trailer = true }, config)
            expectEqual(RseWreckRules.tickHandover(state, 1, { trailer = true, now = true }, config), "handover")
        end)
    end)

    it("has a model for every wreck, and pay", function()
        for _, kind in ipairs({ "truck", "tractor", "trailer", "livestock" }) do
            local def = RseConfig.WRECKS[kind]
            expectTrue(def ~= nil and type(def.file) == "string" and type(def.pay) == "number", kind)
        end
        expectTrue(RseConfig.WRECKS.storm.noVehicle, "the storm has no vehicle")
    end)

    it("uses live animals the catalog knows, each with a livestock model", function()
        for _, kind in ipairs(RseConfig.WRECKS.livestock.kinds) do
            expectTrue(RseAnimalCatalog.get(kind).subType ~= nil, kind)
        end
    end)
end)
