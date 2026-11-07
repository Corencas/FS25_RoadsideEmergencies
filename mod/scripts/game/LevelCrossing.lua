-- Roadside Emergencies: a vehicle stalled on a railroad crossing, and the train on its way (core/CrossingRules.lua).
--   The train is the map's own, running by itself. Nothing here touches it, so a rented one or a map without crossings simply never gets this call.
--   The call comes from any crossing within reach (Z), when the train is the right time away for that distance, so that you can make it if you don't dawdle,
--   and fail if you do (Z).
--   The vehicle is a wreck in the state "held": a pin holds it, so ramming it does nothing (Z), until a line is on it. See RseWrecks:update and RseStrap.
--   If it is still on the tracks when the train comes, the pin lets go just before, and the hit throws it (RseWrecks:throw). The job is lost.
--   Off the tracks in time, it still has to reach a recovery point (Z).

RseLevelCrossing = {
    train = nil,        -- the map's train system, once found
    pending = nil,      -- the crossing just picked, for the scene that is being laid out
    target = nil,       -- the crossing the next call is waiting for
    lastIndex = nil,    -- the crossing of the last call
    offerMs = 0,
    canOfferNow = false
}

local function findTrain(self)
    if self.train == nil then
        local system = g_currentMission.placeableSystem
        for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
            local spec = placeable.spec_trainSystem
            if spec ~= nil and #(spec.railroadCrossings or {}) > 0 then
                self.train = placeable
                break
            end
        end
    end
    return self.train
end

-- what the train is doing now, or nil if it isn't running by itself
local function readTrain(self)
    local placeable = findTrain(self)
    local spec = placeable ~= nil and placeable.spec_trainSystem or nil
    local loco = spec ~= nil and spec.rootLocomotive or nil
    local locoSpec = loco ~= nil and loco.spec_locomotive or nil
    if locoSpec == nil or placeable:getIsRented() or locoSpec.state ~= Locomotive.STATE_AUTOMATIC_TRAVEL_ACTIVE
        or locoSpec.speed < RseConfig.CROSSING_MIN_SPEED then
        return nil
    end
    local length = placeable:getSplineLength()
    return { placeable = placeable, spec = spec, length = length, speed = locoSpec.speed, time = placeable:getSplineTime(), lap = length / locoSpec.speed }
end

-- how far you are from each crossing, and how long until the train is there
local function readCrossings(train)
    local px, pz = RsePowerLine.logs.playerPosition()
    local list = {}
    for i, crossing in ipairs(train.spec.railroadCrossings) do
        if px ~= nil and crossing.nearestTime ~= nil and crossing.rootNode ~= nil then
            local x, _, z = getWorldTranslation(crossing.rootNode)
            local metres = RseCrossingRules.ahead(crossing.nearestTime, train.time, train.length)
            table.insert(list, { index = i, time = crossing.nearestTime, distance = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2), seconds = metres / train.speed })
        end
    end
    return list
end

-- Can this call come at all? Asked every frame while the calls are planned, so it only looks now and then. force: look now.
function RseLevelCrossing:canOffer(force, dt)
    self.offerMs = self.offerMs - (dt or 0)
    if self.offerMs > 0 and not force then
        return self.canOfferNow
    end
    self.offerMs = RseConfig.CROSSING_OFFER_CHECK_MS
    local ok, result = RseLog.try("look for a train", function()
        local train = readTrain(self)
        return train ~= nil and #RseCrossingRules.candidates(readCrossings(train), train.lap, RseConfig) > 0
    end)
    self.canOfferNow = ok and result == true
    return self.canOfferNow
end

-- the next call: which crossing it waits for
function RseLevelCrossing:chooseNext()
    local train = readTrain(self)
    local list = train ~= nil and RseCrossingRules.candidates(readCrossings(train), train.lap, RseConfig) or {}
    self.target = RseCrossingRules.choose(list, self.lastIndex, math.random())
end

-- Has the train come to the right time away from that crossing? If you have gone too far from it meanwhile, another one is chosen.
function RseLevelCrossing:isMoment()
    local train = readTrain(self)
    if train == nil then
        return false
    end
    for _, item in ipairs(RseCrossingRules.candidates(readCrossings(train), train.lap, RseConfig)) do
        if item.index == self.target then
            return RseCrossingRules.isMoment(item, train.lap, RseConfig)
        end
    end
    self:chooseNext()
    return false
end

-- where the track runs at this crossing
local function trackAt(placeable, time)
    local spline = placeable:getSpline()
    local x, y, z = getSplinePosition(spline, time)
    local dirX, _, dirZ = getSplineDirection(spline, time)
    local length = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-6)
    return x, y, z, dirX / length, dirZ / length
end

