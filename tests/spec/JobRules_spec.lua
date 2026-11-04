describe("RseJobRules", function()
    local emergencies = { { id = "deer" }, { id = "cow", needs = "pull" } }

    it("doesn't offer heavy jobs to a farm with nothing that can pull", function()
        local list = RseJobRules.unavailable(emergencies, { canPull = false })
        expectEqual(list.cow, true)
        expectNil(list.deer)
        expectNil(RseJobRules.unavailable(emergencies, { canPull = true }).cow)
    end)

    it("needs a vehicle for cattle, horses and buffalo, not for what can be dragged by hand", function()
        local list = RseJobRules.unavailable(RseConfig.EMERGENCIES, { canPull = false })
        expectEqual(list.cow, true)
        expectEqual(list.horse, true)
        expectEqual(list.buffalo, true)
        expectNil(list.deer)
        expectNil(list.sheep)
    end)

    it("offers a livestock trailer crash without a livestock trailer: the trailer part only needs something that can pull", function()
        expectEqual(RseJobRules.unavailable(RseConfig.EMERGENCIES, { canPull = false }).livestock, true)
        expectNil(RseJobRules.unavailable(RseConfig.EMERGENCIES, { canPull = true }).livestock)
    end)

    it("warns once, then gives the job to another contractor", function()
        local config = { JOB_EXPIRE_MS = 1000, JOB_EXPIRE_WARN_MS = 200 }
        local state = {}
        expectNil(RseJobRules.tickExpiry(state, 700, config))
        expectEqual(RseJobRules.tickExpiry(state, 100, config), "warn")
        expectNil(RseJobRules.tickExpiry(state, 100, config), "only once")
        expectEqual(RseJobRules.tickExpiry(state, 100, config), "expire")
    end)

    it("picks a known caller", function()
        expectEqual(RseJobRules.pickCaller(function(n)
            return n
        end), RseJobRules.CALLERS[#RseJobRules.CALLERS])
    end)
end)
