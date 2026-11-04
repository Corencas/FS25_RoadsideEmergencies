-- Roadside Emergencies: all carcasses in the world. Spawns them (hidden body + animal model), keeps each model on its
-- body every frame, removes them, and delivers the ones lying still at a disposal point (fee: Store, PayRules).
-- Server and singleplayer only for now (DESIGN §4: multiplayer later).

RseCarcasses = {
    entries = {},           -- list of entries; entry.id is the Store id
    showBodies = false,     -- rseCarcassBodies: show the hidden bodies (debug)
    usingFallbackBodies = false
}

-- The animal list gives model paths relative to the game folder ("dataS/..."); without a leading "$" they would be looked
-- up inside this mod's folder (P8).
local function gamePath(path)
    if type(path) ~= "string" or path:sub(1, 1) == "$" or path:sub(1, 1) == "/" or path:sub(2, 2) == ":" then
        return path
    end
    return "$" .. path
end

-- the models of the first livestock subtype whose name contains `pattern`: the animated one and the posed one (which livestock trailers show)
local function livestockModels(pattern)
    local system = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    if system == nil or system.getSubTypeByIndex == nil then
        return nil
    end
    for i = 1, 200 do
        local okS, subType = pcall(system.getSubTypeByIndex, system, i)
        if not okS or subType == nil then
            break
        end
        if string.find(string.upper(tostring(subType.name or "")), pattern, 1, true) ~= nil then
            local okV, visual = pcall(system.getVisualByAge, system, i, RseConfig.ADULT_AGE_MONTHS)
            local model = okV and type(visual) == "table" and visual.visualAnimal or nil
            if type(model) == "table" then
                return gamePath(model.filename), gamePath(model.filenamePosed or model.filename), visual
            end
        end
    end
    return nil
end

RseCarcasses.liveModels = livestockModels

-- the picture the game's animal dealer shows for this animal, or nil
function RseCarcasses.liveImage(pattern)
    local _, _, visual = livestockModels(pattern)
    local store = type(visual) == "table" and visual.store or nil
    if type(store) ~= "table" or type(store.imageFilename) ~= "string" then
        return nil
    end
    return Utils.getFilename(gamePath(store.imageFilename), RoadsideEmergencies.MOD_DIR) -- M4 round 5: an image path has to be resolved, like a model path
end

local function modelFile(def)
    if def.subType ~= nil then
        local _, posed = livestockModels(def.subType)
        return posed
    end
    return def.file
end

local function loadModel(file, modDir)
    local filename = Utils.getFilename(file, modDir)
    local ok, node, sharedId = RseLog.try("loadSharedI3DFile(carcass model)", g_i3DManager.loadSharedI3DFile, g_i3DManager, filename,
        false, false)
    if not ok or node == nil or node == 0 then
        return nil
    end
    return node, sharedId
end

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

-- Registers our body types (xml/bales/bales.xml) with the game's bale list right away; returns how many. The map's own
-- bale loader (loadBaleFromXML) registers immediately; the mod loader (loadModBaleFromXML) only queues for the next map load,
-- which is why 0.1.0.2 still found them unregistered.
local function registerBodyTypes(modDir)
    local xmlFile = XMLFile.load("rseBales", Utils.getFilename(RseConfig.BODY_TYPES_FILE, modDir))
    if xmlFile == nil then
        return 0
    end
    local count = 0
    xmlFile:iterate("bales.bale", function(_, key)
        local ok, registered = RseLog.try("register carcass body type", g_baleManager.loadBaleFromXML, g_baleManager, xmlFile, key, modDir)
        if ok and registered then
            count = count + 1
        end
    end)
    xmlFile:delete()
    return count
end

function RseCarcasses:init(store, modDir, modName)
    self.store = store
    self.modDir = modDir
    self.entries = {}
    self.usingFallbackBodies = false
    self.bodyTypesRegistered = registerBodyTypes(modDir)
    RseLog.debug("carcass body types registered for %s", tostring(modName))
