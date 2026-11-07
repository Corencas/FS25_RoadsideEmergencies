-- Roadside Emergencies: disposal and recovery points in the world, with their map markers.
-- The map always provides one: its shop area (every map has one, P3). Players add their own (console now, menu in
-- milestone 6); only those are saved. The point list itself lives in the Store (RsePointRegistry).

RsePoints = {
    store = nil,
    hotspots = {}
}

-- the middle of the map's first shop spawn place
local function shopPosition()
    local places = g_currentMission ~= nil and g_currentMission.storeSpawnPlaces or nil
    local place = places ~= nil and places[1] or nil
    if place == nil or place.startX == nil then
        return nil
    end
    local half = (place.width or 0) * 0.5
    return place.startX + (place.dirPerpX or 0) * half, place.startZ + (place.dirPerpZ or 0) * half
end

function RsePoints:init(store)
    self.store = store
    self.hotspots = {}
    local x, z = shopPosition()
    if x ~= nil then
        store:apply("addPoint", { name = RseText.get("rse_point_shop"), kind = "both", x = x, z = z, source = "map" })
    else
        RseLog.info("this map has no shop spawn place: no default disposal point (add your own with rsePointAdd)")
    end
end

-- your own point's number, the order you added them in; nil for the shop
function RsePoints:numberOf(point)
    for i, own in ipairs(self.store.points:playerPoints()) do
        if own == point or own.id == point.id then
            return i
        end
    end
    return nil
end

-- which marker picture your own point shows
function RsePoints:markerImage(point)
    local number = self:numberOf(point) or 0
    return number >= 1 and number <= 9 and ("point_" .. number) or "point_x"
end

function RsePoints:at(x, z, kind)
    return self.store.points:at(x, z, kind, RseConfig.POINT_RADIUS)
end

function RsePoints:removeHotspots()
    for _, hotspot in ipairs(self.hotspots) do
        RseLog.try("removeMapHotspot", g_currentMission.removeMapHotspot, g_currentMission, hotspot)
        if hotspot.delete ~= nil then
            RseLog.try("hotspot delete", hotspot.delete, hotspot)
        end
    end
    self.hotspots = {}
end

-- One map marker per point (the game's "unloading" marker). Off until a probe proves a marker class that works without a
-- placeable: in 0.1.0.0 a PlaceableHotspot without one failed in every map draw (PlaceableHotspot.lua:225, "index nil with
-- 'width'") and broke the in-game menu. Until then we only log which marker types exist.
function RsePoints:refreshHotspots()
    self:removeHotspots()
    if not RseConfig.MAP_MARKERS then
        return -- PlaceableHotspot markers stay off: they broke the menu in 0.1.0.0
    end
    if PlaceableHotspot == nil then
        return
    end
    local hotspotType = PlaceableHotspot.getTypeByName("UNLOADING")
    for _, point in ipairs(self.store.points:list()) do
        local ok, hotspot = RseLog.try("PlaceableHotspot.new", PlaceableHotspot.new)
        if ok and hotspot ~= nil then
            if hotspotType ~= nil then
                hotspot:setPlaceableType(hotspotType)
            end
            hotspot:setWorldPosition(point.x, point.z)
            hotspot:setName(RseText.get("rse_point_hotspot", self:numberOf(point) or 0, point.name))
            RseLog.try("addMapHotspot", g_currentMission.addMapHotspot, g_currentMission, hotspot)
            table.insert(self.hotspots, hotspot)
        end
    end
end

function RsePoints:unload()
    self:removeHotspots()
end
