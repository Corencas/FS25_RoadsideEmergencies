-- Roadside Emergencies: where on the map a call can happen. Engine-free. Every metre of road is equally likely, wherever the
-- player is (Z), so a call can come from right next to you; only spots where the scene couldn't work are left out.

RseSpotRules = {}

-- the index the roll in [0, 1) lands on, each index as likely as its weight; nil without any weight
function RseSpotRules.pickWeighted(weights, roll)
    local total = 0
    for _, weight in ipairs(weights) do
        total = total + weight
    end
    if total <= 0 then
        return nil
    end
    local target = roll * total
    for i, weight in ipairs(weights) do
        target = target - weight
        if target < 0 then
            return i
        end
    end
    return #weights
end

-- false if x, z lies inside one of the keep-out circles { { x, z, radius }, ... }
function RseSpotRules.isFree(x, z, keepOuts)
    for _, area in ipairs(keepOuts) do
        local dx, dz = x - area.x, z - area.z
        if dx * dx + dz * dz < area.radius * area.radius then
            return false
        end
    end
    return true
end