end

function RseCarcasses:bodyNode(entry)
    local node = entry.body ~= nil and entry.body.nodeId or nil
    return nodeExists(node) and node or nil
end

-- held by a machine (forks, spikes, grabs, belts) right now
function RseCarcasses:isMounted(entry)
    local body = entry.body
    return body ~= nil and (body.mountObject ~= nil or body.dynamicMountObject ~= nil or body.dynamicMountJointIndex ~= nil)
end

-- the entry whose body is node or one of node's parents (a raycast hits the body's collision shape)
function RseCarcasses:findByNode(node)
    local current, depth = node, 0
    while nodeExists(current) and depth < 5 do
        for _, entry in ipairs(self.entries) do
            if entry.body ~= nil and entry.body.nodeId == current then
                return entry
            end
        end
        current = getParent(current)
        depth = depth + 1
    end
    return nil
end

function RseCarcasses:getById(id)
    for _, entry in ipairs(self.entries) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

-- loads the hidden body; our own bale type first, a base straw bale of the same size if that fails
local function loadBody(self, def, x, y, z, rx, ry, rz)
    local mission = g_currentMission
    local body = RseCarcass.new(mission:getIsServer(), mission:getIsClient())
    local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(def.fillTypeName)
    local xmlFilename = Utils.getFilename(RseConfig.BODY_FILES[def.body], self.modDir)
    local ok, loaded = false, false
    if fillTypeIndex ~= nil then
        ok, loaded = RseLog.try("carcass body", body.loadFromConfigXML, body, xmlFilename, x, y, z, rx, ry, rz)
    end
    if not ok or not loaded then
        local size = RseConfig.BODY_SIZE[def.body]
        fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(RseConfig.FALLBACK_FILL_TYPE)
        local okName, fallback = RseLog.try("getBaleXMLFilename", g_baleManager.getBaleXMLFilename, g_baleManager, fillTypeIndex, false,
            size[1], size[2], size[3])
        if not okName or fallback == nil then
            return nil
        end
        if not self.usingFallbackBodies then
            self.usingFallbackBodies = true
            RseLog.info("our carcass bale type did not load; using base straw bales as carcass bodies")
        end
        ok, loaded = RseLog.try("carcass body (fallback)", body.loadFromConfigXML, body, fallback, x, y, z, rx, ry, rz)
        if not ok or not loaded then
            return nil
        end
    end
    RseLog.try("carcass body fill type", body.setFillType, body, fillTypeIndex, true)
    body.rseKind = def.kind
    body.rseMassKg = def.massKg
    body.defaultMass = def.massKg / 1000
    RseLog.try("setMass(carcass)", setMass, body.nodeId, def.massKg / 1000)
    local farmId = mission.getFarmId ~= nil and mission:getFarmId() or 1
    RseLog.try("carcass owner", body.setOwnerFarmId, body, farmId, true)
    RseLog.try("carcass register", body.register, body)
    return body
end

local function poseModel(entry)
    local size = RseConfig.BODY_SIZE[entry.def.body]
    local rotZ, x, y, z = RseAnimalCatalog.pose(entry.def, size[2])
    setRotation(entry.model, 0, 0, rotZ)
    setTranslation(entry.model, x, y, z)
end

