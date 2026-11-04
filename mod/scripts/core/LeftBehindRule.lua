-- Roadside Emergencies: carcasses left behind (Z's option A, with warnings and a map marker). One left lying gets a warning after
-- LEFT_WARN_AFTER_MS of play, a reminder at each of LEFT_REMINDERS_MS before the end, and after LEFT_COLLECT_MS the county collects it
-- and the player is billed. Animals left at the roadside after a job go the same way. Engine-free. The clock counts play time, not
-- the game's clock: at normal game speed a day would take a real day. It only runs while nobody is within LEFT_PLAYER_DISTANCE; being
-- on a vehicle, held by a machine, strapped or dragged starts it over. Animals of a call in progress are exempt.

RseLeftBehindRule = {}

-- how many of the reminders are due with this much time left
local function remindersDue(remaining, config)
    local due = 0
    for _, before in ipairs(config.LEFT_REMINDERS_MS) do
        if remaining <= before then
            due = due + 1
        end
    end
    return due
end

-- state: { leftMs, warned, reminders }, updated here. carcass: { exempt, held, playerNear }.
-- Returns what happens now: nil, "warn" or "collect".
function RseLeftBehindRule.tick(state, dt, carcass, config)
    if carcass.exempt or carcass.held then
        state.leftMs, state.warned, state.reminders = 0, false, 0
        return nil
    end
    if carcass.playerNear then
        return nil
    end
    state.leftMs = (state.leftMs or 0) + dt
    local remaining = config.LEFT_COLLECT_MS - state.leftMs
    if remaining <= 0 then
        return "collect"
    end
    local due = remindersDue(remaining, config)
    if due > (state.reminders or 0) then
        state.warned, state.reminders = true, due
        return "warn"
    end
    if state.leftMs >= config.LEFT_WARN_AFTER_MS and not state.warned then
        state.warned = true
        return "warn"
    end
    return nil
end

-- whole minutes until the county collects it, rounded up
function RseLeftBehindRule.minutesLeft(state, config)
    return math.ceil(math.max(0, config.LEFT_COLLECT_MS - (state.leftMs or 0)) / 60000)
end

-- the state of a carcass read from a savegame: warnings already given aren't repeated, and its marker comes back
function RseLeftBehindRule.restore(leftMs, config)
    local ms = leftMs or 0
    return { leftMs = ms, warned = ms >= config.LEFT_WARN_AFTER_MS, reminders = remindersDue(config.LEFT_COLLECT_MS - ms, config) }
end
