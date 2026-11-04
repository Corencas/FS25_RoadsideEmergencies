describe("RseSceneSpec", function()
    -- a stand-in for math.random: random() -> 0.5, random(a, b) -> b
    local function fixed(a, b)
        if a == nil then
            return 0.5
        end
        return b
    end

    it("reads single animals, counts and ranges", function()
        local parts, warnings = RseSceneSpec.parse("deer, sheep:2-4 ,cow:2")
        expectEqual(#warnings, 0)
        expectEqual(#parts, 3)
        expectEqual(parts[1].kind, "deer")
        expectEqual(parts[1].min, 1)
        expectEqual(parts[2].min, 2)
        expectEqual(parts[2].max, 4)
        expectEqual(parts[3].max, 2)
    end)

    it("drops unknown animals with a warning and caps the count", function()
        local parts, warnings = RseSceneSpec.parse("dragon,pig:3-99")
        expectEqual(#warnings, 1)
        expectEqual(#parts, 1)
        expectEqual(parts[1].max, RseSceneSpec.MAX_PER_KIND)
    end)

    it("picks the animals for a scene", function()
        local kinds = RseSceneSpec.pick(RseSceneSpec.parse("sheep:2-3,cow"), fixed, "random")
        expectEqual(#kinds, 4)
        expectEqual(kinds[1], "sheep")
        expectEqual(kinds[4], "cow")
    end)

    it("scales the count with the job size setting", function()
        local parts = RseSceneSpec.parse("sheep:2-5")
        expectEqual(#RseSceneSpec.pick(parts, fixed, "small"), 2)
        expectEqual(#RseSceneSpec.pick(parts, fixed, "normal"), 3, "the middle, rounded down")
        expectEqual(#RseSceneSpec.pick(parts, fixed, nil), 3, "normal by default")
        expectEqual(#RseSceneSpec.pick(parts, fixed, "large"), 5)
        expectEqual(#RseSceneSpec.pick(parts, fixed, "random"), 5, "whatever random returns")
    end)

    -- a repeatable stand-in for math.random
    local function sequence()
        local state = 12345
        return function()
            state = (state * 16807) % 2147483647
            return state / 2147483647
        end
    end
    local opts = { span = 14, width = 3, gap = 1.6, maxRoadDistance = 3.4 }

    it("scatters the animals over the road: not in a line, at any heading, apart from each other", function()
        local positions = RseSceneSpec.scatter(5, 10, 20, 0, 2, opts, sequence())
        expectEqual(#positions, 5)
        local minX, maxX, minYaw, maxYaw = 1e9, -1e9, 1e9, -1e9
        for i, p in ipairs(positions) do
            expectTrue(math.abs(p.z - 20) <= 14 and math.abs(p.x - 10) <= 3, "inside the stretch of road")
            minX, maxX, minYaw, maxYaw = math.min(minX, p.x), math.max(maxX, p.x), math.min(minYaw, p.yaw), math.max(maxYaw, p.yaw)
            for j = 1, i - 1 do
                local q = positions[j]
                expectTrue(math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2) >= opts.gap, "apart")
            end
        end
        expectTrue(maxX - minX > 1, "spread across the road")
        expectTrue(maxYaw - minYaw > 1, "headings differ")
    end)

    it("scatters differently with other random numbers", function()
        local first = RseSceneSpec.scatter(3, 0, 0, 0, 1, opts, sequence())
        local random = sequence()
        random()
        local second = RseSceneSpec.scatter(3, 0, 0, 0, 1, opts, random)
        expectTrue(first[1].x ~= second[1].x)
    end)

    it("stays on the road where a bend would carry a spot off it", function()
        -- a short lane along z: spots far along the straight line have no lane near them
        local lane = { { 0, -4, 0, 4 } }
        for _, p in ipairs(RseSceneSpec.scatter(4, 0, 0, 0, 1, opts, sequence(), lane)) do
            expectTrue(RseRoadClearRule.distanceToRoad(p.x, p.z, lane) <= opts.maxRoadDistance)
        end
    end)
end)
