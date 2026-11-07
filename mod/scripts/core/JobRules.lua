-- Roadside Emergencies: which jobs a farm is offered and how a job can lapse (DESIGN §2.3b). Engine-free.
-- A firm rule (Z): dispatch never calls about a job the farm hasn't the equipment to finish. Small animals can be dragged by hand and a flock can be walked
-- in, so those take nothing. Everything else takes something that can pull, and some of it more. A job nobody reaches in time goes to another contractor: no
-- pay, and a small charge.

RseJobRules = {
    CALLERS = { "rse_caller_driver", "rse_caller_bus", "rse_caller_mail", "rse_caller_neighbor", "rse_caller_sheriff" }
}

-- What the farm's machines add up to. machines: { { motorized, mass, lifts, carries, livestockTrailer }, ... }, mass in tonnes.
-- Returns { canPull, canPullHeavy, canLift, canCarry, hasLivestockTrailer }.
function RseJobRules.fleetFrom(machines, config)
    local fleet = { canPull = false, canPullHeavy = false, canLift = false, canCarry = false, hasLivestockTrailer = false, machines = machines }
    for _, machine in ipairs(machines) do
        if machine.motorized then
            fleet.canPull = fleet.canPull or machine.mass >= config.FLEET_PULL_MASS
            fleet.canPullHeavy = fleet.canPullHeavy or machine.mass >= config.FLEET_HEAVY_MASS
        end
        fleet.canLift = fleet.canLift or machine.lifts == true
        fleet.canCarry = fleet.canCarry or machine.carries == true
        fleet.hasLivestockTrailer = fleet.hasLivestockTrailer or machine.livestockTrailer == true
    end
    return fleet
end

local function hasWhatItNeeds(needs, fleet)
    if needs == "pull" then
        return fleet.canPull
    elseif needs == "carry" then
        return fleet.canPull and fleet.canCarry
    elseif needs == "livestock" then
        return fleet.canPull and fleet.hasLivestockTrailer
    end
    return needs == nil
end

-- The emergencies this farm can't finish: { id = true }. emergency.needs: "pull", "carry", "livestock", or nil for nothing. A job with a vehicle to recover
-- also needs at least one of its vehicles to be within the farm's reach: otherwise it is off, however the job is written.
function RseJobRules.unavailable(emergencies, fleet, config)
    local list = {}
    for _, emergency in ipairs(emergencies) do
        local def = emergency.wreck ~= nil and config.WRECKS[emergency.wreck] or nil
        if not hasWhatItNeeds(emergency.needs, fleet) or (def ~= nil and not RseWreckRules.anyVariantFor(def, fleet)) then
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
