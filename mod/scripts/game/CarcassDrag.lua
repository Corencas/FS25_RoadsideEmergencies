-- Roadside Emergencies: dragging a small carcass by hand, through the game's own activate prompt (P8).
-- Up to DRAG_MAX_MASS_KG; heavier animals say they are too heavy (a strap or a machine moves them). While dragged, the body is
-- kinematic and kept DRAG_LENGTH behind you, its long side pointing at you, on the ground.

RseCarcassDrag = {
    dragged = nil
}

local RseCarcassActivatable = {}
local RseCarcassActivatable_mt = Class(RseCarcassActivatable)

function RseCarcassDrag.newActivatable(entry)
    local self = setmetatable({}, RseCarcassActivatable_mt)
    self.entry = entry
    self.activateText = ""
    return self
end

local function onFoot()
    return g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() == nil
end

local function distance2D(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return math.sqrt(dx * dx + dz * dz)
end

function RseCarcassActivatable:getIsActivatable()
    local entry = self.entry
    local node = RseCarcasses:bodyNode(entry)
    if node == nil or not onFoot() or RseCarcasses:isMounted(entry) or RseStrap:isStrapped(entry) then
        return false
    end
    local name = RseText.animalShort(entry.kind)
    if RseCarcassDrag.dragged == entry then
        self.activateText = RseText.action("rse_action_letGo", name)
        return true
    end
    local px, _, pz = g_localPlayer:getPosition()
    local cx, _, cz = getWorldTranslation(node)
    if distance2D(px, pz, cx, cz) > RseConfig.DRAG_REACH then
        return false
    end
    if RseAnimalCatalog.isDraggable(entry.kind, RseConfig.DRAG_MAX_MASS_KG) then
        self.activateText = RseText.action("rse_action_drag", name)
    else
        self.activateText = RseText.action("rse_action_tooHeavyShort") -- pressing it says why, in full
    end
    return true
end

function RseCarcassActivatable:getDistance(x, y, z)
    local node = RseCarcasses:bodyNode(self.entry)
    if node == nil then
        return math.huge
    end
    local cx, cy, cz = getWorldTranslation(node)
    local dx, dy, dz = x - cx, y - cy, z - cz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function RseCarcassActivatable:run()
    RseCarcassDrag.toggle(self.entry)
end

-- lets go of the carcass (if it is the dragged one); the body falls back under physics
function RseCarcassDrag.release(entry)
    if RseCarcassDrag.dragged ~= entry then
        return
    end
    RseCarcassDrag.dragged = nil
    entry.dragged = false
    local node = RseCarcasses:bodyNode(entry)
    if node ~= nil then
        setRigidBodyType(node, RigidBodyType.DYNAMIC)
        RseLog.try("carcass wakeUp", entry.body.wakeUp, entry.body)
    end
end

function RseCarcassDrag.toggle(entry)
    if RseCarcassDrag.dragged == entry then
        RseCarcassDrag.release(entry)
        return
    end
    if not RseAnimalCatalog.isDraggable(entry.kind, RseConfig.DRAG_MAX_MASS_KG) then
        RseText.notify(RseText.get("rse_action_tooHeavy", RseText.animal(entry.kind)), true)
        return
    end
    local node = RseCarcasses:bodyNode(entry)
    if node == nil then
        return
    end
    if RseCarcassDrag.dragged ~= nil then
        RseCarcassDrag.release(RseCarcassDrag.dragged)
    end
    setRigidBodyType(node, RigidBodyType.KINEMATIC)
    RseCarcassDrag.dragged = entry
    entry.dragged = true
end

function RseCarcassDrag.update()
    local entry = RseCarcassDrag.dragged
    if entry == nil then
        return
    end
    local node = RseCarcasses:bodyNode(entry)
    if node == nil or not onFoot() then
        RseCarcassDrag.release(entry)
        return
    end
    local px, _, pz = g_localPlayer:getPosition()
    local cx, _, cz = getWorldTranslation(node)
    local dx, dz = cx - px, cz - pz
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 0.01 then
        return
    end
    local length = RseConfig.DRAG_LENGTH
    if d > length then
        cx, cz = px + dx / d * length, pz + dz / d * length
    end
    local height = RseConfig.BODY_SIZE[entry.def.body][2]
    setWorldTranslation(node, cx, getTerrainHeightAtWorldPos(g_terrainNode, cx, 0, cz) + height / 2 + 0.02, cz)
    setWorldRotation(node, 0, math.atan2(-dx, -dz), 0)
end
