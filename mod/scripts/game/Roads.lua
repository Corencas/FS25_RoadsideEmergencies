-- Roadside Emergencies: the road at a scene. Measured from the map's AI road splines (AISystem.roadSplines, the same list
-- the Emergency Pack's spline start picks its spot from); each spline runs along the centre of one lane. Done once per
-- scene: a coarse pass finds the lanes near it, a fine pass cuts them into short segments for RseRoadClearRule.

RseRoads = {}

local function roadSplines()
    local ai = g_currentMission ~= nil and g_currentMission.aiSystem or nil
    return ai ~= nil and type(ai.roadSplines) == "table" and ai.roadSplines or {}
end

local function isNear(spline, length, x, z, reach)
    local steps = math.max(1, math.ceil(length / RseConfig.ROAD_COARSE_STEP))
    for i = 0, steps do
        local sx, _, sz = getSplinePosition(spline, i / steps)
        if (sx - x) * (sx - x) + (sz - z) * (sz - z) <= reach * reach then
            return true
        end
    end
    return false
end

-- A random spot on the map's roads, every metre of lane equally likely, wherever the player is (Z). keepOuts: circles the
-- spot must stay out of (RseSpotRules). near: { x, z, radius }, only spots around there (a twister's end), or nil. Returns { x, y, z, dirX,
-- dirY, dirZ }, or nil if none was found.
-- onGround: not on a bridge
function RseRoads.randomSpot(keepOuts, near, onGround)
    local splines, lengths = {}, {}
    for _, spline in ipairs(roadSplines()) do
        local length = entityExists(spline) and getSplineLength(spline) or 0
        if length >= RseConfig.SPOT_MIN_LANE then
            table.insert(splines, spline)
            table.insert(lengths, length)
        end
    end
    local half = (g_currentMission.terrainSize or 2048) * 0.5 - RseConfig.SPOT_MAP_MARGIN
    for _ = 1, near ~= nil and RseConfig.SPOT_TRIES * 10 or RseConfig.SPOT_TRIES do
        local spline = splines[RseSpotRules.pickWeighted(lengths, math.random())]
        if spline == nil then
            return nil
        end
        local t = math.random()
        local x, y, z = getSplinePosition(spline, t)
        local closeEnough = near == nil or (x - near.x) ^ 2 + (z - near.z) ^ 2 <= near.radius ^ 2
        local grounded = not onGround or math.abs(y - getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)) <= RseConfig.BRIDGE_HEIGHT
        if closeEnough and grounded and math.abs(x) <= half and math.abs(z) <= half and RseSpotRules.isFree(x, z, keepOuts) then
            local dirX, dirY, dirZ = getSplineDirection(spline, t)
            return { x = x, y = y, z = z, dirX = dirX, dirY = dirY, dirZ = dirZ }
        end
    end
    return nil
end

-- Lane segments within `radius` of (x, z), the direction of the closest lane there and how far away it is.
-- Returns { segments = { { ax, az, bx, bz }, ... }, dirX, dirZ, distance, lanes }; dirX is nil when no lane is near.
function RseRoads.around(x, z, radius)
    local result = { segments = {}, lanes = 0 }
    local reach = radius + RseConfig.ROAD_COARSE_STEP
    local radiusSq = radius * radius
    local bestSq, bestSpline, bestT = nil, nil, nil
    for _, spline in ipairs(roadSplines()) do
        local length = entityExists(spline) and getSplineLength(spline) or 0
        if length > 0 and isNear(spline, length, x, z, reach) then
            result.lanes = result.lanes + 1
            local steps = math.max(1, math.ceil(length / RseConfig.ROAD_FINE_STEP))
            local px, _, pz = getSplinePosition(spline, 0)
            local pInside = (px - x) * (px - x) + (pz - z) * (pz - z) <= radiusSq
            for i = 1, steps do
                local t = i / steps
                local qx, _, qz = getSplinePosition(spline, t)
                local dSq = (qx - x) * (qx - x) + (qz - z) * (qz - z)
                local qInside = dSq <= radiusSq
                if pInside or qInside then
                    table.insert(result.segments, { px, pz, qx, qz })
                end
                if bestSq == nil or dSq < bestSq then
                    bestSq, bestSpline, bestT = dSq, spline, t
                end
                px, pz, pInside = qx, qz, qInside
            end
        end
    end
    if bestSpline ~= nil then
        local dx, _, dz = getSplineDirection(bestSpline, bestT)
        result.dirX, result.dirZ, result.distance = dx, dz, math.sqrt(bestSq)
    end
    return result
end

-- each lane's two ends, measured once per map: where a lane can lead into another (the utility crew's way to a scene)
local ends, endsOf = nil, nil -- the lanes' ends, and the list of lanes they were measured from
local JOIN = 4          -- metres: a lane ending this close to where another starts leads into it
local JOIN_ALONG = 6    -- or one passing this close by it, anywhere along it: at a junction the main road's lane runs on past the side road (Z: a lane
                        -- that started 55 m back found nothing leading into it, and no truck came)
local TURN_LIMIT = -0.5 -- and no sharper than this (the cosine between the two): never a U-turn onto the other lane of the same road