-- Spawns a carcass. y = nil puts its body on the ground. Returns the entry, or nil and a reason.
function RseCarcasses:spawn(kind, x, y, z, rx, ry, rz)
    local def = RseAnimalCatalog.get(kind)
    if def == nil then
        return nil, "unknown animal " .. tostring(kind)
    end
    local file = modelFile(def)
    if file == nil then
        return nil, "no model for " .. def.kind
    end
    local size = RseConfig.BODY_SIZE[def.body]
    if y == nil then
        y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + size[2] / 2 + 0.05
    end
    local model, sharedId = loadModel(file, self.modDir)
    if model == nil then
        return nil, "model did not load: " .. tostring(file)
    end
    local body = loadBody(self, def, x, y, z, rx or 0, ry or 0, rz or 0)
    if body == nil then
        delete(model)
        g_i3DManager:releaseSharedI3DFile(sharedId)
        return nil, "body did not load"
    end
    local id = self.store:apply("addCarcass", { kind = def.kind })
    local anchor = createTransformGroup("rseCarcass")
    link(getRootNode(), anchor)
    link(anchor, model)
    local entry = { id = id, kind = def.kind, def = def, body = body, anchor = anchor, model = model, sharedId = sharedId,
        restMs = 0, lastX = x, lastZ = z }
    poseModel(entry)
    self:followBody(entry)
    entry.activatable = RseCarcassDrag.newActivatable(entry)
    g_currentMission.activatableObjectsSystem:addActivatable(entry.activatable)
    table.insert(self.entries, entry)
    RseLog.debug("carcass %d spawned: %s (%d kg) at %.1f, %.1f", id, def.kind, def.massKg, x, z)
    return entry
end

-- removes a carcass from the world; storeChange: the Store change that goes with it ("removeCarcass" unless already done)
function RseCarcasses:remove(entry, storeChange)
    RseMarkers:hide(entry)
    RseCarcassDrag.release(entry)
    RseStrap:releaseFor(entry)
    if entry.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(entry.activatable)
        entry.activatable = nil
    end
    if self:bodyNode(entry) ~= nil and not entry.body.isDeleted then
        RseLog.try("carcass body delete", entry.body.delete, entry.body)
    end
    entry.body = nil
    if nodeExists(entry.anchor) then
        delete(entry.anchor)
    end
    entry.anchor = nil
    if entry.sharedId ~= nil then
        g_i3DManager:releaseSharedI3DFile(entry.sharedId)
        entry.sharedId = nil
    end
    for i, candidate in ipairs(self.entries) do
        if candidate == entry then
            table.remove(self.entries, i)
            break
        end
    end
    if storeChange ~= false then
        self.store:apply("removeCarcass", { id = entry.id })
    end
end

function RseCarcasses:followBody(entry)
    local node = self:bodyNode(entry)
    if node == nil then
        return false
    end
    local x, y, z = getWorldTranslation(node)
    setWorldTranslation(entry.anchor, x, y, z)
    setWorldRotation(entry.anchor, getWorldRotation(node))
    setVisibility(node, self.showBodies)
    return true
end

-- lying still inside a disposal point for DELIVER_REST_MS, and not held, dragged or strapped
local function checkDelivery(self, entry, dt)
    local node = self:bodyNode(entry)
    local x, _, z = getWorldTranslation(node)
    local moved = math.abs(x - entry.lastX) + math.abs(z - entry.lastZ)
    entry.lastX, entry.lastZ = x, z
    local point = RsePoints:at(x, z, "disposal")
    if point == nil or moved > 0.02 or entry.dragged or RseStrap:isStrapped(entry) or self:isMounted(entry) then
        entry.restMs = 0
        return false
    end
    entry.restMs = entry.restMs + dt
    if entry.restMs < RseConfig.DELIVER_REST_MS then
        return false
    end
    local result = self.store:apply("deliverCarcass", { id = entry.id, pointName = point.name })
    if result ~= nil then
        self:remove(entry, false)
        return true
    end
    return false
end

function RseCarcasses:update(dt)
    local isServer = g_currentMission:getIsServer()
    -- copy: delivery and lost bodies remove entries while we go
    local list = {}
    for i, entry in ipairs(self.entries) do
        list[i] = entry
    end
    for _, entry in ipairs(list) do
        if not self:followBody(entry) then
            -- something else deleted the body (sold, destroyed): drop the rest of it
            RseLog.info("carcass %d (%s) body gone; removed", entry.id, entry.kind)
            self:remove(entry)
        elseif isServer then
            checkDelivery(self, entry, dt)
        end
    end
