-- Roadside Emergencies: where a flock call can happen. Z found the pen on the railroad tracks in a grain yard, and before that the sheep in a fenced lane
-- behind the shop: a call has to look like somewhere a farmer's sheep really got out, with a meadow nearby for the pen. As the map loads, road spots are
-- looked at a few a frame (as RiverPlaces.lua does for water), and a call only ever comes from a place that passed:
--   the start: open country round each bunch, no town, yard or station (RseGroundRules.isCountry); nothing hemming them in; the railroad well away;
--   the pen: on grass or a grass field (RseGroundRules.isPasture) with nothing built underfoot, open country round it, not in the woods, flat and dry, clear
--   of every lane and of the railroad, a clear way to it from the road that doesn't cross the tracks, and room for the farmer's truck.
-- Nothing is saved. A map with no such place never gets this call.

RseFlockPlaces = {
    places = {},
    triesLeft = nil, -- nil: not searching, nothing left to search
    counts = nil,
    rails = nil,     -- the railroad as segments { ax, az, bx, bz }, read when the search starts
    look = nil,      -- the road spot whose pen is being looked for, a few candidates a frame
    fieldData = nil, -- where the game keeps its field ground: { mapId, first, count }, or false if it has none
    chosen = nil,    -- the place the call being laid out uses
    last = nil       -- the last place used
}

local probe = {}

function probe:onHit(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.hit = true
        return false
    end
    return true
end

local function terrainAt(x, z)
    return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
end

local function newCounts()
    return { tried = 0, near = 0, rails = 0, town = 0, wet = 0, hemmed = 0, noPen = 0, seen = {}, pens = {} }
end

local function isWet(x, z)
    local ground = terrainAt(x, z)
    probe.hit = false
    raycastClosest(x, ground + RseConfig.WATER_RAY_START, z, 0, -1, 0, RseConfig.WATER_RAY_START - RseConfig.FLOCK_WET_DEPTH, "onHit", probe,
        CollisionFlag.WATER)
    return probe.hit
end

-- a wall, a fence, a tree, a building or a vehicle on the straight line between two points
local function isBlockedLine(x1, z1, x2, z2)
    local y1, y2 = terrainAt(x1, z1) + RseConfig.FLOCK_RAY_HEIGHT, terrainAt(x2, z2) + RseConfig.FLOCK_RAY_HEIGHT
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local length = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-6)
    probe.hit = false
    raycastClosest(x1, y1, z1, dx / length, dy / length, dz / length, length, "onHit", probe,
        CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING + CollisionFlag.TREE + CollisionFlag.VEHICLE)
    return probe.hit
end

-- a tree on the straight line from (x1, z1) to (x2, z2), and nothing else counts
local function isTreeLine(x1, z1, x2, z2)
    local y1, y2 = terrainAt(x1, z1) + RseConfig.FLOCK_RAY_HEIGHT, terrainAt(x2, z2) + RseConfig.FLOCK_RAY_HEIGHT
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local length = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-6)
    probe.hit = false
    raycastClosest(x1, y1, z1, dx / length, dy / length, dz / length, length, "onHit", probe, CollisionFlag.TREE)
    return probe.hit
end

-- something built lying on the ground at (x, z): rails, a slab, a platform, a road
local function isBuiltOver(x, z)
    local ground = terrainAt(x, z)
    probe.hit = false
    raycastClosest(x, ground + RseConfig.GROUND_RAY_START, z, 0, -1, 0, RseConfig.GROUND_RAY_START + RseConfig.GROUND_RAY_BELOW, "onHit", probe,
        CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING + CollisionFlag.ROAD)
    return probe.hit
end