local function laneEnds()
    local splines = roadSplines()
    if ends ~= nil and endsOf == splines then
        return ends
    end
    ends, endsOf = {}, splines
    for _, spline in ipairs(splines) do
        local length = entityExists(spline) and getSplineLength(spline) or 0
        if length > 1 then
            local ex, _, ez = getSplinePosition(spline, 1)
            local dx, _, dz = getSplineDirection(spline, 1)
            table.insert(ends, { spline = spline, length = length, x = ex, z = ez, dirX = dx, dirZ = dz })
        end
    end
    return ends
end

-- the lane nearest (x, z) and where on it: spline, t; nil when no lane is within reach
local function nearestLane(x, z, reach)
    local bestSq, bestSpline, bestT = nil, nil, nil
    for _, spline in ipairs(roadSplines()) do
        local length = entityExists(spline) and getSplineLength(spline) or 0
        if length > 0 and isNear(spline, length, x, z, reach + RseConfig.ROAD_COARSE_STEP) then
            local steps = math.max(1, math.ceil(length / RseConfig.ROAD_FINE_STEP))
            for i = 0, steps do
                local t = i / steps
                local qx, _, qz = getSplinePosition(spline, t)
                local dSq = (qx - x) * (qx - x) + (qz - z) * (qz - z)
                if dSq <= reach * reach and (bestSq == nil or dSq < bestSq) then
                    bestSq, bestSpline, bestT = dSq, spline, t
                end
            end
        end
    end
    return bestSpline, bestT
end

-- The way along the road to (x, z), coming from up to `length` metres back: along the nearest lane against its direction, then each lane that leads into
-- it, the straightest where several do. Each lane runs along the centre of one lane in the direction traffic takes. Returns the points { x, z } from the far
-- end to (x, z)'s lane, `step` metres apart, and the lane's direction there; nil when no lane is near.
function RseRoads.routeBack(x, z, length, step)
    local spline, t = nearestLane(x, z, RseConfig.CREW_LANE_REACH)
    if spline == nil then
        return nil
    end
    local points, remaining = {}, length
    local current, currentT, visited = spline, t, { [spline] = true }
    while remaining > 0 do
        local currentLength = getSplineLength(current)
        local dt = step / math.max(currentLength, step)
        local tt = currentT
        while tt >= 0 and remaining > 0 do
            local px, _, pz = getSplinePosition(current, tt)
            table.insert(points, { x = px, z = pz })
            tt = tt - dt
            remaining = remaining - step
        end
        if remaining <= 0 then
            break
        end
        local sx, _, sz = getSplinePosition(current, 0)
        local sdx, _, sdz = getSplineDirection(current, 0)
        local best, bestScore = nil, nil
        for _, lane in ipairs(laneEnds()) do
            if not visited[lane.spline] and (lane.x - sx) ^ 2 + (lane.z - sz) ^ 2 <= JOIN * JOIN then
                local score = lane.dirX * sdx + lane.dirZ * sdz
                if score > TURN_LIMIT and (best == nil or score > bestScore) then
                    best, bestScore = lane, score
                end
            end
        end
        local bestT = 1
        if best == nil then
            -- no lane ends here: one that passes close by, anywhere along it, going the right way
            local bestSq = nil
            for _, other in ipairs(roadSplines()) do
                local otherLength = not visited[other] and entityExists(other) and getSplineLength(other) or 0
                if otherLength > 0 and isNear(other, otherLength, sx, sz, JOIN_ALONG) then
                    local steps = math.max(1, math.ceil(otherLength / RseConfig.ROAD_FINE_STEP))
                    for i = 0, steps do
                        local ot = i / steps
                        local ox, _, oz = getSplinePosition(other, ot)
                        local dSq = (ox - sx) ^ 2 + (oz - sz) ^ 2
                        if dSq <= JOIN_ALONG * JOIN_ALONG and (bestSq == nil or dSq < bestSq) then
                            local odx, _, odz = getSplineDirection(other, ot)
                            if odx * sdx + odz * sdz > TURN_LIMIT then
                                best, bestT, bestSq = { spline = other }, ot, dSq
                            end
                        end
                    end
                end
            end
        end
        if best == nil then
            break
        end
        visited[best.spline] = true
        current, currentT = best.spline, bestT
    end
    local route = {}
    for i = #points, 1, -1 do
        table.insert(route, points[i])
    end
    local dirX, _, dirZ = getSplineDirection(spline, t)
    return route, dirX, dirZ
end

-- how far the nearest lane centre is from (x, z), within reach (reach when none is nearer), for the crew truck to pull over away from the other lanes
function RseRoads.laneDistance(x, z, reach)
    local nearest = reach
    for _, segment in ipairs(RseRoads.around(x, z, reach).segments) do
        local ax, az, bx, bz = segment[1], segment[2], segment[3], segment[4]
        local abx, abz = bx - ax, bz - az
        local lengthSq = abx * abx + abz * abz
        local u = lengthSq > 0 and math.max(0, math.min(1, ((x - ax) * abx + (z - az) * abz) / lengthSq)) or 0
        local cx, cz = ax + abx * u, az + abz * u
        nearest = math.min(nearest, math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2))
    end
    return nearest
end
