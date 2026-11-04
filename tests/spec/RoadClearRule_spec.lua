describe("RseRoadClearRule", function()
    -- a straight lane along z through x = 0, and a second lane 3.5 m to the side (the other direction)
    local lanes = { { 0, -40, 0, 40 }, { 3.5, -40, 3.5, 40 } }
    local scene = { x = 0, z = 0, segments = lanes }

    it("measures the distance to a segment, ends included", function()
        expectNear(RseRoadClearRule.segmentDistance(3, 5, 0, 0, 0, 10), 3, 1e-9)
        expectNear(RseRoadClearRule.segmentDistance(0, 13, 0, 0, 0, 10), 3, 1e-9, "past the end")
        expectNear(RseRoadClearRule.segmentDistance(1, 1, 2, 2, 2, 2), math.sqrt(2), 1e-9, "a zero-length segment")
    end)

    it("keeps a carcass in either lane on the road", function()
        expectEqual(RseRoadClearRule.status({ x = 0.5, z = 2, atRest = true }, scene, RseConfig), "onRoad")
        expectEqual(RseRoadClearRule.status({ x = 3.0, z = 2, atRest = true }, scene, RseConfig), "onRoad", "the other lane")
    end)

    it("counts a carcass lying still beside the road as on the verge", function()
        expectEqual(RseRoadClearRule.status({ x = -4.5, z = 2, atRest = true }, scene, RseConfig), "verge")
        expectEqual(RseRoadClearRule.status({ x = 8, z = 2, atRest = true }, scene, RseConfig), "verge", "past the other lane")
        expectEqual(RseRoadClearRule.status({ x = -4.5, z = 2, atRest = false }, scene, RseConfig), "onRoad", "still moving")
    end)

    it("clears loaded carcasses anywhere and towed-away ones beyond the scene", function()
        expectEqual(RseRoadClearRule.status({ x = 0, z = 0, loaded = true }, scene, RseConfig), "loaded")
        expectEqual(RseRoadClearRule.status({ x = 0, z = RseConfig.SCENE_RADIUS + 1 }, scene, RseConfig), "away")
    end)

    it("falls back to the distance from the scene without a road", function()
        local bare = { x = 0, z = 0, segments = {} }
        expectEqual(RseRoadClearRule.status({ x = 3, z = 0, atRest = true }, bare, RseConfig), "onRoad")
        expectEqual(RseRoadClearRule.status({ x = RseConfig.CLEAR_FALLBACK_RADIUS, z = 0, atRest = true }, bare, RseConfig), "verge")
    end)

    it("knows which statuses clear the road", function()
        expectTrue(RseRoadClearRule.isClear("verge"))
        expectTrue(RseRoadClearRule.isClear("loaded"))
        expectTrue(RseRoadClearRule.isClear("away"))
        expectTrue(not RseRoadClearRule.isClear("onRoad"))
    end)
end)
