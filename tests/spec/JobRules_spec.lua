describe("RseJobRules", function()
    local emergencies = { { id = "deer" }, { id = "cow", needs = "pull" } }

    local function offered(fleet)
        return RseJobRules.unavailable(RseConfig.EMERGENCIES, fleet, RseConfig)
    end

    local NOTHING = { canPull = false, canPullHeavy = false, canLift = false, canCarry = false, hasLivestockTrailer = false }
    local PICKUP = { canPull = true, canPullHeavy = false, canLift = false, canCarry = true, hasLivestockTrailer = false }

    it("doesn't offer heavy jobs to a farm with nothing that can pull", function()
        local list = RseJobRules.unavailable(emergencies, { canPull = false }, RseConfig)
        expectEqual(list.cow, true)
        expectNil(list.deer)
        expectNil(RseJobRules.unavailable(emergencies, { canPull = true }, RseConfig).cow)
    end)

    it("with nothing at all: only what can be dragged by hand, and a flock on foot", function()
        local list = offered(NOTHING)
        for _, id in ipairs({ "deer", "boar", "sheep", "pig", "goat", "flock" }) do
            expectNil(list[id], id)
        end
        for _, id in ipairs({ "cow", "horse", "buffalo", "wreck", "rollover", "trailer", "livestock", "powerline", "logging", "crossing", "river", "tree",
            "storm" }) do
            expectEqual(list[id], true, id)
        end
    end)

    it("with a pickup: no wrecked trucks or overturned tractors, which are all big", function()
        local list = offered(PICKUP)
        expectEqual(list.wreck, true)
        expectEqual(list.rollover, true)
        for _, id in ipairs({ "cow", "trailer", "powerline", "logging", "crossing", "river", "tree", "storm" }) do
            expectNil(list[id], id)
        end
    end)

    it("with 3 t or more, those come too", function()
        local list = offered({ canPull = true, canPullHeavy = true, canLift = false, canCarry = true, hasLivestockTrailer = false })
        expectNil(list.wreck)
        expectNil(list.rollover)
    end)

    it("takes your own livestock trailer for a livestock trailer crash: the animals have to go somewhere", function()
        expectEqual(offered({ canPull = true, canPullHeavy = true, canLift = true, canCarry = true, hasLivestockTrailer = false }).livestock, true)
        expectNil(offered({ canPull = true, canPullHeavy = true, canLift = true, canCarry = true, hasLivestockTrailer = true }).livestock)
    end)

    it("takes something to carry bales for storm damage, which has no trailer of its own", function()
        expectEqual(offered({ canPull = true, canPullHeavy = true, canLift = true, canCarry = false, hasLivestockTrailer = true }).storm, true)
        expectNil(offered(PICKUP).storm)
    end)

    it("follows the list of vehicles, however a job is written: all of them too big, and it is off", function()
        local big = { variants = { { file = "a", heavy = true }, { file = "b", heavy = true } } }
        local mixed = { variants = { { file = "a", heavy = true }, { file = "b" } } }
        local config = { WRECKS = { big = big, mixed = mixed } }
        local jobs = { { id = "big", needs = "pull", wreck = "big" }, { id = "mixed", needs = "pull", wreck = "mixed" } }
        local list = RseJobRules.unavailable(jobs, PICKUP, config)
        expectEqual(list.big, true)
        expectNil(list.mixed)
    end)

    it("adds up what a farm has", function()
        local config = RseConfig
        local quad = RseJobRules.fleetFrom({ { motorized = true, mass = 0.5 } }, config)
        expectTrue(not quad.canPull, "a quad doesn't pull a car")
        local pickup = RseJobRules.fleetFrom({ { motorized = true, mass = 2.5, carries = true } }, config)
        expectTrue(pickup.canPull and not pickup.canPullHeavy and pickup.canCarry)
        local tractor = RseJobRules.fleetFrom({ { motorized = true, mass = config.FLEET_HEAVY_MASS } }, config)
        expectTrue(tractor.canPullHeavy)
        local trailer = RseJobRules.fleetFrom({ { motorized = false, mass = 9, carries = true, livestockTrailer = true } }, config)
        expectTrue(not trailer.canPull and not trailer.canPullHeavy, "a trailer can't pull anything, however heavy")
        expectTrue(trailer.canCarry and trailer.hasLivestockTrailer)
        local fork = RseJobRules.fleetFrom({ { motorized = false, mass = 0.2, lifts = true } }, config)
        expectTrue(fork.canLift)
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