-- walkable from (x1, z1) to (x2, z2): not too steep at any step, no water, nothing solid
function RseFlockPlaces.isOpenWay(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    local length = math.sqrt(dx * dx + dz * dz)
    local steps = math.max(1, math.floor(length / RseConfig.FLOCK_PATH_STEP))
    local last = terrainAt(x1, z1)
    for i = 1, steps do
        local x, z = x1 + dx * i / steps, z1 + dz * i / steps
        local height = terrainAt(x, z)
        if math.abs(height - last) > RseConfig.FLOCK_PATH_RISE or isWet(x, z) then
            return false
        end
        last = height
    end
    return not isBlockedLine(x1, z1, x2, z2)
end
local isOpenWay = RseFlockPlaces.isOpenWay

-- the field at a point, as the wheels read it (WheelPhysics, the game's field ground map): "meadow" for grass, "crop" for any other field, nil off a field
local function fieldAt(self, x, y, z)
    if self.fieldData == nil then
        self.fieldData = false
        local system = g_currentMission.fieldGroundSystem
        if system ~= nil and FieldDensityMap ~= nil and FieldGroundType ~= nil and FieldGroundType.getTypeByValue ~= nil then
            local mapId, first, count = system:getDensityMapData(FieldDensityMap.GROUND_TYPE)
            if mapId ~= nil and first ~= nil and count ~= nil then
                self.fieldData = { mapId = mapId, first = first, count = count }
            end
        end
    end
    local data = self.fieldData
    if not data then
        return nil
    end
    local bits = getDensityAtWorldPos(data.mapId, x, y, z)
    local kind = FieldGroundType.getTypeByValue(bit32.band(bit32.rshift(bits, data.first), 2 ^ data.count - 1))
    if kind == nil or kind == FieldGroundType.NONE then
        return nil
    elseif kind == FieldGroundType.GRASS or kind == FieldGroundType.GRASS_CUT then
        return "meadow"
    end
    return "crop"
end

-- the field at (x, z), for other scenes too: "meadow", "crop", or nil off any field (PowerLine.lua: no pole on farmland, Z)
function RseFlockPlaces:fieldKind(x, z)
    return fieldAt(self, x, terrainAt(x, z), z)
end

-- The kind of ground at (x, z) (RseGroundRules): the map's own surface number there, as a horse's hooves read it (Rideable), and the field.
local function groundAt(self, x, z)
    local y = terrainAt(x, z)
    local _, _, _, _, material = getTerrainAttributesAtWorldPos(g_terrainNode, x, y, z, true, true, true, true, false)
    local kind = RseGroundRules.kind(material, fieldAt(self, x, y, z), RseConfig)
    local seen = self.counts.seen
    seen[kind] = (seen[kind] or 0) + 1
    return kind
end

-- the railroad, as short straight pieces
local function readRails()
    local segments = {}
    local system = g_currentMission.placeableSystem
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local spline = placeable.spec_trainSystem ~= nil and placeable.getSpline ~= nil and placeable:getSpline() or nil
        if spline ~= nil and entityExists(spline) then
            local steps = math.max(1, math.ceil(getSplineLength(spline) / RseConfig.FLOCK_RAIL_STEP))
            local px, _, pz = getSplinePosition(spline, 0)
            for i = 1, steps do
                local qx, _, qz = getSplinePosition(spline, i / steps)
                table.insert(segments, { px, pz, qx, qz })
                px, pz = qx, qz
            end
        end
    end
    return segments
end

local function isRailClear(self, x, z)
    local distance = RseRoadClearRule.distanceToRoad(x, z, self.rails)
    return distance == nil or distance >= RseConfig.FLOCK_RAIL_CLEAR
end

-- At a glance, no rays: is the ground either side of the road at each bunch open country, and the railroad well away? Returns nil, or why not.
local function glance(self, x, z, dirX, dirZ)
    local kinds = {}
    for _, along in ipairs({ 0, RseConfig.FLOCK_GROUP_APART, -RseConfig.FLOCK_GROUP_APART }) do
        local bunchX, bunchZ = x + dirX * along, z + dirZ * along
        if not isRailClear(self, bunchX, bunchZ) then
            return "rails"
        end
        for _, away in ipairs(RseConfig.FLOCK_COUNTRY_AWAY) do
            for _, side in ipairs({ 1, -1 }) do
                table.insert(kinds, groundAt(self, bunchX + dirZ * side * away, bunchZ - dirX * side * away))
            end
        end
    end
    if RseGroundRules.isCountry(kinds, RseConfig) then
        return nil
    end
    return "town"
end

-- how many of FLOCK_START_RAYS ways out from (x, z) meet something solid within FLOCK_START_REACH
local function blockedAround(x, z)
    local count, reach = 0, RseConfig.FLOCK_START_REACH
    for i = 0, RseConfig.FLOCK_START_RAYS - 1 do
        local angle = i * 2 * math.pi / RseConfig.FLOCK_START_RAYS
        if isBlockedLine(x, z, x + math.sin(angle) * reach, z + math.cos(angle) * reach) then
            count = count + 1
        end
    end
    return count
end

-- Where each bunch stands from this road spot, as spawn does it: along the road, closer in if the way there is shut. Each has to be dry, open (no fenced
-- lane or yard to get stuck in: Z, behind the shop) and away from the railroad. Returns the places, or nil and why not.
local function startPlaces(self, x, z, dirX, dirZ)
    local bunches = {}
    for _, along in ipairs({ 0, RseConfig.FLOCK_GROUP_APART, -RseConfig.FLOCK_GROUP_APART }) do
        local bunchX, bunchZ = x, z
        for _, share in ipairs({ 1, 0.6, 0.3 }) do
            local tryX, tryZ = x + dirX * along * share, z + dirZ * along * share
            if along == 0 or isOpenWay(x, z, tryX, tryZ) then
                bunchX, bunchZ = tryX, tryZ
                break
            end
        end
        if not isRailClear(self, bunchX, bunchZ) then
            return nil, "rails"
        end
        if isWet(bunchX, bunchZ) then
            return nil, "wet"
        end
        if blockedAround(bunchX, bunchZ) > RseConfig.FLOCK_START_BLOCKED then
            return nil, "hemmed"
        end
        table.insert(bunches, { x = bunchX, z = bunchZ })
    end
    return bunches
end

-- The points of a pen that have to be on grass: its middle, round its ring, where the truck stands and the room in front of the gate.
local function penPoints(pen, truck, gateYaw)
    local points = { { x = pen.x, z = pen.z }, { x = truck.x, z = truck.z } }
    for _, p in ipairs(RseGroundRules.ring(pen.x, pen.z, { pen.radius + 2 }, 8)) do
        table.insert(points, p)
    end
    for _, share in ipairs({ 0.5, 1 }) do
        local room = RseConfig.FLOCK_GATE_ROOM * share
        table.insert(points, { x = pen.gateX + math.sin(gateYaw) * room, z = pen.gateZ + math.cos(gateYaw) * room })
    end
    return points
end

-- Is this a pen a farmer would really put up? Cheap looks first, rays last. Returns the kinds of ground under it, or nil and why not.
local function judgePen(self, candidate, sceneX, sceneZ, segments, bunches)
    local pen = RseFlockRules.newPen(candidate.x, candidate.z, candidate.gateYaw, RseConfig)
    local fromRoad = RseRoadClearRule.distanceToRoad(pen.x, pen.z, segments)
    if fromRoad ~= nil and fromRoad < pen.radius + RseConfig.FLOCK_PEN_ROAD then
        return nil, "road"
    end
    if not isRailClear(self, pen.x, pen.z) then
        return nil, "rails"
    end
    for _, bunch in ipairs(bunches) do
        if RseGroundRules.crosses(bunch.x, bunch.z, pen.gateX, pen.gateZ, self.rails) then
            return nil, "rails"
        end
    end
    local truck = RseFlockRules.truckSpot(pen, RseConfig)
    local truckFromRoad = RseRoadClearRule.distanceToRoad(truck.x, truck.z, segments)
    if truckFromRoad ~= nil and truckFromRoad < RseConfig.FLOCK_TRUCK_ROAD then
        return nil, "road"
    end
    -- the ground under it: grass
    local points = penPoints(pen, truck, candidate.gateYaw)
    local kinds = {}
    for _, p in ipairs(points) do
        table.insert(kinds, groundAt(self, p.x, p.z))
    end
    local isPasture, spoiler = RseGroundRules.isPasture(kinds, RseConfig)
    if not isPasture then
        return nil, "on " .. tostring(spoiler)
    end
    -- the ground round it: open country, the road itself left out
    local around = {}
    for _, p in ipairs(RseGroundRules.ring(pen.x, pen.z, RseConfig.FLOCK_PEN_AROUND, RseConfig.FLOCK_PEN_AROUND_WAYS)) do
        local kind = groundAt(self, p.x, p.z)
        local onRoad = RseGroundRules.isBuilt(kind) and (RseRoadClearRule.distanceToRoad(p.x, p.z, segments) or math.huge) < RseConfig.GROUND_ROAD_SKIP
        if not onRoad then
            table.insert(around, kind)
        end
    end
    if not RseGroundRules.isCountry(around, RseConfig) then
        return nil, "built up round it"
    end
    -- flat and dry
    local middle = terrainAt(pen.x, pen.z)
    for _, p in ipairs(points) do
        if math.abs(terrainAt(p.x, p.z) - middle) > RseConfig.FLOCK_PEN_RISE then
            return nil, "slope"
        end
    end
    for _, p in ipairs(points) do
        if isWet(p.x, p.z) then
            return nil, "wet"
        end
    end
    -- nothing built underfoot, nothing in the ring, and the truck can stand there
    for _, p in ipairs(points) do
        if isBuiltOver(p.x, p.z) then
            return nil, "something built underfoot"
        end
    end
    for i = 0, 7 do
        local angle = i * math.pi / 4
        if isBlockedLine(pen.x, pen.z, pen.x + math.sin(angle) * (pen.radius + 2), pen.z + math.cos(angle) * (pen.radius + 2)) then
            return nil, "blocked"
        end
    end
    if isBlockedLine(pen.x, pen.z, truck.x, truck.z) then
        return nil, "blocked"
    end
    -- not in the woods: the maps give the forest floor the same number as grass, so the trees tell
    local trees = 0
    for _, p in ipairs(RseGroundRules.ring(pen.x, pen.z, { RseConfig.FLOCK_PEN_WOODS }, RseConfig.FLOCK_PEN_AROUND_WAYS)) do
        if isTreeLine(pen.x, pen.z, p.x, p.z) then
            trees = trees + 1
        end
    end
    if trees > RseConfig.FLOCK_PEN_TREES then
        return nil, "woods"
    end
    -- the way from the road to the gate, wide enough for a flock, and room in front of the gate to line them up
    local width = RseConfig.FLOCK_PATH_WIDTH
    local pathX, pathZ = pen.gateX - sceneX, pen.gateZ - sceneZ
    local pathLength = math.max(math.sqrt(pathX * pathX + pathZ * pathZ), 1e-6)
    local sideX, sideZ = pathZ / pathLength, -pathX / pathLength
    for _, offset in ipairs({ 0, -width, width }) do
        if not isOpenWay(sceneX + sideX * offset, sceneZ + sideZ * offset, pen.gateX + sideX * offset, pen.gateZ + sideZ * offset) then
            return nil, "no way there"
        end
    end
    local room = RseConfig.FLOCK_GATE_ROOM
    if not isOpenWay(pen.gateX, pen.gateZ, pen.gateX + math.sin(candidate.gateYaw) * room, pen.gateZ + math.cos(candidate.gateYaw) * room) then
        return nil, "no way there"
    end
    return kinds
end

-- One pen candidate from a look in progress { x, z, segments, bunches, candidates, index }: the candidate if it will do, with the ground under it
local function tryNextPen(self, look)
    local candidate = look.candidates[look.index]
    look.index = look.index + 1
    local kinds, why = judgePen(self, candidate, look.x, look.z, look.segments, look.bunches)
    if kinds ~= nil then
        candidate.ground = RseGroundRules.describe(RseGroundRules.tally(kinds))
        return candidate
    end
    self.counts.pens[why] = (self.counts.pens[why] or 0) + 1
    return nil
end

local function newLook(x, z, road, bunches)
    return { x = x, z = z, segments = road.segments, bunches = bunches, candidates = RseFlockRules.penCandidates(x, z, RseConfig, math.random), index = 1 }
end

-- a good place for the pen from (x, z) all at once: { x, z, gateYaw, ground }, or nil
local function findPen(self, x, z, road, bunches)
    local look = newLook(x, z, road, bunches)
    while look.index <= #look.candidates do
        local pen = tryNextPen(self, look)
        if pen ~= nil then
            return pen
        end
    end
    return nil
end

local function unitDirection(spot)
    local dirX, dirZ = spot.dirX or 1, spot.dirZ or 0
    local length = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-6)
    return dirX / length, dirZ / length
end

local function isNearPlace(self, x, z)
    for _, place in ipairs(self.places) do
        if (place.x - x) ^ 2 + (place.z - z) ^ 2 < RseConfig.FLOCK_PLACE_GAP ^ 2 then
            return true
        end
    end
    return false
end

-- One road spot: "glance" if it was turned down at a glance, "deep" if it took the rays. A spot that gets as far as the pen leaves its look in
-- self.look, for the next frames.
local function lookAt(self, spot)
    local counts = self.counts
    counts.tried = counts.tried + 1
    if isNearPlace(self, spot.x, spot.z) then
        counts.near = counts.near + 1
        return "glance"
    end
    local dirX, dirZ = unitDirection(spot)
    local why = glance(self, spot.x, spot.z, dirX, dirZ)
    if why ~= nil then
        counts[why] = counts[why] + 1
        return "glance"
    end
    local bunches
    bunches, why = startPlaces(self, spot.x, spot.z, dirX, dirZ)
    if bunches == nil then
        counts[why] = counts[why] + 1
        return "deep"
    end
    self.look = newLook(spot.x, spot.z, RseRoads.around(spot.x, spot.z, RseConfig.FLOCK_ROAD_RADIUS), bunches)
    self.look.spot, self.look.dirX, self.look.dirZ = spot, dirX, dirZ
    return "deep"
end

-- a few more of the pen candidates of the look in progress
local function goOnLooking(self)
    local look = self.look
    for _ = 1, RseConfig.FLOCK_SCAN_PENS_PER_FRAME do
        if look.index > #look.candidates then
            self.counts.noPen = self.counts.noPen + 1
            self.look = nil
            return
        end
        local pen = tryNextPen(self, look)
        if pen ~= nil then
            local spot = look.spot
            table.insert(self.places, { x = spot.x, y = spot.y, z = spot.z, dirX = look.dirX, dirZ = look.dirZ, pen = pen })
            self.look = nil
            return
        end
    end
end

function RseFlockPlaces:reset()
    self.places, self.counts, self.rails, self.fieldData, self.look = {}, newCounts(), nil, nil, nil
    self.triesLeft, self.chosen, self.last = RseConfig.FLOCK_SCAN_TRIES, nil, nil
end

-- every frame, until the map has been searched
function RseFlockPlaces:update()
    if self.triesLeft == nil then
        return
    end
    local function search()
        if self.rails == nil then
            self.rails = readRails()
        end
        if self.look ~= nil then
            goOnLooking(self) -- a few pens a frame: a town's roads make each one dear
            return
        end
        local looked = 0
        while looked < RseConfig.FLOCK_SCAN_PER_FRAME and self.triesLeft > 0 do
            looked = looked + 1
            self.triesLeft = self.triesLeft - 1
            local spot = RseRoads.randomSpot({}, nil, true)
            if spot ~= nil and lookAt(self, spot) == "deep" then
                break -- the rays: one of those a frame is enough
            end
        end
    end
    if not RseLog.try("look for places for a flock", search) then
        self.triesLeft, self.look = nil, nil -- once in the log; whatever was found still counts
        return
    end
    if self.look == nil and (self.triesLeft <= 0 or #self.places >= RseConfig.FLOCK_PLACES_MAX) then
        self.triesLeft = nil
        local counts = self.counts
        RseLog.info("flock: %d place(s) in open country, from %d road spots (%d near one already found, %d in a town or yard, %d by the railroad, %d wet, "
            .. "%d hemmed in, %d with no pen: %s); %d piece(s) of railroad; the ground looked at: %s", #self.places, counts.tried, counts.near, counts.town,
            counts.rails, counts.wet, counts.hemmed, counts.noPen, RseGroundRules.describe(counts.pens), #self.rails, RseGroundRules.describe(counts.seen))
    end
end

function RseFlockPlaces:canOffer()
    return self.triesLeft == nil and #self.places > 0
end

-- The place for the call being laid out, as a spot the emergency can stand on: near where it was asked for (rseHere) if it was, otherwise any but the
-- last one and any with a vehicle on it.
function RseFlockPlaces:pickSpot()
    local near = RseScenes.spotNear
    RseScenes.spotNear = nil
    self.chosen = nil
    local player = nil
    if g_localPlayer ~= nil then
        local x, _, z = g_localPlayer:getPosition()
        player = { x = x, z = z }
    end
    local keepOuts = {}
    for _, vehicle in ipairs(g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        if vehicle.rootNode ~= nil then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            table.insert(keepOuts, { x = x, z = z, radius = RseConfig.FLOCK_VEHICLE_CLEAR })
        end
    end
    local free = {}
    for _, place in ipairs(self.places) do
        if RseSpotRules.isFree(place.x, place.z, keepOuts) and RseSpotRules.isFree(place.pen.x, place.pen.z, keepOuts) then
            table.insert(free, place)
        end
    end
    -- the same choice as the river's
    local place = RseWaterRules.choose(#free > 0 and free or self.places, self.last, near, player, RseConfig, math.random)
    if place == nil then
        RseLog.info("flock: this map has no place for a flock")
        return nil
    end
    self.chosen, self.last = place, { x = place.x, z = place.z }
    RseLog.info("flock: the sheep are out at %.0f, %.0f; the pen goes up at %.0f, %.0f on %s", place.x, place.z, place.pen.x, place.pen.z, place.pen.ground)
    return { x = place.x, y = place.y, z = place.z, dirX = place.dirX, dirY = 0, dirZ = place.dirZ }
end

-- Where the pen goes for the call at (x, z): { x, z, gateYaw }. The one pickSpot chose, if the call is where it said; otherwise looked for here, and nil if
-- there is no meadow for it: then the call is called off. Never on the road.
function RseFlockPlaces:takePen(x, z, road)
    local chosen = self.chosen
    self.chosen = nil
    local pen
    if chosen ~= nil and (chosen.x - x) ^ 2 + (chosen.z - z) ^ 2 < 1 then
        pen = chosen.pen
    else
        self.counts = self.counts or newCounts()
        pen = findPen(self, x, z, road, { { x = x, z = z } })
    end
    if pen == nil then
        RseLog.info("flock: no meadow for a pen near %.0f, %.0f, so the call is called off", x, z)
        return nil
    end
    RseLog.info("flock: the pen is at %.0f, %.0f, %.0f m from the flock", pen.x, pen.z, math.sqrt((pen.x - x) ^ 2 + (pen.z - z) ^ 2))
    return pen
end

-- a saved job has come back: the next call goes somewhere else
function RseFlockPlaces:noteLast(x, z)
    self.last = { x = x, z = z }
end
