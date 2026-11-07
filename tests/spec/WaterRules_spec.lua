describe("RseWaterRules", function()
    -- the road lies along +x; the car at x = 0, in water up to height 0
    local function ground(slope, cliffAt, cliffHeight)
        return function(x)
            local height = -1 + x * slope
            if cliffAt ~= nil and x >= cliffAt then
                height = height + cliffHeight
            end
            return height
        end
    end

    local function check(heightAt, isBlocked, toRoad)
        return RseWaterRules.bank(0, 0, 1, 0, toRoad or 30, 0, heightAt, isBlocked, RseConfig)
    end

    it("takes a gentle bank, and says how far off the dry land is", function()
        local verdict, dryAt = check(ground(0.15))
        expectEqual(verdict, "ok")
        expectEqual(dryAt, 10, "1.4 m up from the bottom, 0.4 m above the water")
    end)

    it("refuses a bank like the one that trapped Z's car", function()
        expectEqual(check(ground(0.15, 6, 2.5)), "steep")
        expectEqual(check(ground(0.6)), "steep", "steep all the way")
    end)

    it("refuses water with no dry land within the strap's reach", function()
        expectEqual(check(ground(0.02)), "noDry")
        expectEqual(check(ground(0.05), nil, 8), "noDry", "the road comes first")
    end)

    it("refuses a pull with something solid in the way", function()
        expectEqual(check(ground(0.15), function(x1)
            return x1 >= 4
        end), "blocked")
    end)

    it("doesn't mind what lies beyond the room the pulling vehicle needs", function()
        local steeperLater = function(x)
            return x < 20 and -1 + x * 0.15 or 2 + (x - 20) * 0.45
        end
        expectEqual(check(steeperLater), "ok", "a steeper climb to the road, but a vehicle can take it")
        expectEqual(check(steeperLater, function(x1)
            return x1 >= 18
        end), "ok", "a tree well behind the vehicle doesn't matter")
    end)

    it("counts places close together as one", function()
        local places = {}
        expectTrue(RseWaterRules.addPlace(places, { x = 0, z = 0 }, 20))
        expectEqual(RseWaterRules.addPlace(places, { x = 5, z = 5 }, 20), false)
        expectTrue(RseWaterRules.addPlace(places, { x = 30, z = 0 }, 20))
        expectEqual(#places, 2)
    end)

    it("chooses any place but the last one and the one you stand at, unless nothing else is left", function()
        local a, b, c = { x = 0, z = 0 }, { x = 500, z = 0 }, { x = 1000, z = 0 }
        local function first() return 0 end
        local function lastOfThem() return 0.999 end
        expectNil(RseWaterRules.choose({}, nil, nil, nil, RseConfig, first))
        expectEqual(RseWaterRules.choose({ a, b, c }, nil, nil, nil, RseConfig, first), a)
        expectEqual(RseWaterRules.choose({ a, b, c }, nil, nil, nil, RseConfig, lastOfThem), c)
        expectEqual(RseWaterRules.choose({ a, b, c }, { x = 0, z = 0 }, nil, nil, RseConfig, first), b, "not the last one")
        expectEqual(RseWaterRules.choose({ a, b, c }, nil, nil, { x = 0, z = 0 }, RseConfig, first), b, "not where you stand")
        expectEqual(RseWaterRules.choose({ a }, { x = 0, z = 0 }, nil, { x = 0, z = 0 }, RseConfig, first), a, "a map may have only one")
    end)

    it("takes the place nearest to where it was asked for", function()
        local a, b = { x = 0, z = 0 }, { x = 500, z = 0 }
        local function first() return 0 end
        expectEqual(RseWaterRules.choose({ a, b }, { x = 500, z = 0 }, { x = 450, z = 0 }, nil, RseConfig, first), b, "even if it was the last one")
    end)
end)
