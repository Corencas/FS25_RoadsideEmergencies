-- Roadside Emergencies: wrecks (DESIGN F9, F10, F15). A base-game vehicle, or a trailer with its load of bales spilled around it, that
-- must reach a recovery point before the job ends (Z). Spawned as a mission vehicle, the way the game spawns contract vehicles, so
-- it stays out of your vehicle list and can't be sold; not saved by the game (our savegame file keeps it).
-- locked: pinned in place by a joint to a hidden anchor (P3: never change a vehicle's own body type, it destroys its wheels), can't be
-- entered or started. Prepared on foot with the activate prompt, then towed with a strap you hook where you choose (F26), a winch mod or
-- a rollback. One on its side is laid flat and held as soon as it loads, because on its own it rolls back onto its wheels within a second (P9b,
-- M4 round 1). It stays held after being prepared, until a strap attached to it is pulled tight; then it comes over.

RseWrecks = {
    byVehicle = setmetatable({}, { __mode = "k" }),   -- vehicle -> wreck, for the gates below
    everWreck = setmetatable({}, { __mode = "k" }),   -- every vehicle that has been a wreck, even after its job
    resetCopies = {},                                 -- what the game made when it reset one anyway
    resetSubscribed = false,
    lastFile = {},                                    -- kind -> the vehicle of the last call of that kind
    planned = nil,                                    -- { kind, variant }: the vehicle the pager has named
    modDir = nil
}

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

local function rootNodeOf(vehicle)
    return vehicle ~= nil and vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node or nil
end

---------------------------------------------------------------------------------------------------
-- Gates: a locked wreck can't be entered or started. Each wraps the game's function and only acts on a wreck. They go in as the scripts
-- load, while the game still builds its vehicle types (P3b), and wrap the stored original, so another savegame doesn't stack them.
---------------------------------------------------------------------------------------------------

local function isLocked(vehicle)
    local wreck = RseWrecks.byVehicle[vehicle]
    return wreck ~= nil and wreck.state == "locked"
end

local function wrap(class, name, fn)
    if class == nil or type(class[name]) ~= "function" then
        return
    end
    local key = "rseOriginal_" .. name
    if class[key] == nil then
        class[key] = class[name]
    end
    class[name] = Utils.overwrittenFunction(class[key], fn)
end

-- the utility crew's truck (UtilityCrew.lua) is theirs, not yours
local function isCrew(vehicle)
    return RseUtilityCrew ~= nil and RseUtilityCrew:owns(vehicle)
end

wrap(Enterable, "getIsEnterable", function(vehicle, superFunc)
    if isLocked(vehicle) or isCrew(vehicle) then
        return false
    end
    return superFunc(vehicle)
end)

-- the player's "enter" interaction goes through interact, not getIsEnterable (P3b)
wrap(Enterable, "interact", function(vehicle, enterableInteract, superFunc, player)
    if isLocked(vehicle) then
        if g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(RseText.get("rse_wreck_locked"), 2500)
        end
        return
    end
    if isCrew(vehicle) then
        if g_currentMission ~= nil then
            g_currentMission:showBlinkingWarning(RseText.get("rse_crew_notYours"), 2500)
        end
        return
    end
    return enterableInteract(vehicle, superFunc, player)
end)

wrap(Enterable, "getIsTabbable", function(vehicle, superFunc)
    if RseWrecks.byVehicle[vehicle] ~= nil or isCrew(vehicle) then
        return false
    end
    return superFunc(vehicle)
end)

wrap(Motorized, "getCanMotorRun", function(vehicle, superFunc)
    if RseWrecks.byVehicle[vehicle] ~= nil then
        return false
    end
    return superFunc(vehicle)
end)

wrap(Motorized, "getMotorNotAllowedWarning", function(vehicle, superFunc)
    if RseWrecks.byVehicle[vehicle] ~= nil then
        return RseText.get("rse_wreck_noEngine")
    end
    return superFunc(vehicle)
end)

---------------------------------------------------------------------------------------------------
-- Pinning
---------------------------------------------------------------------------------------------------

local function loadShared(path)
    local filename = Utils.getFilename(path, RoadsideEmergencies.MOD_DIR)
    local ok, node, sharedId = RseLog.try("load " .. path, g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or node == nil or node == 0 then
        return nil
    end
    return node, sharedId
end

-- holds a vehicle where it is: a hidden cone without collisions becomes a kinematic anchor, and a rigid joint ties the vehicle to it (P3b)
local function pin(vehicle)
    local node = rootNodeOf(vehicle)
    local anchor, sharedId = loadShared(RseConfig.KIT_BLOCKER_FILE)
    if node == nil or anchor == nil then
        return nil
    end
    local x, y, z = getWorldTranslation(node)
    local rx, ry, rz = getWorldRotation(node)
    link(getRootNode(), anchor)
    setWorldTranslation(anchor, x, y - 3, z)
    local body = getNumOfChildren(anchor) > 0 and getChildAt(anchor, 0) or anchor
    for i = 0, getNumOfChildren(body) - 1 do
        setVisibility(getChildAt(body, i), false)
    end
    setCollisionFilterGroup(body, 0)
    setCollisionFilterMask(body, 0)
    setRigidBodyType(body, RigidBodyType.KINEMATIC)
    addToPhysics(anchor)
    -- both joint frames sit at the vehicle's current position and rotation, so nothing snaps
    local anchorPoint = createTransformGroup("rseWreckAnchorPoint")
    link(body, anchorPoint)
    setWorldTranslation(anchorPoint, x, y, z)
    setWorldRotation(anchorPoint, rx, ry, rz)
    local vehiclePoint = createTransformGroup("rseWreckVehiclePoint")
    link(node, vehiclePoint)
    local constructor = JointConstructor.new()
    constructor:setActors(body, node)
    constructor:setJointTransforms(anchorPoint, vehiclePoint)
    for axis = 0, 2 do
        constructor:setRotationLimit(axis, 0, 0)
        constructor:setTranslationLimit(axis, true, 0, 0)
    end
    constructor:setEnableCollision(false)
    return { jointIndex = constructor:finalize(), anchor = anchor, sharedId = sharedId, vehiclePoint = vehiclePoint }
end

-- Flat on its side, side on the ground, along the ground from end to end (Z: a 12 m trailer lay level with one end in the air). Rolled 90 degrees, half the
-- vehicle's width is the height of its middle above the ground; its length follows the slope between its two ends.
local function layOnSide(wreck)
    local vehicle = wreck.vehicle
    local node = rootNodeOf(vehicle)
    if node == nil then
        return
    end
    local x, _, z = getWorldTranslation(node)
    local size = vehicle.size or {}
    local width = size.width or RseConfig.WRECK_TIPPED_HEIGHT * 2
    local length = math.max(1, size.length or 4)
    local yaw = wreck.rotation.ry
    local fx, fz = math.sin(yaw), math.cos(yaw)
    local function ground(px, pz)
        return getTerrainHeightAtWorldPos(g_terrainNode, px, 0, pz)
    end
    local middleX, middleZ = x + fx * (size.lengthOffset or 0), z + fz * (size.lengthOffset or 0)
    local back, front = ground(middleX - fx * length / 2, middleZ - fz * length / 2), ground(middleX + fx * length / 2, middleZ + fz * length / 2)
    local rise = front - back
    local along = math.sqrt(length * length + rise * rise)
    -- its forward follows the slope; its up lies level, to the side (as a roll of +90 degrees about its forward axis gives)
    local pose = createTransformGroup("rseWreckPose")
    link(getRootNode(), pose)
    setDirection(pose, fx * length / along, rise / along, fz * length / along, -fz, 0, fx)
    local rx, ry, rz = getWorldRotation(pose)
    delete(pose)
    -- the slope's height at the reference point, which sits lengthOffset behind the middle
    local y = math.max(ground(x, z), (front + back) / 2 - rise * (size.lengthOffset or 0) / length) + width / 2 + 0.05
    vehicle:setAbsolutePosition(x, y, z, rx, ry, rz)
end

-- Put back where it was placed, if something moved it before its pin (Z: traffic on a crossing shoved the stalled vehicle off the tracks). Its height above
-- the ground goes with it.
local function holdWherePlaced(wreck)
    local node = rootNodeOf(wreck.vehicle)
    local placed = wreck.placed
    if node == nil or placed == nil then
        return
    end
    local x, y, z = getWorldTranslation(node)
    local drift = math.sqrt((x - placed.x) ^ 2 + (z - placed.z) ^ 2)
    if drift <= RseConfig.WRECK_DRIFT_MAX then
        return
    end
    local above = y - getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    local rotation = wreck.rotation
    wreck.vehicle:setAbsolutePosition(placed.x, getTerrainHeightAtWorldPos(g_terrainNode, placed.x, 0, placed.z) + above, placed.z, rotation.rx, rotation.ry,
        rotation.rz)
    RseLog.info("wreck %s had moved %.1f m before its pin: put back where it was placed", wreck.kind, drift)
end

local function unpin(wreck)
    local data = wreck.pin
    wreck.pin = nil
    if data == nil then
        return
    end
    if data.jointIndex ~= nil then
        RseLog.try("remove the pin joint", removeJoint, data.jointIndex)
    end
    if nodeExists(data.vehiclePoint) then
        delete(data.vehiclePoint)
    end
    if nodeExists(data.anchor) then
        delete(data.anchor)
    end
    if data.sharedId ~= nil then
        g_i3DManager:releaseSharedI3DFile(data.sharedId)
    end
end

---------------------------------------------------------------------------------------------------
-- The activate prompt on foot
---------------------------------------------------------------------------------------------------

local RseWreckActivatable = {}
local RseWreckActivatable_mt = Class(RseWreckActivatable)

local function newActivatable(wreck)
    local self = setmetatable({}, RseWreckActivatable_mt)
    self.wreck = wreck
    self.activateText = RseText.action(wreck.def.driver and "rse_wreck_driver" or "rse_wreck_prepare")
    return self
end

function RseWreckActivatable:getIsActivatable()
    local wreck = self.wreck
    local node = rootNodeOf(wreck.vehicle)
    if wreck.state ~= "locked" or node == nil or g_localPlayer == nil or g_localPlayer:getCurrentVehicle() ~= nil then
        return false
    end
    local x, _, z = getWorldTranslation(node)
    local px, _, pz = g_localPlayer:getPosition()
    return (x - px) ^ 2 + (z - pz) ^ 2 <= RseConfig.WRECK_REACH ^ 2
end

function RseWreckActivatable:getDistance(x, y, z)
    local node = rootNodeOf(self.wreck.vehicle)
    if node == nil then
        return math.huge
    end
    local cx, cy, cz = getWorldTranslation(node)
    return math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2)
end

function RseWreckActivatable:run()
    if self.wreck.waitForPower then
        RsePowerLine:warnLive(self.wreck.waitForPower)
        return
    end
    if self.wreck.waitForTree ~= nil then
        -- only a log on the car holds the door (Z). If the check itself fails, the door opens: nobody gets stuck on it
        local ok, blocked = RseLog.try("look for a log on the car", RseLogSpill.carBlocked, RseLogSpill, self.wreck.waitForTree)
        if ok and blocked then
            RseText.notify(RseText.get("rse_tree_notYet"), true)
            return
        end
    end
    RseWrecks:prepare(self.wreck)
end

---------------------------------------------------------------------------------------------------
-- Spilled bales: the game's own square bale in a class of ours, so every machine handles it, but it can't be sold or opened, and the
-- game's item saving skips it (our savegame file keeps it)
---------------------------------------------------------------------------------------------------

RseSpillBale = {}
local RseSpillBale_mt = Class(RseSpillBale, Bale)

function RseSpillBale.new(isServer, isClient, customMt)
    return Bale.new(isServer, isClient, customMt or RseSpillBale_mt)
end

function RseSpillBale:getCanBeSold()
    return false
end

function RseSpillBale:getCanBeOpened()
    return false
end

function RseSpillBale:getSupportsWrapping()
    return false
end

function RseSpillBale:getNeedsSaving()
    return false
end

function RseSpillBale:getValue()
    return 0
end

local function spawnBale(load, x, y, z, rx, ry, rz)
    local mission = g_currentMission
    local size = load.size
    local fillType = g_fillTypeManager:getFillTypeIndexByName(RseConfig.WRECK_BALE_FILL)
    local ok, filename = RseLog.try("find the bale model", g_baleManager.getBaleXMLFilename, g_baleManager, fillType, false, size[1], size[2], size[3])
    if not ok or filename == nil then
        return nil
    end
    local bale = RseSpillBale.new(mission:getIsServer(), mission:getIsClient())
    local okLoad, loaded = RseLog.try("spilled bale", bale.loadFromConfigXML, bale, filename, x, y, z, rx, ry, rz)
    if not okLoad or not loaded then
        return nil
    end
    RseLog.try("spilled bale fill type", bale.setFillType, bale, fillType, true)
    RseLog.try("spilled bale owner", bale.setOwnerFarmId, bale, mission.getFarmId ~= nil and mission:getFarmId() or 1, true)
    RseLog.try("spilled bale register", bale.register, bale)
    return bale
end

local function baleNode(item)
    local node = item.bale ~= nil and item.bale.nodeId or nil
    return nodeExists(node) and node or nil
end

local function removeBale(item)
    if baleNode(item) ~= nil and not item.bale.isDeleted then
        RseLog.try("remove a spilled bale", item.bale.delete, item.bale)
    end
    item.bale = nil
end

---------------------------------------------------------------------------------------------------
-- Smoke from the engine: the game's own particles, hanging from the vehicle, so they go with it until it is delivered
---------------------------------------------------------------------------------------------------

local function startSmoke(wreck)
    local vehicle = wreck.vehicle
    local node = rootNodeOf(vehicle)
    local filename = Utils.getFilename(RseConfig.WRECK_SMOKE_FILE, RoadsideEmergencies.MOD_DIR)
    local ok, root, sharedId = RseLog.try("load the smoke", g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or root == nil or root == 0 or node == nil then
        RseLog.info("the smoke did not load (%s)", tostring(filename))
        return
    end
    link(node, root)
    local size = vehicle.size or {}
    setTranslation(root, 0, (size.height or 2) * RseConfig.WRECK_SMOKE_HEIGHT, (size.lengthOffset or 0) + (size.length or 4) / 2 - RseConfig.WRECK_SMOKE_BACK)
    -- the file has a second, smaller emitter that we don't want
    if getNumOfChildren(root) > 1 then
        delete(getChildAt(root, 1))
    end
    local system = {}
    ParticleUtil.loadParticleSystemFromNode(getChildAt(root, 0), system, true, true, false)
    ParticleUtil.setEmittingState(system, true)
    wreck.smoke = { root = root, sharedId = sharedId, system = system }
    RseLog.info("wreck %s: smoke from the engine", wreck.kind)
end

local function stopSmoke(wreck)
    local smoke = wreck.smoke
    wreck.smoke = nil
    if smoke == nil then
        return
    end
    if nodeExists(smoke.root) then
        delete(smoke.root)
    end
    if smoke.sharedId ~= nil then
        g_i3DManager:releaseSharedI3DFile(smoke.sharedId)
    end
end

---------------------------------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------------------------------

function RseWrecks:onLoaded(vehicles, loadingState, wreck)
    if loadingState ~= VehicleLoadingState.OK or vehicles == nil or vehicles[1] == nil then
        RseLog.problem("the %s wreck did not load (state %s)", wreck.kind, tostring(loadingState))
        wreck.failed = true
        return
    end
    if wreck.removed then
        RseLog.try("delete a wreck no longer needed", vehicles[1].delete, vehicles[1])
        return
    end
    wreck.vehicle = vehicles[1]
    self.byVehicle[wreck.vehicle] = wreck
    self.everWreck[wreck.vehicle] = true
    wreck.vehicle.canBeReset = false -- the game's own switch: no reset in its menus, or it would be a free trip to the recovery point at the shop
    if not self.resetSubscribed and g_messageCenter ~= nil and MessageType ~= nil and MessageType.VEHICLE_RESET ~= nil then
        self.resetSubscribed = true
        g_messageCenter:subscribe(MessageType.VEHICLE_RESET, self.onVehicleReset, self)
    end
    if wreck.vehicle.setDamageAmount ~= nil then
        RseLog.try("wreck damage", wreck.vehicle.setDamageAmount, wreck.vehicle, wreck.def.damage or 0.9, true)
    end
    if wreck.state == "locked" then
        wreck.pinInMs = wreck.def.tipped and 0 or RseConfig.WRECK_PIN_MS
        if not wreck.def.scenery and not wreck.retired then -- retired: its job ended while it loaded
            wreck.activatable = newActivatable(wreck)
            g_currentMission.activatableObjectsSystem:addActivatable(wreck.activatable)
        end
    elseif wreck.state == "tipped" then
        wreck.pinInMs = 0 -- a saved one, prepared but not yet pulled over
    elseif wreck.state == "held" then
        wreck.pinInMs = RseConfig.WRECK_HELD_PIN_MS
    end
    if wreck.def.tipped and wreck.pinInMs == 0 then
        RseLog.try("lay the wreck on its side", layOnSide, wreck)
    end
    if (wreck.def.driver or wreck.def.seated) and wreck.state == "locked" then
        self:seatDriver(wreck)
    end
    local inWater = wreck.variant ~= nil and wreck.variant.noDrown
    if inWater then -- the game breaks a vehicle for good once the water over it is this deep
        wreck.vehicle.thresholdTailwaterDepth = math.huge
        wreck.vehicle.thresholdTailwaterDepthWarning = math.huge
    end
    if wreck.def.smoke and not inWater then
        RseLog.try("the smoke", startSmoke, wreck)
    end
    if wreck.def.hazards and wreck.vehicle.spec_lights ~= nil then
        RseLog.try("hazard lights", wreck.vehicle.setTurnLightState, wreck.vehicle, Lights.TURNLIGHT_HAZARD, true, true)
    end
    RseLog.info("wreck '%s' (%s) placed, state %s, mass %.1f t", tostring(wreck.vehicle:getFullName()), wreck.kind, wreck.state,
        wreck.vehicle:getTotalMass(true))
end

-- a seated person, dressed like one of the map's NPCs (the game shows AI helpers the same way, P9b)
function RseWrecks:seatDriver(wreck)
    local vehicle = wreck.vehicle
    if vehicle.setVehicleCharacter == nil or g_npcManager == nil or g_npcManager.getNPCByName == nil then
        return
    end
    local ok, npc = RseLog.try("find an NPC", g_npcManager.getNPCByName, g_npcManager, "FARMER")
    if ok and npc ~= nil and npc.playerStyle ~= nil and RseLog.try("seat the driver", vehicle.setVehicleCharacter, vehicle, npc.playerStyle) then
        wreck.showDriverInMs = RseConfig.WRECK_DRIVER_SHOW_MS
    end
end

local function setDriverVisible(wreck, visible)
    local enterable = wreck.vehicle ~= nil and wreck.vehicle.spec_enterable or nil
    local character = enterable ~= nil and enterable.vehicleCharacter or nil
    if character ~= nil and character.setCharacterVisibility ~= nil then
        RseLog.try("driver visibility", character.setCharacterVisibility, character, visible)
    end
end

-- Hiding the character doesn't last: the game works out its visibility again every frame (Enterable:onPostUpdate, VehicleCharacter:updateVisibility), which is
-- why Z's driver stayed in the seat. So it goes altogether, the way the game itself removes a character when someone leaves a vehicle.
local function removeDriver(wreck)
    wreck.showDriverInMs = nil
    local vehicle = wreck.vehicle
    if vehicle ~= nil and vehicle.deleteVehicleCharacter ~= nil then
        RseLog.try("the driver gets out", vehicle.deleteVehicleCharacter, vehicle)
    end
end

-- is this vehicle in the game? A map or a later game version could leave one out, and a call then takes another
local function inStore(file)
    if g_storeManager == nil or g_storeManager.getItemByXMLFilename == nil then
        return true
    end
    return g_storeManager:getItemByXMLFilename(Utils.getFilename(file, RoadsideEmergencies.MOD_DIR)) ~= nil
end

-- the vehicle for the next wreck of this kind. If the store knows none of them, the lookup itself is at fault, so it doesn't count.
function RseWrecks:pickVariant(kind)
    local def = RseConfig.WRECKS[kind]
    local last = self.lastFile[kind]
    local fleet = RseCalls ~= nil and RseCalls:fleet() or nil
    local function canRecover(_, variant)
        return RseWreckRules.canRecover(variant, fleet)
    end
    local function fits(file, variant)
        return inStore(file) and canRecover(file, variant)
    end
    -- never one the farm couldn't recover: dispatch doesn't call about those at all. Only rseStart gets here with nothing in reach, and takes whatever there
    -- is.
    local variant = RseWreckRules.pickVariant(def, math.random(), last, fits) or RseWreckRules.pickVariant(def, math.random(), last, canRecover)
        or RseWreckRules.pickVariant(def, math.random(), last, inStore) or RseWreckRules.pickVariant(def, math.random(), last)
    if variant ~= nil then
        self.lastFile[kind] = variant.file
    end
    return variant
end

-- its name in the shop, or nil
local function vehicleName(file)
    local item = g_storeManager ~= nil and g_storeManager:getItemByXMLFilename(Utils.getFilename(file, RoadsideEmergencies.MOD_DIR)) or nil
    if item == nil or type(item.name) ~= "string" or string.find(item.name, "[%%$]") ~= nil then
        return nil
    end
    local brand = g_brandManager ~= nil and g_brandManager:getBrandByIndex(item.brandIndex) or nil
    if brand ~= nil and brand.name ~= "NONE" and brand.title ~= nil then
        return brand.title .. " " .. item.name
    end
    return item.name
end

-- the vehicle's name as the shop writes it (brand and name), or nil
function RseWrecks:nameOf(variant)
    local ok, name = RseLog.try("name the vehicle", vehicleName, variant.file)
    return ok and name or nil
end

-- Before the pager asks (Z: you must know before you say yes): which vehicle this call has (self.planned; CallPlan.lua writes the pager's lines).
function RseWrecks:planCall(id)
    self.planned = nil
    for _, emergency in ipairs(RseConfig.EMERGENCIES) do
        if emergency.id == id and emergency.wreck ~= nil then
            local variant = self:pickVariant(emergency.wreck)
            if variant ~= nil then
                self.planned = { kind = emergency.wreck, variant = variant }
            end
            return
        end
    end
end

-- the vehicle for a wreck being laid out: the one the pager has named, if it has
function RseWrecks:takeVariant(kind)
    local planned = self.planned
    self.planned = nil
    if planned ~= nil and planned.kind == kind then
        return planned.variant
    end
    return self:pickVariant(kind)
end

-- for the log: how many of each kind's vehicles the game has
function RseWrecks:logVehicles()
    local parts = {}
    for kind, def in pairs(RseConfig.WRECKS) do
        if def.variants ~= nil then
            local found = 0
            for _, variant in ipairs(def.variants) do
                found = found + (inStore(variant.file) and 1 or 0)
            end
            table.insert(parts, string.format("%s %d/%d", kind, found, #def.variants))
        end
    end
    table.sort(parts)
    RseLog.info("wreck vehicles in the game: %s", table.concat(parts, ", "))
end

-- Puts a wreck in the world: position { x, z, yaw, rx, rz }, loading takes a moment; y, for a saved one: where it stood, on a bridge or a rollback's bed.
-- bales: { { x, y, z, rx, ry, rz }, ... } already chosen, of the kind `load`. delivered: a saved job whose vehicle is already in, so only the bales come back.
function RseWrecks:spawn(kind, position, state, bales, delivered, load, variant)
    local def = RseConfig.WRECKS[kind]
    local wreck = { kind = kind, def = def, variant = variant, state = RseWreckRules.newState(state), bales = {}, restMs = 0, delivered = false, load = load }
    if def.noVehicle or delivered then
        wreck.state, wreck.delivered = "ready", true
    else
        local data = VehicleLoadingData.new()
        data:setFilename(Utils.getFilename(variant.file, RoadsideEmergencies.MOD_DIR))
        data:setPosition(position.x, position.y, position.z, def.tipped and wreck.state == "locked" and RseConfig.WRECK_TIPPED_HEIGHT or RseConfig.WRECK_HEIGHT)
        local tippedRoll = def.tipped and wreck.state == "locked" and math.pi / 2 or 0
        wreck.rotation = { rx = position.rx or 0, ry = position.yaw or 0, rz = position.rz or tippedRoll }
        wreck.placed = { x = position.x, z = position.z }
        data:setRotation(wreck.rotation.rx, wreck.rotation.ry, wreck.rotation.rz)
        -- the way the game spawns contract vehicles: not in your vehicle list, can't be sold
        data:setPropertyState(VehiclePropertyState.MISSION)
        data:setOwnerFarmId(g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or 1)
        data:setIsSaved(false)
        data:load(self.onLoaded, self, wreck)
    end
    for _, spot in ipairs(bales or {}) do
        local bale = spawnBale(load, spot.x, spot.y, spot.z, spot.rx or 0, spot.ry or 0, spot.rz or 0)
        if bale ~= nil then
            table.insert(wreck.bales, { bale = bale, restMs = 0, lastX = spot.x, lastZ = spot.z })
        end
    end
    wreck.balesTotal, wreck.balesIn = #wreck.bales, 0
    local first = wreck.bales[1]
    if first ~= nil then
        local weighed, mass = false, nil
        if first.bale.getTotalMass ~= nil then
            weighed, mass = RseLog.try("weigh a bale", first.bale.getTotalMass, first.bale)
        end
        RseLog.info("load: %d %s bale(s), each %s t; a player can carry up to %s t", #wreck.bales, load.id, weighed and tostring(mass) or "?",
            tostring(HandToolHands ~= nil and HandToolHands.MAXIMUM_PICKUP_MASS or nil))
    end
    if def.noVehicle and #wreck.bales == 0 then
        RseLog.problem("the %s job has nothing to bring in: no bale loaded", kind)
        wreck.failed = true
    end
    return wreck
end

-- prepared on foot: it comes loose. The state machine says what it needs next.
function RseWrecks:prepare(wreck)
    if wreck.state ~= "locked" then
        return
    end
    if not wreck.def.tipped then
        unpin(wreck)
    end
    wreck.state = RseWreckRules.afterPrepare(wreck.state, wreck.def)
    if wreck.def.driver then
        removeDriver(wreck)
        RseText.notify(RseText.get("rse_wreck_driverOut"))
    end
    if wreck.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(wreck.activatable)
        wreck.activatable = nil
    end
    RseLog.info("wreck %s prepared: state %s", wreck.kind, wreck.state)
end

-- Where a strap goes to tow a wreck: on its centre line, on the end nearest (x, y, z). Hooked anywhere else it pulls from the side and the wreck runs wide
-- (Z, M3).
function RseWrecks:towPoint(wreck, x, y, z)
    local vehicle = wreck.vehicle
    local node = rootNodeOf(vehicle)
    local size = vehicle.size or {}
    local half, offset = (size.length or 4) / 2, size.lengthOffset or 0
    local _, _, localZ = worldToLocal(node, x, y, z)
    local endZ = localZ >= offset and offset + half or offset - half
    local worldX, rootY, worldZ = localToWorld(node, 0, 0, endZ)
    return worldX, math.max(getTerrainHeightAtWorldPos(g_terrainNode, worldX, 0, worldZ) + RseConfig.TOW_HOOK_HEIGHT, rootY - 0.2), worldZ
end

-- Where a strap sits on a wreck on its wheels: where you aimed, but low down, so that a pull at an angle can swing it round without tipping it over.
-- Also tells whether that is off the middle of its end, and has to move there when you really tow.
function RseWrecks:hookPoint(wreck, x, y, z)
    local node = rootNodeOf(wreck.vehicle)
    local localX, _, localZ = worldToLocal(node, x, y, z)
    local worldX, rootY, worldZ = localToWorld(node, localX, 0, localZ)
    local hookY = math.max(getTerrainHeightAtWorldPos(g_terrainNode, worldX, 0, worldZ) + RseConfig.TOW_HOOK_HEIGHT, rootY - 0.2)
    local endX, _, endZ = self:towPoint(wreck, x, y, z)
    local offX, offZ = worldX - endX, worldZ - endZ
    return worldX, hookY, worldZ, math.sqrt(offX * offX + offZ * offZ) > RseConfig.STRAP_CENTRE_RANGE
end

-- Better Winch (optional): it hooks a vehicle only where a trailer would hitch up, so its winches refuse a tractor or a truck (Z, on a rollback's own winch).
-- An attach point is its way for other mods to offer one more place: one on each end of a wreck that can be pulled. Without that mod nothing happens.
local function betterWinch()
    if type(g_thBetterWinch) == "table" then
        return g_thBetterWinch
    end
    local mods = g_modManager ~= nil and g_modManager.getActiveMods ~= nil and g_modManager:getActiveMods() or {}
    for _, mod in ipairs(mods) do
        local env = _G[mod.modName]
        if type(env) == "table" and type(env.g_thBetterWinch) == "table" then
            return env.g_thBetterWinch
        end
    end
    return nil
end

local function offerWinchPoints(wreck)
    local winch = betterWinch()
    local vehicle = wreck.vehicle
    local node = rootNodeOf(vehicle)
    if winch == nil or winch.injectObjectAttachPoint == nil or node == nil then
        return
    end
    local size = vehicle.size or {}
    local half, offset = (size.length or 4) / 2, size.lengthOffset or 0
    local object = winch.getAttachableObject ~= nil and winch:getAttachableObject(vehicle, true) or nil
    local count = 0
    for _, endZ in ipairs({ offset + half, offset - half }) do
        -- it takes one point per parent node
        local parent = createTransformGroup("rseWinchPoint")
        link(node, parent)
        local _, hookY = worldToLocal(node, RseWrecks:towPoint(wreck, localToWorld(node, 0, 0, endZ)))
        setTranslation(parent, 0, hookY, endZ)
        local point = winch:injectObjectAttachPoint(vehicle, parent, 0, 0, 0, 0, 0, 0)
        if point ~= nil then
            count = count + 1
            if object ~= nil and object.addMeshNode ~= nil then
                object:addMeshNode(point.node)
            end
        end
    end
    if object ~= nil and object.setIsDirty ~= nil then
        object:setIsDirty(true)
    end
    RseLog.info("Better Winch: %d attach point(s) on the %s wreck, known to it as an attachable object: %s", count, wreck.kind, tostring(object ~= nil))
end

-- a trailer's wheels can't steer
local function hasSteering(vehicle)
    return vehicle.maxRotTime ~= nil and vehicle.minRotTime ~= nil and vehicle.rotatedTime ~= nil and (vehicle.maxRotTime ~= 0 or vehicle.minRotTime ~= 0)
end

-- where a wreck's wheels are: { middleZ, axleZ (the front axle, the one that steers), maxAngle }, once for each wreck
local function wheelLayout(wreck, node)
    if wreck.wheelLayout ~= nil then
        return wreck.wheelLayout
    end
    local zs, axleZ, maxAngle = {}, nil, nil
    for _, wheel in ipairs(wreck.vehicle.spec_wheels ~= nil and wreck.vehicle.spec_wheels.wheels or {}) do
        if wheel.physics ~= nil and nodeExists(wheel.repr) then
            local _, _, z = worldToLocal(node, getWorldTranslation(wheel.repr))
            table.insert(zs, z)
            if (wheel.physics.rotSpeed or 0) ~= 0 then
                axleZ = math.max(axleZ or z, z)
                maxAngle = math.max(maxAngle or 0, math.abs(wheel.physics.rotMax or 0))
            end
        end
    end
    local layout = RseWreckRules.axleLayout(zs, RseConfig)
    layout.axleZ = axleZ
    layout.maxAngle = maxAngle ~= nil and maxAngle > 0 and maxAngle or nil
    wreck.wheelLayout = layout
    return layout
end

-- the axle a wreck follows on, towed from hookZ, in its own axes; nil if it has no wheels to go by
function RseWrecks:farAxleZ(wreck, node, hookZ)
    return RseWreckRules.farAxleZ(wheelLayout(wreck, node), hookZ)
end

-- A wheel that can't steer gives way along the line (RseWreckRules.freeWheelAngle): every wheel of a trailer while you reel, and on any wreck those at the
-- end being pulled. The picture doesn't turn: its tires look dragged sideways. The game keeps a steering angle written on a wheel with no steering of its
-- own.
local function lineUpFreeWheels(wreck, node, hx, hy, hz, reeling, layout, ease)
    local vehicle = wreck.vehicle
    local aimX, _, hitchZ = worldToLocal(node, hx, hy, hz)
    local allFree = reeling and not hasSteering(vehicle)
    for _, wheel in ipairs(vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or {}) do
        local physics = wheel.physics
        if physics ~= nil and nodeExists(wheel.repr) and (physics.rotSpeed or 0) == 0 then
            physics.showSteeringAngle = false
            local _, _, wheelZ = worldToLocal(node, getWorldTranslation(wheel.repr))
            local target = 0
            if allFree or (not layout.single and RseWreckRules.isNearAxle(wheelZ, hitchZ, layout.middleZ)) then
                -- from the middle of the axle: from each wheel's own place, the two of them would point in at each other and scrub
                target = RseWreckRules.freeWheelAngle(aimX, hitchZ - wheelZ, true, RseConfig)
            end
            physics.steeringAngle = physics.steeringAngle + (target - physics.steeringAngle) * ease
        end
    end
end

-- A vehicle nobody is driving isn't active, and the game only hands a wheel's steering on to the physics for an active one (WheelPhysics:serverUpdate). So
-- whatever we set never reached the ground: from 0.4.7.2 until 0.9.5.1 the wheels of a wreck on a strap stayed straight, with no error, and it rolled along
-- its own heading (Z). We hand it on ourselves, for this vehicle's wheels only, without making it active: that would start up everything else an active
-- vehicle does. A wheel with no steering of its own is left out of the game's own update of the angle: on a car, crab steering
-- (CrabSteering:loadWheelFromXML) has that update run for every wheel, and it puts our angle back to zero (0.9.5.1's log: the wheels at 0 degrees all the
-- way).
local function pushWheels(vehicle, dt)
    for _, wheel in ipairs(vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or {}) do
        local physics = wheel.physics
        if physics ~= nil and physics.updateSteeringAngle ~= nil and physics.updatePhysics ~= nil then
            if (physics.rotSpeed or 0) ~= 0 then
                physics:updateSteeringAngle(dt)
            end
            local pedal = wheel.brakePedal or 0
            physics:updatePhysics(pedal > 0 and vehicle:getBrakeForce() * pedal or 0)
        end
    end
end

-- A wreck on a strap: the brakes follow the strap (RseWreckRules.towBrake), because a parked vehicle keeps them on (Wheels:brake), and the wheels at the end
-- being pulled follow what pulls them, so it tracks on its far axle instead of rolling along its own heading. (hx, hy, hz): where they aim.
function RseWrecks:assistTow(wreck, hx, hy, hz, brake, reeling, dt)
    local vehicle = wreck.vehicle
    local node = rootNodeOf(vehicle)
    if node == nil or vehicle.isDeleted then
        return
    end
    local wheels = vehicle.spec_wheels
    local pedal = math.floor((brake or 0) * 10 + 0.5) / 10 -- in steps: each change goes to every wheel
    if vehicle.brake ~= nil and wheels ~= nil and wheels.brakePedal ~= pedal then
        vehicle:brake(pedal)
    end
    local layout = wheelLayout(wreck, node)
    local ease = RseWreckRules.frameShare(RseConfig.TOW_STEER_EASE, dt, RseConfig)
    lineUpFreeWheels(wreck, node, hx, hy, hz, reeling, layout, ease)
    if hasSteering(vehicle) then
        local localX, _, localZ = worldToLocal(node, hx, hy, hz)
        local steer = RseWreckRules.towSteer(localX, localZ, RseConfig, layout.axleZ, layout.maxAngle)
        local target = steer >= 0 and steer * vehicle.maxRotTime or -steer * vehicle.minRotTime
        vehicle.rotatedTime = vehicle.rotatedTime + (target - vehicle.rotatedTime) * ease
    end
    pushWheels(vehicle, dt or 0)
    if vehicle.raiseActive ~= nil then
        vehicle:raiseActive()
    end
end

-- the strap has come off: it stands parked again
function RseWrecks:endTow(vehicle)
    if vehicle == nil or vehicle.isDeleted then
        return
    end
    if vehicle.brake ~= nil and vehicle.spec_wheels ~= nil then
        vehicle:brake(1)
    end
    if vehicle.rotatedTime ~= nil then
        vehicle.rotatedTime = 0
    end
    if vehicle.spec_wheels ~= nil then
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            if wheel.physics ~= nil and (wheel.physics.rotSpeed or 0) == 0 then
                wheel.physics.steeringAngle = 0
            end
        end
        pushWheels(vehicle, 0)
    end
end

-- A strap has pulled a wreck on its side: it comes over (RseStrap). Or a line is on a held one, or a train is coming for it: it is free to move.
function RseWrecks:release(wreck, what)
    unpin(wreck)
    if wreck.state == "held" then
        wreck.state = "ready"
    end
    RseLog.info("wreck %s let go by %s", wreck.kind, what or "the strap")
end

-- The train has hit it. The game's own push is only a shove (Z: an anticlimax), so it goes flying, and looks it. (alongX, alongZ): the way the train runs;
-- (awayX, awayZ): away from the track, so that the train doesn't run it down again. Both are unit vectors.
function RseWrecks:throw(wreck, alongX, alongZ, awayX, awayZ)
    local node = rootNodeOf(wreck.vehicle)
    if node == nil then
        return
    end
    local along, away, spin = RseConfig.CROSSING_THROW_ALONG, RseConfig.CROSSING_THROW_AWAY, RseConfig.CROSSING_THROW_SPIN
    setLinearVelocity(node, alongX * along + awayX * away, RseConfig.CROSSING_THROW_UP, alongZ * along + awayZ * away)
    setAngularVelocity(node, (math.random() * 2 - 1) * spin, (math.random() * 2 - 1) * spin, (math.random() * 2 - 1) * spin)
    if wreck.vehicle.setDamageAmount ~= nil then
        wreck.vehicle:setDamageAmount(0.9, true)
    end
    if wreck.smoke == nil then
        startSmoke(wreck)
    end
end

-- A held wreck only comes loose for a line (Z: ramming it mustn't move it). Our strap lets it go itself once it pulls (RseStrap). This looks for the others:
-- a Better Winch line, or anything that has hitched up to it the game's own way.
local function lineOn(wreck)
    local vehicle = wreck.vehicle
    if vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil then
        return "a vehicle hitched to it"
    end
    local winch = wreck.winchApi
    local object = winch ~= nil and winch.getAttachableObject ~= nil and winch:getAttachableObject(vehicle, true) or nil
    if object ~= nil and object.getIsAttached ~= nil and not wreck.winchAskFailed then
        local ok, attached = RseLog.try("ask Better Winch", object.getIsAttached, object)
        wreck.winchAskFailed = not ok
        if ok and attached then
            return "a winch line"
        end
    end
    return nil
end

-- where the vehicle is now, or nil
function RseWrecks:position(wreck)
    local node = rootNodeOf(wreck.vehicle)
    if node == nil or not nodeExists(node) then
        return nil
    end
    local x, _, z = getWorldTranslation(node)
    return x, z
end

-- how upright it stands: 1 on its wheels, 0 on its side, -1 on its roof
local function uprightness(wreck)
    local node = rootNodeOf(wreck.vehicle)
    if node == nil or not nodeExists(node) then
        return nil
    end
    local _, upY, _ = localDirectionToWorld(node, 0, 1, 0)
    return upY
end

-- called every frame by the steps: pins it once it has settled, seats the driver, sees it righted
function RseWrecks:update(wreck, dt)
    if wreck.vehicle == nil or wreck.vehicle.isDeleted then
        return
    end
    if wreck.pinInMs ~= nil and wreck.state == "ready" then
        wreck.pinInMs = nil -- prepared before the pin came down
    end
    if wreck.pinInMs ~= nil then
        wreck.pinInMs = wreck.pinInMs - dt
        if wreck.pinInMs <= 0 then
            wreck.pinInMs = nil
            if wreck.def.tipped and wreck.state == "locked" then
                RseLog.try("lay the wreck on its side", layOnSide, wreck) -- once more, from wherever a frame of gravity took it
            else
                RseLog.try("hold the wreck where it was put", holdWherePlaced, wreck)
            end
            local ok, data = RseLog.try("pin the wreck", pin, wreck.vehicle)
            wreck.pin = ok and data or nil
            RseLog.info("wreck %s held, uprightness %s (0 on its side, 1 on its wheels)", wreck.kind, string.format("%.2f", uprightness(wreck) or -9))
        end
    end
    if wreck.state == "held" and wreck.pin ~= nil then
        if not wreck.winchOffered then
            wreck.winchOffered = true
            wreck.winchApi = betterWinch()
            RseLog.try("offer winch points", offerWinchPoints, wreck)
        end
        local line = lineOn(wreck)
        if line ~= nil then
            self:release(wreck, line)
        end
    end
    if wreck.def.honks and wreck.state == "locked" and wreck.pin ~= nil then
        wreck.hornMs = (wreck.hornMs or RseConfig.TREE_HORN_MS[1]) - dt
        if wreck.hornMs <= 0 then
            local range = RseConfig.TREE_HORN_MS
            wreck.hornMs = range[1] + math.random() * (range[2] - range[1])
            local x, y, z = getWorldTranslation(wreck.vehicle.rootNode)
            RseSound:play(RseConfig.TREE_HORN_FILE, x, y + 1, z, RseConfig.TREE_HORN_RANGE)
        end
    end
    if wreck.showDriverInMs ~= nil then
        wreck.showDriverInMs = wreck.showDriverInMs - dt
        if wreck.showDriverInMs <= 0 then
            wreck.showDriverInMs = nil
            setDriverVisible(wreck, true)
        end
    end
    if wreck.state == "tipped" and RseWreckRules.isUpright(uprightness(wreck), RseConfig) then
        wreck.state = "ready"
        RseLog.info("wreck %s is back on its wheels", wreck.kind)
    end
end

local function atRecoveryPoint(x, z)
    return RsePoints:at(x, z, "recovery")
end

-- Sees what has reached a recovery point and lies still there. Returns true when the wreck and all its bales are in.
function RseWrecks:checkDelivered(wreck, dt)
    local rest = RseConfig.DELIVER_REST_MS
    if wreck.state == "ready" and not wreck.winchOffered and wreck.vehicle ~= nil then
        wreck.winchOffered = true
        RseLog.try("offer winch points", offerWinchPoints, wreck)
    end
    local node = rootNodeOf(wreck.vehicle)
    if not wreck.delivered and node ~= nil and wreck.state == "ready" then
        local x, _, z = getWorldTranslation(node)
        local moved = math.abs(x - (wreck.lastX or x)) + math.abs(z - (wreck.lastZ or z))
        wreck.lastX, wreck.lastZ = x, z
        if atRecoveryPoint(x, z) ~= nil and moved <= 0.02 then
            wreck.restMs = wreck.restMs + dt
            if wreck.restMs >= rest then
                wreck.delivered = true
                self:removeVehicle(wreck)
                RseText.notify(RseText.get("rse_wreck_delivered"))
                RseLog.info("wreck %s delivered", wreck.kind)
            end
        else
            wreck.restMs = 0
        end
    end
    local left = 0
    for _, item in ipairs(wreck.bales) do
        local baleBody = baleNode(item)
        if baleBody ~= nil then
            local x, _, z = getWorldTranslation(baleBody)
            local moved = math.abs(x - item.lastX) + math.abs(z - item.lastZ)
            item.lastX, item.lastZ = x, z
            local mounted = item.bale.mountObject ~= nil or item.bale.dynamicMountObject ~= nil or item.bale.dynamicMountJointIndex ~= nil
            if atRecoveryPoint(x, z) ~= nil and moved <= 0.02 and not mounted then
                item.restMs = item.restMs + dt
                if item.restMs >= rest then
                    removeBale(item)
                    item.done = true
                    wreck.balesIn = (wreck.balesIn or 0) + 1
                end
            else
                item.restMs = 0
            end
        else
            item.done = true -- gone: something else removed it
        end
        if not item.done then
            left = left + 1
        end
    end
    if wreck.balesLeft ~= left then
        if wreck.balesLeft ~= nil and left < wreck.balesLeft then
            RseText.notify(RseText.get("rse_load_delivered", left))
        end
        wreck.balesLeft = left
    end
    return wreck.delivered and left == 0
end

function RseWrecks:removeVehicle(wreck)
    if wreck.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(wreck.activatable)
        wreck.activatable = nil
    end
    unpin(wreck)
    RseLog.try("stop the smoke", stopSmoke, wreck)
    local vehicle = wreck.vehicle
    wreck.vehicle = nil
    wreck.removed = true
    if vehicle ~= nil then
        RseStrap:releaseForVehicle(vehicle)
        self.byVehicle[vehicle] = nil
        if not vehicle.isDeleted then
            RseLog.try("delete the wreck", vehicle.delete, vehicle)
        end
    end
end

-- The job is over and the vehicle waits for the county (Cleanup.lua): no prompt, and our strap lets go. A pin still holds it where it is.
function RseWrecks:retire(wreck)
    wreck.retired = true
    if wreck.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(wreck.activatable)
        wreck.activatable = nil
    end
    if wreck.vehicle ~= nil then
        RseStrap:releaseForVehicle(wreck.vehicle)
    end
end

-- the vehicle and its bales go: the county has cleared up (Cleanup.lua)
function RseWrecks:remove(wreck)
    self:removeVehicle(wreck)
    for _, item in ipairs(wreck.bales) do
        removeBale(item)
    end
    wreck.bales = {}
end

-- what the savegame keeps of a wreck and its bales
function RseWrecks:saveData(wreck)
    local data = { kind = wreck.kind, file = wreck.variant ~= nil and wreck.variant.file or nil, state = wreck.state, delivered = wreck.delivered,
        load = wreck.load ~= nil and wreck.load.id or nil, bales = {} }
    local node = rootNodeOf(wreck.vehicle)
    if node ~= nil then
        data.x, data.y, data.z = getWorldTranslation(node)
        data.rx, data.ry, data.rz = getWorldRotation(node)
    end
    for _, item in ipairs(wreck.bales) do
        local baleBody = baleNode(item)
        if baleBody ~= nil then
            local x, y, z = getWorldTranslation(baleBody)
            local rx, ry, rz = getWorldRotation(baleBody)
            table.insert(data.bales, { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz })
        end
    end
    return data
end

-- while the map unloads: the game deletes vehicles and objects itself
function RseWrecks:unload()
    self.byVehicle = setmetatable({}, { __mode = "k" })
    self.everWreck = setmetatable({}, { __mode = "k" })
    self.resetCopies = {}
    self.lastFile = {}
    self.planned = nil
    if self.resetSubscribed and g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end
    self.resetSubscribed = false
end

-- The game still sends a vehicle that fell out of the world back to the shop, and another mod could call the same reset. The copy it makes doesn't stay: it
-- would be a free vehicle with nothing locking it. It goes a moment later, so that whoever else listens to this message is done with it.
function RseWrecks:onVehicleReset(oldVehicle, newVehicle)
    if self.everWreck[oldVehicle] and newVehicle ~= nil then
        table.insert(self.resetCopies, newVehicle)
    end
end

function RseWrecks:removeResetCopies()
    for i = #self.resetCopies, 1, -1 do
        local vehicle = table.remove(self.resetCopies, i)
        if not vehicle.isDeleted then
            RseLog.info("a wreck was reset: its copy at the shop is removed")
            RseLog.try("delete the copy of a wreck", vehicle.delete, vehicle)
        end
    end
end
