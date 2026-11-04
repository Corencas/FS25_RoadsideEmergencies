-- Roadside Emergencies: clicking one of our markers on the game's map (Z, M4 round 3): a picture of what it is, its name, and what you can do:
-- teleport there, have the county collect a dead animal now, remove a drop-off point of your own. Each marker of ours
-- carries a table `rseMarker` (RseMarkers:show) and a click area. The game's map screen only lets through the marker categories it knows, so a wrap
-- of IngameMapElement.selectHotspotAt catches a click on one of ours first and selects it; any other click goes on as before. A call after
-- InGameMenuMapFrame.setMapSelectionItem then shows the box the game uses for vehicles, with our buttons added to its list. The FS25 source of that
-- screen isn't public: the names come from the FS22 source and Courseplay's FS25 map page, and M4 round 4's log confirmed them. If the box can't be
-- shown, a game dialog offers the same things. All of it runs protected, so a failure here can't touch the map.

RseMapClicks = {
    reported = false,
    pending = nil    -- a teleport on its way: { x, y, z, stage }
}

local TELEPORT_OFFSET = 2 -- beside what you teleport to, not inside it

local function farmId()
    local mission = g_currentMission
    return mission.getFarmId ~= nil and mission:getFarmId() or 1
end

local function closeMenu()
    g_gui:changeScreen(nil)
end

-- Teleporting waits for the next updates: the menu closes first, then you leave any vehicle, then you move.
local function requestTeleport(hotspot, info)
    local x, z = hotspot:getWorldPosition()
    local y = info.y
    local terrain = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    if y == nil or y < terrain then
        y = terrain
    end
    RseMapClicks.pending = { x = x + TELEPORT_OFFSET, y = y + 0.3, z = z, stage = 1 }
    closeMenu()
end

function RseMapClicks:update()
    local pending = self.pending
    if pending == nil or g_localPlayer == nil then
        return
    end
    if pending.stage == 1 then
        pending.stage = 2
        if g_localPlayer:getCurrentVehicle() ~= nil then
            RseLog.try("leave the vehicle", g_localPlayer.leaveVehicle, g_localPlayer)
        end
    else
        self.pending = nil
        RseLog.try("teleport", g_localPlayer.teleportTo, g_localPlayer, pending.x, pending.y, pending.z, true, true)
        RseLog.debug("teleported to %.1f, %.1f", pending.x, pending.z)
    end
end

-- what a marker offers: { { textKey, run }, ... }
local function actionsFor(hotspot, info)
    local list = { { textKey = "rse_map_teleport", run = function()
        requestTeleport(hotspot, info)
    end } }
    if info.kind == "dead" and info.entry ~= nil then
        table.insert(list, { textKey = "rse_map_collect", run = function()
            RseScenes:collectNow(info.entry)
            closeMenu()
        end })
    elseif info.kind == "point" and info.point ~= nil and RsePoints:numberOf(info.point) ~= nil then
        table.insert(list, { textKey = "rse_map_removePoint", run = function()
            if RsePoints.store:apply("removePoint", { id = info.point.id }) ~= nil then
                RseText.notify(RseText.get("rse_point_removed", info.point.name))
            end
            closeMenu()
        end })
    end
    return list
end

-- names only, once: what the game's map screen has, for fitting this to it
local function reportNames(frame)
    if RseMapClicks.reported then
        return
    end
    RseMapClicks.reported = true
    local names = {}
    for key in pairs(frame) do
        local name = string.lower(tostring(key))
        if string.find(name, "context", 1, true) ~= nil or string.find(name, "button", 1, true) ~= nil or name == "currenthotspot" then
            table.insert(names, tostring(key))
        end
    end
    table.sort(names)
    local actions = {}
    for key, action in pairs(type(frame.contextActions) == "table" and frame.contextActions or {}) do
        local fields = {}
        for field in pairs(type(action) == "table" and action or {}) do
            table.insert(fields, tostring(field))
        end
        table.sort(fields)
        table.insert(actions, tostring(key) .. "(" .. table.concat(fields, ",") .. ")")
    end
    table.sort(actions)
    RseLog.info("map screen names: %s", table.concat(names, " "))
    local showBoxType = InGameMenuMapUtil ~= nil and type(InGameMenuMapUtil.showContextBox) or "no util"
    RseLog.info("map screen actions: %s; showContextBox %s", table.concat(actions, " "), tostring(showBoxType))
end

