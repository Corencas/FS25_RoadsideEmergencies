-- Roadside Emergencies: the one place every state change goes through (DESIGN §4). In multiplayer, events will wrap
-- apply() so the server decides and clients follow. Engine-free; listeners do the game-side work (money, notifications).

RseStore = {}
local RseStore_mt = { __index = RseStore }

function RseStore.new(config)
    return setmetatable({
        config = config,
        settings = RseSettings.fillDefaults({ feeFactor = config.FEE_FACTOR_DEFAULT, callsEnabled = config.CALLS_ENABLED_DEFAULT,
            jobSize = config.JOB_SIZE_DEFAULT }),
        points = RsePointRegistry.new(),
        carcasses = {},           -- id -> { id, kind, massKg }
        nextCarcassId = 1,
        kit = {},                 -- id -> { id, item, sceneId, owed } (scene kit items set down in the world)
        nextKitId = 1,
        listeners = {}
    }, RseStore_mt)
end

-- listener(kind, data, result) runs after every successful change
function RseStore:subscribe(listener)
    table.insert(self.listeners, listener)
end

local handlers = {}

function handlers.setFeeFactor(store, data)
    store.settings.feeFactor = RsePayRules.clampFactor(data.factor, store.config)
    return store.settings.feeFactor
end

-- the guide has been shown in this savegame
function handlers.setGuideSeen(store, data)
    store.settings.guideSeen = data.seen == true
    return store.settings.guideSeen
end

-- any setting of the panel (RseSettings.ROWS)
function handlers.setSetting(store, data)
    local row = RseSettings.row(data.key)
    if row == nil or not RseSettings.isValid(row, data.value) then
        return nil, "not a valid setting"
    end
    store.settings[data.key] = data.value
    return { key = data.key, value = data.value }
end

function handlers.setCallsEnabled(store, data)
    store.settings.callsEnabled = data.enabled == true
    return store.settings.callsEnabled
end

function handlers.setJobSize(store, data)
    if not RseSceneSpec.SIZES[data.size] then
        return nil, "job size must be small, normal, large or random"
    end
    store.settings.jobSize = data.size
    return data.size
end

-- a cone or barricade set down; sceneId: the job running now, or nil; owed: saved as still to be picked up
function handlers.addKitItem(store, data)
    local known = false
    for _, item in ipairs(store.config.KIT_ITEMS) do
        known = known or item.id == data.item
    end
    if not known then
        return nil, "unknown kit item " .. tostring(data.item)
    end
    local count = 0
    for _ in pairs(store.kit) do
        count = count + 1
    end
    if count >= store.config.KIT_MAX_ITEMS then
        return nil, "limit"
    end
    local id = store.nextKitId
    store.nextKitId = id + 1
    store.kit[id] = { id = id, item = data.item, sceneId = data.sceneId, owed = data.owed == true }
    return id
end

function handlers.removeKitItem(store, data)
    local record = store.kit[data.id]
    if record == nil then
        return nil, "no kit item " .. tostring(data.id)
    end
    store.kit[data.id] = nil
    return record
end

-- the job ended: what was set down for it is now owed. Returns how many items that job left out.
function handlers.kitJobEnded(store, data)
    local count = 0
    for _, record in pairs(store.kit) do
        if record.sceneId ~= nil and record.sceneId == data.sceneId then
            record.sceneId = nil
            record.owed = true
            count = count + 1
        end
    end
    return count
end

-- a saved job came back after loading: its items belong to the scene it has now
function handlers.kitMoveJob(store, data)
    local count = 0
    for _, record in pairs(store.kit) do
        if record.sceneId ~= nil and record.sceneId == data.from then
            record.sceneId = data.to
            count = count + 1
        end
    end
    return count
end

function handlers.addPoint(store, data)
    return store.points:add(data.name, data.kind, data.x, data.z, data.source)
end

function handlers.removePoint(store, data)
    local point = nil
    for _, candidate in ipairs(store.points:list()) do
        if candidate.id == data.id then
            point = candidate
        end
    end
    if point == nil then
        return nil, "no point " .. tostring(data.id)
    end
    if point.source ~= "player" then
        return nil, "map points can't be removed"
    end
    return store.points:remove(data.id)
end

function handlers.addCarcass(store, data)
    local entry = RseAnimalCatalog.get(data.kind)
    if entry == nil then
        return nil, "unknown animal " .. tostring(data.kind)
    end
    local id = store.nextCarcassId
    store.nextCarcassId = id + 1
    store.carcasses[id] = { id = id, kind = entry.kind, massKg = entry.massKg }
    return id
end

function handlers.removeCarcass(store, data)
    local record = store.carcasses[data.id]
    if record == nil then
        return nil, "no carcass " .. tostring(data.id)
    end
    store.carcasses[data.id] = nil
    return record
end

-- delivered at a disposal point: the record goes, pay and fee are worked out here so every listener sees the same amounts
function handlers.deliverCarcass(store, data)
    local record = store.carcasses[data.id]
    if record == nil then
        return nil, "no carcass " .. tostring(data.id)
    end
    store.carcasses[data.id] = nil
    return { record = record, pay = RsePayRules.haulPay(record.massKg, store.settings.payFactor, store.config),
        fee = RsePayRules.disposalFee(record.massKg, store.settings.feeFactor, store.config),
        pointName = data.pointName }
end

-- left behind and collected by the county: the record goes, the bill is worked out here
function handlers.collectCarcass(store, data)
    local record = store.carcasses[data.id]
    if record == nil then
        return nil, "no carcass " .. tostring(data.id)
    end
    store.carcasses[data.id] = nil
    local factor = store.settings.feeFactor
    local fee = RsePayRules.disposalFee(record.massKg, factor, store.config)
    local charge = RsePayRules.collectionCharge(record.massKg, factor, store.config)
    local unearned = math.max(0, math.floor(tonumber(data.unearned) or 0))
    return { record = record, fee = fee, charge = charge, unearned = unearned, total = fee + charge + unearned }
end

-- applies one change; returns its result, or nil and a reason
function RseStore:apply(kind, data)
    local handler = handlers[kind]
    if handler == nil then
        return nil, "unknown change " .. tostring(kind)
    end
    local result, reason = handler(self, data or {})
    if result ~= nil then
        for _, listener in ipairs(self.listeners) do
            listener(kind, data, result)
        end
    end
    return result, reason
end

-- items from ended jobs still to be picked up; no new job until this is 0
function RseStore:kitOwedCount()
    local count = 0
    for _, record in pairs(self.kit) do
        if record.owed then
            count = count + 1
        end
    end
    return count
end

function RseStore:carcassCount()
    local count = 0
    for _ in pairs(self.carcasses) do
        count = count + 1
    end
    return count
end
