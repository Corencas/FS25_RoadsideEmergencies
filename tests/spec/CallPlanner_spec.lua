describe("RseCallPlanner", function()
    local function constant(value)
        return function()
            return value
        end
    end

    local config = setmetatable({ CALL_CHECK_MS = 100, CALL_GAP_MS = 1000, CALL_FIRST_MS = 300, CALL_CHANCE = 0.5 },
        { __index = RseConfig })

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

    it("makes deer likelier at dusk and in autumn, and leaves out switched-off emergencies", function()
        local function weightOf(list, id)
            for _, item in ipairs(list) do
                if item.id == id then
                    return item.weight
                end
            end
            return nil
        end
        local noon = RseCallPlanner.weights({ hour = 12 }, RseConfig)
        local dusk = RseCallPlanner.weights({ hour = 19, isAutumn = true }, RseConfig)
        expectNear(weightOf(dusk, "deer"), weightOf(noon, "deer") * 3, 1e-9)
        expectNear(weightOf(dusk, "cow"), weightOf(noon, "cow"), 1e-9)
        expectNil(weightOf(RseCallPlanner.weights({ disabled = { cow = true } }, RseConfig), "cow"))
    end)

    it("picks by weight", function()
        local list = { { id = "a", weight = 1 }, { id = "b", weight = 3 } }
        expectEqual(RseCallPlanner.pick(list, 0.2), "a")
        expectEqual(RseCallPlanner.pick(list, 0.3), "b")
        expectEqual(RseCallPlanner.pick(list, 0.999), "b")
        expectNil(RseCallPlanner.pick({}, 0.5))
    end)
end)
