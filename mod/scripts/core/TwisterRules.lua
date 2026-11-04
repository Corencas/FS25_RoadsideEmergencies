-- Roadside Emergencies: the way a twister travels. Engine-free.

RseTwisterRules = {}

-- One step of its journey: long curves that keep changing, at a steady speed, turning back at the end of its leash.
-- state: { x, z, heading, turn }, updated here; x and z are metres from where it appeared. random: returns 0 to 1.
function RseTwisterRules.wander(state, dt, config, random)
    local seconds = dt / 1000
    if state.heading == nil then
        state.x, state.z, state.heading, state.turn = state.x or 0, state.z or 0, random() * 2 * math.pi, 0
    end
    if math.sqrt(state.x * state.x + state.z * state.z) > config.TWISTER_WANDER_RADIUS then
        local off = (math.atan2(-state.x, -state.z) - state.heading + math.pi) % (2 * math.pi) - math.pi
        local limit = config.TWISTER_TURN_BACK * seconds
        state.heading = state.heading + math.max(-limit, math.min(limit, off))
        state.turn = 0
    else
        local drift = (random() - 0.5) * config.TWISTER_TURN_DRIFT * seconds
        state.turn = math.max(-config.TWISTER_TURN_MAX, math.min(config.TWISTER_TURN_MAX, state.turn + drift))
        state.heading = state.heading + state.turn * seconds
    end
    local step = config.TWISTER_WANDER_SPEED * seconds
    state.x = state.x + math.sin(state.heading) * step
    state.z = state.z + math.cos(state.heading) * step
end
