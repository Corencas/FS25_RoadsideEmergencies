-- Roadside Emergencies: the scene kit. Cones and barricades, free and unlimited, each placed and picked up by hand (Z).
-- Placing is only open during a call, on foot at or right around the scene (KIT_SCENE_RADIUS): there, U opens a strip of item
-- pictures on the screen; I switches item; a preview follows where you look; L places one, or picks up the one you aim at;
-- hold O to rotate the preview; U again closes it (so do leaving the scene, the job ending and getting into a vehicle).
-- Picking up works anywhere. Traffic stops for all of them: only loose bodies stop it, so items with a fixed body get hidden
-- loose cones (RseConfig.KIT_ITEMS, P2). What you set down during a job is yours to collect: when the job ends, the county
-- keeps calling about what is still out, a map marker shows where (RseMarkers), and no new job comes until all of it is picked
-- up (KitRules.lua, Store).

RseKit = {
    entries = {},        -- { id, def, node, sharedId, yaw }
    store = nil,
    current = nil,       -- the item being placed (a KIT_ITEMS entry), or nil
    lastDef = nil,       -- the item the strip opens on
    icons = {},          -- item id -> Overlay
    drawFailed = false,
    ghost = nil,         -- { node, sharedId, defId }: the preview, without physics
    turn = 0,            -- the player's extra turn of the preview
    turnHeld = false,    -- the turn key is down
    groundHit = nil,
    reminder = nil,
    menuEventId = nil,
    useEventId = nil,
    turnEventId = nil,
    nextEventId = nil,
    settingsEventId = nil,
    shown = {}
}

local GROUND_MASK = nil

local function groundMask()
    if GROUND_MASK == nil then
        GROUND_MASK = CollisionFlag.TERRAIN + CollisionFlag.ROAD + CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING
    end
    return GROUND_MASK
end

local function defById(id)
    for _, def in ipairs(RseConfig.KIT_ITEMS) do
        if def.id == id then
            return def
        end
    end
    return nil
end

local function onFoot()
    return g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() == nil
end

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

