-- Roadside Emergencies: what lies at a scene and where. Engine-free, unit-tested.
-- A scenario file names its animals in one attribute, e.g. animals="deer" or animals="sheep:2-4" or "cow:1-2,pig:1".
-- `random` is math.random or a stand-in with the same signature (random(min, max) -> integer, random() -> 0..1).

RseSceneSpec = {
    MAX_PER_KIND = 8,
    SCATTER_TRIES = 30,
    SIZES = { small = true, normal = true, large = true, random = true } -- how much work a call is (the job size setting)
}

-- "sheep:2-4,cow" -> { { kind = "sheep", min = 2, max = 4 }, { kind = "cow", min = 1, max = 1 } }, warnings
function RseSceneSpec.parse(spec)
    local parts, warnings = {}, {}
    if type(spec) ~= "string" then
        return parts, warnings
    end
    for item in string.gmatch(spec, "[^,]+") do
        item = item:gsub("^%s+", ""):gsub("%s+$", "")
        local name, range = item:match("^([%a]+):?(.*)$")
        local entry = name ~= nil and RseAnimalCatalog.get(name) or nil
        if entry == nil then
            table.insert(warnings, string.format("unknown animal '%s'", item))
        else
            local low, high = range:match("^(%d+)%-(%d+)$")
            if low == nil then
                low = range:match("^(%d+)$") or "1"
                high = low
            end
            low = math.max(1, math.min(tonumber(low), RseSceneSpec.MAX_PER_KIND))
            high = math.max(low, math.min(tonumber(high), RseSceneSpec.MAX_PER_KIND))
            table.insert(parts, { kind = entry.kind, min = low, max = high })
        end
    end
    return parts, warnings
end

-- small: the lowest count of the range; large: the highest; random: anything in it; normal (default): the middle, rounded down
local function countFor(part, random, size)
    if size == "small" then
        return part.min
    elseif size == "large" then
        return part.max
    elseif size == "random" then
        return random(part.min, part.max)
    end
    return math.floor((part.min + part.max) / 2)
end

-- a count from a range { min, max } by job size (also for spilled bales)
function RseSceneSpec.count(range, random, size)
    return countFor(range, random, size)
end

-- the animals for one scene: { "sheep", "sheep", "sheep" }
function RseSceneSpec.pick(parts, random, size)
    local kinds = {}
    for _, part in ipairs(parts) do
        for _ = 1, countFor(part, random, size) do
            table.insert(kinds, part.kind)
        end
    end
    return kinds
end

-- Scattered over the road like a real scene (Z), differently every time. opts: span (metres along the road either way of the
-- scene), width (metres across, either way of the lane centre), gap (least distance between animals), maxRoadDistance (a spot
-- further than this from every lane, carried off by a bend, is tried again; only with segments). Each lies at any heading.
-- Returns { { x, z, yaw }, ... }.
function RseSceneSpec.scatter(count, cx, cz, dirX, dirZ, opts, random, segments)
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 1e-6 then
        dirX, dirZ, length = 0, 1, 1
    end
    dirX, dirZ = dirX / length, dirZ / length
    local sideX, sideZ = dirZ, -dirX
    local hasRoad = segments ~= nil and #segments > 0
    local positions = {}
    for _ = 1, count do
        local x, z
        for _ = 1, RseSceneSpec.SCATTER_TRIES do
            local along = (random() * 2 - 1) * opts.span
            local across = (random() * 2 - 1) * opts.width
            x, z = cx + dirX * along + sideX * across, cz + dirZ * along + sideZ * across
            local fits = not hasRoad or RseRoadClearRule.distanceToRoad(x, z, segments) <= opts.maxRoadDistance
            for _, other in ipairs(positions) do
                local dx, dz = x - other.x, z - other.z
                fits = fits and dx * dx + dz * dz >= opts.gap * opts.gap
            end
            if fits then
                break
            end
        end
        table.insert(positions, { x = x, z = z, yaw = random() * 2 * math.pi })
    end
    return positions
end
