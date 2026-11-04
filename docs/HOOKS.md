# Hooks: where Roadside Emergencies touches the game

Every place the mod changes or extends game behaviour. **No base-game function is replaced.** Hooks append a call after the original
or pass through to it; each wraps the *stored original* (so loading another savegame never stacks it). Game source is cited by file
and function name only.

## Appended functions

| Game function | Our file | What we add | Why |
|---|---|---|---|
| `Twister.move` | `scripts/game/TwisterTravel.lua` | Wrapped, returning what the game's function returned (`Utils.appendedFunction` drops it): straight after the game moves its twister, it goes back to where ours is | Z wants to see it move, and its damage with it. Its code isn't readable, so the log counts any frame in which something else moved it |
| `PlayerInputComponent.registerActionEvents` | `scripts/game/RoadsideEmergencies.lua` | For the local player only (`component.player.isOwner`): register the `RSE_STRAP` and `RSE_KIT_*` keys in the player's input context (`RseStrap:registerActionEvents`, `RseKit:registerActionEvents`) | The strap key (DESIGN F26) and the scene kit keys (F27) on foot. Same pattern the probe proved in P5 |
| `FSCareerMissionInfo.saveToXMLFile` (fallback `FSBaseMission.saveSavegame` if the first is missing; the log says which) | `scripts/game/SaveLoad.lua` | Write `roadsideEmergencies.xml` into the savegame folder: settings, player points, carcasses | Our state survives save → quit → reload |

| `InGameMenuMapFrame.setMapSelectionItem` | `scripts/game/MapClicks.lua` | Only for a marker of ours (it carries `rseMarker`): shows the game's context box for it with our buttons. Every other selection only switches our buttons off. Runs protected | Clicking our markers (Z, M4 round 3) |

## Overwritten functions (pass through, except on a wreck of ours)

| Game function | Our file | What it does | Why |
|---|---|---|---|
| `Enterable.getIsEnterable`, `Enterable.interact`, `Enterable.getIsTabbable` | `scripts/game/Wrecks.lua` | A locked wreck can't be entered, and no wreck is in the Tab cycle; every other vehicle goes straight to the game's function | Wreck jobs (DESIGN F9, P3b). Wrapped as the scripts load, while the game builds its vehicle types |
| `Motorized.getCanMotorRun`, `Motorized.getMotorNotAllowedWarning` | `scripts/game/Wrecks.lua` | A wreck's engine can't start; every other vehicle goes straight to the game's function | The same |

| `IngameMapElement.selectHotspotAt` | `scripts/game/MapClicks.lua` | A click on a marker of ours selects it; any other click goes to the game's function untouched | The game's map screen only lets through the marker categories it knows, and ours aren't among them |

## Subclasses (affect only our own objects)