-- $data paths must go through Utils.getFilename: the model loader doesn't resolve them itself (0.2.0.3: "not found")
local function loadModel(def)
    local filename = Utils.getFilename(def.file, RoadsideEmergencies.MOD_DIR)
    local ok, node, sharedId = RseLog.try("load kit item " .. def.id, g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or node == nil or node == 0 then
        RseLog.info("scene kit: the %s model did not load (%s)", def.id, tostring(filename))
        RseText.notify(RseText.get("rse_kit_loadFailed", RseText.get(def.textKey)), true)
        return nil
    end
    return node, sharedId
end

-- where an item is now: the cone is a loose physics body under the loaded root, so it can be knocked away from it
local function bodyNode(entry)
    if nodeExists(entry.node) and getNumOfChildren(entry.node) > 0 then
        return getChildAt(entry.node, 0)
    end
    return entry.node
end

local function release(node, sharedId)
    if nodeExists(node) then
        delete(node)
    end
    if sharedId ~= nil then
        g_i3DManager:releaseSharedI3DFile(sharedId)
    end
end

function RseKit:init(store)
    self.store = store
    self.entries = {}
    self.current = nil
    self.turn = 0
    self.reminder = RseKitRules.newReminder()
end

-- how many items from ended jobs are still out; no new job until this is 0
function RseKit:owedCount()
    return self.store ~= nil and self.store:kitOwedCount() or 0
end

local function positions(self, onlyOwed)
    local list = {}
    for _, entry in ipairs(self.entries) do
        local record = self.store.kit[entry.id]
        if nodeExists(entry.node) and (not onlyOwed or (record ~= nil and record.owed)) then
            local x, y, z = getWorldTranslation(bodyNode(entry))
            table.insert(list, { x = x, y = y + entry.def.aimHeight, z = z, radius = entry.def.pickRadius, entry = entry })
        end
    end
    return list
end

-- a hidden loose cone at x, z, which is what stops traffic (P2: a cone with its mesh hidden); y: the height of whatever it stands in for.
-- Returns { node, sharedId }, or nil.
function RseKit.newBlocker(x, y, z)
    local filename = Utils.getFilename(RseConfig.KIT_BLOCKER_FILE, RoadsideEmergencies.MOD_DIR)
    local ok, node, sharedId = RseLog.try("load a traffic blocker", g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or node == nil or node == 0 then
        return nil
    end
    link(getRootNode(), node)
    local terrain = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    setWorldTranslation(node, x, (math.abs(terrain - y) < 2 and terrain or y) + 0.02, z)
    addToPhysics(node)
    if getNumOfChildren(node) > 0 then
        local body = getChildAt(node, 0)
        for i = 0, getNumOfChildren(body) - 1 do
            setVisibility(getChildAt(body, i), false)
        end
    end
    return { node = node, sharedId = sharedId }
end

function RseKit.removeBlocker(blocker)
    release(blocker.node, blocker.sharedId)
end

-- where it is now: x, y, z (something may have knocked it away)
function RseKit.blockerPosition(blocker)
    local body = getNumOfChildren(blocker.node) > 0 and getChildAt(blocker.node, 0) or blocker.node
    return getWorldTranslation(body)
end

-- hidden cones across the item
local function addBlockers(entry, def, y)
    entry.blockers = {}
    for _, offset in ipairs(def.blockers or {}) do
        local x, _, z = localToWorld(entry.node, offset, 0, 0)
        local blocker = RseKit.newBlocker(x, y, z)
        if blocker ~= nil then
            table.insert(entry.blockers, blocker)
        end
    end
end

local function removeBlockers(entry)
    for _, blocker in ipairs(entry.blockers or {}) do
        RseKit.removeBlocker(blocker)
    end
    entry.blockers = {}
end

-- puts an item in the world. Returns the entry, or nil and a reason.
local function place(self, def, x, y, z, yaw, sceneId, owed)
    local id, reason = self.store:apply("addKitItem", { item = def.id, sceneId = sceneId, owed = owed })
    if id == nil then
        return nil, reason
    end
    local node, sharedId = loadModel(def)
    if node == nil then
        self.store:apply("removeKitItem", { id = id })
        return nil, "the model did not load"
    end
    link(getRootNode(), node)
    setWorldTranslation(node, x, y, z)
    setWorldRotation(node, 0, yaw, 0)
    if def.physics then
        addToPhysics(node)
    end
    local entry = { id = id, def = def, node = node, sharedId = sharedId, yaw = yaw }
    addBlockers(entry, def, y)
    table.insert(self.entries, entry)
    return entry
end

local function pickUp(self, entry)
    for i, candidate in ipairs(self.entries) do
        if candidate == entry then
            table.remove(self.entries, i)
            break
        end
    end
    RseMarkers:hide(entry)
    release(entry.node, entry.sharedId)
    removeBlockers(entry)
    local wasOwed = self:owedCount() > 0
    self.store:apply("removeKitItem", { id = entry.id })
    if wasOwed and self:owedCount() == 0 then
        RseText.notify(RseText.get("rse_kit_allCollected"))
    end
end

---------------------------------------------------------------------------------------------------
-- Aiming
---------------------------------------------------------------------------------------------------

local function viewRay()
    local camera = g_cameraManager ~= nil and g_cameraManager:getActiveCamera() or nil
    if camera == nil then
        return nil
    end
    local cx, cy, cz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    return cx, cy, cz, dx, dy, dz
end

function RseKit:onGroundRaycast(hitObjectId, x, y, z)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.groundHit = { x = x, y = y, z = z }
        return false
    end
    return true
end

-- the item you look at, for picking it up
local function aimedEntry(self, cx, cy, cz, dx, dy, dz)
    local hit = RseKitRules.aimed(positions(self, false), cx, cy, cz, dx, dy, dz, RseConfig.KIT_PICK_REACH, RseConfig.KIT_PICK_RADIUS)
    return hit ~= nil and hit.entry or nil
end

---------------------------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------------------------

local function removeGhost(self)
    if self.ghost ~= nil then
        release(self.ghost.node, self.ghost.sharedId)
        self.ghost = nil
    end
end

local function updateGhost(self, cx, cy, cz, dx, dy, dz)
    self.groundHit = nil
    if self.current == nil or cx == nil then
        removeGhost(self)
        return
    end
    if self.ghost == nil or self.ghost.defId ~= self.current.id then
        removeGhost(self)
        local node, sharedId = loadModel(self.current)
        if node == nil then
            self.current = nil
            return
        end
        link(getRootNode(), node) -- no addToPhysics: the preview has no collision
        self.ghost = { node = node, sharedId = sharedId, defId = self.current.id }
    end
    raycastClosest(cx, cy, cz, dx, dy, dz, RseConfig.KIT_REACH, "onGroundRaycast", self, groundMask())
    local hit = self.groundHit
    setVisibility(self.ghost.node, hit ~= nil)
    if hit ~= nil then
        hit.yaw = math.atan2(dx, dz) + self.turn
        setWorldTranslation(self.ghost.node, hit.x, hit.y, hit.z)
        setWorldRotation(self.ghost.node, 0, hit.yaw, 0)
    end
end

---------------------------------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------------------------------

local function choose(self, def)
    self.current = def
    self.turn = 0
    if def ~= nil then
        self.lastDef = def
    else
        removeGhost(self)
    end
end

-- placing is only open during a call, on foot at or right around the scene (Z)
local function atScene()
    local scene = RseScenes:get(RseScenes:activeId())
    if scene == nil or not onFoot() then
        return false
    end
    local x, _, z = g_localPlayer:getPosition()
    local dx, dz = x - scene.x, z - scene.z
    return dx * dx + dz * dz <= RseConfig.KIT_SCENE_RADIUS * RseConfig.KIT_SCENE_RADIUS
end

-- H: the settings panel, which has its own keys while it is open
function RseKit:onSettings()
    if not onFoot() then
        return
    end
    choose(self, nil)
    RseSettingsPanel:requestOpen()
end

-- U: opens the strip on the item used last, or closes it
function RseKit:onMenu()
    if not atScene() then
        return
    end
    if self.current ~= nil then
        choose(self, nil)
    else
        choose(self, self.lastDef or RseConfig.KIT_ITEMS[1])
    end
end

-- I: the next item on the strip
function RseKit:onNext()
    if self.current == nil then
        return
    end
    local items = RseConfig.KIT_ITEMS
    for i, def in ipairs(items) do
        if def == self.current then
            choose(self, items[i % #items + 1])
            return
        end
    end
end

function RseKit:onUse()
    if not onFoot() then
        return
    end
    local cx, cy, cz, dx, dy, dz = viewRay()
    if cx == nil then
        return
    end
    local aimed = aimedEntry(self, cx, cy, cz, dx, dy, dz)
    if aimed ~= nil then
        pickUp(self, aimed)
        return
    end
    local hit = self.groundHit
    if self.current ~= nil and hit ~= nil then
        -- a little above the ground, so a loose body doesn't start inside it
        local entry, reason = place(self, self.current, hit.x, hit.y + 0.02, hit.z, hit.yaw or 0, RseScenes:activeId(), false)
        if entry == nil then
            if reason == "limit" then
                RseText.notify(RseText.get("rse_kit_limit", RseConfig.KIT_MAX_ITEMS), true)
            else
                RseLog.info("scene kit: not placed: %s", tostring(reason))
            end
        end
    end
end

-- called every frame while the event is active; inputValue tells whether the key is down
function RseKit:onTurn(_, inputValue)
    self.turnHeld = (inputValue or 0) > 0
end

-- added to the local player's own key registration, like the strap key
function RseKit:registerActionEvents()
    if InputAction.RSE_KIT_MENU == nil then
        return
    end
    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    for _, name in ipairs({ "menuEventId", "useEventId", "turnEventId", "nextEventId", "settingsEventId" }) do
        if self[name] ~= nil then
            g_inputBinding:removeActionEvent(self[name])
            self[name] = nil
        end
    end
    local _, menuId = g_inputBinding:registerActionEvent(InputAction.RSE_KIT_MENU, self, self.onMenu, false, true, false, false)
    local _, useId = g_inputBinding:registerActionEvent(InputAction.RSE_KIT_USE, self, self.onUse, false, true, false, false)
    local _, turnId = g_inputBinding:registerActionEvent(InputAction.RSE_KIT_TURN, self, self.onTurn, false, true, true, false)
    local _, nextId = g_inputBinding:registerActionEvent(InputAction.RSE_KIT_NEXT, self, self.onNext, false, true, false, false)
    local _, settingsId = g_inputBinding:registerActionEvent(InputAction.RSE_SETTINGS, self, self.onSettings, false, true, false, true)
    self.menuEventId, self.useEventId, self.turnEventId, self.nextEventId, self.settingsEventId = menuId, useId, turnId, nextId, settingsId
    self.shown = {}
    -- high priority: the help list only has room for so many lines, and 0.2.0.4's U line didn't make it
    if menuId ~= nil then
        g_inputBinding:setActionEventText(menuId, RseText.action("rse_kit_open"))
        g_inputBinding:setActionEventTextPriority(menuId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventTextVisibility(menuId, false)
    end
    if useId ~= nil then
        g_inputBinding:setActionEventTextPriority(useId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventTextVisibility(useId, false)
    end
    if turnId ~= nil then
        g_inputBinding:setActionEventTextPriority(turnId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventTextVisibility(turnId, false)
    end
    if nextId ~= nil then
        g_inputBinding:setActionEventText(nextId, RseText.action("rse_kit_next"))
        g_inputBinding:setActionEventTextPriority(nextId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventTextVisibility(nextId, false)
    end
    if settingsId ~= nil then
        g_inputBinding:setActionEventText(settingsId, RseText.action("rse_set_open"))
    end
    g_inputBinding:endActionEventsModification()
end

local function showEvent(self, name, eventId, active, visible, text)
    if eventId == nil then
        return
    end
    local key = name .. "State"
    local state = (active and "a" or "-") .. (visible and "v" or "-")
    if self.shown[key] ~= state then
        g_inputBinding:setActionEventActive(eventId, active)
        g_inputBinding:setActionEventTextVisibility(eventId, visible)
        self.shown[key] = state
    end
    if text ~= nil and self.shown[name .. "Text"] ~= text then
        g_inputBinding:setActionEventText(eventId, text)
        self.shown[name .. "Text"] = text
    end
end

---------------------------------------------------------------------------------------------------
-- Frame update
---------------------------------------------------------------------------------------------------

-- the county's reminders and the map marker, while items from ended jobs are out
-- a marker on each item, exactly where it stands: steady for the job in progress, blinking when it is left from an earlier job and the county waits for it
local function updateItemMarkers(self, dt)
    self.markerMs = (self.markerMs or 0) - dt
    if self.markerMs > 0 then
        return
    end
    self.markerMs = 500
    for _, item in ipairs(positions(self, false)) do
        local entry = item.entry
        local record = self.store.kit[entry.id]
        entry.markerInfo = entry.markerInfo or { kind = "kit", title = RseText.get(entry.def.textKey),
            image = Utils.getFilename(entry.def.icon, RoadsideEmergencies.MOD_DIR) }
        RseMarkers:show(entry, item.x, item.z, { steady = record == nil or not record.owed, name = entry.markerInfo.title, image = "kit",
            info = entry.markerInfo })
    end
end

local function updateOwed(self, dt)
    updateItemMarkers(self, dt)
    local owed = positions(self, true)
    if #owed == 0 then
        RseKitRules.tickReminder(self.reminder, dt, 0, false, RseConfig)
        return
    end
    local cx, cz = RseKitRules.centre(owed)
    local near = false
    if g_localPlayer ~= nil then
        local vehicle = g_localPlayer:getCurrentVehicle()
        local px, pz
        if vehicle ~= nil and vehicle.rootNode ~= nil then
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            px, pz = vx, vz
        else
            local fx, _, fz = g_localPlayer:getPosition()
            px, pz = fx, fz
        end
        for _, item in ipairs(owed) do
            near = near or (item.x - px) ^ 2 + (item.z - pz) ^ 2 <= RseConfig.KIT_REMINDER_NEAR ^ 2
        end
    end
    if RseKitRules.tickReminder(self.reminder, dt, #owed, near, RseConfig) then
        RseText.notify(RseText.get("rse_kit_reminder", #owed), true)
        RseLog.info("county reminder: %d kit item(s) still out, around %.0f, %.0f", #owed, cx, cz)
    end
end

function RseKit:update(dt)
    if self.store == nil then
        return
    end
    local foot = onFoot()
    local cx, cy, cz, dx, dy, dz = nil, nil, nil, nil, nil, nil
    if foot then
        cx, cy, cz, dx, dy, dz = viewRay()
    end
    local canPlace = atScene()
    if self.current ~= nil and not canPlace then
        choose(self, nil) -- the job ended, you left the scene, or you got into a vehicle
    end
    -- the key sets this again every frame while it is down; cleared here, so the preview can't keep spinning after a release
    if self.turnHeld and self.current ~= nil then
        self.turn = self.turn + RseConfig.KIT_TURN_SPEED * dt
    end
    self.turnHeld = false
    updateGhost(self, cx, cy, cz, dx, dy, dz)
    local aimed = cx ~= nil and aimedEntry(self, cx, cy, cz, dx, dy, dz) or nil
    local placing = foot and self.current ~= nil

    -- F1 lines name the item in hand or aimed at (Z: "Set down: pylon barrier" while holding a cone, and "Turn it" said nothing)
    local useText = nil
    if aimed ~= nil then
        useText = RseText.action("rse_kit_pickup", RseText.get("rse_kitShort_" .. aimed.def.id))
    elseif placing and self.groundHit ~= nil then
        useText = RseText.action("rse_kit_place", RseText.get("rse_kitShort_" .. self.current.id))
    end
    showEvent(self, "use", self.useEventId, useText ~= nil, useText ~= nil, useText)
    showEvent(self, "turn", self.turnEventId, placing, placing,
        placing and RseText.action("rse_kit_turn", RseText.get("rse_kitShort_" .. self.current.id)) or nil)
    showEvent(self, "next", self.nextEventId, placing, placing, RseText.action("rse_kit_next"))
    showEvent(self, "settings", self.settingsEventId, foot, foot, RseText.action("rse_set_open"))
    -- the menu key and its help line exist only where placing is open
    showEvent(self, "menu", self.menuEventId, canPlace, canPlace, RseText.action(placing and "rse_kit_stop" or "rse_kit_open"))

    updateOwed(self, dt)
end

---------------------------------------------------------------------------------------------------
-- The strip: the items as a row of pictures while placing (Z chose this over a dialog, M2 round 5)
---------------------------------------------------------------------------------------------------

-- sizes in pixels at 1920 x 1080
local TILE_WIDTH, TILE_HEIGHT, TILE_GAP, ICON_SIZE, STRIP_BOTTOM = 168, 148, 10, 104, 46
local TEXT_SIZE = 0.012

local function iconFor(self, def)
    if self.icons[def.id] == nil then
        self.icons[def.id] = Overlay.new(Utils.getFilename(def.icon, RoadsideEmergencies.MOD_DIR), 0, 0, 1, 1)
    end
    return self.icons[def.id]
end

local function drawStrip(self)
    local sx, sy = (1 / 1920) * ((16 / 9) / g_screenAspectRatio), 1 / 1080
    local items = RseConfig.KIT_ITEMS
    local tileW, tileH, gap = TILE_WIDTH * sx, TILE_HEIGHT * sy, TILE_GAP * sx
    local x, y = 0.5 - (#items * tileW + (#items - 1) * gap) / 2, STRIP_BOTTOM * sy
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    for _, def in ipairs(items) do
        local selected = def == self.current
        drawFilledRect(x, y, tileW, tileH, 0, 0, 0, selected and 0.72 or 0.48)
        if selected then
            RseDraw.rect(RseTheme.ACCENT, x, y + tileH - 5 * sy, tileW, 5 * sy)
        end
        local icon = iconFor(self, def)
        icon:setDimension(ICON_SIZE * sx, ICON_SIZE * sy)
        icon:setPosition(x + (tileW - ICON_SIZE * sx) / 2, y + 32 * sy)
        icon:setColor(1, 1, 1, selected and 1 or 0.55)
        icon:render()
        setTextColor(1, 1, 1, selected and 1 or 0.7)
        renderText(x + tileW / 2, y + 10 * sy, TEXT_SIZE, RseText.get(def.textKey))
        x = x + tileW + gap
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- Anything drawn every frame can take the whole GUI down (M1), so it only draws while placing, not behind menus, and one
-- failure switches it off for the session.
function RseKit:draw()
    if self.current == nil or self.drawFailed or (g_gui ~= nil and g_gui:getIsGuiVisible()) then
        return
    end
    if not RseLog.try("scene kit strip", drawStrip, self) then
        self.drawFailed = true
    end
end

-- rseKit: how far each hidden traffic blocker has moved from its item
function RseKit:logBlockers()
    for _, entry in ipairs(self.entries) do
        for i, blocker in ipairs(entry.blockers or {}) do
            if nodeExists(blocker.node) and getNumOfChildren(blocker.node) > 0 then
                local bx, _, bz = getWorldTranslation(getChildAt(blocker.node, 0))
                local ix, _, iz = getWorldTranslation(entry.node)
                RseLog.info("kit %s blocker %d: at %.1f, %.1f, %.1f m from its item (offset %.1f)", entry.def.id, i, bx, bz,
                    math.sqrt((bx - ix) ^ 2 + (bz - iz) ^ 2), entry.def.blockers[i])
            end
        end
    end
end

-- a job ended: what was set down for it is now owed
function RseKit:onJobEnded(sceneId)
    local count = self.store:apply("kitJobEnded", { sceneId = sceneId })
    if count ~= nil and count > 0 then
        RseText.notify(RseText.get("rse_kit_collect", count), true)
        RseLog.info("job ended with %d kit item(s) still out", count)
    end
end

-- what the savegame keeps (job: placed for the call in progress, which comes back after loading)
function RseKit:saveData()
    local list = {}
    for _, entry in ipairs(self.entries) do
        local record = self.store.kit[entry.id]
        if record ~= nil and nodeExists(entry.node) then
            local x, y, z = getWorldTranslation(bodyNode(entry))
            table.insert(list, { item = entry.def.id, x = x, y = y, z = z, yaw = entry.yaw, owed = record.owed, job = record.sceneId ~= nil })
        end
    end
    return list
end

function RseKit:restore(saved)
    local placed = 0
    for _, data in ipairs(saved) do
        local def = defById(data.item)
        if def ~= nil and place(self, def, data.x, data.y, data.z, data.yaw, data.job and "resume" or nil, data.owed) ~= nil then
            placed = placed + 1
        end
    end
    return placed
end

-- removes every item (rseKit clear)
function RseKit:clear()
    while #self.entries > 0 do
        pickUp(self, self.entries[1])
    end
end

-- while the map unloads
function RseKit:unload()
    removeGhost(self)
    for _, entry in ipairs(self.entries) do
        release(entry.node, entry.sharedId)
        removeBlockers(entry)
    end
    self.entries = {}
    self.current = nil
    self.lastDef = nil
    self.turnHeld = false
    self.drawFailed = false
    for _, icon in pairs(self.icons) do
        RseLog.try("delete a kit picture", icon.delete, icon)
    end
    self.icons = {}
    self.store = nil
    self.menuEventId, self.useEventId, self.turnEventId, self.nextEventId, self.settingsEventId = nil, nil, nil, nil, nil
    self.shown = {}
end
