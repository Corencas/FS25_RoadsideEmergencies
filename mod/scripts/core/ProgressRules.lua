-- Roadside Emergencies: how far along a job is, for the pack's progress bar (Z: true to the scene). Engine-free. The pack only knows its own steps,
-- so getting to a scene used to show 50% and the job then jumped to the end. Here each part of a job counts for what has really been done: animals off
-- the road, bales brought in, a wreck prepared, righted and on its way.

RseProgressRules = {}

-- done out of total, 0 to 1; nothing to do counts as done
function RseProgressRules.share(done, total)
    if total <= 0 then
        return 1
    end
    return math.max(0, math.min(1, done / total))
end

-- A wreck, 0 to 1. state: "locked", "tipped" or "ready"; delivered: it is in; towed: the share of the way to the recovery point; tipped: it had to be righted.
function RseProgressRules.wreck(state, delivered, towed, tipped, config)
    if delivered then
        return 1
    end
    if state == "locked" then
        return 0
    end
    if state == "tipped" then
        return config.PROGRESS_PREPARED
    end
    local start = tipped and config.PROGRESS_RIGHTED or config.PROGRESS_PREPARED
    return start + (1 - start) * math.max(0, math.min(1, towed or 0))
end

-- The whole job, 0 to 1. arrived: you have reached it; parts: each part's share, all counting the same. It stays short of the end until the job is really over.
function RseProgressRules.scene(arrived, parts, config)
    if not arrived then
        return 0
    end
    local sum = 0
    for _, part in ipairs(parts) do
        sum = sum + part
    end
    local work = #parts > 0 and sum / #parts or 0
    return math.min(config.PROGRESS_MOST, config.PROGRESS_ARRIVED + (1 - config.PROGRESS_ARRIVED) * work)
end
