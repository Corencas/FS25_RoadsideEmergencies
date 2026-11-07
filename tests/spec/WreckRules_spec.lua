describe("RseWreckRules", function()
    it("never picks a vehicle the farm couldn't recover", function()
        local fleet = { canPull = true, canPullHeavy = false }
        local function fits(_, variant)
            return RseWreckRules.canRecover(variant, fleet)
        end
        for _, kind in ipairs({ "crossing", "trailer", "livestock" }) do
            for roll = 0, 0.99, 0.01 do
                local variant = RseWreckRules.pickVariant(RseConfig.WRECKS[kind], roll, nil, fits)
                expectTrue(variant ~= nil and not variant.heavy, kind)
            end
        end
        expectNil(RseWreckRules.pickVariant(RseConfig.WRECKS.truck, 0.5, nil, fits), "the wrecked trucks are all big")
    end)

    it("spills no big bales for a farm with nothing to lift them", function()
        local fleet = { canLift = false }
        for roll = 0, 0.99, 0.01 do
            expectEqual(RseWreckRules.pickLoad(RseConfig.WRECKS.trailer, roll, RseConfig, fleet).id, "small")
        end
        local seen = {}
        for roll = 0, 0.99, 0.01 do
            seen[RseWreckRules.pickLoad(RseConfig.WRECKS.trailer, roll, RseConfig, { canLift = true }).id] = true
        end
        expectTrue(seen.small and seen.big, "with one, either")
    end)

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

    it("turns the front wheels toward a pull at the front, and leaves them straight for one at the rear", function()
        expectEqual(RseWreckRules.towSteer(0, 5, RseConfig), 0, "straight ahead")
        expectEqual(RseWreckRules.towSteer(5, 5, RseConfig), 1, "front, to one side")
        expectEqual(RseWreckRules.towSteer(-5, 5, RseConfig), -1, "front, to the other")
        expectEqual(RseWreckRules.towSteer(5, -5, RseConfig), 0, "rear: they are the far axle")
        expectEqual(RseWreckRules.towSteer(-5, -5, RseConfig), 0, "rear, the other side")
        local slight = RseWreckRules.towSteer(0.3, 5, RseConfig)
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
        local trailer, storm = RseConfig.WRECKS.trailer.variants[1], RseConfig.WRECKS.storm
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
            expectTrue(def ~= nil and #def.variants > 0 and type(def.pay) == "number", kind)
            for _, variant in ipairs(def.variants) do
                expectTrue(type(variant.file) == "string" and type(variant.length) == "number", variant.file)
            end
        end
        expectTrue(RseConfig.WRECKS.storm.noVehicle, "the storm has no vehicle")
    end)

    it("uses live animals the catalog knows, each with a livestock model", function()
        for _, kind in ipairs(RseConfig.WRECKS.livestock.kinds) do
            expectTrue(RseAnimalCatalog.get(kind).subType ~= nil, kind)
        end
    end)

    it("picks a vehicle the game has, and not the same one twice while there is another", function()
        local def = { variants = { { file = "a" }, { file = "b" }, { file = "c" } } }
        expectEqual(RseWreckRules.pickVariant(def, 0, nil).file, "a")
        expectEqual(RseWreckRules.pickVariant(def, 0.999, nil).file, "c")
        expectEqual(RseWreckRules.pickVariant(def, 0, "a").file, "b", "not the last one again")
        local onlyB = function(file)
            return file == "b"
        end
        expectEqual(RseWreckRules.pickVariant(def, 0.9, nil, onlyB).file, "b")
        expectEqual(RseWreckRules.pickVariant(def, 0.9, "b", onlyB).file, "b", "the last one if it is all there is")
        expectNil(RseWreckRules.pickVariant(def, 0.5, nil, function()
            return false
        end))
        expectNil(RseWreckRules.pickVariant(RseConfig.WRECKS.storm, 0.5), "a storm has no vehicle")
    end)

    it("brings back the vehicle a saved job had", function()
        local def = { variants = { { file = "a" }, { file = "b" } } }
        expectEqual(RseWreckRules.variantByFile(def, "b").file, "b")
        expectEqual(RseWreckRules.variantByFile(def, nil).file, "a", "a save from before there was a choice")
        expectEqual(RseWreckRules.variantByFile(def, "gone").file, "a", "a vehicle no longer on the list")
        expectNil(RseWreckRules.variantByFile(RseConfig.WRECKS.storm, nil))
    end)

    it("picks by weight, so bigger vehicles are rarer than smaller ones", function()
        local def = { variants = { { file = "small", weight = 3 }, { file = "big", weight = 1 } } }
        expectEqual(RseWreckRules.pickVariant(def, 0.74, nil).file, "small")
        expectEqual(RseWreckRules.pickVariant(def, 0.76, nil).file, "big")
        for _, kind in ipairs({ "truck", "tractor", "trailer", "livestock", "powerline" }) do
            local smallest, biggest = 0, math.huge
            for _, variant in ipairs(RseConfig.WRECKS[kind].variants) do
                smallest, biggest = math.max(smallest, variant.weight), math.min(biggest, variant.weight)
            end
            expectTrue(smallest > biggest, kind .. " has rarer vehicles")
        end
    end)

    it("knows which vehicles a pickup truck can't tow, and which call has which", function()
        for _, emergency in ipairs(RseConfig.EMERGENCIES) do
            if emergency.wreck ~= nil then
                expectTrue(RseConfig.WRECKS[emergency.wreck].variants ~= nil, emergency.id)
            end
        end
        local function heavyOf(kind, part)
            for _, variant in ipairs(RseConfig.WRECKS[kind].variants) do
                if string.find(variant.file, part, 1, true) ~= nil then
                    return variant.heavy == true
                end
            end
            error("no " .. part)
        end
        expectTrue(heavyOf("crossing", "multiPurposeTruck"), "Z towed the Dragon with a pickup, and couldn't")
        expectTrue(not heavyOf("crossing", "fabia"), "a small car")
        expectTrue(not heavyOf("powerline", "pickup2017"), "a pickup tows a pickup")
        expectTrue(heavyOf("tractor", "farmall120C"), "even the smallest tractor is over 3 t")
        expectTrue(heavyOf("livestock", "noahTTW140"), "very long")
    end)

    describe("towing like a trailer", function()
        local config = RseConfig
        it("stops towing the moment you back toward it, or it rides on the vehicle", function()
            local state = {}
            RseWreckRules.isTowing(state, 2000, { speed = 20, slack = 0 }, config)
            expectTrue(state.towing)
            expectTrue(not RseWreckRules.isTowing(state, 16, { speed = 5, slack = 0, pushing = true }, config), "a strap doesn't push")
            RseWreckRules.isTowing(state, 2000, { speed = 20, slack = 0 }, config)
            expectTrue(state.towing, "pull away again and it is towing again")
            expectTrue(not RseWreckRules.isTowing(state, 16, { speed = 20, slack = 0, carried = true }, config), "on a rollback")
        end)

        it("knows a wreck on the vehicle from one behind it", function()
            expectTrue(RseWreckRules.isCarried(0, -1, 8, 0, 2.5), "over the bed")
            expectTrue(not RseWreckRules.isCarried(0, -6, 8, 0, 2.5), "behind it")
            expectTrue(not RseWreckRules.isCarried(3, -1, 8, 0, 2.5), "beside it")
            expectTrue(not RseWreckRules.isCarried(0, 0, nil, 0, nil), "no size known")
        end)

        it("hangs the wreck on the vehicle's centre line, just past its end", function()
            local x, z, endZ = RseWreckRules.hitchPoint(0.5, -2, -1, 5, 0, 1.8, config)
            expectEqual(x, -0.5, "back to the middle, wherever the strap sits")
            expectEqual(endZ, -2.5 + 2, "the vehicle's end, seen from the strap's point")
            expectEqual(z, -2.5 - config.TOW_GAP + 2)
            local _, frontZ = RseWreckRules.hitchPoint(0, 2, 1, 5, 0, 1.8, config)
            expectEqual(frontZ, 2.5 + config.TOW_GAP - 2, "from its front as well")
            local _, loneZ, loneEnd = RseWreckRules.hitchPoint(0, -2, -1, nil, 0, 1.8, config)
            expectEqual(loneEnd, 0, "not on its main body: from the strap's point")
            expectEqual(loneZ, -config.TOW_GAP)
        end)

        it("keeps a wide wreck far enough back for its corners to clear", function()
            local _, z = RseWreckRules.hitchPoint(0, 0, -1, nil, 0, 3, config)
            expectEqual(z, -(1.5 + config.TOW_GAP_SIDE))
        end)

        it("moves the hinge bit by bit and stops there", function()
            local anchor = { x = 1, y = 0, z = -5 }
            expectTrue(RseWreckRules.moveAnchor(anchor, 1, -3, 0.5))
            expectEqual(anchor.z, -4.5)
            expectTrue(RseWreckRules.moveAnchor(anchor, 1, -3, 100))
            expectEqual(anchor.z, -3)
            expectEqual(RseWreckRules.moveAnchor(anchor, 1, -3, 1), false)
        end)

        it("reads how far the wreck has run up on the hinge", function()
            local travel = config.TOW_TRAVEL
            expectNear(RseWreckRules.hitchSlack(-3 - travel, -3, -1, config), 0, 1e-6, "pulling: at the far end of its travel")
            expectNear(RseWreckRules.hitchSlack(-3, -3, -1, config), travel, 1e-6, "in the middle")
            expectNear(RseWreckRules.hitchSlack(-3 + travel, -3, -1, config), 2 * travel, 1e-6, "run right up")
            expectNear(RseWreckRules.hitchSlack(3 + travel, 3, 1, config), 0, 1e-6, "from the front too")
        end)

        it("aims the front wheels from their own axle", function()
            local fromMiddle = RseWreckRules.towSteer(1, 4, config)
            local fromAxle = RseWreckRules.towSteer(1, 4, config, 1.4, 0.6)
            expectTrue(fromAxle > fromMiddle, "a sharper angle, the true one")
            expectEqual(RseWreckRules.towSteer(1, -4, config, 1.4, 0.6), 0, "towed by the rear, they stay straight")
        end)

        it("finds the axle a wreck follows on", function()
            local config2 = { TOW_AXLE_SPAN = 0.5 }
            local truck = RseWreckRules.axleLayout({ 2.6, 2.6, -2.2, -2.2, -3.6, -3.6 }, config2)
            expectEqual(truck.single, false)
            expectNear(RseWreckRules.farAxleZ(truck, 4), -2.9, 1e-9, "hooked at the front: between the two rear axles")
            expectNear(RseWreckRules.farAxleZ(truck, -4.4), 2.6, 1e-9, "hooked at the rear: the front axle")
            local trailer = RseWreckRules.axleLayout({ -1, -1, -1.2, -1.2 }, config2)
            expectEqual(trailer.single, true, "one group of wheels")
            expectNear(RseWreckRules.farAxleZ(trailer, 4), -1.1, 1e-9, "a single axle is the far axle from either end")
            expectNear(RseWreckRules.farAxleZ(trailer, -4), -1.1, 1e-9)
            expectEqual(RseWreckRules.farAxleZ(RseWreckRules.axleLayout({}, config2), 4), nil, "no wheels, nothing to go by")
        end)

        it("turns a towed wreck so that its far axle doesn't slide", function()
            local config2 = { TOW_FOLLOW_MIN_ARM = 1 }
            expectNear(RseWreckRules.followYaw(2, 4, -2.9, config2), 2 / 6.9, 1e-9, "the hinge going to +x turns +z toward +x")
            expectNear(RseWreckRules.followYaw(2, -4.4, 2.6, config2), -2 / 7, 1e-9, "hooked at the other end, the other way")
            expectEqual(RseWreckRules.followYaw(0, 4, -2.9, config2), 0, "going straight, none")
            expectEqual(RseWreckRules.followYaw(2, 0.5, 0, config2), nil, "an axle at the hook says nothing")
            expectEqual(RseWreckRules.followYaw(2, 4, nil, config2), nil, "nor no axle at all")
        end)

        it("follows about the hook, and takes the sideways speed off the hitch", function()
            local input = { yaw = 0.5, wantYaw = 0.1, vx = 1, vz = 5, armX = 0, armZ = 3, hookVX = 2.5, hookVZ = 5, hingeVX = 0.5, hingeVZ = 5,
                sideX = 2, sideZ = 0 }
            local yaw, vx, vz = RseWreckRules.follow(input, 0.5, 0)
            expectNear(yaw, 0.3, 1e-9, "half way to the yaw it should have")
            -- the hook's speed is v + yaw * arm sideways: turning about the hook leaves that where it was
            expectNear(vx + yaw * input.armZ, input.vx + input.yaw * input.armZ, 1e-9, "the hook doesn't jump")
            expectNear(vz, 5, 1e-9)
            yaw, vx, vz = RseWreckRules.follow(input, 0, 0.8)
            expectNear(yaw, 0.5, 1e-9, "no yaw share, no yaw change")
            expectNear(vx, 1 + (0.5 - 2.5) * 0.8, 1e-9, "most of the hook's speed against the hinge goes, and a side that isn't one unit long is no matter")
            expectNear(vz, 5, 1e-9, "and nothing along the pull: the wreck's weight still counts")
            input.wantYaw = nil
            yaw = RseWreckRules.follow(input, 1, 0)
            expectNear(yaw, 0.5, 1e-9, "nothing to go by: the yaw stays")
        end)

        it("stops following only if the engine's yaw keeps disagreeing with the wreck's speeds", function()
            local config2 = { TOW_YAW_CHECK_RATE = 0.05, TOW_YAW_CHECK_MS = 500 }
            local state = {}
            expectTrue(RseWreckRules.yawAgrees(state, 0.3, 0.3, 400, config2), "the same way")
            expectTrue(RseWreckRules.yawAgrees(state, 0.3, -0.3, 400, config2), "opposite, but not for long")
            expectTrue(RseWreckRules.yawAgrees(state, 0.3, 0.3, 400, config2), "and that wipes it")
            expectTrue(RseWreckRules.yawAgrees(state, 0.01, -0.3, 900, config2), "too small to tell")
            expectTrue(RseWreckRules.yawAgrees(state, 0.3, -0.3, 400, config2))
            expectTrue(not RseWreckRules.yawAgrees(state, 0.3, -0.3, 400, config2), "opposite for long enough")
        end)

        it("keeps the same feel at any frame rate", function()
            local share = 0.1
            expectNear(RseWreckRules.frameShare(share, config.TOW_FRAME_MS, config), share, 1e-9, "one frame of the size it is meant for")
            local twoShort = 1 - (1 - RseWreckRules.frameShare(share, config.TOW_FRAME_MS / 2, config)) ^ 2
            expectNear(twoShort, share, 1e-9, "two half frames come to the same")
            expectTrue(RseWreckRules.frameShare(share, config.TOW_FRAME_MS * 2, config) > share, "a long frame does more")
            expectNear(RseWreckRules.frameShare(share, nil, config), share, 1e-9, "no time known: one frame")
            expectEqual(RseWreckRules.frameShare(share, 0, config), 0, "no time, nothing")
        end)

        it("frees the wheels at the end being pulled, and only those", function()
            expectTrue(RseWreckRules.isNearAxle(1.3, 4, 0), "front wheels, front tow")
            expectTrue(not RseWreckRules.isNearAxle(-1.3, 4, 0), "rear wheels, front tow")
            expectTrue(RseWreckRules.isNearAxle(-1.3, -4, 0), "rear wheels, rear tow")
            expectTrue(not RseWreckRules.isNearAxle(1.3, -4, 0), "front wheels, rear tow")
        end)
    end)
end)
