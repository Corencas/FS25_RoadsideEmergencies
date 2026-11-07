-- Roadside Emergencies: logs from a savegame come back where they were.
-- The game saves a cut tree's pieces with their place in the world, and as it loads them those numbers become their position against their parent.
-- It corrects that for the pieces directly under the tree's node (TreePlantManager:loadTreeNode). The pieces of a transport tree, which our logs are
-- cut from, don't get that: they hang under transportTreeGroup, and so land at the saved place plus the tree's own place, usually off the map, where
-- they fall for ever. Z's logs, 2026-11-04: saved at 202.7, 62.5, -703.9, found at 403.8, -88.2, -1461.9. This does for them what the game does for
-- the others, as they load, before anything has moved.
-- Only our own logs (Z): every tree this mod lays down is remembered by where it stands, in our save, for as long as a piece of it is left, also the
-- logs you keep when you hand a logging job over. Logs of that kind from the game or from other mods are left as the game loads them. A save from
-- before the list (0.9.6.2 and older) has none, so that one load corrects every log of the kind as before, and from then on only those it corrected.

RseSavedLogs = {
    original = nil,
    origins = {},   -- where each tree of ours stands: { x, z, seen }, seen once the game has it in its list of cut trees
    legacy = false  -- the save is from before the list
}

-- a tree of ours, about to be laid down at (x, z)
function RseSavedLogs:remember(x, z)
    table.insert(self.origins, { x = x, z = z })
end

local function originAt(x, z)
    for _, origin in ipairs(RseSavedLogs.origins) do
        if (origin.x - x) ^ 2 + (origin.z - z) ^ 2 <= RseConfig.LINE_TREE_MATCH ^ 2 then
            return origin
        end
    end
    return nil
end

-- What the savegame keeps: the trees of ours the game still has. One not in its list yet (asked for a moment ago) stays.
function RseSavedLogs:saveData()
    local data = g_treePlantManager ~= nil and g_treePlantManager.treesData or nil
    local list = {}
    for _, origin in ipairs(self.origins) do
        local found = data == nil or data.splitTrees == nil
        for _, tree in ipairs(data ~= nil and data.splitTrees or {}) do
            if tree.x ~= nil and tree.node ~= nil and tree.node ~= 0 and entityExists(tree.node)
                and (tree.x - origin.x) ^ 2 + (tree.z - origin.z) ^ 2 <= RseConfig.LINE_TREE_MATCH ^ 2 then
                found = true
                break
            end
        end
        if found or not origin.seen then
            origin.seen = origin.seen or found
            table.insert(list, { x = origin.x, z = origin.z })
        end
    end
    self.origins = list
    return list
end

-- from our save, before the game loads its trees. origins: the list, or nil if the save has none; hadSave: there was a save of ours at all
function RseSavedLogs:restore(origins, hadSave)
    self.origins, self.legacy = {}, origins == nil and hadSave == true
    for _, origin in ipairs(origins or {}) do
        table.insert(self.origins, { x = origin.x, z = origin.z, seen = true })
    end
    if self.legacy then
        RseLog.info("saved logs: this save is from before the list of our own logs, so every transport log is put back this time")
    end
end

function RseSavedLogs:unload()
    self.origins, self.legacy = {}, false
end

-- what the game does for the pieces it corrects itself
local function putBack(node, x, y, z)
    local rx, ry, rz = getRotation(node)
    removeFromPhysics(node)
    setWorldRotation(node, rx, ry, rz)
    setWorldTranslation(node, x, y, z)
    addToPhysics(node)
end

local function correctBelow(node, treeId)
    local count = 0
    for i = 0, getNumOfChildren(node) - 1 do
        local child = getChildAt(node, i)
        if getHasClassId(child, ClassIds.MESH_SPLIT_SHAPE) then
            local x, y, z = getTranslation(child)
            -- the game has seen to this one, or it is an uncut trunk, still at its tree's foot
            local isSeenTo = node == treeId and getIsSplitShapeSplit(child)
            if not isSeenTo and x * x + z * z > 1 then
                putBack(child, x, y, z)
                count = count + 1
            end
        else
            count = count + correctBelow(child, treeId)
        end
    end
    return count
end

local function correct(treeId, treeName, x, z)
    local count = correctBelow(treeId, treeId)
    if count > 0 then
        RseLog.info("saved logs: %d piece(s) of a %s tree back where they were saved", count, treeName)
        if RseSavedLogs.legacy and originAt(x, z) == nil then
            RseSavedLogs:remember(x, z) -- an old save: from now on, these count as ours
        end
    end
end

-- Hands back what the game's function returned, whatever becomes of the correction.
function RseSavedLogs.install()
    if RseSavedLogs.original ~= nil then
        return
    end
    if type(TreePlantManager) ~= "table" or type(TreePlantManager.loadTreeNode) ~= "function" then
        RseLog.problem("saved logs: the game's tree manager isn't what we know, so logs may not come back after a reload")
        return
    end
    RseSavedLogs.original = TreePlantManager.loadTreeNode
    TreePlantManager.loadTreeNode = function(self, treeTypeDesc, x, y, z, rx, ry, rz, growthStateI, variationIndex, splitShapeLoadingFileId, ...)
        local treeId, splitShapeFileId = RseSavedLogs.original(self, treeTypeDesc, x, y, z, rx, ry, rz, growthStateI, variationIndex,
            splitShapeLoadingFileId, ...)
        local isOurKind = type(treeTypeDesc) == "table" and treeTypeDesc.name == RseConfig.LINE_POLE_TREES[1]
        local isOurs = isOurKind and x ~= nil and z ~= nil and (RseSavedLogs.legacy or originAt(x, z) ~= nil)
        if isOurs and treeId ~= nil and treeId ~= 0 and splitShapeLoadingFileId ~= nil and splitShapeLoadingFileId ~= -1 then
            RseLog.try("put a saved log back", correct, treeId, treeTypeDesc.name, x, z)
        end
        return treeId, splitShapeFileId
    end
end

RseSavedLogs.install()
