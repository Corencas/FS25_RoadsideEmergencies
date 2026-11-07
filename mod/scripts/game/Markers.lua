-- Roadside Emergencies: map markers for what is still out: scene kit items, each animal left behind or loose, and drop-off points. As many as needed, each
-- under its own key. Uses AITargetHotspot, a marker that stands on its own (a PlaceableHotspot without a placeable broke the whole
-- in-game menu in 0.1.0.0). Proven by Z in M2 round 4: map and in-game menu fine. rseMarkers off switches them off for this session.
-- Each kind has its own picture, by giving the marker's own overlay another image (Overlay:setImage): the same object the game draws, only the picture changes.
-- Courseplay and AdditionalContracts also put their own icons on map markers. The colour is in the picture (tools/marker_icons.py): the game draws each marker
-- in the colour stored on it, over anything set on the image. A marker also carries `rseMarker`, what a click on it shows (MapClicks.lua).

RseMarkers = {
    enabled = true,
    markers = {},   -- key -> { hotspot, x, z }
    reported = false
}

function RseMarkers:setEnabled(enabled)
    self.enabled = enabled
    if not enabled then
        self:clear()
    end
end

-- the file of one of our marker pictures
function RseMarkers.imagePath(image)
    return Utils.getFilename("icons/marker_" .. image .. ".dds", RoadsideEmergencies.MOD_DIR)
end

local function setImage(marker, image)
    marker.image = image
    local icon = marker.hotspot.icon
    if type(icon) ~= "table" or icon.setImage == nil or icon.setUVs == nil then
        if not RseMarkers.reportedIcon then
            RseMarkers.reportedIcon = true
            RseLog.info("this map marker has no overlay to give a picture: it keeps the game's")
        end
        return
    end
    icon:setImage(RseMarkers.imagePath(image))
    icon:setUVs({ unpack(Overlay.DEFAULT_UVS) })
    if marker.hotspot.setColor ~= nil then
        marker.hotspot:setColor(1, 1, 1)
    end
end

-- smaller than the game's markers, on both maps: the map scales a marker from the overlay's default size
local function shrink(hotspot)
    local icon = hotspot.icon
    if type(icon) == "table" and icon.defaultWidth ~= nil and icon.defaultHeight ~= nil and icon.setScale ~= nil then
        icon.defaultWidth, icon.defaultHeight = icon.defaultWidth * RseConfig.MARKER_SCALE, icon.defaultHeight * RseConfig.MARKER_SCALE
        icon:setScale(icon.scaleWidth or 1, icon.scaleHeight or 1)
    end
end

local function create(steady, name)
    if type(AITargetHotspot) ~= "table" or type(AITargetHotspot.new) ~= "function" then
        if not RseMarkers.reported then
            RseMarkers.reported = true
            RseLog.info("AITargetHotspot not found: no map markers")
        end
        return nil
    end
    local ok, hotspot = RseLog.try("create a map marker", AITargetHotspot.new)
    if not ok or hotspot == nil then
        return nil
    end
    g_currentMission:addMapHotspot(hotspot)
    RseLog.try("map marker blinking", hotspot.setBlinking, hotspot, not steady)
    RseLog.try("map marker persistent", hotspot.setPersistent, hotspot, true)
    RseLog.try("map marker visible", hotspot.setVisible, hotspot, true)
    if name ~= nil and hotspot.setName ~= nil then
        RseLog.try("map marker name", hotspot.setName, hotspot, name)
    end
    RseLog.try("map marker size", shrink, hotspot)
    -- a marker without a click area can't be clicked at all (MapHotspot:hasMouseOverlap), and this kind has none of its own (M4 round 4)
    if MapHotspot ~= nil and MapHotspot.getClickCircle ~= nil then
        hotspot.clickArea = MapHotspot.getClickCircle(1)
    end
    return hotspot
end

-- shows the marker under `key` at x, z (moves it if it is already there). options: { steady (it doesn't blink), quiet (it doesn't blink or stay at the edge
-- of the minimap, while something else needs your attention), name (what it is), image, info (for a click: MapClicks.lua) }
function RseMarkers:show(key, x, z, options)
    if not self.enabled then
        return
    end
    local marker = self.markers[key]
    if marker == nil then
        local hotspot = create(options.steady, options.name)
        if hotspot == nil then
            return
        end
        marker = { hotspot = hotspot, steady = options.steady == true, persistent = true }
        self.markers[key] = marker
    end
    local calm = options.steady == true or options.quiet == true
    if calm ~= marker.steady then
        marker.steady = calm
        RseLog.try("map marker blinking", marker.hotspot.setBlinking, marker.hotspot, not calm)
    end
    local persistent = options.quiet ~= true
    if persistent ~= marker.persistent then
        marker.persistent = persistent
        RseLog.try("map marker persistent", marker.hotspot.setPersistent, marker.hotspot, persistent)
    end
    if options.image ~= nil and marker.image ~= options.image then
        RseLog.try("map marker picture", setImage, marker, options.image)
    end
    marker.hotspot.rseMarker = options.info
    if x ~= marker.x or z ~= marker.z then
        RseLog.try("map marker position", marker.hotspot.setWorldPosition, marker.hotspot, x, z)
        marker.x, marker.z = x, z
    end
end

function RseMarkers:hide(key)
    local marker = self.markers[key]
    if marker ~= nil then
        RseLog.try("remove a map marker", g_currentMission.removeMapHotspot, g_currentMission, marker.hotspot)
        RseLog.try("delete a map marker", marker.hotspot.delete, marker.hotspot)
        self.markers[key] = nil
    end
end

function RseMarkers:clear()
    local keys = {}
    for key in pairs(self.markers) do
        table.insert(keys, key)
    end
    for _, key in ipairs(keys) do
        self:hide(key)
    end
end

-- while the map unloads
function RseMarkers:unload()
    self:clear()
    self.enabled = true
    self.reported = false
    self.reportedIcon = false
end
