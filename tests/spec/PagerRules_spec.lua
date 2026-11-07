describe("RsePagerRules", function()
    it("names the way on the map: north is up (-z), east is +x", function()
        expectEqual(RsePagerRules.compass(0, -100), "n")
        expectEqual(RsePagerRules.compass(100, 0), "e")
        expectEqual(RsePagerRules.compass(0, 100), "s")
        expectEqual(RsePagerRules.compass(-100, 0), "w")
        expectEqual(RsePagerRules.compass(70, -70), "ne")
        expectEqual(RsePagerRules.compass(-70, 70), "sw")
        expectNil(RsePagerRules.compass(0, 0), "right here")
    end)

    it("names a vehicle of yours that can do it: the heaviest for a big wreck, the lightest that will do otherwise", function()
        local machines = {
            { name = "Lizard Pickup", motorized = true, mass = 2.4 },
            { name = "Fendt 942", motorized = true, mass = 11 },
            { name = "International CV Rollback", motorized = true, mass = 6 },
            { name = "Quad", motorized = true, mass = 0.4 },
            { name = "Bale Grab", lifts = true, mass = 0.3 },
            { name = "Cattle Trailer", livestockTrailer = true, mass = 2 }
        }
        expectEqual(RsePagerRules.bestMachine(machines, "heavy", RseConfig), "Fendt 942")
        expectEqual(RsePagerRules.bestMachine(machines, "pull", RseConfig), "Lizard Pickup", "not the quad: too light to pull")
        expectEqual(RsePagerRules.bestMachine(machines, "lift", RseConfig), "Bale Grab")
        expectEqual(RsePagerRules.bestMachine(machines, "livestock", RseConfig), "Cattle Trailer")
        expectNil(RsePagerRules.bestMachine(machines, "carry", RseConfig), "nothing carries")
        expectNil(RsePagerRules.bestMachine({}, "pull", RseConfig))
    end)

    it("reckons the pay as the pack will: the economy difficulty, or what the pack said last time", function()
        expectNear(RsePagerRules.payRatio(1, nil), 1.2, 1e-9, "easy: 1.2 (Z's game paid $720 for a $600 deer)")
        expectNear(RsePagerRules.payRatio(3, nil), 1.0, 1e-9)
        expectNear(RsePagerRules.payRatio(1, 1.15), 1.15, 1e-9, "what the pack said wins")
        expectEqual(RsePagerRules.payRatio(nil, nil), 1)
    end)

    it("rounds an amount it can only guess", function()
        expectEqual(RsePagerRules.about(723, RseConfig), math.floor(723 / RseConfig.PAGER_PAY_STEP + 0.5) * RseConfig.PAGER_PAY_STEP)
        expectEqual(RsePagerRules.about(1, RseConfig), RseConfig.PAGER_PAY_STEP, "never nothing")
    end)

    it("puts each field on its own line under what happened, and leaves out empty ones", function()
        expectEqual(RsePagerRules.compose("A deer.", { "Where: north", "", "Pay: $700" }), "A deer.\n\nWhere: north\nPay: $700")
        expectEqual(RsePagerRules.compose("A deer.", {}), "A deer.")
    end)
end)
