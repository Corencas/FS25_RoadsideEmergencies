-- Roadside Emergencies: a car in the water: can it be pulled out here? Engine-free.

RseWaterRules = {}

-- Walks from a car at (x, z) toward the road along (dirX, dirZ), a unit vector, toRoad metres. heightAt(x, z): the ground; waterY: the water's surface;
-- isBlocked(x1, z1, x2, z2): something solid in the way. Returns "ok" and how far off the dry land is, or why not: "steep", "noDry" or "blocked".
function RseWaterRules.bank(x, z, dirX, dirZ, toRoad, waterY, heightAt, isBlocked, config)
    local lastX, lastZ, last = x, z, heightAt(x, z)
    local dryAt = nil
    local distance = config.WATER_BANK_STEP
    while distance <= toRoad do
        local px, pz = x + dirX * distance, z + dirZ * distance
        local height = heightAt(px, pz)
        local onPull = dryAt == nil or distance <= dryAt + config.WATER_BANK_ROOM
        if math.abs(height - last) > (onPull and config.WATER_BANK_RISE or config.WATER_ROAD_RISE) then
            return "steep"
        end
        if onPull and isBlocked ~= nil and isBlocked(lastX, lastZ, px, pz) then
            return "blocked"
        end
        if dryAt == nil and height >= waterY + config.WATER_BANK_DRY then
            dryAt = distance
        elseif dryAt == nil and distance >= config.WATER_BANK_REACH then
            return "noDry"
        end
        lastX, lastZ, last = px, pz, height
        distance = distance + config.WATER_BANK_STEP
    end
    if dryAt == nil then
        return "noDry"
    end
    return "ok", dryAt
end

-- a place found, unless one this close is known already. Returns true if it is new.
function RseWaterRules.addPlace(places, place, gap)
    for _, other in ipairs(places) do
        if (other.x - place.x) ^ 2 + (other.z - place.z) ^ 2 < gap ^ 2 then
            return false
        end
    end
    table.insert(places, place)
    return true
end

-- Which place the next call uses. near { x, z }, if given: the closest to it. Otherwise any but the last one used and any but those right where you stand,
-- unless nothing else is left: a map may have only one. Returns the place, or nil if there is none.
function RseWaterRules.choose(places, last, near, player, config, random)
    if #places == 0 then
        return nil
    end
    if near ~= nil then
        local best, bestDistance = nil, math.huge
        for _, place in ipairs(places) do
            local distance = (place.x - near.x) ^ 2 + (place.z - near.z) ^ 2
            if distance < bestDistance then
                best, bestDistance = place, distance
            end
        end
        return best
    end
    local allowed = {}
    for _, place in ipairs(places) do
        local isLast = last ~= nil and (place.x - last.x) ^ 2 + (place.z - last.z) ^ 2 < config.WATER_PLACE_GAP ^ 2
        local isHere = player ~= nil and (place.x - player.x) ^ 2 + (place.z - player.z) ^ 2 < config.SPOT_PLAYER_CLEAR ^ 2
        if not isLast and not isHere then
            table.insert(allowed, place)
        end
    end
    local list = #allowed > 0 and allowed or places
    return list[math.min(#list, math.floor(random() * #list) + 1)]
end
