-- Roadside Emergencies: what the pager says (P5 in docs/UI_RESEARCH.md, U3): what happened, then one field a line: where, what is there, what it takes, a
-- vehicle of yours that can do it, how long you have, and about what it pays. Engine-free: CallPlan.lua plans the call before the pager asks and fills the
-- fields in; this only does the reckoning and the layout.

RsePagerRules = {}

local COMPASS = { "n", "ne", "e", "se", "s", "sw", "w", "nw" }

-- the compass word's key suffix for a direction on the map: north is -z, east is +x (the game's map has north up, z growing southward)
function RsePagerRules.compass(dx, dz)
    if dx * dx + dz * dz < 1e-6 then
        return nil
    end
    local bearing = math.atan2(dx, -dz) -- 0 north, clockwise
    local sector = math.floor(bearing / (math.pi / 4) + 0.5) % 8
    return COMPASS[sector + 1]
end

-- One of your vehicles that can do what the job takes, for "You have": need is "heavy" (the heaviest motorized vehicle of FLEET_HEAVY_MASS or more), "pull"
-- (the lightest of FLEET_PULL_MASS or more: a pickup rather than your biggest tractor), "lift", "carry" or "livestock". machines: { name, motorized, mass,
-- lifts, carries, livestockTrailer }. Returns a name, or nil.
function RsePagerRules.bestMachine(machines, need, config)
    local best, bestMass = nil, nil
    for _, machine in ipairs(machines or {}) do
        local fits, mass = false, machine.mass or 0
        if need == "heavy" then
            fits = machine.motorized and mass >= config.FLEET_HEAVY_MASS
        elseif need == "pull" then
            fits = machine.motorized and mass >= config.FLEET_PULL_MASS
        elseif need == "lift" then
            fits = machine.lifts == true
        elseif need == "carry" then
            fits = machine.carries == true
        elseif need == "livestock" then
            fits = machine.livestockTrailer == true
        end
        if fits and type(machine.name) == "string" and machine.name ~= "" then
            local better = best == nil or (need == "heavy" and mass > bestMass) or (need ~= "heavy" and mass < bestMass)
            if better then
                best, bestMass = machine.name, mass
            end
        end
    end
    return best
end

-- What the pack pays for our amount, before the call exists to ask: the game's economy difficulty, as the FS22 pack applies it (getReward: 1.3 - 0.1 times
-- the difficulty). The call panel asks the real pack on each job; when it has, that ratio is better (known).
function RsePagerRules.payRatio(difficulty, known)
    if type(known) == "number" and known > 0 then
        return known
    end
    local d = tonumber(difficulty)
    if d == nil then
        return 1
    end
    return math.max(0.5, 1.3 - 0.1 * d)
end

-- "about" money: to the nearest step (PAGER_PAY_STEP), never below one step
function RsePagerRules.about(amount, config)
    local step = config.PAGER_PAY_STEP
    return math.max(step, math.floor(amount / step + 0.5) * step)
end

-- The pager's text: what happened, an empty line, then each field that has something to say, one a line
function RsePagerRules.compose(description, fields)
    local lines = {}
    for _, field in ipairs(fields) do
        if type(field) == "string" and field ~= "" then
            table.insert(lines, field)
        end
    end
    if #lines == 0 then
        return description
    end
    return description .. "\n\n" .. table.concat(lines, "\n")
end
