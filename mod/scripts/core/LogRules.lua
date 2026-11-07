-- Roadside Emergencies: a logging crash: when a log is clear of the road, what the logs pay, and where a saved one belongs (game side: game/LogSpill.lua).
-- Engine-free.

RseLogRules = {}

-- How far along the job is, 0 to 1. inCount: pieces clear of the road; gone: pieces brought to a recovery point, sold or chipped; pieces: those still there.
function RseLogRules.share(inCount, gone, pieces)
    local all = pieces + gone
    if all <= 0 then
        return 0
    end
    return (inCount + gone) / all
end

-- All of it: the job's pay and each log. Handed over before that: only the logs you have moved, and a log you have started on counts.
function RseLogRules.pay(def, total, share)
    if share >= 1 then
        return def.pay + def.payPerLog * total
    end
    if share <= 0 then
        return 0
    end
    return math.max(1, math.floor(total * share + 0.5)) * def.payPerLog
end

-- Handed over part of the way through a job that goes on to a vehicle: only the logs.
function RseLogRules.logsPay(def, total, share)
    if share <= 0 then
        return 0
    end
    return math.max(1, math.floor(total * math.min(1, share) + 0.5)) * def.payPerLog
end

-- Is a log clear of the road? log: { x, z (its middle), loaded, atRest, ends = { { x, z }, ... } }; scene: { x, z, segments }. The same rule as a carcass, but
-- a log is long: lying still beside the road, neither end may reach into a lane either. Returns "loaded", "away", "verge" or "onRoad".
function RseLogRules.status(log, scene, config)
    local status = RseRoadClearRule.status(log, scene, config)
    if status == "verge" then
        for _, point in ipairs(log.ends or {}) do
            local away = RseRoadClearRule.distanceToRoad(point.x, point.z, scene.segments)
            if away ~= nil and away < config.LOG_END_CLEARANCE then
                return "onRoad"
            end
        end
    end
    return status
end

-- Does this piece count as cleared? Back in the road, it no longer does. On a vehicle it has to have come to rest first, so a log swung across a truck bed
-- doesn't count, and after that it goes on counting while the truck drives off.
function RseLogRules.counts(status, wasIn, restMs, config)
    if not RseRoadClearRule.isClear(status) then
        return false
    end
    return wasIn == true or status ~= "loaded" or restMs >= config.CLEAR_REST_MS
end

-- Is a log lying on a car? a, b: its ends, in the car's own axes ({ x, y, z }, with the car's foot at y = 0); car: { width, length, offsetZ }. Any part of it
-- over the car's outline, higher than a log on the ground could be. A log beside the car, or under its overhang, doesn't count.
function RseLogRules.onCar(a, b, car, config)
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy + dz * dz) / config.TREE_ON_CAR_STEP))
    local halfWidth = car.width / 2 + config.TREE_ON_CAR_MARGIN
    local halfLength = car.length / 2 + config.TREE_ON_CAR_MARGIN
    for i = 0, steps do
        local t = i / steps
        if a.y + dy * t >= config.TREE_ON_CAR_HEIGHT and math.abs(a.x + dx * t) <= halfWidth and math.abs(a.z + dz * t - (car.offsetZ or 0)) <= halfLength then
            return true
        end
    end
    return false
end

-- After a reload: which saved place is each piece's? found: { { x, y, z (where it is), lx, lz (its position against its parent) }, ... };
-- saved: { { x, y, z }, ... }. A piece within `near` of a saved place is still there. The others take the places left, the closest to their position against
-- their parent first, because the game loads a split shape with its world position as that. Returns by found piece { saved = index, inPlace = true or false },
-- or nothing for a piece with no place left.
function RseLogRules.matchSaved(found, saved, near)
    local result, taken = {}, {}
    local function assign(distance, limit, inPlace)
        local candidates = {}
        for i, piece in ipairs(found) do
            for j, place in ipairs(saved) do
                if result[i] == nil and not taken[j] then
                    local d = distance(piece, place)
                    if limit == nil or d <= limit then
                        table.insert(candidates, { i = i, j = j, d = d })
                    end
                end
            end
        end
        table.sort(candidates, function(a, b)
            return a.d < b.d
        end)
        for _, c in ipairs(candidates) do
            if result[c.i] == nil and not taken[c.j] then
                result[c.i] = { saved = c.j, inPlace = inPlace }
                taken[c.j] = true
            end
        end
    end
    assign(function(piece, place)
        return math.sqrt((piece.x - place.x) ^ 2 + (piece.y - place.y) ^ 2 + (piece.z - place.z) ^ 2)
    end, near, true)
    assign(function(piece, place)
        return math.sqrt(((piece.lx or piece.x) - place.x) ^ 2 + ((piece.lz or piece.z) - place.z) ^ 2)
    end, nil, false)
    return result
end
