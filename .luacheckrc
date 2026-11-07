-- luacheck config for FS25 mod code (Lua 5.1 dialect, as the game runs it).
-- Add a game global to read_globals the first time our code uses it, so typos in global names still get caught.

std = "lua51"
max_line_length = 160
codes = true

-- Our own global tables (one per mod/probe).
globals = {
    "RoadsideProbe",
}

read_globals = {
    -- set by the game while a mod's scripts load
    "g_currentModName", "g_currentModDirectory",

    -- optional mods, read only if present
    "g_thBetterWinch",

    -- read for one log line
    "HandToolHands",

    -- game singletons and state
    "g_currentMission", "g_localPlayer", "g_terrainNode", "g_i3DManager", "g_modManager", "g_fillTypeManager",
    "g_gameVersionDisplay", "g_screenAspectRatio",

    -- game classes / enums
    "Utils", "Overlay", "VehicleLoadingData", "VehiclePropertyState", "VehicleLoadingState", "DensityMapHeightUtil",
    "FillType", "ToolType", "RigidBodyType", "JointConstructor",

    -- mod lifecycle and console
    "addModEventListener", "addConsoleCommand", "removeConsoleCommand",

    -- engine functions
    "getTerrainHeightAtWorldPos", "getRootNode", "link", "delete", "setWorldTranslation", "setWorldRotation",
    "addToPhysics", "getNumOfChildren", "getChildAt", "addTrafficSystemPlayer", "removeTrafficSystemPlayer",
    "getName", "getQuaternion", "setQuaternion", "setJointTranslationLimit", "setJointFrame", "ParticleUtil", "getHasClassId", "ClassIds", "getSplitType", "getMass", "getVolume", "getUserAttribute", "overlapSphere",
    "g_treePlantManager", "g_messageCenter", "setTextWrapWidth", "getTextHeight", "getTextWidth", "Overlay", "InGameMenuMapUtil", "InGameMenuMapFrame", "InfoDialog", "SplineUtil", "g_brandManager", "setAngularVelocity", "setLinearVelocity", "Locomotive", "g_storeManager", "IngameMapElement", "MapHotspot", "FocusManager", "OptionDialog",
    "createTransformGroup", "setRotation", "setTranslation", "setVisibility",
    "copyFile", "createFolder", "fileExists", "getFiles", "getUserProfileAppPath",
    "setRigidBodyType", "getWorldTranslation", "localToWorld", "removeJoint", "getName", "clone", "setScale",
    "getMaterial", "setMaterial", "setMaterialDiffuseMapFromFile", "getWorldRotation", "entityExists",
    "setCollisionFilterGroup", "setCollisionFilterMask", "XMLSchema", "XMLFile", "ForestryRope",
    "raycastClosest", "CollisionFlag", "g_cameraManager", "localDirectionToWorld", "worldDirectionToLocal", "worldToLocal",
    "getAngularVelocity", "getVelocityAtWorldPos", "getLinearVelocity", "createAudioSource", "getAudioSourceSample", "setAudioSourceAutoPlay", "setSampleGroup", "playSample", "AudioGroup",
    "setDirection", "getRotation", "getIsSplitShapeSplit", "getCenterOfMass", "getSplitShapeStats", "removeFromPhysics", "getParent", "VehicleConfigurationItem", "g_vehicleConfigurationManager", "AttacherJoints",
    "getShapeBoundingSphere", "getHasShaderParameter", "setShaderParameter", "getVisibility", "getTranslation",
    "g_inputBinding", "InputAction", "GS_PRIO_VERY_HIGH", "renderText", "setTextAlignment", "RenderText",
    "setMaterialNormalMapFromFile", "setMaterialGlossMapFromFile", "setShapeCastShadowmap",
    "getShapeGeometryBoundingSphere", "setShapeDecalLayer", "getShapeWorldBoundingSphere", "invalidateShapeBoundingVolume",
    "Class", "loadXMLFile", "hasXMLProperty", "getXMLString", "getXMLNumOfAttributes", "getXMLAttributeName",
    "getXMLNumOfChildren", "getXMLElementName",
    "Bale", "g_baleManager", "g_i18n", "setMass",
    "getRigidBodyType", "Twister", "MessageType", "g_npcManager", "HumanModel", "Lights",
}

