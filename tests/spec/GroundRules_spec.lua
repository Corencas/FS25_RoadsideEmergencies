describe("RseGroundRules", function()
    local function many(kind, count)
        local list = {}
        for _ = 1, count do
            table.insert(list, kind)
        end
        return list
    end

    local function join(...)
        local list = {}
        for _, part in ipairs({ ... }) do
            for _, kind in ipairs(part) do
                table.insert(list, kind)
            end
        end
        return list
    end

    it("reads the maps' surface numbers, and a field over them", function()
        expectEqual(RseGroundRules.kind(2, nil, RseConfig), "grass")
        expectEqual(RseGroundRules.kind(6, nil, RseConfig), "gravel", "the ballast under the tracks and a grain yard's lot")
        expectEqual(RseGroundRules.kind(7, nil, RseConfig), "hard", "asphalt, concrete, rock")
        expectEqual(RseGroundRules.kind(1, nil, RseConfig), "dirt")
        expectEqual(RseGroundRules.kind(4, nil, RseConfig), "other", "a number the maps don't use for ground")
        expectEqual(RseGroundRules.kind(nil, nil, RseConfig), "other")
        expectEqual(RseGroundRules.kind(0, "meadow", RseConfig), "meadow", "a grass field")
        expectEqual(RseGroundRules.kind(2, "crop", RseConfig), "crop", "a sown field, whatever the layer under it")
    end)

    it("puts a pen only on grass, with a bare patch or two at most", function()
        expectTrue(RseGroundRules.isPasture(many("grass", 13), RseConfig), "all grass")
        expectTrue(RseGroundRules.isPasture(join(many("grass", 8), many("meadow", 5)), RseConfig), "a grass field counts")
        expectTrue(RseGroundRules.isPasture(join(many("grass", 11), many("dirt", 2)), RseConfig), "two bare patches")
        local ok, why = RseGroundRules.isPasture(join(many("grass", 10), many("dirt", 3)), RseConfig)
        expectEqual(ok, false, "three bare patches")
        expectEqual(why, "dirt")
    end)

    it("never puts a pen on gravel, rails, a field, the woods or the road (Z: a pen on the tracks in a grain yard)", function()
        for _, spoiler in ipairs({ "gravel", "hard", "object", "crop", "leaves", "water", "sand", "soil", "other" }) do
            local ok, why = RseGroundRules.isPasture(join(many("grass", 12), { spoiler }), RseConfig)
            expectEqual(ok, false, "one point on " .. spoiler)
            expectEqual(why, spoiler)
        end
    end)

    it("tells open country from a town, a yard or a station", function()
        expectTrue(RseGroundRules.isCountry(join(many("grass", 10), many("crop", 6), many("dirt", 2)), RseConfig), "fields and verges")
        expectTrue(RseGroundRules.isCountry(join(many("grass", 16), many("hard", 2)), RseConfig), "a farm drive or two")
        expectEqual(RseGroundRules.isCountry(join(many("grass", 12), many("gravel", 6)), RseConfig), false, "a third gravel: a yard")
        expectEqual(RseGroundRules.isCountry(join(many("grass", 13), many("hard", 3), many("object", 2)), RseConfig), false, "sidewalks and slabs: a town")
        expectEqual(RseGroundRules.isCountry(join(many("grass", 10), many("water", 8)), RseConfig), false, "mostly water")
        expectEqual(RseGroundRules.isCountry({}, RseConfig), false, "nothing to go on")
    end)

    it("sees a railroad between the flock and its pen", function()
        local rails = { { -100, 50, 100, 50 } }
        expectTrue(RseGroundRules.crosses(0, 0, 10, 120, rails), "straight across")
        expectEqual(RseGroundRules.crosses(0, 0, 10, 40, rails), false, "stops short")
        expectEqual(RseGroundRules.crosses(0, 0, 120, 0, rails), false, "alongside")
        expectEqual(RseGroundRules.crosses(0, 0, 10, 120, nil), false, "a map with no railroad")
    end)

    it("counts the kinds for the log", function()
        local counts = RseGroundRules.tally({ "grass", "dirt", "grass", "meadow", "grass" })
        expectEqual(counts.grass, 3)
        expectEqual(RseGroundRules.describe(counts), "grass 3, dirt 1, meadow 1")
        expectEqual(RseGroundRules.describe({}), "nothing")
    end)

    it("lays points round a place", function()
        local points = RseGroundRules.ring(10, 20, { 5, 8 }, 4)
        expectEqual(#points, 8)
        expectNear(points[1].x, 10, 1e-9)
        expectNear(points[1].z, 25, 1e-9)
        expectNear(points[6].x, 18, 1e-9)
    end)
end)
