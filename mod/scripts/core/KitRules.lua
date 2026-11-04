-- Roadside Emergencies: the rules of the scene kit (cones and barricades you set down and pick up by hand). Engine-free.
-- Items set down during a job belong to that job. When the job ends they become "owed": the county keeps reminding you and
-- no new job comes until every one is picked up (Z, M2 round 2).

RseKitRules = {}

-- The item the view ray points at, nearest first. items: { { x, y, z, radius }, ... } (y: the middle of the model; radius:
-- its own pick radius, else the one given); the ray starts at o and runs along the unit vector d. Returns the item or nil.
function RseKitRules.aimed(items, ox, oy, oz, dx, dy, dz, reach, radius)
    local best, bestAlong = nil, nil
    for _, item in ipairs(items) do
        local vx, vy, vz = item.x - ox, item.y - oy, item.z - oz
        local along = vx * dx + vy * dy + vz * dz
        if along > 0 and along <= reach then
            local ex, ey, ez = vx - dx * along, vy - dy * along, vz - dz * along
            if math.sqrt(ex * ex + ey * ey + ez * ez) <= (item.radius or radius) and (bestAlong == nil or along < bestAlong) then
                best, bestAlong = item, along
            end
        end
    end
    return best
end

-- the middle of the items in the ground plane (x, z), or nil for none
function RseKitRules.centre(items)
    if #items == 0 then
        return nil
    end
    local sumX, sumZ = 0, 0
    for _, item in ipairs(items) do
        sumX, sumZ = sumX + item.x, sumZ + item.z
    end
    return sumX / #items, sumZ / #items
end

function RseKitRules.newReminder()
    return { remainingMs = nil }
end

-- Called every frame. True when the county should call about the items still out. The clock doesn't run while you are near
-- them (you are probably picking them up); it starts over once none are left.
function RseKitRules.tickReminder(state, dt, owedCount, playerNear, config)
    if owedCount <= 0 then
        state.remainingMs = nil
        return false
    end
    if state.remainingMs == nil then
        state.remainingMs = config.KIT_REMINDER_FIRST_MS
    end
    if playerNear then
        return false
    end
    state.remainingMs = state.remainingMs - dt
    if state.remainingMs > 0 then
        return false
    end
    state.remainingMs = config.KIT_REMINDER_MS
    return true
end
