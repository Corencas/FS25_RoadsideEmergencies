-- Roadside Emergencies: a vehicle stalled on a railroad crossing: when the call comes, which crossing, and what the train does to the job. Engine-free.
-- The game side: game/LevelCrossing.lua. The train is never touched: it runs by itself, so the call waits for the right moment instead.

RseCrossingRules = {}

-- the time a player gets to a crossing this far away: the drive at a fair speed, and the time to get a line on the vehicle; never more than the train allows
function RseCrossingRules.allowance(distance, lapSeconds, config)
    return math.min(distance / config.CROSSING_DRIVE_SPEED + config.CROSSING_WORK_SECONDS, lapSeconds - config.CROSSING_LAP_MARGIN)
end

-- how far the train still has to go to a place on its track. Times: 0 to 1 along the track, the way the train runs.
function RseCrossingRules.ahead(crossingTime, trainTime, trackLength)
    return ((crossingTime - trainTime) % 1) * trackLength
end

-- The crossings a call can come from: list: { { index, distance, seconds }, ... }, how far you are from each one and how long until the train is there. Only
-- those close enough that the time to get there fits into one lap of the train.
function RseCrossingRules.candidates(list, lapSeconds, config)
    local result = {}
    for _, item in ipairs(list) do
        local fair = item.distance / config.CROSSING_DRIVE_SPEED + config.CROSSING_WORK_SECONDS
        if item.distance <= config.CROSSING_MAX_DISTANCE and fair <= lapSeconds - config.CROSSING_LAP_MARGIN then
            table.insert(result, item)
        end
    end
    return result
end

-- Which one the next call comes from: any of them (Z), and not the one from last time while there is another. Returns its index, or nil.
function RseCrossingRules.choose(list, lastIndex, roll)
    local others = {}
    for _, item in ipairs(list) do
        if item.index ~= lastIndex then
            table.insert(others, item)
        end
    end
    local from = #others > 0 and others or list
    if #from == 0 then
        return nil
    end
    return from[math.min(#from, math.floor(roll * #from) + 1)].index
end

-- Is this the moment to call? item: the crossing chosen. It comes when the train is just the time you get away from it.
function RseCrossingRules.isMoment(item, lapSeconds, config)
    if item == nil then
        return false
    end
    local allowed = RseCrossingRules.allowance(item.distance, lapSeconds, config)
    return item.seconds >= allowed and item.seconds <= allowed + config.CROSSING_SLACK
end

-- Which crossing, now that the player has said yes. The chosen one, unless the pager took so long that it no longer leaves enough time; then any that does;
-- if none does, the one that comes closest. Returns an item of the list, or nil for an empty list.
function RseCrossingRules.pick(list, chosenIndex, lapSeconds, config, roll)
    local enough, closest, closestMargin = {}, nil, -math.huge
    for _, item in ipairs(list) do
        local margin = item.seconds - RseCrossingRules.allowance(item.distance, lapSeconds, config)
        if item.index == chosenIndex and margin >= -config.CROSSING_PAGER_GRACE then
            return item
        end
        if margin >= 0 then
            table.insert(enough, item)
        end
        if margin > closestMargin then
            closest, closestMargin = item, margin
        end
    end
    if #enough > 0 then
        return enough[math.min(#enough, math.floor(roll * #enough) + 1)]
    end
    return closest
end

-- is a vehicle at (x, z) in the train's way? (trackX, trackZ) and the unit vector (dirX, dirZ): the track at the crossing
function RseCrossingRules.isOnTracks(x, z, trackX, trackZ, dirX, dirZ, halfLength, config)
    local across = math.abs((x - trackX) * dirZ - (z - trackZ) * dirX)
    return across < halfLength + config.CROSSING_TRAIN_HALF
end

-- which way is away from the track, for a vehicle at (x, z)
function RseCrossingRules.awayFromTrack(x, z, trackX, trackZ, dirX, dirZ)
    local across = (x - trackX) * dirZ - (z - trackZ) * dirX
    local side = across >= 0 and 1 or -1
    return dirZ * side, -dirX * side
end

-- Follows the train as it comes. state: a table of its own; ahead: metres to the crossing; onTracks: the vehicle is in the way. Returns nil, or once each:
-- "release": whatever holds the vehicle lets go, so that the train can move it; "hit": it was still there; "passed": it wasn't.
function RseCrossingRules.tick(state, ahead, onTracks, config)
    if state.over then
        return nil
    end
    local arrived = ahead <= config.CROSSING_HIT_M or (state.lastAhead ~= nil and ahead > state.lastAhead + config.CROSSING_HIT_M)
    state.lastAhead = ahead
    if arrived then
        state.over = true
        return onTracks and "hit" or "passed"
    end
    if onTracks and not state.released and ahead <= config.CROSSING_RELEASE_M then
        state.released = true
        return "release"
    end
    return nil
end

-- 185 seconds as 3:05
function RseCrossingRules.clock(seconds)
    local whole = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end
