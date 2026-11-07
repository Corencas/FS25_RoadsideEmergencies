describe("RseLeftBehindRule", function()
    local config = { LEFT_COLLECT_MS = 1000, LEFT_WARN_AFTER_MS = 100, LEFT_REMINDERS_MS = { 400, 200 } }

    it("warns, reminds at each time before the end, then collects", function()
        local state = { leftMs = 0 }
        expectNil(RseLeftBehindRule.tick(state, 50, {}, config))
        expectEqual(RseLeftBehindRule.tick(state, 50, {}, config), "warn", "the first warning")
        expectNil(RseLeftBehindRule.tick(state, 100, {}, config), "only once")
        expectEqual(RseLeftBehindRule.tick(state, 400, {}, config), "warn", "the first reminder")
        expectNil(RseLeftBehindRule.tick(state, 100, {}, config))
        expectEqual(RseLeftBehindRule.tick(state, 100, {}, config), "warn", "the last reminder")
        expectNil(RseLeftBehindRule.tick(state, 100, {}, config))
        expectEqual(RseLeftBehindRule.tick(state, 100, {}, config), "collect")
    end)

    it("stops the clock while someone is near", function()
        local state = { leftMs = 900 }
        expectNil(RseLeftBehindRule.tick(state, 500, { playerNear = true }, config))
        expectEqual(state.leftMs, 900)
    end)

    it("starts over when it is on a vehicle, held or strapped, so the warnings and marker go", function()
        local state = { leftMs = 900, warned = true, reminders = 2 }
        expectNil(RseLeftBehindRule.tick(state, 500, { held = true }, config))
        expectEqual(state.leftMs, 0)
        expectEqual(state.warned, false)
        expectEqual(state.reminders, 0)
    end)

    it("leaves out animals of a call in progress", function()
        local state = { leftMs = 999 }
        expectNil(RseLeftBehindRule.tick(state, 500, { exempt = true }, config))
        expectEqual(state.leftMs, 0)
    end)

    it("gives one warning when little time is left, not one for each reminder missed", function()
        local state = { leftMs = 790 }
        expectEqual(RseLeftBehindRule.tick(state, 20, {}, config), "warn")
        expectEqual(state.warned, true)
        expectEqual(state.reminders, 2)
        expectNil(RseLeftBehindRule.tick(state, 20, {}, config))
    end)

    it("works out the minutes left, rounded up", function()
        local minutes = { LEFT_COLLECT_MS = 30 * 60000 }
        expectEqual(RseLeftBehindRule.minutesLeft({ leftMs = 0 }, minutes), 30)
        expectEqual(RseLeftBehindRule.minutesLeft({ leftMs = 25 * 60000 + 1 }, minutes), 5)
        expectEqual(RseLeftBehindRule.minutesLeft({ leftMs = 40 * 60000 }, minutes), 0)
    end)

    it("doesn't repeat warnings after a reload, and keeps the marker", function()
        local fresh = RseLeftBehindRule.restore(nil, config)
        expectEqual(fresh.warned, false)
        expectEqual(fresh.reminders, 0)
        local warned = RseLeftBehindRule.restore(500, config)
        expectEqual(warned.warned, true)
        expectEqual(warned.reminders, 0)
        expectEqual(RseLeftBehindRule.restore(700, config).reminders, 1)
        expectEqual(RseLeftBehindRule.restore(900, config).reminders, 2)
    end)

    it("clears up a job's scene once nobody is near, never before the wait, and after the longest wait anyway", function()
        local c = { CLEANUP_WAIT_MS = 1000, CLEANUP_MAX_MS = 5000 }
        local item = {}
        expectEqual(RseLeftBehindRule.crewDue(item, 500, true, c), false, "too soon, even with nobody near")
        expectEqual(RseLeftBehindRule.crewDue(item, 600, false, c), false, "the wait is over, but someone is near")
        expectEqual(RseLeftBehindRule.crewDue(item, 100, true, c), true, "and now nobody is")
        local stays = {}
        for _ = 1, 4 do
            expectEqual(RseLeftBehindRule.crewDue(stays, 1000, false, c), false, "someone stays near")
        end
        expectEqual(RseLeftBehindRule.crewDue(stays, 1000, false, c), true, "it goes after the longest wait all the same")
    end)

    it("uses reminders at 15 and 5 minutes", function()
        expectEqual(RseConfig.LEFT_REMINDERS_MS[1], 15 * 60000)
        expectEqual(RseConfig.LEFT_REMINDERS_MS[2], 5 * 60000)
    end)
end)
