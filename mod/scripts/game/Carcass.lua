-- Roadside Emergencies: the body of a carcass.
-- A bale of our own type (xml/bales/: the base-game square bale model, hidden), so everything that handles bales handles a
-- carcass: forks, spikes, grabs, buckets, cranes, trailers, tension belts, autoload, and winch mods that hook objects
-- tension belts can hold (P8). The animal model follows the body (Carcasses.lua). The game's own item saving skips it; our
-- savegame file keeps carcasses (SaveLoad.lua).

RseCarcass = {}
local RseCarcass_mt = Class(RseCarcass, Bale)

function RseCarcass.new(isServer, isClient, customMt)
    local self = Bale.new(isServer, isClient, customMt or RseCarcass_mt)
    self.rseKind = nil
    self.rseMassKg = nil
    return self
end

function RseCarcass:getSupportsWrapping()
    return false
end

function RseCarcass:getCanBeOpened()
    return false
end

function RseCarcass:getCanBeSold()
    return false
end

function RseCarcass:getNeedsSaving()
    return false
end

function RseCarcass:getValue()
    return 0
end

-- the engine works in tonnes
function RseCarcass:getDefaultMass()
    if self.rseMassKg ~= nil then
        return self.rseMassKg / 1000
    end
    return RseCarcass:superClass().getDefaultMass(self)
end

-- What a vehicle's belts or a loader show on the fill display: "3 Deer", not "3pieces" (Z). The game writes a fill type's short unit right after the
-- number, so the unit is the animal's name, with a space, one or many by how many of this kind the display has had this frame. The game's own bales
-- have no such function: belts and loaders then read fill type, level and capacity themselves, which is what this does too.
RseCarcass.unitTally = { display = nil, time = nil, levels = {} }

function RseCarcass:getFillLevelInformation(display)
    local fillType, fillLevel, capacity = self:getFillType(), self:getFillLevel(), self:getCapacity()
    local tally = RseCarcass.unitTally
    if tally.display ~= display or tally.time ~= g_time then
        tally.display, tally.time, tally.levels = display, g_time, {}
    end
    local total = (tally.levels[fillType] or 0) + (fillLevel or 0)
    tally.levels[fillType] = total
    local desc = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(fillType) or nil
    if desc ~= nil and self.rseKind ~= nil then
        desc.unitShort = " " .. RseText.animalUnit(self.rseKind, total)
    end
    display:addFillLevel(fillType, fillLevel, capacity)
end

function RseCarcass:showInfo(box)
    box:addLine(RseText.get("rse_info_deadAnimal"), RseText.animalName(self.rseKind))
    if self.rseMassKg ~= nil then
        box:addLine(RseText.get("rse_info_mass"), g_i18n:formatMass(self.rseMassKg / 1000)) -- as the game's own bales show theirs
    end
end
