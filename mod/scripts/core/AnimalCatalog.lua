-- Roadside Emergencies: the animals a carcass can be. Engine-free.
-- Wild animals come from their model file; livestock from the game's animal list (the first subtype whose name contains
-- `subType`, using its posed model). height and thickness are the animal's size lying on its side, for the pose.

RseAnimalCatalog = {}

RseAnimalCatalog.BODY_SMALL = "small"
RseAnimalCatalog.BODY_LARGE = "large"

local ANIMALS = {
    deer = { file = "$dataS/character/animals/wild/deer/deerAdult.i3d", massKg = 80, body = "small", height = 1.1, thickness = 0.4 },
    boar = { file = "$dataS/character/animals/wild/boar/boar.i3d", massKg = 100, body = "small", height = 0.9, thickness = 0.45 },
    pig = { subType = "PIG", massKg = 120, body = "small", height = 0.9, thickness = 0.45 },
    sheep = { subType = "SHEEP", massKg = 70, body = "small", height = 0.9, thickness = 0.45 },
    goat = { subType = "GOAT", massKg = 60, body = "small", height = 0.8, thickness = 0.35 },
    cow = { subType = "COW", massKg = 650, body = "large", height = 1.5, thickness = 0.7 },
    buffalo = { subType = "BUFFALO", massKg = 600, body = "large", height = 1.5, thickness = 0.7 },
    horse = { subType = "HORSE", massKg = 550, body = "large", height = 1.7, thickness = 0.6 }
}

-- the animal's entry (a copy, with its kind and text key), or nil
function RseAnimalCatalog.get(kind)
    local entry = type(kind) == "string" and ANIMALS[string.lower(kind)] or nil
    if entry == nil then
        return nil
    end
    local copy = {}
    for k, v in pairs(entry) do
        copy[k] = v
    end
    copy.kind = string.lower(kind)
    copy.textKey = "rse_animal_" .. copy.kind
    copy.fillTypeName = "RSE_CARCASS_" .. string.upper(copy.kind)
    return copy
end

-- every kind, sorted
function RseAnimalCatalog.kinds()
    local kinds = {}
    for kind in pairs(ANIMALS) do
        table.insert(kinds, kind)
    end
    table.sort(kinds)
    return kinds
end

function RseAnimalCatalog.isDraggable(kind, maxMassKg)
    local entry = ANIMALS[kind]
    return entry ~= nil and entry.massKg <= maxMassKg
end

-- Where the model sits inside its hidden body: rolled onto its side (90 degrees about its forward axis), its middle at the
-- body's centre and its underside on the body's underside. Returns rotZ, x, y, z in the body's frame.
function RseAnimalCatalog.pose(entry, bodyHeight)
    return math.pi / 2, entry.height / 2, -(bodyHeight - entry.thickness) / 2, 0
end