-- The mod (mod/): its own globals, the game APIs it uses, and the game classes it hooks (each one in docs/HOOKS.md).
files["mod"] = {
    -- methods the game calls by name keep their self even when they don't use it
    self = false,
    globals = {
        -- our tables and classes
        "RoadsideEmergencies", "RseConfig", "RseLog", "RseAnimalCatalog", "RsePayRules", "RsePointRegistry", "RseSaveCodec",
        "RseStore", "RseText", "RseCarcass", "RseCarcasses", "RseCarcassDrag", "RseStrap", "RsePoints", "RseSaveLoad",
        "RseEpBridge", "RseConsole", "RseRoadClearRule", "RseSceneSpec", "RseCallPlanner", "RseRoads", "RseScenes",
        "RseEpSteps", "RseCalls", "RseKit", "RseKitRules", "RseMarkers", "RseSpotRules", "RseLeftBehindRule", "RseJobRules", "RseGuide", "RseCrossingRules", "RseLevelCrossing", "RseStepCrossing", "RseLogRules", "RseWaterRules", "RseRiver", "RseFlock", "RseFlockRules", "RseSound", "RseStepTree", "RseStepFlock", "RseLogSpill", "RseCleanup", "RseSavedLogs", "RseStepLogs", "RseProgressRules", "RseHerdRules", "RseGaitRules", "RseWreckRules", "RseTwisterRules", "RseTwisterTravel", "RseLineRules", "RsePowerLine", "RseStepPower", "RseToolRules", "RseToolSwitch", "RseWrecks", "RseSpillBale", "RseSettings", "RseSettingsPanel", "RseSurvivors", "RseMapClicks",
        "RseGroundRules", "RseFlockPlaces", "RseTheme", "RsePlayerFile", "RseWelcome", "RseWelcomeDialog", "RseDraw", "RsePanelRules", "RseCallPanel", "RseCrewRules", "RseUtilityCrew", "RsePagerRules", "RseCallPlan",
        -- step classes the Emergency Pack looks up by name ("FS25_RoadsideEmergencies.RseStepArrive")
        "RseStepArrive", "RseStepClearRoad", "RseStepPrepare", "RseStepUpright", "RseStepDeliver", "RseStepCrash",
        -- hooked game classes: wreck gates (Wrecks.lua; wrap the stored original, act only on a wreck)
        "Enterable", "Motorized",
        -- hooked game classes (appended functions, stored original, restored on unload)
        "PlayerInputComponent", "FSCareerMissionInfo", "FSBaseMission", "g_splitShapeManager"
    },
    read_globals = {
        "MoneyType", "PlaceableHotspot", "createXMLFile", "setXMLInt", "setXMLFloat", "setXMLString", "saveXMLFile",
        "getXMLInt", "getXMLFloat", "unpack", "setXMLBool", "getXMLBool", "getSplineLength", "getSplinePosition",
        "getSplineDirection", "Season", "AITargetHotspot", "NavigationMarker", "g_gui", "g_farmlandManager", "VehicleLoadingData", "VehicleLoadingState", "VehiclePropertyState", "g_npcManager", "drawFilledRect", "setTextBold", "setTextColor",
        "getTerrainAttributesAtWorldPos", "getDensityAtWorldPos", "bit32", "FieldGroundType", "FieldDensityMap", "MessageDialog", "GameSettings", "g_time", "g_inputDisplayManager",
        "utf8ToUpper", "getCamera", "localDirectionToWorld", "AIVehicleUtil", "CollisionFlag", "raycastClosest", "Lights", "g_gameSettings"
    }
}

-- Unit tests (tests/): the runner defines the test functions as globals; dofile loads the core.
files["tests"] = {
    globals = { "describe", "it", "expectEqual", "expectNear", "expectTrue", "expectNil",
        "RseConfig", "RseLog", "RseAnimalCatalog", "RsePayRules", "RsePointRegistry", "RseSaveCodec", "RseStore",
        "RseRoadClearRule", "RseSceneSpec", "RseCallPlanner", "RseKitRules", "RseSpotRules", "RseLeftBehindRule", "RseJobRules", "RseGuide", "RseCrossingRules", "RseLevelCrossing", "RseStepCrossing", "RseLogRules", "RseWaterRules", "RseFlockRules", "RseLogSpill", "RseStepLogs", "RseProgressRules", "RseHerdRules", "RseGaitRules", "RseWreckRules", "RseTwisterRules", "RseTwisterTravel", "RseLineRules", "RsePowerLine", "RseStepPower", "RseToolRules", "RseToolSwitch", "RseSettings", "RseGroundRules", "RseTheme", "RsePanelRules", "RseCrewRules", "RsePagerRules" },
    read_globals = { "os" }
}

-- Throwaway probe code: tolerate unused callback arguments (game passes them positionally).
files["probe"] = {
    unused_args = false,
    -- the probe overrides these class functions directly; the real mod uses a specialization instead
    globals = { "Enterable", "Motorized", "ConfigurationUtil", "PlayerInputComponent",
        -- checkpoint actions the Emergency Pack looks up by name ("FS25_RoadsideProbe.RoadsideProbeEpArrive")
        "RoadsideProbeEpArrive", "RoadsideProbeEpClear",
        -- probe P8: a carcass is a bale subclass (RoadsideProbeP8.lua)
        "RoadsideProbeCarcass",
        -- probe P9: the pack's cone step with the pack's folder (RoadsideProbeEpActions.lua)
        "RoadsideProbeEpCones" },
}

files["mod/scripts/game/SavedLogs.lua"] = {
    globals = { "TreePlantManager" },
}

files["mod/scripts/game/TwisterTravel.lua"] = {
    globals = { "Twister" },
}
