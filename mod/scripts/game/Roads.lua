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

-- Logs what the traffic system stops for (0.2.0.8 found these fields on it): compare with the items' collision groups.
function RseRoads.logTrafficNames()
    local system = g_currentMission ~= nil and g_currentMission.trafficSystem or nil
    if type(system) ~= "table" then
        return
    end
    local function hex(value)
        return type(value) == "number" and string.format("0x%x", value) or tostring(value)
    end
    RseLog.info("traffic collision masks: stop %s, playerStop %s, ignore %s, ground %s", hex(system.stopMask), hex(system.playerStopMask),
        hex(system.ignoreMask), hex(system.groundMask))
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
