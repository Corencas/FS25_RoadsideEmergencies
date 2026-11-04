describe("RseSpotRules", function()
    it("picks in proportion to the weights", function()
        local weights = { 1, 3 }
        expectEqual(RseSpotRules.pickWeighted(weights, 0.2), 1)
        expectEqual(RseSpotRules.pickWeighted(weights, 0.3), 2)
        expectEqual(RseSpotRules.pickWeighted(weights, 0.999), 2)
        expectNil(RseSpotRules.pickWeighted({}, 0.5))
        expectNil(RseSpotRules.pickWeighted({ 0, 0 }, 0.5))
    end)

    it("leaves out spots inside a keep-out circle", function()
        local keepOuts = { { x = 0, z = 0, radius = 10 }, { x = 100, z = 0, radius = 5 } }
        expectTrue(not RseSpotRules.isFree(3, 4, keepOuts))
        expectTrue(not RseSpotRules.isFree(102, 0, keepOuts))
        expectTrue(RseSpotRules.isFree(50, 0, keepOuts))
        expectTrue(RseSpotRules.isFree(0, 0, {}), "nothing to keep out")
    end)
end)