| Game class | Our class | Overridden methods | Why |
|---|---|---|---|
| Emergency Pack `ScenarioAction` (`pdlc_emergencyPack`) | `RseStepArrive`, `RseStepClearRoad` (`scripts/game/EpSteps.lua`) | `new`, `loadFromXML` (reads our attributes, then the pack's), `onUpdate`, `canBeCompleted`, `delete` (each calls the pack's own first or last) | Our steps inside the pack's emergencies; the pack finds them by dotted name (P7b) |
| Emergency Pack `PlaceObjectAction` | `RseStepCones` (`EpSteps.lua`) | `loadFromXML`: passes the pack's own folder, so the pack finds its cone hand tool | The pack's cone step in our emergencies (P9) |
| `Bale` | `RseSpillBale` (`scripts/game/Wrecks.lua`) | `getCanBeSold`, `getCanBeOpened`, `getSupportsWrapping`, `getNeedsSaving`, `getValue` | A spilled load every machine handles, which must be delivered and can't be sold |
| Emergency Pack `ScenarioAction` | `RseStepPrepare`, `RseStepUpright`, `RseStepSurvivors`, `RseStepDeliver` (`scripts/game/EpSteps.lua`) | `new`, `onUpdate`, `canBeCompleted`, `delete` | Wreck jobs |
| `Bale` (`objects/Bale.lua`, the way the game's own `PackedBale` extends it) | `RseCarcass` (`scripts/game/Carcass.lua`) | `getSupportsWrapping`, `getCanBeOpened`, `getCanBeSold`, `getNeedsSaving` (our file saves them), `getValue`, `getDefaultMass`, `showInfo` | A carcass body that every machine handles like a bale (P8), but that can't be wrapped, opened, sold or saved as a bale |

## Public APIs used (no hook)

| API | Our file | Use |
|---|---|---|
| `g_currentMission.activatableObjectsSystem` (`addActivatable` / `removeActivatable`) | `CarcassDrag.lua`, `Carcasses.lua` | The activate prompt to drag a carcass |
| `MoneyType.register("other", …)`, `g_currentMission:addMoney` | `RoadsideEmergencies.lua` | Haul-off pay and disposal fees under their own names in the finances |
| `NavigationMarker` (`new`, `setWorldPosition`, `setVisibility`, `render`, `delete`) in the mod's `draw` callback | `Scenes.lua` | A pin over each animal, the same marker the game's navigation uses; not behind menus, and one failure switches it off |
| `PlaceableHotspot` (read only: lists its marker types) | `Points.lua` | Map markers are **off** (`RseConfig.MAP_MARKERS`): a `PlaceableHotspot` without a placeable broke the in-game menu in 0.1.0.0 |
| `g_currentMission:addIngameNotification` | `Text.lua` | Short messages |
| `JointConstructor`, `removeJoint`, `ForestryRope` | `Strap.lua` | The strap joint and its visible rope |
| `raycastClosest` | `Strap.lua`, `Scenes.lua`, `Kit.lua` | What the player looks at (hook point, the ground for a kit item); whether a vehicle is right under a carcass (loaded) |
| `g_currentMission.aiSystem.roadSplines` (AISystem, read only), `getSplineLength`, `getSplinePosition`, `getSplineDirection` | `Roads.lua` | The lanes around a scene, sampled once per scene: lay the animals across the lane, tell the road from the verge |
| `g_currentMission.environment` (`currentHour`, `currentSeason`, read only) | `Calls.lua` | Deer and boar calls likelier at dusk and dawn, deer in autumn |
| `vehicle:setTensionBeltsActive(false/true, beltId, true, false)` (TensionBelts) | `Carcasses.lua` | After a reload, open and close every fastened belt of a vehicle near a carcass, so the belt joins the carcass that came back after the game had fastened it (0.1.0.4 used `refreshTensionBelts`, which only redraws the belt) |
| `VehicleLoadingData` with `VehiclePropertyState.MISSION` (as `AbstractMission:spawnVehicle`), `vehicle:delete`, `setDamageAmount`, `setVehicleCharacter`, `g_npcManager` | `Wrecks.lua` | The wreck: not in the vehicle list, can't be sold; a seated driver |
| `vehicle:getUniqueId()`, `vehicleSystem:getVehicleByUniqueId` | `Strap.lua` | Save a strap with its vehicle and find that vehicle again after a reload |
| `g_i3DManager:loadSharedI3DFile` with base-game `$data/maps/...` props | `Kit.lua` | The scene kit's cones, barriers and signs (models referenced, not copied) |
| `Overlay`, `drawFilledRect`, `renderText` in the mod's `draw` callback | `Kit.lua`, `SettingsPanel.lua` | The scene kit strip and the settings panel, only while open and not behind menus; one failure switches them off |
| `AITargetHotspot`, `g_currentMission:addMapHotspot` / `removeMapHotspot` | `Markers.lua` | Map marker for kit items still out. Proven by Z in M2 round 4 (`PlaceableHotspot` broke the menu in 0.1.0.0; this class stands on its own) |
| `g_currentMission.animalSystem` (`getSubTypeByIndex`, `getVisualByAge`) | `Carcasses.lua`, `Survivors.lua` | Posed livestock models |
| `g_inputBinding:setContext`, `registerActionEvent`, `revertContext` with the game's menu actions | `SettingsPanel.lua` | Arrow keys while the panel is open, the way `TextInputElement` takes the keyboard |
| `hotspot.icon` of our own `AITargetHotspot` objects: `Overlay:setImage`, `setUVs`, `setColor` | `Markers.lua` | Our own picture and colour on our own markers |
| `getQuaternion`, `setQuaternion` on the bones of our own model copies | `Survivors.lua` | The walk |
| `vehicle:brake`, `vehicle.rotatedTime`, `raiseActive` on our own wrecks while strapped | `Wrecks.lua` | Brakes off on a tight strap and on when it goes slack, and front wheels steering, so it follows the tow and stops with it |
| `g_currentMission:setMapTargetHotspot`, `currentMapTargetHotspot` | `Scenes.lua` | Near an animal on a bridge, the map target steps aside for a pin on the animal, and comes back afterwards. Only while the target is our own emergency's |
| Better Winch, optional and only if present: `g_thBetterWinch` (`injectObjectAttachPoint`, `getAttachableObject`), its attachable object's `addMeshNode`, `setIsDirty` | `Wrecks.lua` | An attach point on each end of our own wrecks. No dependency |
| `setJointTranslationLimit` on our own strap joints | `Strap.lua` | Shortening the strap, and reeling it |
| `wheel.physics.steeringAngle`, `wheel.physics.showSteeringAngle` on our own wrecks without steering | `Wrecks.lua` | While you reel, a trailer's wheels give way along the line, so it moves over; the picture doesn't turn. Back to 0 when you stop reeling or the strap comes off |
| `PlayerInputComponent.onInputToggleHandTool`, `onInputCycleHandTool`, `onInputToggleFlashlight` | `ToolSwitch.lua` | Wrapped, returning what they returned. If a press changed nothing during one of our jobs and your hands are empty, `Player:setCurrentHandTool` changes the tool. Away from a job they only pass through |
| `setWorldTranslation` on the root node of the game's twister, `setWorldPosition` on its map hotspot | `TwisterTravel.lua` | It travels within 80 m of where it appeared, and all its damage goes with it |
| `TreePlantManager:loadTreeTrunk`, reading `loadTreeTrunkDatas` for the result | `PowerLine.lua` | The fallen pole is a real loose log |
| `vehicle.canBeReset = false` on our own wrecks | `Wrecks.lua` | The game's own field, read by `Vehicle:getCanBeReset` |
| `g_messageCenter:subscribe(MessageType.VEHICLE_RESET)` | `Wrecks.lua` | If a wreck is reset anyway (the game's own out-of-the-world reset, or another mod), the copy it makes is deleted. Acts only on our own wrecks |
| `registerCustomInput` / `removeCustomInput` on our wire prompt, `InputAction.ACTIVATE_OBJECT` | `PowerLine.lua` | The way the game's winch control takes a held key. Not a hook, listed because it registers the game's action |
| `g_messageCenter:subscribe(MessageType.TREE_SHAPE_CUT)` | `PowerLine.lua` | Follows each piece when the pole is cut |
| `g_splitShapeManager.getIsShapeCutAllowed` | `PowerLine.lua` | Set on the manager from the first power line job until the map unloads, in front of whatever is there. Passes the game's answer through, and only turns a no into a yes for a log belonging to a running job, because the pole lies on a public road. Comes off on unload |
| `g_treePlantManager.treesData.splitTrees`, read only; `removingSplitShape` | `PowerLine.lua` | Pieces loaded from a savegame hang under the tree record they came from; a deleted piece is reported as the game does |
| `delete` on a piece of our own pole at a recovery point; `overlapSphere` to find saved pieces again, and a piece that went without a cut message | `PowerLine.lua` | The game saves loose logs itself, with new node numbers |
| `setJointFrame`, `setDirection` on our own strap joints | `Strap.lua` | Keeps the joint turned along the line, so the strap pulls where it runs |
| Emergency Pack scenario `setProgress`: **replaced on our own emergency objects only** (the instance, not the class) | `EpSteps.lua` | The bar shows what has really been done |
| `Vehicle:setAbsolutePosition` on our own wrecks | `Wrecks.lua` | Lay a wreck flat on its side |
| `LivestockTrailer` (`getSupportsAnimalSubType`, `getNumOfFreeAnimalSlots`, `addAnimals`) on the player's own trailers | `Survivors.lua` | Lead a live animal into a trailer as a real animal |
| `environment.weather.twister` (`isSpawned`, `fadeValue`, `sendPosX`, `sendPosZ`, read only), `weather:consoleCommandWeatherTwisterSpawn` (only from `rseTwister`) | `Calls.lua`, `Console.lua` | A storm call when a twister ends |
| `g_currentMission.rolePlay.thirdPartyMods`, `scenarioReferences`, `scenarioPools`, `runningScenarios` (Emergency Pack, read only) | `EpBridge.lua` | Check the pack read our emergency folder; is the farm busy |
| Emergency Pack `messageCenter:publish(ScenarioMessageType.SCENARIO_TOGGLE, farmId, pool, true)` | `EpBridge.lua` | Ask the pack to page the player with one of our emergencies (the route its own pager and console command use, P7b) |
| Emergency Pack scenario `targetPosition`, checkpoint `getScenario`, `isActive`, `setActionCompleted` | `EpSteps.lua` | Where the pack put the emergency; complete our steps |
| Emergency Pack scenario `targetPosition`, `rootNode`, `mapHotspot` written, `onTargetPositionDetermined`, `updateMarker`, `aiSystem:removeObstacle`, on our own emergency only, before anything is laid out | `EpSteps.lua` | Our location: anywhere on the road network, or where a saved call was |
| Emergency Pack `loadScenarioByInfoId`, `pendingScenarios`, `startStopScenarioForFarm` | `EpBridge.lua` | Run a saved call again after loading, without the pager: the pack's own steps after a Yes |
| Emergency Pack scenario `calculateReward`: **replaced on our own emergency objects only** (the instance, not the class), `getReward` read for the log | `EpSteps.lua` | Our flat call reward instead of the pack's speed-based one; the pack still applies the economy difficulty and pays it |

## Data the game reads from our modDesc

| Section | File | Use |
|---|---|---|
| `fillTypes` | `xml/fillTypes.xml` | `RSE_CARCASS_<ANIMAL>` (deer, boar, pig, sheep, goat, cow, buffalo, horse): one fill type per animal so each body shows its own name and picture; nothing sells, feeds or wraps them |
| (not listed) | `xml/bales/bales.xml` → `carcassSmall.xml`, `carcassLarge.xml` | Bale types that use the base-game square bale models by path (`$data/...`). `Carcasses.lua` registers them on map load with `g_baleManager:loadBaleFromXML` (the map's own loader; `loadModBaleFromXML` only queues for the next map load), because the game reads modDesc bale types before mod fill types and refuses unregistered ones |
| `actions` / `inputBinding` | modDesc | On foot: `RSE_STRAP` on `K`; `RSE_KIT_MENU` on `U`, `RSE_KIT_USE` on `L`, `RSE_KIT_TURN` on `O`, `RSE_KIT_NEXT` on `I`, `RSE_SETTINGS` on `P` |
| `emergencyPack` (version 1, `scenarioDirectory`) | `emergencies/init.xml` | The Emergency Pack's add-on loader (P7b): eight scenario files, one pool each (`rse_<animal>`) |
