-- Roadside Emergencies: a flock on the road, to drive into a pen (core/FlockRules.lua). The animals are the loose ones of Survivors.lua, with their walk, their
-- ground and their hidden cones, but they move as a flock. The pen is a ring of hurdles the farmer has put up nearby, with the farmer's truck off to one side:
-- something you can see from the road. Where the sheep are out and where the pen stands come from FlockPlaces.lua: open country, and a meadow for the pen.

RseFlock = {
    nextMarker = 0
}

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

local function terrainAt(x, z)
    return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
end

function RseFlock:onRay(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.rayHit = true
        return false
    end
    return true
end

local function hurdleFile()
    for _, item in ipairs(RseConfig.KIT_ITEMS) do
        if item.id == RseConfig.FLOCK_HURDLE then
            return item.file
        end
    end
    return nil
end

-- one hurdle standing at (x, z), its length along `yaw`: { node, sharedId }, or nil
local function loadHurdle(file, x, z, yaw)
    local filename = Utils.getFilename(file, RoadsideEmergencies.MOD_DIR)
    local ok, node, sharedId = RseLog.try("load a hurdle", g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or node == nil or node == 0 then
        return nil
    end
    link(getRootNode(), node)
    setWorldTranslation(node, x, terrainAt(x, z), z)
    setWorldRotation(node, 0, yaw, 0)
    addToPhysics(node)
    return { node = node, sharedId = sharedId }
end

local function placeHurdles(flock, pieces)
    local file = hurdleFile()
    flock.hurdles = flock.hurdles or {}
    if file == nil then
        return
    end
    for _, piece in ipairs(pieces) do
        local hurdle = loadHurdle(file, piece.x, piece.z, piece.yaw)
        if hurdle ~= nil then
            table.insert(flock.hurdles, hurdle)
        end
    end
end

local function deleteHurdle(hurdle)
    if nodeExists(hurdle.node) then
        delete(hurdle.node)
    end
    if hurdle.sharedId ~= nil then
        g_i3DManager:releaseSharedI3DFile(hurdle.sharedId)
    end
end

local function removeHurdles(flock)
    for _, hurdle in ipairs(flock.hurdles or {}) do
        deleteHurdle(hurdle)
    end
    flock.hurdles = {}
    if flock.probe ~= nil then
        deleteHurdle(flock.probe)
        flock.probe = nil
    end
end

-- How long a hurdle really is, in metres, or nil: rays straight down onto it along its length, out from its middle each way until they miss. The game has
-- no call that gives an object's size, and the ring has gaps if this is wrong (Z).
local function measureHurdle(node)
    local x, y, z = getWorldTranslation(node)
    local dirX, _, dirZ = localDirectionToWorld(node, 1, 0, 0)
    local total = 0
    for _, side in ipairs({ 1, -1 }) do
        local reach = 0
        local along = RseConfig.FLOCK_HURDLE_STEP
        while along <= RseConfig.FLOCK_HURDLE_REACH do
            RseFlock.rayHit = false
            raycastClosest(x + dirX * side * along, y + 3, z + dirZ * side * along, 0, -1, 0, 3.5, "onRay", RseFlock, CollisionFlag.STATIC_OBJECT)
            if RseFlock.rayHit then
                reach = along
            end
            along = along + RseConfig.FLOCK_HURDLE_STEP
        end
        if reach == 0 or reach >= RseConfig.FLOCK_HURDLE_REACH - RseConfig.FLOCK_HURDLE_STEP then
            return nil -- nothing there, or something else under it as well
        end
        total = total + reach
    end
    return total
end

-- The hurdle put up in the middle of the first pen, measured once it is in the world: if the ring was spaced for the wrong length, it goes up again (the
-- pen is far from the road, and this is a second after the call). Every later pen this session is spaced right from the start.
local function checkHurdles(flock)
    local probe = flock.probe
    local length = nodeExists(probe.node) and measureHurdle(probe.node) or nil
    deleteHurdle(probe)
    flock.probe = nil
    if length == nil then
        RseLog.info("flock: a hurdle couldn't be measured, so they stand %.2f m apart", flock.hurdleLength * RseConfig.FLOCK_HURDLE_SHARE)
        return
    end
    RseFlock.hurdleLength = length
    local redo = math.abs(length - flock.hurdleLength) > RseConfig.FLOCK_HURDLE_REDO and not flock.parked
    RseLog.info("flock: a hurdle is %.2f m long%s", length, redo and ", so the pen goes up again with the right spacing" or "")
    if redo then
        removeHurdles(flock)
        flock.hurdleLength = length
        placeHurdles(flock, RseFlockRules.penPieces(flock.pen, RseConfig, length))
    end
end

local function newFlock(scene, total, penPlace)
    local pen = RseFlockRules.newPen(penPlace.x, penPlace.z, penPlace.gateYaw, RseConfig)
    local flock = { total = total, pen = pen, bleatMs = 0, world = { animals = {}, pen = pen, obstacles = {}, inPen = 0, cx = scene.x, cz = scene.z },
        hurdleLength = RseFlock.hurdleLength or RseConfig.FLOCK_HURDLE_LENGTH }
    scene.flock = flock
    RseLog.try("put up the pen", placeHurdles, flock, RseFlockRules.penPieces(pen, RseConfig, flock.hurdleLength))
    local file = hurdleFile()
    if RseFlock.hurdleLength == nil and file ~= nil then
        -- one more in the middle of the pen, alone, to measure (checkHurdles)
        local ok, probe = RseLog.try("put up a hurdle to measure", loadHurdle, file, pen.x, pen.z, 0)
        flock.probe, flock.probeMs = ok and probe or nil, RseConfig.FLOCK_HURDLE_MEASURE_MS
    end
    RseMarkers:show(flock.pen, pen.x, pen.z, { name = RseText.get("rse_flock_pen"), image = "flockPen", steady = true,
        info = { kind = "flockPen", title = RseText.get("rse_flock_pen"), image = RseMarkers.imagePath("flockPen") } })
    return flock
end

-- Lays out a new flock around the scene. penPlace: from RseFlockPlaces:takePen. Returns how many animals it has.
function RseFlock:spawn(scene, road, kind, count, penPlace)
    local flock = newFlock(scene, count, penPlace)
    flock.kind = kind
    local dirX, dirZ = road.dirX or 1, road.dirZ or 0
    local length = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-6)
    dirX, dirZ = dirX / length, dirZ / length
    for _, group in ipairs(RseFlockRules.startGroups(count, RseConfig, math.random)) do
        -- a bunch stays where the way to it from the scene is open, closer in if it has to be, so all of them can always be reached
        local x, z = scene.x, scene.z
        for _, share in ipairs({ 1, 0.6, 0.3 }) do
            local tryX, tryZ = scene.x + dirX * group.along * share, scene.z + dirZ * group.along * share
            if group.along == 0 or RseFlockPlaces.isOpenWay(scene.x, scene.z, tryX, tryZ) then
                x, z = tryX, tryZ
                break
            end
        end
        local spots = RseSceneSpec.scatter(group.count, x, z, dirX, dirZ, { span = RseConfig.FLOCK_SPAN, width = RseConfig.FLOCK_WIDTH,
            gap = RseConfig.FLOCK_GAP, maxRoadDistance = RseConfig.CLEAR_DISTANCE + 2 }, math.random, road.segments)
        for _, spot in ipairs(spots) do
            spot.y = terrainAt(spot.x, spot.z)
            if scene.y ~= nil and scene.y - spot.y > RseConfig.BRIDGE_HEIGHT then
                spot.y = scene.y
            end
            spot.lamb = math.random() < RseConfig.FLOCK_LAMB_CHANCE
        end
        RseSurvivors:spawn(scene, kind, spots, true)
    end
    flock.total = RseSurvivors:remaining(scene)
    return flock.total
end

-- a saved job: the pen goes back up, and the animals back where they were
function RseFlock:restore(scene, data, animals)
    local flock = newFlock(scene, data.total, { x = data.x, z = data.z, gateYaw = data.gateYaw })
    flock.kind = animals[1] ~= nil and animals[1].kind or nil
    for _, animal in ipairs(animals) do
        RseSurvivors:spawn(scene, animal.kind, { animal }, true)
    end
end

function RseFlock:saveData(scene)
    local flock = scene.flock
    if flock == nil then
        return nil
    end
    return { total = flock.total, x = flock.pen.x, z = flock.pen.z, gateYaw = flock.pen.gateYaw }
end

function RseFlock:pennedCount(scene)
    local count = 0
    for _, animal in ipairs(scene.survivors or {}) do
        if animal.penned then
            count = count + 1
        end
    end
    return count
end

function RseFlock:share(scene)
    return RseFlockRules.share(self:pennedCount(scene), scene.flock.total)
end

function RseFlock:isDone(scene)
    local flock = scene.flock
    return flock ~= nil and flock.total > 0 and self:pennedCount(scene) >= flock.total
end

local function bleat(flock, x, y, z, pressing, dt)
    flock.bleatMs = flock.bleatMs - dt
    if flock.bleatMs > 0 then
        return
    end
    local range = RseConfig.FLOCK_BLEAT_MS
    flock.bleatMs = range[1] + math.random() * (range[2] - range[1]) * (pressing and 0.4 or 1)
    local files = RseConfig.FLOCK_BLEATS
    RseSound:play(files[math.random(#files)], x, y, z, RseConfig.FLOCK_BLEAT_RANGE, RseConfig.FLOCK_BLEAT_VOLUME)
end

local function isHonking()
    local vehicle = g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or nil
    local honk = vehicle ~= nil and vehicle.spec_honk or nil
    return honk ~= nil and honk.isPlaying == true
end

-- the farmer's truck, where it really stands: they walk around that before they get there
local function placeTruck(scene, world)
    local vehicle = scene.wreck ~= nil and scene.wreck.vehicle or nil
    if vehicle == nil or vehicle.rootNode == nil or vehicle.isDeleted then
        world.obstacles = {}
        return
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local length = vehicle.size ~= nil and vehicle.size.length or 6
    world.obstacles = { { x = x, z = z, radius = length / 2 + RseConfig.FLOCK_TRUCK_MARGIN } }
end

-- every frame, before the animals move
function RseFlock:think(scene, dt, px, pz, onFoot)
    local flock = scene.flock
    local world = flock.world
    local animals = scene.survivors or {}
    if flock.probe ~= nil then
        flock.probeMs = flock.probeMs - dt
        if flock.probeMs <= 0 and not RseLog.try("measure a hurdle", checkHurdles, flock) and flock.probe ~= nil then
            deleteHurdle(flock.probe)
            flock.probe = nil
        end
    end
    if flock.parked then
        RseFlockRules.think(world, animals, nil, dt, RseConfig)
        return
    end
    local player, speed = nil, 0
    if px ~= nil then
        if flock.lastX ~= nil and dt > 0 then
            speed = math.sqrt((px - flock.lastX) ^ 2 + (pz - flock.lastZ) ^ 2) / (dt / 1000)
            speed = speed <= RseConfig.FLOCK_SPEED_SANE and speed or 0
        end
        flock.lastX, flock.lastZ = px, pz
        player = { x = px, z = pz, onFoot = onFoot, speed = speed, horn = isHonking() }
    end
    if RseFlockRules.think(world, animals, player, dt, RseConfig) == 0 then
        return
    end
    local inPen = world.inPen
    if flock.penned == nil then
        -- just laid out, or back from a save: nothing to say yet
        flock.penned, flock.toldHalf = inPen, inPen >= flock.total * RseConfig.FLOCK_HALF
    elseif inPen ~= flock.penned then
        flock.penned = inPen
        if inPen == flock.total - 1 and flock.total > 1 then
            RseText.notify(RseText.get("rse_flock_oneLeft"))
        elseif inPen >= flock.total * RseConfig.FLOCK_HALF and not flock.toldHalf then
            flock.toldHalf = true
            RseText.notify(RseText.get("rse_flock_half"))
        end
    end
    if world.scattered and not flock.toldScattered then
        flock.toldScattered = true
        RseText.notify(RseText.get("rse_flock_scattered"), true)
    end
    if world.scatteredByHorn and not flock.toldHorn then
        flock.toldHorn = true
        RseText.notify(RseText.get("rse_flock_hornScared"), true)
    end
    local cx, cz = world.cx, world.cz
    local nearest = px ~= nil and RseFlockRules.nearest(animals, px, pz) or nil
    if px ~= nil and (cx - px) ^ 2 + (cz - pz) ^ 2 <= RseConfig.FLOCK_BLEAT_RANGE ^ 2 then
        bleat(flock, cx, terrainAt(cx, cz) + 1, cz, RseFlockRules.pressure(nearest, onFoot, RseConfig) > 0, dt)
    end
    self.nextMarker = self.nextMarker - dt
    if self.nextMarker <= 0 then
        self.nextMarker = RseConfig.FLOCK_MARKER_MS
        placeTruck(scene, world)
        -- the map marker is on the biggest bunch; a pin in the world stands over each of the others (Survivors.lua)
        local main = RseFlockRules.markGroups(world, animals, RseConfig)[1]
        if main ~= nil then
            cx, cz = main.x, main.z
        end
        local title = RseText.get("rse_flock_marker")
        local image = flock.kind ~= nil and RseCarcasses.liveImage(RseAnimalCatalog.get(flock.kind).subType) or nil
        RseMarkers:show(flock, cx, cz, { name = title, image = "loose",
            info = { kind = "loose", title = title, y = terrainAt(cx, cz), image = image or RseMarkers.imagePath("loose") } })
    end
end

-- a hidden cone stops traffic for it only near a lane, and away from the road there is no need to keep making new ones for a flock on the move. A long list of
-- lanes to go through, so not at every look.
function RseFlock:nearRoad(animal)
    animal.roadLooks = (animal.roadLooks or 0) - 1
    if animal.isNearRoad == nil or animal.roadLooks <= 0 then
        animal.roadLooks = RseConfig.FLOCK_ROAD_LOOKS
        local distance = RseRoadClearRule.distanceToRoad(animal.x, animal.z, animal.scene.segments)
        animal.isNearRoad = distance == nil or distance <= RseConfig.FLOCK_BLOCKER_ROAD
    end
    return animal.isNearRoad
end

-- they are all in: the farmer shuts the gap with the last of the hurdles (Z)
function RseFlock:closeGate(scene)
    local flock = scene.flock
    if flock ~= nil then
        placeHurdles(flock, RseFlockRules.gatePieces(flock.pen, RseConfig, flock.hurdleLength))
    end
end

-- one that has been stuck for a long time joins the others again, when you aren't right there to see it
function RseFlock:rejoin(animal)
    local world = animal.scene.flock.world
    local px, pz = world.playerX, world.playerZ
    if px ~= nil and (animal.x - px) ^ 2 + (animal.z - pz) ^ 2 < RseConfig.FLOCK_UNSEEN ^ 2 then
        return
    end
    local angle = math.random() * 2 * math.pi
    animal.x, animal.z = world.cx + math.sin(angle) * RseConfig.FLOCK_TIGHT * 0.5, world.cz + math.cos(angle) * RseConfig.FLOCK_TIGHT * 0.5
    -- on the ground of the nearest one already there: up on a bridge with them, not under it
    local nearest, best = nil, math.huge
    for _, other in ipairs(animal.scene.survivors or {}) do
        local gap = (other.x - animal.x) ^ 2 + (other.z - animal.z) ^ 2
        if other ~= animal and not other.penned and gap < best then
            nearest, best = other, gap
        end
    end
    if nearest ~= nil then
        RseSurvivors.standLike(animal, nearest)
    end
    animal.blocked = false
    RseLog.debug("flock: one that was stuck has rejoined the others")
end

-- The job is over: the pen and the flock stay until you have gone, and the farmer sees to them (Cleanup.lua; the sheep go with RseSurvivors:leaveBehind).
-- Those not in the pen graze where they stand.
function RseFlock:leaveBehind(scene, item)
    local flock = scene.flock
    if flock == nil then
        return
    end
    flock.parked = true
    RseMarkers:hide(flock)
    RseMarkers:hide(flock.pen)
    for _, animal in ipairs(scene.survivors or {}) do
        if not animal.penned then
            animal.parkedAt = { x = animal.x, z = animal.z }
        end
    end
    table.insert(item.extras, function()
        removeHurdles(flock)
    end)
end

-- the job was abandoned: the animals go with RseSurvivors:remove, this is the rest
function RseFlock:remove(scene)
    local flock = scene.flock
    if flock == nil then
        return
    end
    RseMarkers:hide(flock)
    RseMarkers:hide(flock.pen)
    removeHurdles(flock)
end
