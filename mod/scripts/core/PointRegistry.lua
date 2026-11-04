-- Roadside Emergencies: disposal and recovery points. Engine-free.
-- A point has an id, a name, a kind ("disposal", "recovery" or "both"), x and z, and a source ("map" for the defaults the
-- map provides, "player" for points the player sets; only player points are saved).

RsePointRegistry = {}
local RsePointRegistry_mt = { __index = RsePointRegistry }

RsePointRegistry.KINDS = { disposal = true, recovery = true, both = true }

function RsePointRegistry.new()
    return setmetatable({ points = {}, nextId = 1 }, RsePointRegistry_mt)
end

local function serves(point, kind)
    return kind == nil or point.kind == "both" or point.kind == kind
end

-- adds a point and returns its id, or nil and a reason
function RsePointRegistry:add(name, kind, x, z, source)
    if type(x) ~= "number" or type(z) ~= "number" then
        return nil, "position missing"
    end
    if not RsePointRegistry.KINDS[kind] then
        return nil, "unknown kind " .. tostring(kind)
    end
    local id = self.nextId
    self.nextId = id + 1
    table.insert(self.points, { id = id, name = name or ("Point " .. id), kind = kind, x = x, z = z, source = source or "player" })
    return id
end

function RsePointRegistry:remove(id)
    for i, point in ipairs(self.points) do
        if point.id == id then
            table.remove(self.points, i)
            return point
        end
    end
    return nil
end

function RsePointRegistry:list()
    return self.points
end

-- the nearest point serving `kind`, and its distance
function RsePointRegistry:nearest(x, z, kind)
    local best, bestDistance = nil, math.huge
    for _, point in ipairs(self.points) do
        if serves(point, kind) then
            local dx, dz = point.x - x, point.z - z
            local d = math.sqrt(dx * dx + dz * dz)
            if d < bestDistance then
                best, bestDistance = point, d
            end
        end
    end
    return best, bestDistance
end

-- the point serving `kind` whose radius contains (x, z), or nil
function RsePointRegistry:at(x, z, kind, radius)
    local point, d = self:nearest(x, z, kind)
    if point ~= nil and d <= radius then
        return point
    end
    return nil
end

function RsePointRegistry:playerPoints()
    local list = {}
    for _, point in ipairs(self.points) do
        if point.source == "player" then
            table.insert(list, point)
        end
    end
    return list
end
