-- Roadside Emergencies: the loose animals at a livestock trailer crash (DESIGN F16). They wander off slowly (RseHerdRules), each with a pin, a map
-- marker and, while on the road, a hidden cone that stops traffic for it. On foot you catch one with the activate prompt and it follows you on a
-- lead; next to your own livestock trailer the same prompt loads it, and it becomes a real animal (LivestockTrailer:addAnimals, P9) that you can
-- sell like any other. One at a time, so the others keep wandering while you walk one over.
-- They walk on the animated model's bones (GaitRules.lua): the base models have no walking clips a mod can reach, but they do have named leg joints, so the mod
-- turns those itself, feet planted where they land, and lowers the head to graze when one stands still. A model without those joints uses the posed model,
-- rocking a little with each step. An animal on a lead has a rope from your hand to its neck.
-- The log says which, and lists each model's nodes once by name (rseLive to try one).

RseSurvivors = {
    leading = nil,     -- the animal you have on a lead
    lead = nil,        -- its rope: { animal, point, rope, aimed, hook }
    test = nil,        -- rseLive: a scene of its own, not part of any call
    reported = {},     -- animals whose model is already in the log
    rayHit = false,
    rayY = nil,
    stillMs = 0        -- how long you have stood still
}

local AGE_MONTHS = 24 -- proven in P9: these sold normally
local CHECK_INTERVAL_MS = 400
local RAY_HEIGHT = 0.6
local RAY_START = 1.5  -- looking down for the ground from this far above the animal
local RAY_BELOW = 3.5  -- to this far below it

local RseSurvivorActivatable = {}
local RseSurvivorActivatable_mt = Class(RseSurvivorActivatable)

local function nodeExists(node)
    return node ~= nil and node ~= 0 and entityExists(node)
end

local function farmId()
    local mission = g_currentMission
    return mission.getFarmId ~= nil and mission:getFarmId() or 1
end

-- the first subtype of this animal that the trailer supports (and, with needRoom, has room for right now), or nil
local function subTypeFor(trailer, pattern, needRoom)
    local system = g_currentMission.animalSystem
    for i = 1, 200 do
        local okS, subType = pcall(system.getSubTypeByIndex, system, i)
        if not okS or subType == nil then
            break
        end
        if string.find(string.upper(tostring(subType.name or "")), pattern, 1, true) ~= nil and trailer:getSupportsAnimalSubType(i)
            and (not needRoom or trailer:getNumOfFreeAnimalSlots(i) > 0) then
            return i
        end
    end
    return nil
end

-- your own livestock trailers, never the wreck
local function ownTrailers()
    local list = {}
    for _, vehicle in ipairs(g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}) do
        if vehicle.spec_livestockTrailer ~= nil and vehicle.addAnimals ~= nil and vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId()
            and vehicle.propertyState ~= VehiclePropertyState.MISSION and vehicle.rootNode ~= nil then
            table.insert(list, vehicle)
        end
    end
    return list
end

-- your nearest livestock trailer in loading range: the trailer and, if it has room for this animal, the subtype to add
local function trailerFor(pattern, x, z)
    local best, bestSubType, bestDistance = nil, nil, RseConfig.SURVIVOR_LOAD_RANGE ^ 2
    for _, vehicle in ipairs(ownTrailers()) do
        local vx, _, vz = getWorldTranslation(vehicle.rootNode)
        local distance = (vx - x) ^ 2 + (vz - z) ^ 2
        if distance < bestDistance then
            best, bestSubType, bestDistance = vehicle, subTypeFor(vehicle, pattern, true), distance
        end
    end
    return best, bestSubType
end

