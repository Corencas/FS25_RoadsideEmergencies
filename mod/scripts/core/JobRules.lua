-- Roadside Emergencies: which jobs a farm is offered and how a job can lapse (DESIGN §2.3b). Engine-free.
-- Dispatch only calls about what the farm's vehicles can handle: small animals can be dragged by hand, anything heavier needs
-- something that can pull. A job nobody reaches in time goes to another contractor: no pay, no penalty.

RseJobRules = {
    CALLERS = { "rse_caller_driver", "rse_caller_bus", "rse_caller_mail", "rse_caller_neighbor", "rse_caller_sheriff" }
}

-- the emergencies this farm can't handle yet: { id = true }. fleet: { canPull }. emergency.needs: "pull", or nil for nothing.
function RseJobRules.unavailable(emergencies, fleet)
    local list = {}
    for _, emergency in ipairs(emergencies) do
        if emergency.needs == "pull" and not fleet.canPull then
            list[emergency.id] = true
        end
    end
    return list
end

-- what happens to a job not reached yet. state: { waitMs, warned }, updated here. Returns nil, "warn" or "expire".
function RseJobRules.tickExpiry(state, dt, config)
    state.waitMs = (state.waitMs or 0) + dt
    local remaining = config.JOB_EXPIRE_MS - state.waitMs
    if remaining <= 0 then
        return "expire"
    end
    if remaining <= config.JOB_EXPIRE_WARN_MS and not state.warned then
        state.warned = true
        return "warn"
    end
    return nil
end

-- the text key of who called it in; random as math.random
function RseJobRules.pickCaller(random)
    return RseJobRules.CALLERS[random(#RseJobRules.CALLERS)]
end
