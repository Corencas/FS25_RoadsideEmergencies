describe("RseCallPlanner", function()
    local function constant(value)
        return function()
            return value
        end
    end

    local config = setmetatable({ CALL_CHECK_MS = 100, CALL_GAP_MS = 1000, CALL_FIRST_MS = 300, CALL_CHANCE = 0.5,
        EMERGENCIES = { { id = "deer", weight = 1 }, { id = "cow", weight = 1 } } }, { __index = RseConfig })

    it("waits for the first-call delay, then calls on a lucky check", function()
        local state = RseCallPlanner.newState(config)
        local context = { enabled = true, busy = false, hour = 12 }
        for _ = 1, 2 do
            expectNil(RseCallPlanner.tick(state, 100, context, config, constant(0.1)), "within the first 300 ms")
        end
        expectEqual(RseCallPlanner.tick(state, 100, context, config, constant(0.1)), "deer", "the first in the list for a low roll")
        expectNil(RseCallPlanner.tick(state, 100, context, config, constant(0.1)), "the gap starts again")
    end)

    it("does not call while switched off, busy or unlucky", function()
        local context = { enabled = false, busy = false }
        local state = RseCallPlanner.newState(config)
        state.sinceLastMs = 5000
        expectNil(RseCallPlanner.tick(state, 100, context, config, constant(0.1)))
        context.enabled, context.busy = true, true
        expectNil(RseCallPlanner.tick(state, 100, context, config, constant(0.1)))
        context.busy = false
        expectNil(RseCallPlanner.tick(state, 100, context, config, constant(0.9)), "roll above the chance")
    end)

    it("can make a call likelier at dusk and in autumn, and leaves out switched-off emergencies", function()
        local function weightOf(list, id)
            for _, item in ipairs(list) do
                if item.id == id then
                    return item.weight
                end
            end
            return nil
        end
        local seasonal = setmetatable({ EMERGENCIES = { { id = "deer", weight = 1, duskFactor = 2, autumnFactor = 1.5 }, { id = "cow", weight = 1 } } },
            { __index = RseConfig })
        local noon = RseCallPlanner.weights({ hour = 12 }, seasonal)
        local dusk = RseCallPlanner.weights({ hour = 19, isAutumn = true }, seasonal)
        expectNear(weightOf(dusk, "deer"), weightOf(noon, "deer") * 3, 1e-9)
        expectNear(weightOf(dusk, "cow"), weightOf(noon, "cow"), 1e-9)
        expectNil(weightOf(RseCallPlanner.weights({ disabled = { cow = true } }, seasonal), "cow"))
    end)

    it("picks by weight", function()
        local list = { { id = "a", weight = 1 }, { id = "b", weight = 3 } }
        expectEqual(RseCallPlanner.pick(list, 0.2), "a")
        expectEqual(RseCallPlanner.pick(list, 0.3), "b")
        expectEqual(RseCallPlanner.pick(list, 0.999), "b")
        expectNil(RseCallPlanner.pick({}, 0.5))
    end)

    it("keeps big jobs apart at any frequency, and lets animal calls through", function()
        local big = setmetatable({ CALL_CHECK_MS = 100, CALL_GAP_MS = 100, CALL_FIRST_MS = 0, CALL_CHANCE = 1, CALL_BIG_GAP_MS = 1000,
            EMERGENCIES = { { id = "wreck", weight = 1, group = "wreck" }, { id = "deer", weight = 1 } } }, { __index = RseConfig })
        local state = RseCallPlanner.newState(big)
        local context = { enabled = true, busy = false }
        expectEqual(RseCallPlanner.tick(state, 100, context, big, constant(0.1)), "wreck", "the first big job")
        expectEqual(RseCallPlanner.tick(state, 100, context, big, constant(0.1)), "deer", "too soon for another")
        expectEqual(RseCallPlanner.tick(state, 900, context, big, constant(0.1)), "wreck", "its wait is over")
    end)

    it("waits for the first-call delay even if the gap is shorter", function()
        local short = setmetatable({ CALL_CHECK_MS = 100, CALL_GAP_MS = 50, CALL_FIRST_MS = 300, CALL_CHANCE = 1,
            EMERGENCIES = { { id = "deer", weight = 1 } } }, { __index = RseConfig })
        local state = RseCallPlanner.newState(short)
        local context = { enabled = true, busy = false, hour = 12 }
        expectNil(RseCallPlanner.tick(state, 100, context, short, constant(0.1)))
        expectNil(RseCallPlanner.tick(state, 100, context, short, constant(0.1)))
        expectEqual(RseCallPlanner.tick(state, 100, context, short, constant(0.1)), "deer")
    end)

    it("counts a call asked for by hand towards the wait for big jobs", function()
        local state = RseCallPlanner.newState(RseConfig)
        RseCallPlanner.noteCall(state, "deer", RseConfig)
        expectEqual(state.sinceBigMs, math.huge, "an animal doesn't count")
        RseCallPlanner.noteCall(state, "rollover", RseConfig)
        expectEqual(state.sinceBigMs, 0)
        expectEqual(state.sinceLastMs, 0)
    end)

    it("makes every call as likely as any other", function()
        for _, emergency in ipairs(RseConfig.EMERGENCIES) do
            if emergency.id ~= "storm" then
                expectEqual(emergency.weight, 1, emergency.id)
            end
        end
    end)
end)