-- one of these animals, among those your own trailers can carry when there are any: a sheep trailer can't take cattle
function RseSurvivors:pickKind(kinds)
    local possible = {}
    local trailers = ownTrailers()
    for _, kind in ipairs(kinds) do
        for _, trailer in ipairs(trailers) do
            if subTypeFor(trailer, RseAnimalCatalog.get(kind).subType, false) ~= nil then
                table.insert(possible, kind)
                break
            end
        end
    end
    local list = #possible > 0 and possible or kinds
    return list[math.random(#list)]
end

---------------------------------------------------------------------------------------------------
-- The model and its bones
---------------------------------------------------------------------------------------------------

local LEGS = {
    { phase = "hindLeft", part = "_hip_l_", isFront = false },
    { phase = "hindRight", part = "_hip_r_", isFront = false },
    { phase = "frontLeft", part = "_shoulder_l_", isFront = true },
    { phase = "frontRight", part = "_shoulder_r_", isFront = true }
}

local function nodeNamed(node, part, depth)
    if string.find(string.lower(tostring(getName(node))), part, 1, true) ~= nil then
        return node
    end
    if depth > 0 then
        for i = 0, getNumOfChildren(node) - 1 do
            local found = nodeNamed(getChildAt(node, i), part, depth - 1)
            if found ~= nil then
                return found
            end
        end
    end
    return nil
end

-- the joint whose name contains `part` and the joints below it, top down
local function chainFrom(root, part, longest)
    local chain = {}
    local node = nodeNamed(root, part, 12)
    while node ~= nil and #chain < longest do
        table.insert(chain, node)
        local below = nil
        for i = 0, getNumOfChildren(node) - 1 do
            local child = getChildAt(node, i)
            if string.find(string.lower(tostring(getName(child))), "jnt", 1, true) ~= nil then
                below = child
                break
            end
        end
        node = below
    end
    return chain
end

-- A joint at rest, and the animal's left-right, up and forward axes in the joint's own terms. Rigs orient their joints any which way.
local function jointAtRest(node, root)
    local joint = { node = node }
    joint.x, joint.y, joint.z, joint.w = getQuaternion(node)
    joint.restX, joint.restY, joint.restZ = worldToLocal(root, getWorldTranslation(node))
    joint.sideX, joint.sideY, joint.sideZ = worldDirectionToLocal(node, localDirectionToWorld(root, 1, 0, 0))
    joint.upX, joint.upY, joint.upZ = worldDirectionToLocal(node, localDirectionToWorld(root, 0, 1, 0))
    joint.forwardX, joint.forwardY, joint.forwardZ = worldDirectionToLocal(node, localDirectionToWorld(root, 0, 0, 1))
    return joint
end

local function jointsAtRest(chain, root)
    local joints = {}
    for _, node in ipairs(chain) do
        table.insert(joints, jointAtRest(node, root))
    end
    return joints
end

-- the legs, neck and tail of a model, or nil and which leg is missing
local function findRig(root)
    local rig = { legs = {} }
    for _, leg in ipairs(LEGS) do
        local chain = chainFrom(root, leg.part, 5)
        if #chain < 5 then
            return nil, leg.part
        end
        local joints = jointsAtRest(chain, root)
        local points = {}
        for i = 1, 4 do
            points[i] = { joints[i].restZ, joints[i].restY }
        end
        table.insert(rig.legs, { phase = RseGaitRules.PHASES[leg.phase], isFront = leg.isFront, joints = joints,
            rest = RseGaitRules.restLeg(points, leg.isFront) })
    end
    rig.spine = jointsAtRest(chainFrom(root, "_spine_", 3), root)
    rig.neck = jointsAtRest(chainFrom(root, "_neck_", 4), root) -- down to the head
    rig.tail = jointsAtRest(chainFrom(root, "_tail_", 3), root)
    rig.legLength = math.max(0.3, rig.legs[1].joints[1].restY)
    return rig
end

-- node names below `node`, each with its depth: names only, for fitting the walk to a new rig
local function nodeNames(node, depth, list)
    if depth > 12 or #list >= 120 then
        return list
    end
    table.insert(list, string.format("%d:%s", depth, tostring(getName(node))))
    for i = 0, getNumOfChildren(node) - 1 do
        nodeNames(getChildAt(node, i), depth + 1, list)
    end
    return list
end

local function loadFile(file)
    local filename = Utils.getFilename(file, RoadsideEmergencies.MOD_DIR)
    local ok, node, sharedId = RseLog.try("load a live animal", g_i3DManager.loadSharedI3DFile, g_i3DManager, filename, false, false)
    if not ok or node == nil or node == 0 then
        return nil
    end
    link(getRootNode(), node)
    return node, sharedId
end

-- Returns the node, its shared id, and its rig if it can walk on its bones.
local function loadModel(kind, def)
    local animated, posed = RseCarcasses.liveModels(def.subType)
    if animated ~= nil then
        local node, sharedId = loadFile(animated)
        if node ~= nil then
            local ok, rig, missing = RseLog.try("find the bones", findRig, node)
            rig = ok and rig or nil
            if not RseSurvivors.reported[kind] then
                RseSurvivors.reported[kind] = true
                RseLog.info("live %s: model %s; %s", kind, tostring(animated), rig ~= nil and string.format("walks on its bones, legs %.2f m", rig.legLength)
                    or ("no walking bones, posed instead; missing " .. tostring(missing)))
                RseLog.try("list the model's nodes", function()
                    RseLog.info("live %s: nodes: %s", kind, table.concat(nodeNames(node, 0, {}), " "))
                end)
            end
            if rig ~= nil then
                return node, sharedId, rig
            end
            delete(node)
            g_i3DManager:releaseSharedI3DFile(sharedId)
        end
    end
    if posed == nil then
        return nil
    end
    return loadFile(posed)
end

-- a joint turned from its rest pose: about the animal's left-right axis, then up, then forward
local function poseJoint(joint, side, up, forward)
    local x, y, z, w = joint.x, joint.y, joint.z, joint.w
    if side ~= 0 then
        local qx, qy, qz, qw = RseGaitRules.axisAngle(joint.sideX, joint.sideY, joint.sideZ, side)
        x, y, z, w = RseGaitRules.multiply(x, y, z, w, qx, qy, qz, qw)
    end
    if up ~= 0 then
        local qx, qy, qz, qw = RseGaitRules.axisAngle(joint.upX, joint.upY, joint.upZ, up)
        x, y, z, w = RseGaitRules.multiply(x, y, z, w, qx, qy, qz, qw)
    end
    if forward ~= 0 then
        local qx, qy, qz, qw = RseGaitRules.axisAngle(joint.forwardX, joint.forwardY, joint.forwardZ, forward)
        x, y, z, w = RseGaitRules.multiply(x, y, z, w, qx, qy, qz, qw)
    end
    setQuaternion(joint.node, x, y, z, w)
end

-- The walk: each leg in turn, the spine bending and the hips and shoulders rolling with the steps, the head nodding or down to graze, the tail swinging.
-- Standing, it breathes and looks around. Returns how far the body rises and rolls with the step.
local function poseRig(animal, dt, blend)
    local rig = animal.rig
    local cycles, reach = RseGaitRules.stride(animal.speed, rig.legLength, RseConfig)
    animal.gaitPhase = (animal.gaitPhase + cycles * dt / 1000) % 1
    animal.swing = animal.swing + (reach - animal.swing) * blend
    animal.clock = animal.clock + dt / 1000
    local phase, gait, stride = animal.gaitPhase, animal.gait, animal.swing
    local wave = math.sin(2 * math.pi * phase)
    local body = ((1 - math.cos(4 * math.pi * phase)) / 2 * RseConfig.GAIT_BOB - RseConfig.GAIT_CROUCH * rig.legLength) * gait
    local tilt = animal.graze * RseConfig.GAIT_GRAZE_TILT
    local lift = math.min(rig.legLength * RseConfig.GAIT_LIFT_MAX, stride * RseConfig.GAIT_LIFT_PER_STRIDE)
    for _, leg in ipairs(rig.legs) do
        local along, up = RseGaitRules.leg((phase + leg.phase) % 1, RseConfig.GAIT_DUTY)
        local fold = leg.isFront and RseConfig.GAIT_CANNON_FOLD.front or RseConfig.GAIT_CANNON_FOLD.hind
        local cannon = (along * stride / rig.legLength * RseConfig.GAIT_CANNON_LEAN + up * fold) * gait
        -- the body rises and sinks with the step while the foot stays on the ground
        -- and when the body leans forward to graze, the feet stay on the ground too
        local a1, a2, a3, a4 = RseGaitRules.solveLeg(leg.rest, -along * stride * gait, up * lift * gait - body + leg.rest.footZ * tilt, cannon,
            up * RseConfig.GAIT_HOOF_FOLD * gait)
        poseJoint(leg.joints[1], a1, 0, 0)
        poseJoint(leg.joints[2], a2, 0, 0)
        poseJoint(leg.joints[3], a3, 0, 0)
        poseJoint(leg.joints[4], a4, 0, 0)
    end
    local breath = math.sin(animal.clock * 1.4) * RseConfig.GAIT_BREATH * (1 - gait)
    for i, joint in ipairs(rig.spine) do
        local sign = i == 1 and 1 or i == #rig.spine and -1 or 0
        poseJoint(joint, breath, wave * RseConfig.GAIT_SPINE * gait * sign, wave * RseConfig.GAIT_ROLL * gait * sign)
    end
    local nod = math.sin(4 * math.pi * phase) * RseConfig.GAIT_NOD * gait
    local look = math.sin(animal.clock * 0.5 + animal.gaitSeed) * RseConfig.GAIT_LOOK * (1 - gait) * (1 - animal.graze)
    for i, joint in ipairs(rig.neck) do
        local chew = i == #rig.neck and math.sin(animal.clock * 4) * RseConfig.GAIT_GRAZE_CHEW * animal.graze or 0
        poseJoint(joint, nod + animal.graze * RseConfig.GAIT_GRAZE / #rig.neck + chew, look / #rig.neck, 0)
    end
    local tail = wave * RseConfig.GAIT_TAIL * (0.25 + 0.75 * gait)
    for i, joint in ipairs(rig.tail) do
        poseJoint(joint, 0, tail / i, 0)
    end
    return body, wave * RseConfig.GAIT_SWAY * gait, tilt
end

---------------------------------------------------------------------------------------------------
-- The activate prompt on foot
---------------------------------------------------------------------------------------------------

function RseSurvivorActivatable:getIsActivatable()
    local animal = self.animal
    if not nodeExists(animal.node) or g_localPlayer == nil or g_localPlayer:getCurrentVehicle() ~= nil then
        return false
    end
    local name = RseText.animal(animal.kind)
    if RseSurvivors.leading == animal then
        local _, subType = trailerFor(animal.def.subType, animal.x, animal.z)
        self.activateText = RseText.get(subType ~= nil and "rse_survivor_load" or "rse_action_letGo", name)
        return true
    end
    if RseSurvivors.leading ~= nil then
        return false
    end
    local px, _, pz = g_localPlayer:getPosition()
    if (animal.x - px) ^ 2 + (animal.z - pz) ^ 2 > RseConfig.SURVIVOR_REACH ^ 2 then
        return false
    end
    self.activateText = RseText.get("rse_survivor_catch", name)
    return true
end

function RseSurvivorActivatable:getDistance(x, y, z)
    local animal = self.animal
    if RseSurvivors.leading == animal then
        return 0
    end
    return math.sqrt((x - animal.x) ^ 2 + (y - animal.y) ^ 2 + (z - animal.z) ^ 2)
end

function RseSurvivorActivatable:run()
    local animal = self.animal
    if RseSurvivors.leading ~= animal then
        RseSurvivors.leading = animal
        RseText.notify(RseText.get("rse_survivor_caught", RseText.animal(animal.kind)))
        return
    end
    local trailer, subType = trailerFor(animal.def.subType, animal.x, animal.z)
    if subType == nil then
        RseSurvivors.leading = nil
        if trailer ~= nil then
            RseText.notify(RseText.get("rse_survivor_noRoom"), true)
        end
        return
    end
    if RseLog.try("load an animal into the trailer", trailer.addAnimals, trailer, subType, 1, AGE_MONTHS) then
        local scene = animal.scene
        scene.led = (scene.led or 0) + 1
        RseSurvivors:removeOne(animal)
        RseText.notify(RseText.get("rse_survivor_loaded", RseText.animal(animal.kind), RseSurvivors:remaining(scene)))
    end
end

---------------------------------------------------------------------------------------------------
-- In the world
---------------------------------------------------------------------------------------------------

-- Puts loose animals in the world. spots: { { x, y, z, yaw }, ... }.
function RseSurvivors:spawn(scene, kind, spots)
    local def = RseAnimalCatalog.get(kind)
    scene.survivors = scene.survivors or {}
    if def == nil or def.subType == nil then
        RseLog.problem("no model for the live %s", tostring(kind))
        return
    end
    for _, spot in ipairs(spots) do
        local node, sharedId, rig = loadModel(kind, def)
        if node ~= nil then
            local animal = { kind = kind, def = def, scene = scene, node = node, sharedId = sharedId, rig = rig, x = spot.x, y = spot.y,
                z = spot.z, yaw = spot.yaw or 0, moving = false, speed = 0, pauseMs = math.random() * RseConfig.HERD_PAUSE_MS[2],
                checkMs = math.random() * CHECK_INTERVAL_MS, blocked = false, stepPhase = 0, gait = 0, pitch = 0, roll = 0, slopePitch = 0, slopeRoll = 0,
                gaitPhase = math.random(), swing = 0, graze = 0, wasMoving = false, wantsGraze = math.random() < RseConfig.GAIT_GRAZE_CHANCE,
                clock = 0, gaitSeed = math.random() * 6 }
            local title = RseText.get("rse_marker_loose", RseText.animal(kind))
            animal.markerInfo = { kind = "loose", title = title, image = RseCarcasses.liveImage(def.subType) or RseMarkers.imagePath("loose") }
            animal.groundOffset = math.max(0, spot.y - getTerrainHeightAtWorldPos(g_terrainNode, spot.x, 0, spot.z))
            animal.groundTarget = animal.groundOffset
            setWorldTranslation(node, animal.x, animal.y, animal.z)
            setWorldRotation(node, 0, animal.yaw, 0)
            local activatable = setmetatable({ animal = animal }, RseSurvivorActivatable_mt)
            activatable.activateText = ""
            animal.activatable = activatable
            g_currentMission.activatableObjectsSystem:addActivatable(activatable)
            table.insert(scene.survivors, animal)
        end
    end
end

local function removeBlocker(animal)
    if animal.blocker ~= nil then
        RseKit.removeBlocker(animal.blocker)
        animal.blocker = nil
    end
end

-- the rope goes before the animal it is tied to
local function stopLead(self)
    local lead = self.lead
    self.lead = nil
    if lead == nil then
        return
    end
    if lead.rope ~= nil then
        RseLog.try("remove the lead", lead.rope.delete, lead.rope)
    end
    if nodeExists(lead.hook) then
        delete(lead.hook)
    end
    if nodeExists(lead.point) then
        delete(lead.point)
    end
end

-- The character's own right hand to tie the lead to, or nil. In first person the game hides the body, and anything linked to it with it (M4 round 6: no
-- rope), so the rope's end stays a node of its own that follows the hand, and there is no hand to follow in first person: it starts low on your right, in view.
local function playerHand()
    local camera = g_localPlayer ~= nil and g_localPlayer.camera or nil
    if camera == nil or camera.isFirstPerson then
        return nil
    end
    local graphics = g_localPlayer ~= nil and g_localPlayer.graphicsComponent or nil
    local model = graphics ~= nil and graphics.model or nil
    local hand = model ~= nil and model.thirdPersonRightHandNode or nil
    return nodeExists(hand) and hand or nil
end

local function startLead(self, animal)
    local point = createTransformGroup("rseLeadHand")
    link(getRootNode(), point)
    -- the neck on a model with bones; otherwise a point on the model about there
    local hook = createTransformGroup("rseLeadHook")
    local neck = animal.rig ~= nil and animal.rig.neck[#animal.rig.neck] or nil
    if neck ~= nil then
        link(neck.node, hook)
    else
        link(animal.node, hook)
        setTranslation(hook, 0, animal.def.height * 0.75, 0.3)
    end
    local ok, rope = RseLog.try("the lead", RseStrap.createRope, point, RoadsideEmergencies.MOD_DIR, RseConfig.LEAD_ROPE_FILE)
    self.lead = { animal = animal, point = point, hook = hook, rope = ok and rope or nil, aimed = false }
end

-- from your hand to its neck, as long as it is on the lead
local function updateLead(self)
    if self.lead ~= nil and self.lead.animal ~= self.leading then
        stopLead(self)
    end
    if self.leading == nil or g_localPlayer == nil then
        return
    end
    if self.lead == nil then
        startLead(self, self.leading)
    end
    local lead = self.lead
    local hand = playerHand()
    if hand ~= nil then
        setWorldTranslation(lead.point, getWorldTranslation(hand))
    else
        local x, y, z = g_localPlayer:getPosition()
        local dirX, dirZ = g_localPlayer:getCurrentFacingDirection()
        local length = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 0.001)
        dirX, dirZ = dirX / length, dirZ / length
        setWorldTranslation(lead.point, x + dirX * RseConfig.LEAD_HAND_AHEAD + dirZ * RseConfig.LEAD_HAND_SIDE, y + RseConfig.LEAD_HAND_HEIGHT,
            z + dirZ * RseConfig.LEAD_HAND_AHEAD - dirX * RseConfig.LEAD_HAND_SIDE)
    end
    if lead.rope ~= nil and not lead.aimed and lead.rope.referenceFrame ~= nil then
        lead.aimed = true
        RseLog.try("aim the lead", lead.rope.setTargetNode, lead.rope, lead.hook, true)
    end
end

function RseSurvivors:removeOne(animal)
    if self.leading == animal then
        self.leading = nil
    end
    if self.lead ~= nil and self.lead.animal == animal then
        stopLead(self)
    end
    if animal.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(animal.activatable)
        animal.activatable = nil
    end
    removeBlocker(animal)
    RseMarkers:hide(animal)
    if animal.pin ~= nil then
        RseLog.try("remove a pin", animal.pin.delete, animal.pin)
        animal.pin = nil
    end
    if nodeExists(animal.node) then
        delete(animal.node)
    end
    animal.node = nil
    if animal.sharedId ~= nil then
        g_i3DManager:releaseSharedI3DFile(animal.sharedId)
        animal.sharedId = nil
    end
    for i, candidate in ipairs(animal.scene.survivors) do
        if candidate == animal then
            table.remove(animal.scene.survivors, i)
            break
        end
    end
end

function RseSurvivors:remaining(scene)
    return scene.survivors ~= nil and #scene.survivors or 0
end

-- the job ended before they were all loaded
function RseSurvivors:remove(scene)
    while self:remaining(scene) > 0 do
        self:removeOne(scene.survivors[1])
    end
end

function RseSurvivors:onObstacleRaycast(hitObjectId)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.rayHit = true
        return false
    end
    return true
end

function RseSurvivors:onHeightRaycast(hitObjectId, _, y)
    if hitObjectId ~= nil and hitObjectId ~= 0 then
        self.rayY = y
        return false
    end
    return true
end

-- the height of what lies below this point, among these collision flags, or nil
local function heightBelow(x, y, z, reach, mask)
    RseSurvivors.rayY = nil
    raycastClosest(x, y, z, 0, -1, 0, reach, "onHeightRaycast", RseSurvivors, mask)
    return RseSurvivors.rayY
end

-- something right ahead: a wall, a tree, a vehicle, a slope too steep to climb, or water
local function lookAhead(animal, y)
    local dirX, dirZ = math.sin(animal.yaw), math.cos(animal.yaw)
    local reach = RseConfig.HERD_LOOK_AHEAD
    local aheadX, aheadZ = animal.x + dirX * reach, animal.z + dirZ * reach
    local terrainAhead = getTerrainHeightAtWorldPos(g_terrainNode, aheadX, 0, aheadZ)
    if animal.groundOffset < 1 and math.abs(terrainAhead - getTerrainHeightAtWorldPos(g_terrainNode, animal.x, 0, animal.z)) > RseConfig.HERD_MAX_RISE then
        return true
    end
    local water = heightBelow(aheadX, y + RAY_START, aheadZ, RAY_START + RAY_BELOW, CollisionFlag.WATER)
    if water ~= nil and water > terrainAhead + 0.2 then
        return true
    end
    RseSurvivors.rayHit = false
    raycastClosest(animal.x, y + RAY_HEIGHT, animal.z, dirX, 0, dirZ, reach, "onObstacleRaycast", RseSurvivors,
        CollisionFlag.STATIC_OBJECT + CollisionFlag.VEHICLE + CollisionFlag.BUILDING)
    return RseSurvivors.rayHit
end

-- how far the ground under it lies above the terrain: a road surface, a bridge. It used to compare with the height of the scene, so an animal that
-- walked downhill floated, and then stood stuck in the air because everything looked too steep (M4 round 1).
local function measureGround(animal)
    local terrain = getTerrainHeightAtWorldPos(g_terrainNode, animal.x, 0, animal.z)
    local hit = heightBelow(animal.x, terrain + animal.groundOffset + RAY_START, animal.z, RAY_START + RAY_BELOW,
        CollisionFlag.TERRAIN + CollisionFlag.STATIC_OBJECT + CollisionFlag.ROAD)
    local offset = hit ~= nil and hit - terrain or 0
    if offset > animal.groundOffset + RseConfig.HERD_MAX_STEP then
        offset = animal.groundOffset -- something above the ground it stands on: a rail, a low wall
    end
    animal.groundTarget = math.max(0, offset)
end

-- leaning with the ground
local function measureSlope(animal)
    if animal.groundOffset >= 1 then
        animal.slopePitch, animal.slopeRoll = 0, 0
        return
    end
    local dirX, dirZ = math.sin(animal.yaw), math.cos(animal.yaw)
    local long, wide = 0.7, 0.3
    local function terrain(x, z)
        return getTerrainHeightAtWorldPos(g_terrainNode, animal.x + x, 0, animal.z + z)
    end
    animal.slopePitch = -math.atan((terrain(dirX * long, dirZ * long) - terrain(-dirX * long, -dirZ * long)) / (2 * long))
    animal.slopeRoll = math.atan((terrain(dirZ * wide, -dirX * wide) - terrain(-dirZ * wide, dirX * wide)) / (2 * wide))
end

-- the hidden cone that stops traffic for it, wherever it walks (Z: cars stop for animals in the road); off the road it does nothing
local function updateBlocker(animal, y)
    if animal.blocker ~= nil then
        local x, _, z = RseKit.blockerPosition(animal.blocker)
        if (animal.x - x) ^ 2 + (animal.z - z) ^ 2 <= RseConfig.HERD_BLOCKER_STEP ^ 2 then
            return
        end
        removeBlocker(animal)
    end
    animal.blocker = RseKit.newBlocker(animal.x, y, animal.z)
end

-- the slower things, a few times a second
local function check(self, animal, y, px, pz)
    RseLog.try("measure the ground", measureGround, animal)
    RseLog.try("measure the slope", measureSlope, animal)
    local okLook, blocked = RseLog.try("look ahead", lookAhead, animal, y)
    animal.blocked = okLook and blocked == true
    RseLog.try("the hidden cone", updateBlocker, animal, y)
    if self.leading == animal then
        RseMarkers:hide(animal)
    else
        animal.markerInfo.y = y
        RseMarkers:show(animal, animal.x, animal.z, { name = animal.markerInfo.title, image = "loose", info = animal.markerInfo })
    end
    if animal.pin == nil and type(NavigationMarker) == "table" then
        local ok, pin = RseLog.try("create a pin", NavigationMarker.new)
        animal.pin = ok and pin or nil
    end
    if animal.pin ~= nil then
        animal.pin:setVisibility(self.leading ~= animal and px ~= nil and (animal.x - px) ^ 2 + (animal.z - pz) ^ 2 <= RseConfig.PIN_RANGE ^ 2)
    end
end

local function playerAt()
    if g_localPlayer == nil then
        return nil
    end
    local vehicle = g_localPlayer:getCurrentVehicle()
    if vehicle ~= nil then
        if vehicle.rootNode == nil then
            return nil
        end
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        return x, z, false
    end
    local x, _, z = g_localPlayer:getPosition()
    return x, z, true
end

local function updateAnimal(self, animal, dt, px, pz, onFoot)
    if self.leading == animal and not onFoot then
        self.leading = nil -- you got in a vehicle: it stays behind
    end
    local world = { homeX = animal.scene.x, homeZ = animal.scene.z, playerX = px, playerZ = pz, playerStill = self.stillMs >= RseConfig.HERD_STILL_MS,
        led = self.leading == animal, blocked = animal.blocked }
    if RseHerdRules.step(animal, dt, world, RseConfig, math.random) == "broke" then
        self.leading = nil
        RseText.notify(RseText.get("rse_survivor_gotAway", RseText.animal(animal.kind)), true)
    end
    local blend = math.min(1, dt / RseConfig.HERD_SMOOTH_MS)
    animal.groundOffset = animal.groundOffset + (animal.groundTarget - animal.groundOffset) * blend
    animal.pitch = animal.pitch + (animal.slopePitch - animal.pitch) * blend
    animal.roll = animal.roll + (animal.slopeRoll - animal.roll) * blend
    local y = getTerrainHeightAtWorldPos(g_terrainNode, animal.x, 0, animal.z) + animal.groundOffset
    animal.y = y
    local bob, rock, sway = 0, 0, 0
    animal.gait = animal.gait + (math.min(1, animal.speed / RseConfig.HERD_GAIT_FULL) - animal.gait) * blend
    if animal.rig ~= nil then
        if animal.wasMoving and not animal.moving then
            animal.wantsGraze = math.random() < RseConfig.GAIT_GRAZE_CHANCE
        end
        animal.wasMoving = animal.moving
        local grazing = not animal.moving and animal.wantsGraze and self.leading ~= animal
        animal.graze = animal.graze + ((grazing and 1 or 0) - animal.graze) * math.min(1, dt / RseConfig.GAIT_GRAZE_MS)
        if px ~= nil and (animal.x - px) ^ 2 + (animal.z - pz) ^ 2 <= RseConfig.GAIT_RANGE ^ 2 then
            local ok, up, roll, tilt = RseLog.try("move the legs", poseRig, animal, dt, blend)
            if ok then
                bob, sway, rock = up, roll, tilt
            else
                animal.rig = nil -- stays as it stands, and the body still rocks
            end
        end
    else
        local rate = math.max(RseConfig.HERD_STEP_MIN, math.min(RseConfig.HERD_STEP_MAX, animal.speed * RseConfig.HERD_STEP_RATE))
        animal.stepPhase = animal.stepPhase + rate * dt
        bob = math.abs(math.sin(animal.stepPhase)) * RseConfig.HERD_STEP_BOB * animal.gait
        rock = math.sin(animal.stepPhase) * RseConfig.HERD_STEP_ROCK * animal.gait
        sway = math.sin(animal.stepPhase / 2) * RseConfig.HERD_STEP_SWAY * animal.gait
    end
    setWorldTranslation(animal.node, animal.x, y + bob, animal.z)
    setWorldRotation(animal.node, animal.pitch + rock, animal.yaw + RseConfig.HERD_MODEL_YAW, animal.roll + sway)
    if animal.pin ~= nil then
        animal.pin:setWorldPosition(animal.x, y + animal.def.height + RseConfig.PIN_HEIGHT / 2, animal.z)
    end
    animal.checkMs = animal.checkMs - dt
    if animal.checkMs <= 0 then
        animal.checkMs = CHECK_INTERVAL_MS
        check(self, animal, y, px, pz)
    end
end

function RseSurvivors:update(dt)
    local px, pz, onFoot = playerAt()
    if px ~= nil and self.lastPlayerX ~= nil and (px - self.lastPlayerX) ^ 2 + (pz - self.lastPlayerZ) ^ 2 < (0.2 * dt / 1000) ^ 2 then
        self.stillMs = self.stillMs + dt
    else
        self.stillMs = 0
    end
    self.lastPlayerX, self.lastPlayerZ = px, pz
    local function updateScene(scene)
        for _, animal in ipairs(scene.survivors or {}) do
            if nodeExists(animal.node) then
                updateAnimal(self, animal, dt, px, pz, onFoot)
            end
        end
    end
    for _, scene in pairs(RseScenes.scenes) do
        updateScene(scene)
    end
    if self.test ~= nil then
        updateScene(self.test)
    end
    RseLog.try("the lead", updateLead, self)
end

function RseSurvivors:draw(scene)
    for _, animal in ipairs(scene.survivors or {}) do
        if animal.pin ~= nil and not RseLog.try("draw a pin", animal.pin.render, animal.pin) then
            return false
        end
    end
    return true
end

-- rseLive: one loose animal at x, z, walking off from there. Returns how many there are now.
function RseSurvivors:spawnTest(kind, x, z, yaw)
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    self.test = self.test or { id = "test", segments = {}, survivors = {} }
    self.test.x, self.test.y, self.test.z = x, y, z
    self:spawn(self.test, kind, { { x = x, y = y, z = z, yaw = yaw } })
    return self:remaining(self.test)
end

function RseSurvivors:clearTest()
    if self.test ~= nil then
        self:remove(self.test)
        self.test = nil
    end
end

-- what the savegame keeps of them
function RseSurvivors:saveData(scene)
    local list = {}
    for _, animal in ipairs(scene.survivors or {}) do
        table.insert(list, { kind = animal.kind, x = animal.x, y = animal.y, z = animal.z, yaw = animal.yaw })
    end
    return list
end

-- while the map unloads
function RseSurvivors:unload()
    stopLead(self)
    self:clearTest()
    self.leading = nil
    self.reported = {}
end