-- our buttons go at the end of the game's list; they stay there, switched off, when something else is selected
local function setButtons(frame, list)
    local actions = frame.contextActions
    frame.rseActionSlots = frame.rseActionSlots or {}
    local slots = frame.rseActionSlots
    for i = 1, math.max(#slots, #list) do
        if slots[i] == nil or actions[slots[i]] == nil then
            slots[i] = #actions + 1
        end
        local def = list[i]
        actions[slots[i]] = { text = def ~= nil and RseText.get(def.textKey) or "", title = def ~= nil and RseText.get(def.textKey) or "",
            callback = def ~= nil and def.run or function() end, isActive = def ~= nil }
    end
    frame.contextButtonList:reloadData()
end

local function showBox(frame, hotspot, info)
    if type(frame.contextActions) ~= "table" or frame.contextBox == nil or frame.contextButtonList == nil or InGameMenuMapUtil == nil
        or type(InGameMenuMapUtil.showContextBox) ~= "function" then
        error("the map screen has no context box as expected")
    end
    frame.currentHotspot = hotspot
    frame.currentContextBox = frame.contextBox
    InGameMenuMapUtil.showContextBox(frame.contextBox, hotspot, info.title, info.image, Overlay.DEFAULT_UVS, farmId())
    setButtons(frame, actionsFor(hotspot, info))
    if frame.updateContextActions ~= nil then
        RseLog.try("the box's buttons", frame.updateContextActions, frame)
    end
    if FocusManager ~= nil then
        RseLog.try("the box's focus", FocusManager.setFocus, FocusManager, frame.contextButtonList)
    end
end

-- the same choices in a game dialog, if the box can't be shown
local function showDialog(hotspot, info)
    local list = actionsFor(hotspot, info)
    local options = {}
    for _, def in ipairs(list) do
        table.insert(options, RseText.get(def.textKey))
    end
    OptionDialog.show(function(index)
        if type(index) == "number" and list[index] ~= nil then
            list[index].run()
        end
    end, info.title, "", options)
end

local function onSelected(frame, hotspot)
    reportNames(frame)
    local info = type(hotspot) == "table" and hotspot.rseMarker or nil
    if info == nil then
        if frame.rseActionSlots ~= nil and type(frame.contextActions) == "table" then
            setButtons(frame, {})
        end
        return
    end
    if not RseLog.try("show the marker's box", showBox, frame, hotspot, info) then
        RseLog.try("show the marker's dialog", showDialog, hotspot, info)
    end
end

-- the marker of ours under the mouse, or nil. Ours are drawn on top of the others, so they go first.
local function markerAt(posX, posY)
    local best, bestDistance = nil, math.huge
    for _, marker in pairs(RseMarkers.markers) do
        local hotspot = marker.hotspot
        if hotspot.rseMarker ~= nil and hotspot:getIsVisible() then
            local isOver, distance = hotspot:hasMouseOverlap(posX, posY)
            if isOver and (distance or 0) < bestDistance then
                best, bestDistance = hotspot, distance or 0
            end
        end
    end
    return best
end

-- true if the click was on a marker of ours, on the game's own map screen
local function clickOurs(element, posX, posY)
    local frame = element.target
    if not element.isHotspotSelectionActive or type(frame) ~= "table" or frame.setMapSelectionItem ~= InGameMenuMapFrame.setMapSelectionItem then
        return false
    end
    local hotspot = markerAt(posX, posY)
    if hotspot == nil then
        return false
    end
    RseLog.info("map click on our marker: %s, %s", tostring(hotspot.rseMarker.kind), tostring(hotspot.rseMarker.title))
    frame:setMapSelectionItem(hotspot)
    return true
end

-- both wrap the stored original, so another savegame doesn't stack them
local function appendTo(class, name, fn)
    local key = "rseOriginal_" .. name
    if class[key] == nil then
        class[key] = class[name]
    end
    class[name] = Utils.appendedFunction(class[key], fn)
end

local function overwrite(class, name, fn)
    local key = "rseOriginal_" .. name
    if class[key] == nil then
        class[key] = class[name]
    end
    class[name] = Utils.overwrittenFunction(class[key], fn)
end

-- the map screen exists before mods load
function RseMapClicks.install()
    if InGameMenuMapFrame == nil or type(InGameMenuMapFrame.setMapSelectionItem) ~= "function"
        or IngameMapElement == nil or type(IngameMapElement.selectHotspotAt) ~= "function" then
        RseLog.info("the game's map screen isn't as expected: clicking our markers does nothing")
        return false
    end
    appendTo(InGameMenuMapFrame, "setMapSelectionItem", function(frame, hotspot)
        RseLog.try("a click on the map", onSelected, frame, hotspot)
    end)
    overwrite(IngameMapElement, "selectHotspotAt", function(element, superFunc, posX, posY)
        local ok, handled = RseLog.try("a click on our marker", clickOurs, element, posX, posY)
        if not (ok and handled) then
            return superFunc(element, posX, posY)
        end
    end)
    return true
end

function RseMapClicks:unload()
    self.pending = nil
    self.reported = false
end

RseMapClicks.install()
