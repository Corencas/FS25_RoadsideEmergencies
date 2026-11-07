-- Roadside Emergencies: what the ground is, and whether a place looks like where something belongs. Z found the flock's pen on the railroad tracks in a
-- grain yard: nothing had looked at the ground. Engine-free: the game side reads each point and passes its kind; these rules only count.
--   Kinds: "grass", "meadow" (a grass field), "crop" (any other field), "soil", "dirt", "leaves", "sand", "gravel", "hard" (asphalt, concrete, rock),
--   "object" (something built lies on the ground there: rails, a slab, a platform), "water", "other".

RseGroundRules = {}

local SOFT = { grass = true, meadow = true, crop = true, soil = true, dirt = true, leaves = true, sand = true }
local BUILT = { gravel = true, hard = true, object = true }

-- The kind of ground from the map's surface number (the numbers each map gives its ground layers for footstep and wheel sounds) and the field there:
-- field is "meadow", "crop" or nil.
function RseGroundRules.kind(material, field, config)
    if field == "meadow" or field == "crop" then
        return field
    end
    return config.GROUND_MATERIALS[material] or "other"
end

function RseGroundRules.isBuilt(kind)
    return BUILT[kind] == true
end

-- how many of each kind
function RseGroundRules.tally(kinds)
    local counts = {}
    for _, kind in ipairs(kinds) do
        counts[kind] = (counts[kind] or 0) + 1
    end
    return counts
end

-- "grass 9, dirt 2", for the log
function RseGroundRules.describe(counts)
    local names = {}
    for name in pairs(counts) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    local parts = {}
    for _, name in ipairs(names) do
        table.insert(parts, string.format("%s %d", name, counts[name]))
    end
    return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

-- Ground a farmer would put a pen of hurdles on: grass or a grass field at every point, with a bare patch or two. Not a sown field, not a yard, not gravel,
-- not the woods. Returns true, or false and the kind that spoils it.
function RseGroundRules.isPasture(kinds, config)
    local dirt = 0
    for _, kind in ipairs(kinds) do
        if kind == "dirt" then
            dirt = dirt + 1
            if dirt > config.GROUND_PEN_DIRT then
                return false, "dirt"
            end
        elseif kind ~= "grass" and kind ~= "meadow" then
            return false, kind
        end
    end
    return true
end

-- Open country: of the points (the game side leaves out those on a road), at most a small share built over and most of the rest soft ground. A town, a
-- yard or a station fails. Returns true, or false and why.
function RseGroundRules.isCountry(kinds, config)
    if #kinds == 0 then
        return false, "nothing to go on"
    end
    local built, soft = 0, 0
    for _, kind in ipairs(kinds) do
        if BUILT[kind] then
            built = built + 1
        elseif SOFT[kind] then
            soft = soft + 1
        end
    end
    if built > #kinds * config.GROUND_COUNTRY_BUILT then
        return false, "built"
    end
    if soft < #kinds * config.GROUND_COUNTRY_SOFT then
        return false, "not soft"
    end
    return true
end

local function side(ax, az, bx, bz, px, pz)
    return (bx - ax) * (pz - az) - (bz - az) * (px - ax)
end

-- Does the straight line from a to b cross any of the segments { ax, az, bx, bz }? (a railroad between the flock and its pen)
function RseGroundRules.crosses(ax, az, bx, bz, segments)
    for _, s in ipairs(segments or {}) do
        local d1, d2 = side(ax, az, bx, bz, s[1], s[2]), side(ax, az, bx, bz, s[3], s[4])
        local d3, d4 = side(s[1], s[2], s[3], s[4], ax, az), side(s[1], s[2], s[3], s[4], bx, bz)
        if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then
            return true
        end
    end
    return false
end

-- Points round (x, z): `count` ways round at each distance in `distances`, as { x, z }.
function RseGroundRules.ring(x, z, distances, count)
    local points = {}
    for _, distance in ipairs(distances) do
        for i = 0, count - 1 do
            local angle = i * 2 * math.pi / count
            table.insert(points, { x = x + math.sin(angle) * distance, z = z + math.cos(angle) * distance })
        end
    end
    return points
end
