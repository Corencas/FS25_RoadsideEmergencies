describe("RsePanelRules", function()
    local function keys(steps)
        local list = {}
        for _, step in ipairs(steps) do
            table.insert(list, step.key .. ":" .. step.state)
        end
        return table.concat(list, " ")
    end

    it("lists an animal call: reach the scene, then the animals in the road", function()
        local steps = RsePanelRules.steps({ arrived = false, animals = { left = 2, total = 2 } })
        expectEqual(keys(steps), "rse_panel_reach:now rse_panel_animals:todo")
        steps = RsePanelRules.steps({ arrived = true, animals = { left = 1, total = 2 } })
        expectEqual(keys(steps), "rse_panel_reach:done rse_panel_animals:now")
        expectEqual(steps[2].count, 1, "how many are left")
    end)

    it("lists a rollover: the driver, then upright, then the recovery point, ticked off as the wreck's state moves on", function()
        local wreck = { state = "locked", tipped = true, driver = true }
        local facts = { arrived = true, wreck = wreck, pointDistance = 3100 }
        expectEqual(keys(RsePanelRules.steps(facts)), "rse_panel_reach:done rse_panel_driver:now rse_panel_upright:todo rse_panel_deliver:todo")
        wreck.state = "tipped"
        expectEqual(keys(RsePanelRules.steps(facts)), "rse_panel_reach:done rse_panel_driver:done rse_panel_upright:now rse_panel_deliver:todo")
        wreck.state = "ready"
        local steps = RsePanelRules.steps(facts)
        expectEqual(keys(steps), "rse_panel_reach:done rse_panel_driver:done rse_panel_upright:done rse_panel_deliver:now")
        expectEqual(steps[4].distance, 3100, "the way to the recovery point")
        expectTrue(RsePanelRules.goesToPoint(RsePanelRules.current(steps)), "the marker leads to the point")
        wreck.delivered = true
        expectNil(RsePanelRules.current(RsePanelRules.steps(facts)), "all done")
    end)

    it("lists a power line: the power, the driver, the wires, the car, and last the pole, which is optional (Z)", function()
        local facts = { arrived = true, wreck = { state = "locked", driver = true, what = "car" },
            line = { powerOff = false, secondsLeft = 70, wiresLeft = 3, poleIn = false, polePay = 1200 } }
        local steps = RsePanelRules.steps(facts)
        expectEqual(keys(steps), "rse_panel_reach:done rse_panel_power:now rse_panel_driver:todo rse_panel_wires:todo "
            .. "rse_panel_deliverCar:todo rse_panel_pole:optional")
        expectEqual(steps[6].extraPay, 1200, "what the pole adds")
        local clock = RsePanelRules.clock(facts, RseConfig)
        expectEqual(clock.key, "rse_panel_clockPower")
        expectEqual(clock.urgent, false, "waiting for the crew is no hurry")
        facts.line.powerOff, facts.line.wiresLeft, facts.wreck.state, facts.wreck.delivered = true, 0, "ready", true
        expectNil(RsePanelRules.current(RsePanelRules.steps(facts)), "all but the pole done: nothing is \"now\"")
        facts.line.poleIn = true
        expectEqual(RsePanelRules.steps(facts)[6].state, "done", "the pole in: ticked off")
    end)

    it("lists a tree on a car: the log, the driver, the logs, the car", function()
        local facts = { arrived = true, wreck = { state = "locked", driver = true, what = "car" }, tree = { doorFree = true, rescueLeftMs = 200000 },
            logs = { left = 3 } }
        expectEqual(keys(RsePanelRules.steps(facts)), "rse_panel_reach:done rse_panel_treeLog:done rse_panel_driver:now rse_panel_logs:todo "
            .. "rse_panel_deliverCar:todo")
        expectEqual(RsePanelRules.clock(facts, RseConfig).key, "rse_panel_clockRescue")
    end)

    it("lists the jobs with nothing to recover by what is left of them", function()
        expectEqual(keys(RsePanelRules.steps({ arrived = true, flock = { left = 12 } })), "rse_panel_reach:done rse_panel_flock:now")
        expectEqual(keys(RsePanelRules.steps({ arrived = true, logs = { left = 0 } })), "rse_panel_reach:done rse_panel_logs:done")
        expectEqual(keys(RsePanelRules.steps({ arrived = true, bales = { left = 4, total = 6 } })), "rse_panel_reach:done rse_panel_bales:now")
    end)

    it("puts the train first, and turns it urgent near the end", function()
        local facts = { arrived = false, expireLeftMs = 600000, wreck = { state = "held" }, crossing = { seconds = 95, clear = false } }
        expectEqual(keys(RsePanelRules.steps(facts)), "rse_panel_reach:now rse_panel_tracks:todo rse_panel_deliver:todo")
        local clock = RsePanelRules.clock(facts, RseConfig)
        expectEqual(clock.key, "rse_panel_clockTrain")
        expectEqual(clock.urgent, false)
        facts.crossing.seconds = RseConfig.CROSSING_CLOCK_URGENT
        expectEqual(RsePanelRules.clock(facts, RseConfig).urgent, true)
        facts.crossing.clear = true
        expectEqual(RsePanelRules.clock(facts, RseConfig).key, "rse_panel_clockArrive", "off the tracks: the train no longer counts")
    end)

    it("shows the time to get there until you arrive, urgent in the last two minutes", function()
        local facts = { arrived = false, expireLeftMs = 121000, animals = { left = 1, total = 1 } }
        expectEqual(RsePanelRules.clock(facts, RseConfig).urgent, false)
        facts.expireLeftMs = RseConfig.PANEL_URGENT_SECONDS * 1000
        expectEqual(RsePanelRules.clock(facts, RseConfig).urgent, true)
        facts.arrived = true
        expectNil(RsePanelRules.clock(facts, RseConfig), "once there, no clock")
    end)

    it("shows the rest of a two-part job going to another contractor", function()
        local clock = RsePanelRules.clock({ arrived = true, handoverLeftMs = 90000 }, RseConfig)
        expectEqual(clock.key, "rse_panel_clockHandover")
        expectEqual(clock.urgent, true)
    end)

    it("writes clocks as people read them", function()
        expectEqual(RsePanelRules.clockText(0), "0:00")
        expectEqual(RsePanelRules.clockText(4.2), "0:05", "rounds up")
        expectEqual(RsePanelRules.clockText(245), "4:05")
        expectEqual(RsePanelRules.clockText(3723), "1:02:03")
    end)

    it("turns the arrow toward the target, right of ahead positive", function()
        -- looking along +z, with +x on the right
        expectNear(RsePanelRules.bearing(0, 1, 1, 0, 0, 10), 0, 1e-9, "straight ahead")
        expectNear(RsePanelRules.bearing(0, 1, 1, 0, 10, 0), math.pi / 2, 1e-9, "to the right")
        expectNear(RsePanelRules.bearing(0, 1, 1, 0, -10, 0), -math.pi / 2, 1e-9, "to the left")
        expectNear(math.abs(RsePanelRules.bearing(0, 1, 1, 0, 0, -10)), math.pi, 1e-9, "behind")
        expectNil(RsePanelRules.bearing(0, 1, 1, 0, 0, 0), "right here")
    end)
end)
