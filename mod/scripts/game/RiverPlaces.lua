-- Roadside Emergencies: where a car can go into the water: shallow water beside a road, with a bank it can be pulled up (core/WaterRules.lua; Z's first test
-- car sat under a bank far too steep). The map is searched a little every frame after it loads, and nothing is saved: a map with no such place never gets this
-- call.

RseRiver = {
    places = {},
    triesLeft = nil, -- nil: not searching, nothing left to search
    counts = nil,
    chosen = nil, -- the place the call in the making will use
    last = nil    -- the last place used
}

local probe = {}

function probe:onWater(hitObjectId, _, y)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.y = y
        return false
    end
    return true
end

function probe:onBlock(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.hit = true
        return false
    end
    return true
end

local function terrainAt(x, z)
    return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
end

local function waterDepth(x, z)
    local ground = terrainAt(x, z)
    probe.y = nil
    raycastClosest(x, ground + RseConfig.WATER_RAY_START, z, 0, -1, 0, RseConfig.WATER_RAY_START * 2, "onWater", probe, CollisionFlag.WATER)
    return probe.y ~= nil and probe.y - ground or nil
end

-- a rock, a wall or a tree in the way of the pull
local function lineBlocked(x1, z1, x2, z2)
    local y1, y2 = terrainAt(x1, z1) + RseConfig.WATER_BANK_RAY, terrainAt(x2, z2) + RseConfig.WATER_BANK_RAY
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local length = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-6)
    probe.hit = false
    raycastClosest(x1, y1, z1, dx / length, dy / length, dz / length, length, "onBlock", probe,
        CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING + CollisionFlag.TREE)
    return probe.hit
end

-- one spot on the road: is there shallow water beside it, with a bank a car can come up?
local function lookFrom(self, spot)
    if spot == nil or (waterDepth(spot.x, spot.z) or 0) > 0 then
        return
    end
    local counts = self.counts
    counts.tried = counts.tried + 1
    local length = math.max(math.sqrt(spot.dirX ^ 2 + spot.dirZ ^ 2), 1e-6)
    local sideX, sideZ = spot.dirZ / length, -spot.dirX / length
    for _, away in ipairs(RseConfig.WATER_AWAY) do
        for _, side in ipairs({ 1, -1 }) do
            local x, z = spot.x + sideX * side * away, spot.z + sideZ * side * away
            local depth = waterDepth(x, z)
            if depth ~= nil and depth >= RseConfig.WATER_DEPTH[1] and depth <= RseConfig.WATER_DEPTH[2] then
                local toX, toZ = -sideX * side, -sideZ * side
                local verdict = RseWaterRules.bank(x, z, toX, toZ, away, terrainAt(x, z) + depth, terrainAt, lineBlocked, RseConfig)
                counts[verdict] = counts[verdict] + 1
                if verdict == "ok" then
                    -- its nose in the water, as if it had just come off the road
                    RseWaterRules.addPlace(self.places, { x = x, z = z, depth = depth, away = away, yaw = math.atan2(-toX, -toZ) }, RseConfig.WATER_PLACE_GAP)
                end
            end
        end
    end
end

function RseRiver:reset()
    self.places, self.counts = {}, { tried = 0, ok = 0, steep = 0, noDry = 0, blocked = 0 }
    self.triesLeft, self.chosen, self.last = RseConfig.WATER_SCAN_TRIES, nil, nil
end

-- every frame, until the map has been searched
function RseRiver:update()
    if self.triesLeft == nil then
        return
    end
    local function search()
        for _ = 1, math.min(RseConfig.WATER_SCAN_PER_FRAME, self.triesLeft) do
            lookFrom(self, RseRoads.randomSpot({}, nil, true))
        end
    end
    if not RseLog.try("look for water", search) then
        self.triesLeft = nil -- once in the log; this map just doesn't get the call
        return
    end
    self.triesLeft = self.triesLeft - RseConfig.WATER_SCAN_PER_FRAME
    if self.triesLeft <= 0 then
        self.triesLeft = nil
        local counts = self.counts
        RseLog.info("river: %d place(s) for a car in the water, from %d road spots (%d too steep, %d with no dry land in reach, %d blocked)", #self.places,
            counts.tried, counts.steep, counts.noDry, counts.blocked)
    end
end

function RseRiver:canOffer()
    return self.triesLeft == nil and #self.places > 0
end

-- the place for the call being laid out, as a spot the emergency can stand on
function RseRiver:pickSpot()
    local near = RseScenes.spotNear
    RseScenes.spotNear = nil
    local player = nil
    if g_localPlayer ~= nil then
        local x, _, z = g_localPlayer:getPosition()
        player = { x = x, z = z }
    end
    local place = RseWaterRules.choose(self.places, self.last, near, player, RseConfig, math.random)
    self.chosen = place
    if place == nil then
        return nil
    end
    self.last = { x = place.x, z = place.z }
    RseLog.info("river: the car goes in at %.0f, %.0f, %.1f m deep, %d m from the lane", place.x, place.z, place.depth, place.away)
    return { x = place.x, y = terrainAt(place.x, place.z), z = place.z, dirX = 1, dirY = 0, dirZ = 0 }
end

-- the place pickSpot chose, once
function RseRiver:takeChosen()
    local place = self.chosen
    self.chosen = nil
    return place
end

-- a saved job has come back: the next call goes somewhere else
function RseRiver:noteLast(x, z)
    self.last = { x = x, z = z }
end
