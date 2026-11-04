describe("RseLineRules", function()
    local def = RseConfig.WRECKS.powerline

    it("pays for the pole and each wire, whatever is done of them", function()
        expectEqual(RseLineRules.pay(def, false, 0), 0)
        expectEqual(RseLineRules.pay(def, true, 0), def.polePay)
        expectEqual(RseLineRules.pay(def, false, 2), def.wirePay * 2)
        expectEqual(RseLineRules.pay(def, true, 3), def.polePay + def.wirePay * 3)
    end)

    it("is part of the crash pay, with the bonus only for both parts", function()
        local pay, bonus = RseWreckRules.crashReward(def, { trailer = true, animals = true, haulPay = 0, linePay = RseLineRules.pay(def, true, 3) }, RseConfig)
        local subtotal = def.pay + def.polePay + def.wirePay * 3
        expectEqual(bonus, math.floor(subtotal * def.bothBonus + 0.5))
        expectEqual(pay, subtotal + bonus)
        expectEqual((RseWreckRules.crashReward(def, { linePay = def.wirePay }, RseConfig)), def.wirePay, "one wire, nothing else")
        expectEqual((RseWreckRules.crashReward(def, { trailer = true, haulPay = 100 }, RseConfig)), def.pay + 100, "the car alone")
    end)

    it("says how long the crew still needs, in whole seconds and never none", function()
        local config = { LINE_POWER_CUT_MS = 90000 }
        expectEqual(RseLineRules.secondsLeft({}, config), 90, "the clock hasn't started")
        expectEqual(RseLineRules.secondsLeft({ liveMs = 45500 }, config), 45)
        expectEqual(RseLineRules.secondsLeft({ liveMs = 89990 }, config), 1)
        expectEqual(RseLineRules.secondsLeft({ liveMs = 95000 }, config), 1)
    end)

    describe("when the pole counts as brought in", function()
        it("when nothing of it is left", function()
            expectTrue(RseLineRules.poleIsIn({ hadPole = true, pieces = {} }))
        end)

        it("not while a piece is still there", function()
            expectEqual(RseLineRules.poleIsIn({ hadPole = true, pieces = { {} } }), false)
        end)

        it("not while a saved pole is being looked for, or a lost piece, or a new pole is on its way", function()
            expectEqual(RseLineRules.poleIsIn({ hadPole = true, pieces = {}, searchMs = 100 }), false)
            expectEqual(RseLineRules.poleIsIn({ hadPole = true, pieces = {}, lostMs = 100 }), false)
            expectEqual(RseLineRules.poleIsIn({ hadPole = true, pieces = {}, pending = {} }), false)
        end)

        it("not before there has been a pole, and only once", function()
            expectEqual(RseLineRules.poleIsIn({ pieces = {} }), false)
            expectEqual(RseLineRules.poleIsIn({ hadPole = true, poleIn = true, pieces = {} }), false)
        end)
    end)

    describe("where a saved job's pole belongs", function()
        it("where it was asked for", function()
            local spot = RseLineRules.savedPoleSpot({ poleX = 5, poleZ = 6, poleDirX = 0, poleDirZ = 1, pieces = { { x = 50, z = 60 } } }, 1, 2)
            expectEqual(spot.x, 5)
            expectEqual(spot.z, 6)
            expectEqual(spot.dirZ, 1)
        end)

        it("in an older save, where its first piece lay, or else at the scene", function()
            local spot = RseLineRules.savedPoleSpot({ yaw = 0, pieces = { { x = 50, z = 60 } } }, 1, 2)
            expectEqual(spot.x, 50)
            expectEqual(spot.z, 60)
            expectEqual(spot.dirX, 1, "across the road")
            local empty = RseLineRules.savedPoleSpot({ pieces = {} }, 1, 2)
            expectEqual(empty.x, 1)
            expectEqual(empty.z, 2)
        end)
    end)

    it("cuts the pay only after staying too long near live wires", function()
        expectEqual(RseLineRules.afterPenalty(1000, {}, RseConfig), 1000)
        expectEqual(RseLineRules.afterPenalty(1000, { penalized = true }, RseConfig), math.floor(1000 * (1 - RseConfig.LINE_DANGER_CUT) + 0.5))
    end)

    it("winds a wire into loops that lie on top of each other, each a little smaller", function()
        local dx, dy, dz = RseLineRules.coilPoint(0, RseConfig)
        expectEqual(dx, 0)
        expectEqual(dy, 0)
        expectEqual(dz, RseConfig.LINE_COIL_RADIUS, "it starts at the edge")
        local _, higher, far = RseLineRules.coilPoint(RseConfig.LINE_COIL_POINTS, RseConfig)
        expectEqual(higher, RseConfig.LINE_COIL_RISE, "one loop up")
        expectTrue(math.abs(far - (RseConfig.LINE_COIL_RADIUS - RseConfig.LINE_COIL_STEP)) < 1e-6, "and a little smaller")
        expectTrue(RseConfig.LINE_COIL_RADIUS - RseConfig.LINE_COIL_RINGS * RseConfig.LINE_COIL_STEP > 0, "loops never close up")
    end)

    describe("the clock on the live wires", function()
        local config = { LINE_POWER_CUT_MS = 10000, LINE_DANGER_GRACE_MS = 3000 }

        it("cuts the power in the end, wherever you are", function()
            local state = {}
            expectEqual(RseLineRules.tickPower(state, 9000, false, config), nil)
            expectEqual(RseLineRules.tickPower(state, 1000, false, config), "off")
            expectTrue(state.powerOff)
            expectEqual(RseLineRules.tickPower(state, 1000, true, config), nil, "nothing happens once it is off")
        end)

        it("warns once, then cuts the pay, counting all the time spent inside", function()
            local state = {}
            expectEqual(RseLineRules.tickPower(state, 100, true, config), "warn")
            expectEqual(RseLineRules.tickPower(state, 1400, true, config), nil)
            expectEqual(RseLineRules.tickPower(state, 100, false, config), nil, "stepped out")
            expectEqual(RseLineRules.tickPower(state, 1500, true, config), "cut", "back in")
            expectTrue(state.penalized)
            expectEqual(RseLineRules.tickPower(state, 100, true, config), nil, "only once")
        end)

        it("doesn't warn someone who stays out", function()
            local state = {}
            RseLineRules.tickPower(state, 5000, false, config)
            expectTrue(not state.warned)
            expectTrue(not state.penalized)
        end)
    end)

    describe("the layout", function()
        it("puts the poles on the side away from the lanes", function()
            -- a road along +x; a second lane on the +z side
            local segments = { { -50, 0, 50, 0 }, { -50, 4, 50, 4 } }
            local side = RseLineRules.roadside(0, 0, 1, 0, segments, RseConfig)
            local layout = RseLineRules.layout(0, 0, 1, 0, side, 2, RseConfig)
            expectTrue(layout.standing[1].z < 0, "away from the other lane")
            expectTrue(layout.standing[2].z < 0)
        end)

        it("lays the pole from its foot at the roadside across the lane, and has one wire per job size", function()
            local layout = RseLineRules.layout(0, 0, 1, 0, 1, 3, RseConfig)
            local pole = layout.pole
            local endZ = pole.z + pole.dirZ * RseConfig.LINE_POLE_LENGTH
            expectTrue(math.abs(pole.z) > 3, "its foot is off the lane")
            expectTrue(pole.z * endZ < 0, "it reaches across the lane")
            expectEqual(#layout.wires, 3)
            expectTrue(math.abs(pole.dirX * pole.dirX + pole.dirZ * pole.dirZ - 1) < 1e-6, "a unit direction")
        end)

        it("hangs each wire from a pole that exists, whatever the count", function()
            local layout = RseLineRules.layout(0, 0, 0, 1, -1, 8, RseConfig)
            expectEqual(#layout.wires, 8)
            for _, wire in ipairs(layout.wires) do
                expectTrue(layout.standing[wire.pole] ~= nil)
            end
        end)
    end)
end)
