describe("RseKitRules", function()
    local config = { KIT_REMINDER_FIRST_MS = 100, KIT_REMINDER_MS = 300 }

    it("finds the nearest item the view points at, within reach and radius", function()
        local near, far = { x = 0, y = 0, z = 3 }, { x = 0, y = 0, z = 6 }
        local items = { far, near }
        expectEqual(RseKitRules.aimed(items, 0, 0, 0, 0, 0, 1, 8, 0.5), near)
        expectEqual(RseKitRules.aimed(items, 0.4, 0, 0, 0, 0, 1, 8, 0.5), near, "a little off the ray")
        expectNil(RseKitRules.aimed(items, 2, 0, 0, 0, 0, 1, 8, 0.5), "too far off the ray")
        expectNil(RseKitRules.aimed(items, 0, 0, 0, 0, 0, 1, 2, 0.5), "out of reach")
        expectNil(RseKitRules.aimed(items, 0, 0, 0, 0, 0, -1, 8, 0.5), "behind you")
        expectNil(RseKitRules.aimed({}, 0, 0, 0, 0, 0, 1, 8, 0.5))
        local wide = { x = 2, y = 0, z = 3, radius = 2.5 }
        expectEqual(RseKitRules.aimed({ wide }, 0, 0, 0, 0, 0, 1, 8, 0.5), wide, "an item with its own pick radius")
    end)

    it("works out the middle of the items", function()
        local x, z = RseKitRules.centre({ { x = 0, z = 0 }, { x = 4, z = 2 } })
        expectNear(x, 2, 1e-9)
        expectNear(z, 1, 1e-9)
        expectNil(RseKitRules.centre({}))
    end)

    it("reminds after the first delay, then at every interval, as long as items are owed", function()
        local state = RseKitRules.newReminder()
        expectTrue(not RseKitRules.tickReminder(state, 50, 2, false, config))
        expectTrue(RseKitRules.tickReminder(state, 60, 2, false, config), "first call")
        expectTrue(not RseKitRules.tickReminder(state, 200, 2, false, config))
        expectTrue(RseKitRules.tickReminder(state, 110, 2, false, config), "next call")
    end)

    it("doesn't count down while you are near them, and starts over when none are left", function()
        local state = RseKitRules.newReminder()
        expectTrue(not RseKitRules.tickReminder(state, 500, 2, true, config), "near")
        expectEqual(state.remainingMs, config.KIT_REMINDER_FIRST_MS)
        expectTrue(not RseKitRules.tickReminder(state, 50, 0, false, config))
        expectNil(state.remainingMs)
    end)
end)
