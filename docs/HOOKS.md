# Hooks: where Roadside Emergencies touches the game

Every place the mod changes or extends game behaviour. **No base-game function is replaced.** Hooks append a call after the original
or pass through to it; each wraps the *stored original* (so loading another savegame never stacks it). Game source is cited by file
and function name only.

## Appended functions

| Game function | Our file | What we add | Why |
|---|---|---|---|
| `TreePlantManager.loadTreeNode` | `scripts/game/SavedLogs.lua` | Wrapped, returning what the game's function returned. For a transport tree **of ours** loaded from a savegame (one this mod laid down, by where it stands, from the list in our save), it does for the pieces under `transportTreeGroup` what the function does for those directly under the tree. Other logs of that kind, from the game or other mods, are left as the game loads them. A save from before the list (0.9.6.2 and older) gets the old behavior once | Without it the game adds the tree's position to each saved log, so they load off the map and fall for ever (proven by the log, 2026-11-04). Other kinds of tree aren't touched |
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
| `Overlay` (with `setRotation` for the arrow), `drawFilledRect`, `renderText`, `getTextWidth`, `utf8ToUpper`, `getCamera` and `localDirectionToWorld` in the mod's `draw` callback; `g_currentMission.hud:getIsVisible` if the game has it | `CallPanel.lua` | The call panel, only while a job runs, not behind menus, the map, our settings panel or a hidden HUD; one failure switches it off for the session |
| `Overlay`, `drawFilledRect`, `renderText` in the mod's `draw` callback, through `RseScenes:draw` (not behind menus) | `Draw.lua` (`warningBanner`), `PowerLine.lua` | The live wires warning, the whole time you are too close; a failure switches the scene's drawing off for the session |
| `raycastClosest` (buildings, static objects, road surfaces, water) | `PowerLine.lua` (`findLayout`, `pickSpot`) | A power line's poles, wires and fallen pole only where they fit; the call's spot is chosen before it is laid out, as the river, crossing and flock calls do |
| `VehicleLoadingData` for the crew truck (the game's contract-vehicle way: `MISSION`, not saved), `setVehicleCharacter`, `setTurnLightState`; the game's `AIVehicleUtil.driveToPoint` on it, with `forceIsActive` and `startMotor`, and `raycastClosest` ahead of it; our enter gate on `Enterable` also refuses it | `UtilityCrew.lua`, `Wrecks.lua` | The utility crew drives up to a power line the way the game's own AI helpers drive (the game's Drivable only drives a vehicle a player controls, so nothing else drives it); the AI road splines for its way (`Roads.lua` `routeBack`) |
| Our own description text (`rse_ep_<id>_description`) in the text tables that hold it, for one call, and the pending emergency's `description` put back once the pager has it | `EpBridge.lua`, `CallPlan.lua` | The pager's fields (U3): the call is planned before the pager asks (place, animals, load, vehicle, the train's time) and laid out from the same plan; our text goes back after `PAGER_CHECK_MS` |
| The pack's `getReward` on **our own** emergency object, once per job, with our reward set to a round number and put back at once | `CallPanel.lua` | The panel's "about" pay includes the game's economy difficulty, as the pack applies it (in the FS22 pack, `getReward` only multiplies `calculateReward`) |
| `Overlay`, `drawFilledRect`, `renderText` in the mod's `draw` callback | `Kit.lua`, `SettingsPanel.lua` | The scene kit strip and the settings panel, only while open and not behind menus; one failure switches them off |
| `AITargetHotspot`, `g_currentMission:addMapHotspot` / `removeMapHotspot` | `Markers.lua` | Map marker for kit items still out. Proven by Z in M2 round 4 (`PlaceableHotspot` broke the menu in 0.1.0.0; this class stands on its own) |
| `g_currentMission.animalSystem` (`getSubTypeByIndex`, `getVisualByAge`) | `Carcasses.lua`, `Survivors.lua` | Posed livestock models |
| `g_inputBinding:setContext`, `registerActionEvent`, `revertContext` with the game's menu actions | `SettingsPanel.lua` | Arrow keys while the panel is open, the way `TextInputElement` takes the keyboard |
| `hotspot.icon` of our own `AITargetHotspot` objects: `Overlay:setImage`, `setUVs`, `setColor` | `Markers.lua` | Our own picture and colour on our own markers |
| `getQuaternion`, `setQuaternion` on the bones of our own model copies | `Survivors.lua` | The walk |
| `vehicle:brake`, `vehicle.rotatedTime`, `raiseActive` on our own wrecks while strapped | `Wrecks.lua` | Brakes off on a tight strap and on when it goes slack, and front wheels steering, so it follows the tow and stops with it |
| `g_currentMission:setMapTargetHotspot`, `currentMapTargetHotspot` | `Scenes.lua` | Near an animal on a bridge, the map target steps aside for a pin on the animal, and comes back afterwards. Only while the target is our own emergency's |
| Better Winch, optional and only if present: `g_thBetterWinch` (`injectObjectAttachPoint`, `getAttachableObject`), its attachable object's `addMeshNode`, `setIsDirty` | `Wrecks.lua` | An attach point on each end of our own wrecks. No dependency |
| Reading `currentMapTargetHotspot` during a job, and `setMapTargetHotspot` if one of our own markers holds it | `Scenes.lua` | The job's marker always wins |
| `InfoDialog.show` | `EpBridge.lua` | Says the Emergency Pack is required, on a load without it |
| `spec_trainSystem`, `railroadCrossings` (`nearestTime`, `rootNode`), `rootLocomotive.spec_locomotive` (`state`, `speed`), `getIsRented`, `getSplineLength`, `getSplineTime`, `getSpline`, read only | `LevelCrossing.lua` | The railroad crossing call waits for the train and follows it. **Nothing touches the train** |
| `setLinearVelocity`, `setAngularVelocity` on our own wreck | `Wrecks.lua` | The train's hit throws it |
| Not a hook: our own `rse_ep_*_description` text, in the text tables that already hold it (our `g_i18n.texts`, the game's, the game's for our mod), for a moment while a call is asked for | `EpBridge.lua` | The pager says which vehicle it is, and what it takes to tow it. Put back within a second, and when the map unloads |
| `MoneyType.register` (`rse_finance_penalty`), `mission:addMoney` | `RoadsideEmergencies.lua`, `Scenes.lua` | The small charge for a job you said yes to that ends with no pay |
| Not a hook: our own hint texts that hold a `{...}` (such as `{key:RSE_STRAP}`), filled in with the key names in the text tables that hold them, before the pack loads a call and on a resumed one | `EpBridge.lua`, `Text.lua` | The pack reads a step's hint from the text table itself, so it never sees our fill-in otherwise. Our own messages read the kept template |
| `pendingScenarios`, `runningScenarios` and the emergency's `description`, read only | `EpBridge.lua` | Checks that the pager's text has the vehicle in it; if not, it goes on the screen. Once our call is pending (the pager is up), the pager beeps |
| Not a hook: `createSample`, `loadSample`, `setSampleGroup` (`AudioGroup.GUI`), `playSample` on our own `sounds/pager.ogg` | `Sound.lua` | The pager's beeps, at the game's interface volume |
| Better Winch, optional and only if present: `getAttachableObject`, `getIsAttached` on its attachable object | `Wrecks.lua` | A held vehicle comes loose when a winch line is on it |
| `raycastClosest` with `CollisionFlag.WATER`, and `thresholdTailwaterDepth`, `thresholdTailwaterDepthWarning` on our own river car | `RiverPlaces.lua`, `Wrecks.lua` | Looks for shallow water beside roads with a bank a car can come up, and keeps the job's car from drowning: the game breaks a vehicle for good once the water over it is that deep |
| `g_storeManager:getItemByXMLFilename` (read only) | `Wrecks.lua` | A call only picks a wreck vehicle the game has |
| `MessageDialog` (our own subclass), `g_gui:loadGui` with our `gui/rseWelcomeDialog.xml` on the game's dialog profiles, `g_gui:showDialog`, `closeDialogByName`; `mission:setManualPause` | `Welcome.lua` | The welcome dialog, once per player; it pauses the game while open. Proven by the U0 probe (0.9.6.4). It writes out where to report a bug: the game can't open a link (`openWebFile` returns nothing and no browser shows, U0 and U1) |
| `getUserProfileAppPath`, `createFolder` and an XML file in `modSettings/FS25_RoadsideEmergencies/player.xml` | `PlayerFile.lua` | Your last settings, for a new savegame, and whether you have seen the welcome. Our own file, where mods keep such files |
| `g_i18n:formatMoney(amount, 0, true)` (as the game's own dialogs write a price in a sentence), `formatMass`, `formatDistance`; `g_inputDisplayManager:getKeyboardInputActionKey` if the game has it | `Text.lua` | Money, weights and distances as the game writes them; key names in texts from your bindings, our default keys if the game can't say (the log says which) |
| Our carcass's own `getFillLevelInformation(display)`, which the game's belts and loaders call on an object that has one, and `unitShort` on **our own** fill types | `Carcass.lua` | "3 Deer" on the fill display, one or many by the count (Z) |
| `getTerrainAttributesAtWorldPos` (the fifth value, the map's surface number, as `Rideable` reads it for hoof sounds), `g_currentMission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)` with `getDensityAtWorldPos` and `FieldGroundType.getTypeByValue` (as `WheelPhysics` reads the field under a wheel), the train system's `getSpline`, and `raycastClosest` (straight down with `STATIC_OBJECT`, `BUILDING`, `ROAD`; across with `TREE`), all read only | `FlockPlaces.lua` | Where a flock call can come from: open country, and grass or a grass field for the pen, away from towns, yards, the railroad and the woods. Searched a few road spots a frame as the map loads |
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
| `delete` on a piece of our own pole at a recovery point; `overlapSphere` to find saved pieces again, and a piece that went without a cut message; the same search for the logs of a job that is over, after a load | `PowerLine.lua`, `Cleanup.lua` | The game saves loose logs itself, with new node numbers |
| `setJointFrame`, `setDirection` on our own strap joints | `Strap.lua` | Keeps the joint turned along the line, so the strap pulls where it runs |
| Emergency Pack scenario `setProgress`: **replaced on our own emergency objects only** (the instance, not the class) | `EpSteps.lua` | The bar shows what has really been done |
| `Vehicle:setAbsolutePosition` on our own wrecks | `Wrecks.lua` | Lay a wreck flat on its side |
| `LivestockTrailer` (`getSupportsAnimalSubType`, `getNumOfFreeAnimalSlots`, `addAnimals`) on the player's own trailers | `Survivors.lua` | Lead a live animal into a trailer as a real animal |
| `environment.weather.twister` (`isSpawned`, `fadeValue`, `sendPosX`, `sendPosZ`, read only) | `Calls.lua` | A storm call when a twister ends |
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
