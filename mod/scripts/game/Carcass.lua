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

function RseCarcass:showInfo(box)
    box:addLine(RseText.get("rse_info_deadAnimal"), RseText.animal(self.rseKind))
    if self.rseMassKg ~= nil then
        box:addLine(RseText.get("rse_info_mass"), RseText.get("rse_info_massValue", self.rseMassKg))
    end
end