-- The player has said yes: which crossing, and where on it: a random spot on the tracks (Z). Returns a spot for the emergency, or nil.
function RseLevelCrossing:pickSpot()
    local train = readTrain(self)
    if train == nil then
        return nil
    end
    local list = readCrossings(train)
    local within = RseCrossingRules.candidates(list, train.lap, RseConfig)
    local choice = RseCrossingRules.pick(#within > 0 and within or list, self.target, train.lap, RseConfig, math.random())
    self.target = nil
    if choice == nil then
        return nil
    end
    self.lastIndex = choice.index
    local x, y, z, dirX, dirZ = trackAt(train.placeable, choice.time)
    self.pending = { index = choice.index, time = choice.time, x = x, z = z, dirX = dirX, dirZ = dirZ, seconds = choice.seconds }
    local reach = RseConfig.CROSSING_SPOT_JITTER
    local along, across = (math.random() * 2 - 1) * reach, (math.random() * 2 - 1) * reach
    RseLog.info("crossing %d: you are %.0f m away, so you get about %.0f s; the train is %.0f s away, one lap is %.0f s", choice.index, choice.distance,
        RseCrossingRules.allowance(choice.distance, train.lap, RseConfig), choice.seconds, train.lap)
    return { x = x + dirX * along - dirZ * across, y = y, z = z + dirZ * along + dirX * across, dirX = dirX, dirY = 0, dirZ = dirZ }
end

-- the scene has been laid out at the spot from pickSpot. Returns false if there is none, and the job can't go on.
function RseLevelCrossing:begin(scene)
    local pending = self.pending
    self.pending = nil
    if pending == nil then
        return false
    end
    scene.crossing = { index = pending.index, time = pending.time, x = pending.x, z = pending.z, dirX = pending.dirX, dirZ = pending.dirZ,
        seconds = pending.seconds, state = {} }
    return true
end

local function follow(self, scene, crossing)
    local train = readTrain(self)
    if train == nil then
        crossing.seconds = nil -- someone has rented it: nothing is coming for now
        return false
    end
    local ahead = RseCrossingRules.ahead(crossing.time, train.time, train.length)
    crossing.seconds = ahead / train.speed
    local x, z = RseWrecks:position(scene.wreck)
    if x == nil then
        return false -- still loading
    end
    local onTracks = RseCrossingRules.isOnTracks(x, z, crossing.x, crossing.z, crossing.dirX, crossing.dirZ, (scene.wreck.variant.length or 4) / 2, RseConfig)
    if not onTracks and not crossing.clear then
        crossing.clear = true
        RseText.notify(RseText.get("rse_crossing_clear"))
    elseif onTracks then
        crossing.clear = false
    end
    local event = RseCrossingRules.tick(crossing.state, ahead, onTracks, RseConfig)
    if event == "release" then
        RseWrecks:release(scene.wreck, "the train")
    elseif event == "passed" then
        crossing.seconds = nil
        RseLog.info("scene %d: the train has gone by, and the vehicle was clear of the tracks", scene.id)
    elseif event == "hit" then
        crossing.seconds = nil
        if scene.wreck.pin ~= nil then
            RseWrecks:release(scene.wreck, "the train") -- a long frame went past the moment for it
        end
        local awayX, awayZ = RseCrossingRules.awayFromTrack(x, z, crossing.x, crossing.z, crossing.dirX, crossing.dirZ)
        RseLog.try("the train throws it", RseWrecks.throw, RseWrecks, scene.wreck, crossing.dirX, crossing.dirZ, awayX, awayZ)
        RseScenes:loseCrossing(scene)
        return true
    end
    return false
end

-- Every frame, from the steps. Returns true when the train has hit it, and the job is lost.
function RseLevelCrossing:update(scene)
    local crossing = scene.crossing
    if crossing == nil or crossing.failed or crossing.state.over then
        return false
    end
    local ok, lost = RseLog.try("the crossing", follow, self, scene, crossing)
    if not ok then
        crossing.failed = true -- once in the log; the player can still hand the job over
        crossing.seconds = nil
    end
    return ok and lost == true
end

-- every frame, from RseScenes:draw: how long until the train
local function drawClock(seconds)
    local text = RseText.get("rse_crossing_clock", RseCrossingRules.clock(seconds))
    local size = RseConfig.CROSSING_CLOCK_SIZE
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    local width = getTextWidth(size, text) + size
    drawFilledRect(0.5 - width / 2, RseConfig.CROSSING_CLOCK_Y - size * 0.3, width, size * 1.4, 0, 0, 0, 0.6)
    if seconds <= RseConfig.CROSSING_CLOCK_URGENT then
        setTextColor(1, 0.25, 0.2, 1)
    else
        setTextColor(1, 1, 1, 1)
    end
    renderText(0.5, RseConfig.CROSSING_CLOCK_Y, size, text)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

-- Returns false when it failed to draw.
function RseLevelCrossing:draw(scene)
    local crossing = scene.crossing
    if crossing == nil or crossing.seconds == nil or (RseCallPanel ~= nil and RseCallPanel:visible()) then
        return true -- the call panel shows the train's clock when it is on the screen
    end
    return (RseLog.try("the train clock", drawClock, crossing.seconds))
end

-- what the savegame keeps
function RseLevelCrossing:saveData(scene)
    local crossing = scene.crossing
    if crossing == nil then
        return nil
    end
    return { index = crossing.index, passed = crossing.state.over == true }
end

-- A saved job comes back. Returns false if its crossing can't be found, and the job can't go on.
function RseLevelCrossing:restore(scene, data)
    self.lastIndex = data.index -- the next call comes from somewhere else, reload or not (Z)
    local placeable = findTrain(self)
    local crossing = placeable ~= nil and placeable.spec_trainSystem.railroadCrossings[data.index] or nil
    if crossing == nil or crossing.nearestTime == nil then
        return false
    end
    local x, _, z, dirX, dirZ = trackAt(placeable, crossing.nearestTime)
    scene.crossing = { index = data.index, time = crossing.nearestTime, x = x, z = z, dirX = dirX, dirZ = dirZ, state = { over = data.passed == true } }
    return true
end

function RseLevelCrossing:unload()
    self.train, self.pending, self.offerMs, self.canOfferNow, self.target, self.lastIndex = nil, nil, 0, false, nil, nil
end