end

function RseCarcasses:clear()
    local list = {}
    for i, entry in ipairs(self.entries) do
        list[i] = entry
    end
    for _, entry in ipairs(list) do
        self:remove(entry)
    end
end

-- while the map unloads: the game deletes objects itself; release only our nodes, prompts and shared files
function RseCarcasses:unload()
    for _, entry in ipairs(self.entries) do
        if entry.activatable ~= nil then
            g_currentMission.activatableObjectsSystem:removeActivatable(entry.activatable)
        end
        if self:bodyNode(entry) ~= nil and not entry.body.isDeleted then
            RseLog.try("carcass body delete", entry.body.delete, entry.body)
        end
        if nodeExists(entry.anchor) then
            delete(entry.anchor)
        end
        if entry.sharedId ~= nil then
            g_i3DManager:releaseSharedI3DFile(entry.sharedId)
        end
    end
    self.entries = {}
end

-- After a reload the game fastens saved tension belts before our carcasses are back, so belts over a carcass hold nothing
-- (M1: they closed on the empty bed). Redrawing them is not enough: 0.1.0.4 redrew the belts around the carcass
-- (TensionBelts:refreshTensionBelts only rebuilds the belt meshes), but the carcass stayed loose (M2 round 1, a pickup bed).
-- So once the carcasses lie in place again, every fastened belt of a vehicle near one is opened and closed again
-- (TensionBelts:setTensionBeltsActive, the same as the player pressing the belt key twice), which joins what lies under it.
-- Returns the number of vehicles and the number of carcasses held by belts afterwards.
function RseCarcasses:refastenBeltsNearCarcasses()
    local vehicles = 0
    for _, vehicle in ipairs(g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        local spec = vehicle.spec_tensionBelts
        if spec ~= nil and spec.hasTensionBelts and vehicle.setTensionBeltsActive ~= nil and vehicle.components ~= nil then
            local vx, _, vz = getWorldTranslation(vehicle.components[1].node)
            local near = false
            for _, entry in ipairs(self.entries) do
                local node = self:bodyNode(entry)
                if node ~= nil then
                    local cx, _, cz = getWorldTranslation(node)
                    near = near or math.abs(cx - vx) + math.abs(cz - vz) <= RseConfig.BELT_REFRESH_RANGE
                end
            end
            if near then
                local refastened = 0
                for _, belt in pairs(spec.sortedBelts or {}) do
                    if belt.mesh ~= nil then
                        RseLog.try("open belt", vehicle.setTensionBeltsActive, vehicle, false, belt.id, true, false)
                        RseLog.try("close belt", vehicle.setTensionBeltsActive, vehicle, true, belt.id, true, false)
                        refastened = refastened + 1
                    end
                end
                if refastened > 0 then
                    vehicles = vehicles + 1
                end
            end
        end
    end
    local held = 0
    for _, entry in ipairs(self.entries) do
        if entry.body ~= nil and entry.body.tensionMountObject ~= nil then
            held = held + 1
        end
    end
    return vehicles, held
end

-- what the savegame keeps of each carcass (scene: part of the call in progress), and each entry's number in the list (for the
-- straps)
function RseCarcasses:saveData()
    local list, indexOf = {}, {}
    for _, entry in ipairs(self.entries) do
        local node = self:bodyNode(entry)
        if node ~= nil then
            local x, y, z = getWorldTranslation(node)
            local rx, ry, rz = getWorldRotation(node)
            table.insert(list, { kind = entry.kind, x = x, y = y, z = z, rx = rx, ry = ry, rz = rz,
                leftMs = entry.left ~= nil and entry.left.leftMs or 0, unearned = entry.unearned or 0,
                scene = entry.sceneId ~= nil or entry.resuming == true })
            indexOf[entry] = #list
        end
    end
    return list, indexOf
end
