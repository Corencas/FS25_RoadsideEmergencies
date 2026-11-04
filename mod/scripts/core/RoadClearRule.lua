-- Roadside Emergencies: is a carcass still in the road? Engine-free (plain numbers), so the rule is unit-tested.
-- The game side measures the road around a scene as short line segments along the lane centres (the map's AI road
-- splines, Roads.lua) and tells us whether the carcass is loaded on something and lying still.
--   loaded: on a vehicle, held by a machine           -> clear
--   away:   moved far from the scene (towed off)       -> clear
--   verge:  lying still far enough from every lane     -> clear
--   onRoad: anything else                              -> traffic still waits

RseRoadClearRule = {}

-- shortest distance from point p to the segment a-b, in the ground plane
function RseRoadClearRule.segmentDistance(px, pz, ax, az, bx, bz)
    local abx, abz = bx - ax, bz - az
    local lengthSq = abx * abx + abz * abz
    local t = 0
    if lengthSq > 0 then
        t = math.max(0, math.min(1, ((px - ax) * abx + (pz - az) * abz) / lengthSq))
    end
    local dx, dz = px - (ax + abx * t), pz - (az + abz * t)
    return math.sqrt(dx * dx + dz * dz)
end

-- distance to the nearest lane centre; nil when there are no segments. segments: { { ax, az, bx, bz }, ... }
function RseRoadClearRule.distanceToRoad(px, pz, segments)
    local best = nil
    for _, s in ipairs(segments or {}) do
        local d = RseRoadClearRule.segmentDistance(px, pz, s[1], s[2], s[3], s[4])
        if best == nil or d < best then
            best = d
        end
    end
    return best
end

-- carcass: { x, z, loaded, atRest }; scene: { x, z, segments }. Returns the status and the distance it was judged by.
function RseRoadClearRule.status(carcass, scene, config)
    if carcass.loaded then
        return "loaded", 0
    end
    local dx, dz = carcass.x - scene.x, carcass.z - scene.z
    local fromScene = math.sqrt(dx * dx + dz * dz)
    if fromScene > config.SCENE_RADIUS then
        return "away", fromScene
    end
    local fromRoad = RseRoadClearRule.distanceToRoad(carcass.x, carcass.z, scene.segments)
    if fromRoad == nil then
        -- no road found around the scene: judge by the distance from where it lay
        if carcass.atRest and fromScene >= config.CLEAR_FALLBACK_RADIUS then
            return "verge", fromScene
        end
        return "onRoad", fromScene
    end
    if carcass.atRest and fromRoad >= config.CLEAR_DISTANCE then
        return "verge", fromRoad
    end
    return "onRoad", fromRoad
end

function RseRoadClearRule.isClear(status)
    return status == "loaded" or status == "away" or status == "verge"
end
