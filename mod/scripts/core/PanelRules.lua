-- Roadside Emergencies: what the call panel shows (P4 in docs/UI_RESEARCH.md): the job's steps, each done, now or to do, and the clock that applies.
-- Engine-free: CallPanel.lua gathers the facts from the scene and draws what comes back. The facts are the same state the progress bar reads
-- (Scenes.lua, reportProgress), so the panel and the bar can't disagree.
--
-- facts:
--   arrived; expireLeftMs: before you arrive, until another contractor takes over
--   animals = { left, total }: dead animals still in the road
--   wreck = { state, delivered, tipped, driver, what }: the vehicle to recover (nil when nobody recovers it: storm, flock, logging). what: "car",
--     "trailer" or nil, for the step's words
--   bales = { left, total }; survivors = { left, total }; logs = { left }; flock = { left }
--   line = { powerOff, secondsLeft, wiresLeft, poleIn, polePay }: the pole is optional (Z), shown last with what it adds
--   tree = { doorFree, rescueLeftMs }: rescueLeftMs only while the driver's bonus can still be earned
--   crossing = { seconds, clear }: seconds until the train, nil once it has gone by
--   handoverLeftMs: a two-part job with one part done, until another contractor takes the rest
--   pointDistance: metres from the wreck to its recovery point

RsePanelRules = {}

local function add(steps, key, done, extra)
    local step = { key = key, done = done == true }
    if extra ~= nil then
        step.count, step.distance, step.optional, step.extraPay = extra.count, extra.distance, extra.optional, extra.extraPay
    end
    table.insert(steps, step)
end

local function deliverKey(wreck)
    if wreck.what == "car" then
        return "rse_panel_deliverCar"
    elseif wreck.what == "trailer" then
        return "rse_panel_deliverTrailer"
    end
    return "rse_panel_deliver"
end

-- The steps in the order they are usually done; parts that can go in any order are listed one after the other. The first step not done is "now", the
-- rest "todo"; an optional step is "optional" until it is done, and never "now". Returns { { key, state, count, distance, optional, extraPay } }.
function RsePanelRules.steps(facts)
    local steps = {}
    local wreck = facts.wreck
    add(steps, "rse_panel_reach", facts.arrived)
    if facts.animals ~= nil and facts.animals.total > 0 then
        add(steps, "rse_panel_animals", facts.animals.left == 0, { count = facts.animals.left })
    end
    if facts.line ~= nil then
        add(steps, "rse_panel_power", facts.line.powerOff)
    end
    if facts.tree ~= nil then
        add(steps, "rse_panel_treeLog", facts.tree.doorFree or (wreck ~= nil and wreck.state ~= "locked"))
    end
    if wreck ~= nil then
        if facts.crossing ~= nil then
            add(steps, "rse_panel_tracks", facts.crossing.clear or wreck.delivered)
        elseif wreck.driver then
            add(steps, "rse_panel_driver", wreck.state ~= "locked")
        else
            add(steps, "rse_panel_prepare", wreck.state ~= "locked")
        end
        if wreck.tipped then
            add(steps, "rse_panel_upright", wreck.delivered or wreck.state == "ready")
        end
    end
    if facts.logs ~= nil then
        add(steps, "rse_panel_logs", facts.logs.left == 0, { count = facts.logs.left })
    end
    if facts.line ~= nil then
        add(steps, "rse_panel_wires", facts.line.wiresLeft == 0, { count = facts.line.wiresLeft })
    end
    if facts.bales ~= nil and facts.bales.total > 0 then
        add(steps, "rse_panel_bales", facts.bales.left == 0, { count = facts.bales.left })
    end
    if facts.survivors ~= nil and facts.survivors.total > 0 then
        add(steps, "rse_panel_survivors", facts.survivors.left == 0, { count = facts.survivors.left })
    end
    if facts.flock ~= nil then
        add(steps, "rse_panel_flock", facts.flock.left == 0, { count = facts.flock.left })
    end
    if wreck ~= nil then
        add(steps, deliverKey(wreck), wreck.delivered, { distance = facts.pointDistance })
    end
    if facts.line ~= nil then
        add(steps, "rse_panel_pole", facts.line.poleIn, { optional = true, extraPay = facts.line.polePay })
    end
    local now = false
    for _, step in ipairs(steps) do
        if step.done then
            step.state = "done"
        elseif step.optional then
            step.state = "optional"
        elseif not now then
            step.state, now = "now", true
        else
            step.state = "todo"
        end
    end
    return steps
end

-- the step that is "now", or nil when all are done
function RsePanelRules.current(steps)
    for _, step in ipairs(steps) do
        if step.state == "now" then
            return step
        end
    end
    return nil
end

-- does this step take you to a recovery point?
function RsePanelRules.goesToPoint(step)
    return step ~= nil and (step.distance ~= nil or step.key == "rse_panel_bales" or step.key == "rse_panel_pole")
end

-- The one clock that matters most right now, or nil: { key, seconds, urgent }. The train first (you can lose the job), then getting there in time, the power
-- cut, the rest of a two-part job, and the driver's bonus. Only a clock that can lose you the job turns urgent.
function RsePanelRules.clock(facts, config)
    local crossing = facts.crossing
    if crossing ~= nil and crossing.seconds ~= nil and not crossing.clear then
        return { key = "rse_panel_clockTrain", seconds = crossing.seconds, urgent = crossing.seconds <= config.CROSSING_CLOCK_URGENT }
    end
    if not facts.arrived and facts.expireLeftMs ~= nil then
        local seconds = facts.expireLeftMs / 1000
        return { key = "rse_panel_clockArrive", seconds = seconds, urgent = seconds <= config.PANEL_URGENT_SECONDS }
    end
    if facts.line ~= nil and not facts.line.powerOff and facts.line.secondsLeft ~= nil then
        return { key = "rse_panel_clockPower", seconds = facts.line.secondsLeft, urgent = false }
    end
    if facts.handoverLeftMs ~= nil then
        local seconds = facts.handoverLeftMs / 1000
        return { key = "rse_panel_clockHandover", seconds = seconds, urgent = seconds <= config.PANEL_URGENT_SECONDS }
    end
    if facts.tree ~= nil and facts.tree.rescueLeftMs ~= nil and facts.tree.rescueLeftMs > 0 then
        return { key = "rse_panel_clockRescue", seconds = facts.tree.rescueLeftMs / 1000, urgent = false }
    end
    return nil
end

-- a clock as people read one: 4:05, 59:59, 1:02:03. Rounds up, so 0:00 only shows when the time is up.
function RsePanelRules.clockText(seconds)
    local whole = math.max(0, math.ceil(seconds or 0))
    local hours, minutes, rest = math.floor(whole / 3600), math.floor(whole % 3600 / 60), whole % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, rest)
    end
    return string.format("%d:%02d", minutes, rest)
end

-- The arrow's turn on screen, in radians, for a target seen from a camera: 0 straight ahead, positive to the right. aheadX, aheadZ: the camera's forward
-- direction on the ground; rightX, rightZ: its right; dx, dz: from the camera to the target. Nil when the target is right here.
function RsePanelRules.bearing(aheadX, aheadZ, rightX, rightZ, dx, dz)
    if dx * dx + dz * dz < 1e-6 then
        return nil
    end
    return math.atan2(dx * rightX + dz * rightZ, dx * aheadX + dz * aheadZ)
end
