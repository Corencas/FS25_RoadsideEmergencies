-- Roadside Emergencies: a twister you can see moving, doing its damage where you see it (Z). The game moves it 150 m an hour, too slow to see. Here the
-- whole twister travels at TWISTER_WANDER_SPEED in long curves, within TWISTER_WANDER_RADIUS of where it appeared, and everything it destroys goes with it,
-- because it all hangs under its root node (data/sky/twister.i3d). Staying near that spot keeps its damage to one area, however long the twister lasts.

RseTwisterTravel = {
    wander = nil,      -- { x, z, heading, turn }: metres from where it appeared; nil: not following one
    savedBase = nil,   -- { x, z }: the middle of its area, from the savegame
    baseX = nil,
    baseZ = nil,
    height = 0,        -- how far its root sits above the ground
    aliveMs = 0,
    overruled = 0,     -- frames something else had moved it, for the log
    failed = false
}

local function nodeOf(twister)
    local node = twister.rootNode
    return node ~= nil and node ~= 0 and entityExists(node) and node or nil
end

-- puts it where it should be now, on the ground, and its map icon with it
local function place(self, twister, node)
    local x, z = self.baseX + self.wander.x, self.baseZ + self.wander.z
    setWorldTranslation(node, x, getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + self.height, z)
    local hotspot = twister.mapHotspot
    if type(hotspot) == "table" and hotspot.setWorldPosition ~= nil then
        hotspot:setWorldPosition(x, z)
    end
    self.placedX, self.placedZ = x, z
end

local function update(self, twister, dt)
    local node = nodeOf(twister)
    if node == nil then
        return
    end
    local x, y, z = getWorldTranslation(node)
    if self.wander == nil then
        local baseX, baseZ = RseTwisterRules.base(self.savedBase, x, z, RseConfig)
        self.savedBase = nil
        self.wander, self.baseX, self.baseZ, self.aliveMs, self.overruled = { x = x - baseX, z = z - baseZ }, baseX, baseZ, 0, 0
        self.height = y - getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
        RseLog.info("twister: it travels at %.1f m/s within %d m of %.0f, %.0f, and its damage goes with it", RseConfig.TWISTER_WANDER_SPEED,
            RseConfig.TWISTER_WANDER_RADIUS, baseX, baseZ)
    elseif self.placedX ~= nil and math.abs(x - self.placedX) + math.abs(z - self.placedZ) > 1 then
        self.overruled = self.overruled + 1
    end
    self.aliveMs = self.aliveMs + dt
    RseTwisterRules.wander(self.wander, dt, RseConfig, math.random)
    place(self, twister, node)
end

-- every frame while a twister is up (RseCalls)
function RseTwisterTravel:update(twister, dt)
    if self.failed then
        return
    end
    if not RseLog.try("move the twister", update, self, twister, dt) then
        self.failed = true -- once in the log, and the twister is the game's own again
    end
end

-- where it is now, for the storm call; nil if it isn't being followed
function RseTwisterTravel:position()
    return self.placedX, self.placedZ
end

-- the game has just moved it: back on its way, in the same frame
local function afterMove(self, twister)
    if self.failed or self.wander == nil then
        return
    end
    local node = nodeOf(twister)
    if node == nil then
        return
    end
    if not RseLog.try("move the twister", place, self, twister, node) then
        self.failed = true
    end
end

-- it has gone: what the log should know
function RseTwisterTravel:finish()
    if self.wander == nil then
        return
    end
    RseLog.info("twister gone after %.0f s, %.0f m from where it appeared; something else moved it in %d frame(s)", self.aliveMs / 1000,
        math.sqrt(self.wander.x * self.wander.x + self.wander.z * self.wander.z), self.overruled)
    self.wander, self.placedX, self.placedZ = nil, nil, nil
end

-- what the save keeps: the middle of its area, so that a reload doesn't move it
function RseTwisterTravel:saveData()
    if self.wander == nil then
        return nil
    end
    return { x = self.baseX, z = self.baseZ }
end

-- a new savegame: nothing to follow yet
function RseTwisterTravel:reset()
    self.wander, self.placedX, self.placedZ, self.failed, self.savedBase = nil, nil, nil, false, nil
end

-- Hands back what the game's function returned: Utils.appendedFunction throws that away.
local function afterMoveReturning(twister, ...)
    afterMove(RseTwisterTravel, twister)
    return ...
end

-- the game's own function that moves it; hooked once, even across savegames
function RseTwisterTravel:hook()
    if Twister == nil or Twister.move == nil then
        RseLog.info("twister: no move function to follow, so it only follows once a frame")
        return
    end
    if Twister.rseOriginal_move == nil then
        Twister.rseOriginal_move = Twister.move
        Twister.move = function(twister, ...)
            return afterMoveReturning(twister, Twister.rseOriginal_move(twister, ...))
        end
    end
end
