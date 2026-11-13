-- Roadside Emergencies: every tunable in one place. Engine-free (plain values), so tests load it too.

RseConfig = {
    LOG_PREFIX = "[FS25_RoadsideEmergencies] ",

    -- carcasses
    ADULT_AGE_MONTHS = 48,        -- picks the adult model of a livestock subtype
    DRAG_MAX_MASS_KG = 150,       -- heavier animals need a strap or a machine
    DRAG_LENGTH = 1.6,            -- metres between you and the carcass you drag
    DRAG_REACH = 2.5,             -- how close you must be to grab one
    BODY_FILES = {                -- hidden bodies (our bale types; xml/bales/)
        small = "xml/bales/carcassSmall.xml",
        large = "xml/bales/carcassLarge.xml"
    },
    BODY_TYPES_FILE = "xml/bales/bales.xml",   -- registered with the game's bale list on map load
    BODY_SIZE = {              -- width, height, length in metres (the base square bales they use)
        small = { 0.45, 0.35, 1.2 },
        large = { 1.2, 0.9, 2.4 }
    },
    FILL_TYPE_PREFIX = "RSE_CARCASS_", -- one fill type per animal (RSE_CARCASS_DEER, ...), each with its own picture
    FALLBACK_FILL_TYPE = "STRAW", -- if our bale type can't load, a base straw bale of the same size

    -- recovery strap
    STRAP_REACH = 3.5,            -- how far away you can hook or attach a strap
    STRAP_MAX_LENGTH = 20,        -- longest strap between hook point and vehicle
    STRAP_MIN_LENGTH = 0.8,
    STRAP_HOOK_SLACK = 0.05,      -- metres of slack when it is attached, so that hooking up pulls nothing
    STRAP_AIM_TOLERANCE = 0.02,   -- metres off the line before the joint is turned to follow it
    STRAP_CENTRE_RANGE = 0.15,     -- a hook this close to the middle of a wreck's end already sits right for towing
    STRAP_SNAP = 1.0,             -- aim this close to a hitch and the strap goes on the hitch
    STRAP_REEL_SPEED = 0.6,       -- metres per second, reeling a strap in or out by hand
    STRAP_REEL_NEAR = 15,         -- how close to a strap you must be to reel it
    -- Really towing, the wreck's end hangs on a hinge just behind the vehicle, on its centre line, the way the game's own trailers do (Z: it swerved wide, and
    -- was hard to tow with a small pickup). A loose line lets it wander, and a sideways box of 1.5 m let it swing that far either way.
    TOW_GAP = 1.0,                -- metres from the vehicle's end to the wreck's end,
    TOW_GAP_SIDE = 0.1,           -- or half the wreck's width and this much, so that their corners can't meet however sharply you turn
    TOW_LATERAL = 0.04,           -- the play at the hinge: side to side,
    TOW_VERTICAL = 0.35,          -- up and down, for dips and crests,
    TOW_TRAVEL = 0.2,             -- and along, either way: when you slow down it runs up this far and brakes, like a trailer's surge brake
    TOW_PUSH_SPEED = 1,           -- km/h: moving toward the wreck this fast, you aren't towing: a strap doesn't push
    -- Really towing, the wreck follows as a trailer's geometry says (Z: it veered to either side as it gained speed, and more in turns; RseWreckRules.follow).
    TOW_FOLLOW_YAW = 0.3,         -- this share of the difference from the yaw that keeps its far axle from sliding goes each frame,
    TOW_FOLLOW_SIDE = 0.8,        -- and this share of the hook's speed sideways against the hinge, which would otherwise push the towing vehicle about
    TOW_FOLLOW_MIN_ARM = 1,       -- metres: a far axle closer to the hook than this says nothing about the yaw
    TOW_AXLE_SPAN = 0.5,          -- metres: wheels this close together along the vehicle are one axle group, so no wheel is at the near end
    TOW_YAW_CHECK_RATE = 0.05,    -- radians a second: the engine's yaw and the yaw the wreck's speeds show only count as disagreeing above this,
    TOW_YAW_CHECK_MS = 500,       -- and after this long in a row following stops, and the log says so
    TOW_FRAME_MS = 16.67,         -- the frame those shares (TOW_STEER_EASE, TOW_FOLLOW_YAW, TOW_FOLLOW_SIDE) are meant for: at other frame rates they scale
    -- a towed wreck rolls free on a tight strap and brakes on a slack one, so it stops when you stop instead of running into you (RseWreckRules.towBrake)
    TOW_REEL_HOLD_MS = 300,       -- while you reel, and this long after, the brakes stay off: the line decides where it goes
    TOW_SLACK_FREE = 0.05,        -- metres of slack it ignores
    TOW_SLACK_FULL = 0.4,         -- metres of slack at which it brakes fully
    TOW_CLOSING = 0.1,            -- brakes fully when the two ends come together this fast, in metres per second
    -- the strap only tidies itself up (TOW_LENGTH, TOW_LATERAL) while it is really towing: hooking up doesn't mean you are ready to tow (Z)
    TOW_START_SPEED = 5,          -- km/h: the vehicle on the strap is being driven this fast
    TOW_START_MS = 2000,          -- with the strap tight, for this long
    TOW_END_MS = 5000,            -- slower than that for this long, and it is no longer towing
    TOW_REEL_SPEED = 0.5,         -- metres per second, shortening by itself
    TOW_STEER_ANGLE = 0.6,        -- radians off to the tow vehicle at which the wreck's wheels are fully turned
    TOW_STEER_EASE = 0.15,        -- how much of the way there the wheels turn each frame
    TOW_WHEEL_SWING = 1.2,        -- radians: the most a trailer's wheels give way to a pull from the side while you reel
    TOW_HOOK_HEIGHT = 0.8,        -- metres above the ground: where the strap sits on the end of a wreck
    PROGRESS_ARRIVED = 0.1,       -- the progress bar: for getting to the scene
    PROGRESS_PREPARED = 0.2,      -- of a wreck: prepared
    PROGRESS_RIGHTED = 0.4,       -- of a wreck: righted, if it had to be
    PROGRESS_MOST = 0.98,         -- the job itself takes it to the end
    STRAP_ROPE_FILE = "xml/strapRope.xml",
    LEAD_ROPE_FILE = "xml/leadRope.xml",
    LEAD_HAND_HEIGHT = 1,         -- metres above the ground: where the lead starts in first person, when the game hides your character's hand
    LEAD_HAND_AHEAD = 0.35,
    LEAD_HAND_SIDE = 0.25,

    -- disposal points and fees
    MAP_MARKERS = false,          -- off until a probe proves a marker class (0.1.0.0's broke the in-game menu)
    POINT_RADIUS = 12,           -- a carcass lying still this close to a point is delivered
    DELIVER_REST_MS = 3000,
    -- Delivering a carcass (Z, M2 round 6): the county pays for the haul-off, and the disposal site charges its fee. Both show in
    -- the finances. A deer nets $164 ($209 - $45), a cow $620 ($808 - $188).
    HAUL_PAY_BASE = 125,          -- dollars per carcass
    HAUL_PAY_PER_KG = 1.05,       -- plus dollars per kilogram
    FEE_BASE = 25,                -- dollars per carcass
    FEE_PER_KG = 0.25,            -- plus dollars per kilogram
    -- Carcasses left behind, roadside included (Z's option A; LeftBehindRule.lua): a warning and a map marker, then the county collects
    -- them and bills the disposal fee plus this charge. A deer costs $165, a cow $451. Game balance: no real-world figures were found.
    LEFT_COLLECT_MS = 30 * 60000, -- of play, while nobody is within LEFT_PLAYER_DISTANCE
    LEFT_PLAYER_DISTANCE = 20,    -- metres (Z: 150 was far too much)
    LEFT_WARN_AFTER_MS = 60000,   -- the first warning and the map marker come this long after it was left
    LEFT_REMINDERS_MS = { 15 * 60000, 5 * 60000 }, -- then a reminder this long before the end (Z)
    COLLECTION_BASE = 100,        -- dollars per carcass
    COLLECTION_PER_KG = 0.25,     -- plus dollars per kilogram
    FEE_FACTOR_DEFAULT = 1.0,     -- scales pay, fee and charge (menu in milestone 6)
    FEE_FACTOR_MIN = 0,
    FEE_FACTOR_MAX = 5,

    -- what the county pays for a cleared road (instead of the Emergency Pack's own reward, which grows the faster you are
    -- and paid thousands for a deer in 0.2.0.1). Flat, like a call-out rate: a base amount plus an amount per animal and
    -- per kilogram. Z's mark: about $600 for a deer, scaling up. The game's economy difficulty still scales it.
    CALL_PAY_BASE = 500,          -- dollars per call
    CALL_PAY_PER_ANIMAL = 50,
    CALL_PAY_PER_KG = 0.625,      -- a deer pays $600, one cow $956, two cows $1,413
    CALL_LIGHTS_BONUS = 0.07,     -- extra pay when warning lights were on at the scene (Z: 10% was too much for pressing a button)
    LIGHTS_RANGE = 40,            -- metres from the scene
    LIGHTS_EARN_MS = 20000,       -- on this long in all at the scene, and the bonus is earned (Z: switching them on and off at once earned it)
    -- Animals only moved to the roadside pay very little (Z: it takes under a minute): a deer $125.
    CALL_PAY_ROADSIDE_BASE = 100,
    CALL_PAY_ROADSIDE_PER_ANIMAL = 25,

    -- emergencies (the Emergency Pack runs them; emergencies/*.xml)
    EP_ENV_NAME = "pdlc_emergencyPack", -- the pack's script environment
    POOL_PREFIX = "rse_",               -- one pool per emergency: rse_deer, rse_cow, ...
    SCENE_RADIUS = 30,            -- a carcass moved further than this from the scene is off the road (towed away)
    CLEAR_DISTANCE = 4.0,         -- lying still this far from every lane centre counts as on the verge
    CLEAR_FALLBACK_RADIUS = 8,    -- if no road is found around the scene: this far from where it lay
    CLEAR_REST_MS = 1500,         -- how long it must lie still to count as on the verge
    ROAD_SEARCH_RADIUS = 45,      -- lanes this close to the scene are measured
    ROAD_COARSE_STEP = 10,        -- metres between samples when looking for lanes near the scene
    ROAD_FINE_STEP = 2,           -- metres between samples along the lanes found
    LOADED_RAY = 2.5,             -- a vehicle this far below a carcass means it is loaded on it
    SCATTER_SPAN_BASE = 4,        -- animals lie anywhere along this many metres of road either way of the scene,
    SCATTER_SPAN_PER_ANIMAL = 2.5, -- plus this per animal,
    SCATTER_SPAN_MAX = 14,        -- up to this
    SCATTER_WIDTH = 3,            -- and this far to either side of the lane centre
    SCATTER_GAP = { small = 1.6, large = 3 }, -- at least this far apart, by body size
    BRIDGE_HEIGHT = 2,            -- this far above the terrain, a road or an animal is on a bridge: wrecks stay off them, and the map target can't show one
    SPOT_TRIES = 40,              -- how many random road spots a call tries before it leaves the choice to the pack
    SPOT_MIN_LANE = 20,           -- lanes shorter than this are junction pieces: no calls on them
    SPOT_MAP_MARGIN = 60,         -- roads run off the map's edge: no calls this close to it
    SPOT_PLAYER_CLEAR = 25,       -- a call can come from right next to you, but not on top of you
    SPOT_VEHICLE_CLEAR = 8,       -- nor on a vehicle
    RESUME_TIMEOUT_MS = 30000,    -- after loading, how long a saved call has to come back before it is canceled
    PIN_RANGE = 150,              -- a pin over each animal shows within this distance; further off, the pack's one marker leads
    PIN_HEIGHT = 1.2,             -- metres above the animal's body
    JOB_SIZE_DEFAULT = "normal",  -- how much work a call is: small, normal, large or random (RseSceneSpec; menu in M6)

    -- scene kit: cones and barricades, free and unlimited, each placed and picked up by hand (Kit.lua, KitRules.lua). Base-game
    -- models, referenced by path. aimHeight: the middle of the model; pickRadius: how close to that point you must aim.
    -- connectedPylons.i3d holds a cone and a tape strip built around the same point; they belong together. Z ruled out
    -- concrete, metal gates and metal signs as unrealistic.
    -- Traffic: sensing lives in the engine, and in every test so far only loose (dynamic) bodies stopped it: the traffic cone
    -- (P1), a hidden cone (P2), carcass bodies (M2). The taped cone's fixed collision did not (M2 round 4). So items with a fixed
    -- body get hidden loose cones (blockers, offsets across the item in metres, P2's trick). physics: its own collision. The taped
    -- cone has none, as a blocker would start inside it and be thrown out; its blocker in the middle is its collision.
    KIT_ITEMS = {
        { id = "cone", textKey = "rse_kit_cone", file = "$data/maps/mapUS/textures/props/trafficCone.i3d", aimHeight = 0.3, physics = true,
            icon = "icons/kit_cone.dds" },
        { id = "barricade", textKey = "rse_kit_barricade", file = "$data/maps/mapEU/textures/props/sawhorse.i3d", aimHeight = 0.5, pickRadius = 1.2,
            physics = true, blockers = { -1.2, 1.2 }, icon = "icons/kit_barricade.dds" },
        { id = "coneTape", textKey = "rse_kit_coneTape", file = "$data/maps/mapUS/textures/props/connectedPylons.i3d", aimHeight = 0.4,
            physics = false, blockers = { -3, -1.5, 0, 1.5, 3 }, icon = "icons/kit_coneTape.dds" }
    },
    KIT_BLOCKER_FILE = "$data/maps/mapUS/textures/props/trafficCone.i3d",
    KIT_SCENE_RADIUS = 60,        -- placing is only open during a call, this close to the scene (Z)
    KIT_REACH = 8,                -- how far ahead you can set one down
    KIT_PICK_REACH = 5,           -- how far away you can pick one up
    KIT_PICK_RADIUS = 0.7,        -- how close to the middle of one you must aim
    KIT_TURN_SPEED = math.pi / 1500, -- radians per millisecond while the turn key is held (120 degrees a second)
    KIT_MAX_ITEMS = 150,          -- a safety limit, far above any real scene
    KIT_REMINDER_FIRST_MS = 90 * 1000, -- the county first calls this long after the job ended, if items are still out
    KIT_REMINDER_MS = 3 * 60000,  -- and then again at this interval
    KIT_REMINDER_NEAR = 80,       -- no calls while you are this close to them

    -- wrecks (WreckRules.lua, Wrecks.lua): base-game vehicles, referenced by path. tipped: lies on its side and must be righted;
    -- driver: a person sits in it; spills: a load of bales comes with it (WRECK_LOADS); pay: dollars when everything reached a recovery point.
    -- variants: what it can be, one picked per call (Z). weight: how often, relative: the bigger, the rarer (Z). length: metres, for how it lies and how far
    -- its load stays clear. loadLimit: most bales it spilled. heavy: a pickup truck can't tow it, and the pager says so (my line: 3 t and up, or very long).
    -- Left out on purpose: the Wilson Silverstar livestock semi-trailer, 15 m long: too long to lie on a road or fit a rollback.
    WRECKS = {
        truck = { variants = {
            { file = "$data/vehicles/lizard/multiPurposeTruck/multiPurposeTruck.xml", length = 5.75, weight = 4, heavy = true },
            { file = "$data/vehicles/international/cvSeries/cvSeries.xml", length = 7.8, weight = 3, heavy = true },
            { file = "$data/vehicles/international/transtarII/transtarIIEagle.xml", length = 7.4, weight = 1, heavy = true },
            { file = "$data/vehicles/mack/anthem/anthem.xml", length = 7.15, weight = 1, heavy = true },
            { file = "$data/vehicles/volvo/vnx300/vnx300.xml", length = 7.7, weight = 1, heavy = true }
        }, pay = 3500, damage = 0.9, smoke = true },
        tractor = { variants = {
            { file = "$data/vehicles/fendt/vario300/vario300.xml", length = 4.1, weight = 3, heavy = true },
            { file = "$data/vehicles/johnDeere/series6M/series6M.xml", length = 4.2, weight = 2, heavy = true },
            { file = "$data/vehicles/masseyFerguson/series5700S/series5700S.xml", length = 4.2, weight = 3, heavy = true },
            { file = "$data/vehicles/caseIH/farmall120C/farmall120C.xml", length = 3.75, weight = 3, heavy = true },
            { file = "$data/vehicles/claas/arion400/arion400.xml", length = 4.25, weight = 2, heavy = true },
            { file = "$data/vehicles/zetor/proximaHS120/proximaHS120.xml", length = 4.2, weight = 3, heavy = true },
            { file = "$data/vehicles/deutzFahr/series6C/series6C.xml", length = 4.2, weight = 2, heavy = true },
            { file = "$data/vehicles/valtra/tSeries/tSeries.xml", length = 4.85, weight = 1, heavy = true },
            { file = "$data/vehicles/fendt/vario700/vario700.xml", length = 4.9, weight = 1, heavy = true }
        }, pay = 4500, damage = 0.7, tipped = true, driver = true, ditch = true, smoke = true },
        -- two parts as well (Z): the trailer (pay) and the bales (each one brought in pays, WRECK_LOADS); both earn bothBonus
        trailer = { variants = {
            { file = "$data/vehicles/farmtech/edk650/edk650.xml", length = 5.48, weight = 3, loadLimit = { big = 4 } }, -- Z: about 4 big bales fit
            { file = "$data/vehicles/salek/ans1900/ans1900.xml", length = 3.65, weight = 3, loadLimit = { big = 2, small = 8 } },
            { file = "$data/vehicles/rudolphSohn/tdk301RA/tdk301RA.xml", length = 7, weight = 2, heavy = true, loadLimit = { big = 6 } },
            { file = "$data/vehicles/kroeger/pwo24/pwo24.xml", length = 12, weight = 1, heavy = true }
        }, pay = 3000, damage = 0.6, tipped = true, twoParts = true, bothBonus = 0.25, spills = true },
        -- a livestock trailer on its side, with two parts to the job (Z): the trailer (pay) and the animals (dead ones as on an animal call, plus
        -- payPerSurvivor for each one caught and loaded). Doing both earns bothBonus on top. kinds: one is picked per call, and the trailer carries all of
        -- them. Left out (Z, 0.9.10.0): the Kingston Belvedere, a horse trailer: it carries nothing else, and cows in it looked wrong.
        livestock = { variants = {
            { file = "$data/vehicles/fliegl/noahTTW140/noahTTW140.xml", length = 10, weight = 1, heavy = true }
        }, pay = 3000, damage = 0.6, tipped = true, twoParts = true, payPerSurvivor = 75,
            bothBonus = 0.25, kinds = { "sheep", "pig", "cow" }, dead = { min = 1, max = 2 }, survivors = { min = 2, max = 5 } },
        -- bales blown across the road by a twister: no vehicle at all
        -- a car has hit a utility pole: two parts as well, the car (pay) and the pole and wires (polePay, wirePay each); both earn bothBonus (LineRules.lua)
        powerline = { variants = {
            { file = "$data/vehicles/lizard/pickup2017/pickup2017.xml", length = 5.5, weight = 2 },
            { file = "$data/vehicles/skoda/fabia/fabia.xml", length = 4.15, weight = 3 },
            { file = "$data/vehicles/skoda/kodiaq/kodiaq.xml", length = 4.8, weight = 2 },
            { file = "$data/vehicles/international/series200/series200.xml", length = 5.35, weight = 2 }
        }, pay = 2500, damage = 0.9, driver = true, twoParts = true, bothBonus = 0.25,
            line = true, hazards = true, smoke = true, polePay = 1200, wirePay = 100, wires = { min = 2, max = 4 } },
        storm = { noVehicle = true, pay = 1200, spills = true },
        -- a vehicle stalled on a railroad crossing, the driver out and safe: only a line moves it (Z), the train decides how long you have (LevelCrossing.lua)
        crossing = { variants = {
            { file = "$data/vehicles/skoda/fabia/fabia.xml", length = 4.15, weight = 3 },
            { file = "$data/vehicles/skoda/kodiaq/kodiaq.xml", length = 4.8, weight = 2 },
            { file = "$data/vehicles/international/series200/series200.xml", length = 5.35, weight = 2 },
            { file = "$data/vehicles/lizard/pickup2017/pickup2017.xml", length = 5.5, weight = 2 },
            { file = "$data/vehicles/lizard/multiPurposeTruck/multiPurposeTruck.xml", length = 5.75, weight = 1, heavy = true }
        }, pay = 3000, damage = 0.2, held = true, hazards = true, crossing = true },
        -- a car off the road in shallow water, the driver inside: only where it can come up the bank (RiverPlaces.lua). noDrown: or the game breaks it for good
        river = { variants = {
            { file = "$data/vehicles/skoda/fabia/fabia.xml", length = 4.15, weight = 3, noDrown = true },
            { file = "$data/vehicles/skoda/kodiaq/kodiaq.xml", length = 4.8, weight = 2, noDrown = true },
            { file = "$data/vehicles/international/series200/series200.xml", length = 5.35, weight = 2, noDrown = true },
            { file = "$data/vehicles/lizard/pickup2017/pickup2017.xml", length = 5.5, weight = 2, noDrown = true }
        }, pay = 3000, damage = 0.3, driver = true, hazards = true, water = true },
        -- a storm has dropped a tree on a car, the driver trapped inside: clear the road, get the driver out, take the car away (TreeOnCar in LogSpill.lua).
        -- logs: how many more lie across the road besides the one on the car. A chainsaw makes the job quicker, and something to do with the time
        tree = { variants = {
            { file = "$data/vehicles/skoda/fabia/fabia.xml", length = 4.15, weight = 3 },
            { file = "$data/vehicles/skoda/kodiaq/kodiaq.xml", length = 4.8, weight = 2 },
            { file = "$data/vehicles/international/series200/series200.xml", length = 5.35, weight = 2 },
            { file = "$data/vehicles/lizard/pickup2017/pickup2017.xml", length = 5.5, weight = 2 }
        }, pay = 2500, payPerLog = 200, rescueBonus = 500, damage = 0.7, driver = true, hazards = true, honks = true, treeOnCar = true,
            logs = { min = 2, max = 4 } },
        -- a flock on the road, to drive into a pen the farmer has put up nearby (Flock.lua, FlockRules.lua). The truck is the farmer's: nobody recovers it,
        -- it marks the pen
        flock = { variants = {
            { file = "$data/vehicles/lizard/pickup2017/pickup2017.xml", length = 5.5, weight = 2 },
            { file = "$data/vehicles/international/series200/series200.xml", length = 5.35, weight = 1 }
        }, pay = 1200, payPerAnimal = 150, damage = 0, scenery = true, seated = true, hazards = true, flock = { min = 10, max = 16 },
            flockKinds = { "sheep" } },
        -- a timber trailer on its side and its logs across the road: the logs are the job (Z). scenery: nobody recovers the trailer, it goes a while after
        -- the job.
        -- logs: how many (LogSpill.lua, LogRules.lua); pay: when all are in, plus payPerLog each
        logging = { variants = {
            { file = "$data/vehicles/schwarzmueller/timberTrailer/timberTrailer.xml", length = 8.8, weight = 1 },
            { file = "$data/vehicles/riedler/timberTrailer3A/timberTrailer3A.xml", length = 9.8, weight = 1 }
        }, pay = 1200, payPerLog = 300, damage = 0.6, tipped = true, scenery = true, logs = { min = 5, max = 9 } }
    },
    CROSSING_DRIVE_SPEED = 8.33,  -- metres per second, in a straight line: the fair drive to a crossing (30 km/h; roads wind)
    CROSSING_WORK_SECONDS = 120,  -- and this long to get a line on the vehicle and pull it clear
    CROSSING_LAP_MARGIN = 20,     -- never more than one lap of the train, less this
    CROSSING_SLACK = 20,          -- seconds: the call may come when the train is this much further away than the time you get
    CROSSING_MAX_DISTANCE = 2500, -- no call from a crossing further than this, nor from one the train gives too little time for
    CROSSING_MIN_SPEED = 5,       -- metres per second: a train slower than this isn't running by itself
    CROSSING_WAIT_MS = 15 * 60000, -- the call gives up waiting for its moment after this long
    CROSSING_OFFER_CHECK_MS = 5000, -- how often to look whether the call can come at all
    CROSSING_SPOT_JITTER = 1.5,   -- metres either way, along the track and across it: where the vehicle stands (Z: random)
    CROSSING_TRAIN_HALF = 2,      -- half a train's width, near enough
    CROSSING_RELEASE_M = 40,      -- metres of track: a vehicle still on the tracks is let go this far before the train, so that it can be moved
    CROSSING_HIT_M = 4,           -- and this far before, the train has got there
    CROSSING_THROW_ALONG = 9,     -- metres per second: what the hit gives it, the way the train runs,
    CROSSING_THROW_AWAY = 8,      -- away from the track,
    CROSSING_THROW_UP = 6,        -- and up (the game's own push is only a shove; Z: an anticlimax)
    CROSSING_THROW_SPIN = 3,      -- radians per second, about each axis, in a random direction
    CROSSING_PAGER_GRACE = 30,    -- seconds: the chosen crossing stays, even if answering the pager has cost this much of the time
    CROSSING_CLOCK_Y = 0.93,      -- the time left, on screen
    CROSSING_CLOCK_SIZE = 0.024,
    CROSSING_CLOCK_URGENT = 30,   -- seconds: it turns red
    LOG_SPREAD = 10,              -- logs lie this far along the road either way
    LOG_GAP = 1.5,                -- and at least this far apart
    LOG_STACK = 0.35,             -- each appears this much higher than the one before, so none is born inside another
    LOG_LENGTH = { 6, 9 },        -- metres
    LOG_END_CLEARANCE = 2.5,      -- lying beside the road, both ends of a log stay this far from every lane centre: a long one can reach across
    LOG_SAVED_NEAR = 2.5,         -- after a reload, a piece this close to where it was saved is still there
    TREE_TRUNK_LENGTH = 9,        -- a tree on a car: this long,
    TREE_BASE_AWAY = 5,           -- its foot this far from the car, on the ground, on the side away from the road,
    TREE_ROOF_CLEAR = 0.3,        -- and it comes to rest on the roof from this far above it
    TREE_LEAN_MAX = 0.6,          -- radians: the steepest it leans
    TREE_CAR_JITTER = 0.3,        -- radians: the car isn't always quite straight in its lane
    TREE_TRUNK_JITTER = 0.5,      -- nor the tree quite square to the road
    TREE_PIN_WAIT_MS = 8000,      -- how long the tree waits for the car to settle, if that goes wrong
    TREE_FOOT_STEP = 1.2,         -- metres: its foot no further below or above the road than this (Z: on a bridge, it stood in the creek below and missed)
    TREE_ON_CAR_HEIGHT = 0.6,     -- metres above the car's foot: a log's axis this high up can't be lying on the ground
    TREE_ON_CAR_MARGIN = 0.1,     -- and this far around its outline it still counts as on the car
    TREE_ON_CAR_STEP = 0.2,       -- metres: how finely a log is looked at along its length
    TREE_DOOR_CHECK_MS = 300,     -- how often the job looks whether the log is off the car
    TREE_RESCUE_MS = 360000,      -- the driver out within this long of your arriving earns a bonus
    TREE_HORN_FILE = "$data/sounds/vehicles/horn/honkCar.ogg", -- the driver leans on the horn
    TREE_HORN_MS = { 12000, 25000 }, -- this often,
    TREE_HORN_RANGE = 250,        -- and you can hear it this far
    LOG_TINY_MASS = 0.02,         -- tons: a piece this small doesn't have to be moved
    PAGER_SOUND_FILE = "sounds/pager.ogg", -- the pager's beeps when a call comes in (tools/pager_sounds.py; Z chose them)
    PAGER_SOUND_VOLUME = 1,       -- on top of the game's interface volume
    PAGER_RING_WAIT_MS = 5000,    -- the pager beeps once the pack shows our call, if it does so within this long of asking
    CLEANUP_WAIT_MS = 60000,      -- however a job ends, what is left at the scene stays at least this long (game/Cleanup.lua),
    CLEANUP_DISTANCE = 80,        -- until nobody is this close to the scene,
    CLEANUP_MAX_MS = 300000,      -- or this long has gone by anyway
    WATER_SCAN_TRIES = 2500,      -- a car in the water: as a map loads, this many road spots are looked at,
    WATER_SCAN_PER_FRAME = 5,     -- this many a frame, so that it doesn't show,
    WATER_AWAY = { 8, 12, 16, 20, 24, 28, 32, 36, 40 }, -- this far from the lane,
    WATER_DEPTH = { 0.4, 1.2 },   -- for water this deep: enough to look like it, not enough to hide a car
    WATER_RAY_START = 25,         -- metres above the ground the look for water starts
    WATER_PLACE_GAP = 20,         -- places closer together than this count as one
    -- the ground (GroundRules.lua): each map numbers its ground layers for footstep and wheel sounds, the same in all three base maps (their sounds.xml):
    GROUND_MATERIALS = { [0] = "soil", [1] = "dirt", [2] = "grass", [3] = "sand", [5] = "leaves", [6] = "gravel", [7] = "hard" }, -- 7: rock, asphalt, concrete
    GROUND_PEN_DIRT = 2,          -- a pen stands on grass, with at most this many bare patches among the points looked at
    GROUND_COUNTRY_BUILT = 0.15,  -- open country: at most this share of the ground round a place is gravel, asphalt, concrete or built on,
    GROUND_COUNTRY_SOFT = 0.7,    -- and at least this share is grass, field, dirt or the like
    GROUND_ROAD_SKIP = 8,         -- metres: hard ground this close to a lane is the road itself, and doesn't count against a place
    GROUND_RAY_START = 2,         -- metres above the ground: a ray from here straight down finds anything built lying there (rails, a slab),
    GROUND_RAY_BELOW = 0.3,       -- down to this far under the ground's surface
    WATER_YAW_JITTER = 0.6,       -- radians: a car doesn't always go in straight
    WATER_BANK_STEP = 2,          -- metres: the way from the water to the road, looked at in steps of this
    WATER_BANK_RISE = 0.7,        -- the most a step may rise or fall where the car comes out (about 19 degrees; Z's car stuck on a much steeper bank)
    WATER_ROAD_RISE = 1.1,        -- and on the rest of the way to the road (about 29 degrees)
    WATER_BANK_DRY = 0.4,         -- metres above the water: dry enough to stand on
    WATER_BANK_REACH = 14,        -- dry land this close to the car, so that a 20 m strap reaches from it
    WATER_BANK_ROOM = 6,          -- and this much gentle ground beyond that, for the vehicle that pulls
    WATER_BANK_RAY = 1,           -- metres above the ground: what would be in the car's way
    -- driving a flock (FlockRules.lua). Z: it must not be a pain
    FLOCK_PUSH_VEHICLE = 24,      -- metres: each one feels a vehicle from this far (Z: a little further than 20),
    FLOCK_PUSH_FOOT = 17,         -- a person from this far,
    FLOCK_PUSH_FULL = 7,          -- and is going as fast as it will from this close
    FLOCK_WALK = 1.0,             -- metres per second, lightly pressed: the job is a walk, and that is what the legs do well (Z: a little faster than 0.8)
    FLOCK_TROT = 2.2,             -- hard pressed
    FLOCK_RUN = 2.9,              -- frightened, or you are right on it: past about 3.5 the legs reach as far as they can and it shows (Z's picture)
    FLOCK_ACCEL = 2.5,            -- how fast it picks up speed,
    FLOCK_DECEL = 1.2,            -- and how slowly it loses it, so a flock flows instead of stopping dead
    FLOCK_TURN = 2.5,             -- radians per second: a quick spin leaves the feet behind
    FLOCK_TURN_SLOW = 0.35,       -- turning right round it slows to this share of its speed
    FLOCK_STEER_MS = 300,         -- how long a change of mind takes to come through: no twitching, and no lag going round them (Z)
    FLOCK_MIN_SPEED = 0.15,       -- slower than this it is just standing
    FLOCK_SEE = 28,               -- metres: it keeps to those it can see this close, and doesn't know of any further off,
    FLOCK_SENSE = 8,              -- it knows what those this close are doing,
    FLOCK_FOLLOW = 0.85,          -- moves with them when they move, at this share of their speed,
    FLOCK_FOLLOW_MIN = 0.5,       -- unless that is slower than this,
    FLOCK_CLOSE_UP = 0.7,         -- and, pressed, closes up on them this much, against moving away from you (Z: hard to bunch them for the gate at 0.4),
    FLOCK_ALIGN = 0.5,            -- and takes on their heading this much, so they go like a stream and don't fan out
    FLOCK_GROUP_AWAY = 1,         -- pressed, it goes away from you through the middle of those it sees this much, against its own way: a bunch turns
                                  -- together as you go round it (Z: answer the angle you take)
    FLOCK_AWARE = 12,             -- metres past where it feels you, it still minds where you are:
    FLOCK_AWARE_TURN = 0.8,       -- on the move, it bends away from you this much there,
    FLOCK_CARRY_MS = 3000,        -- and one you have just pushed walks on for this long, slowing, so swinging out wide round them doesn't stop them dead
    FLOCK_GROUP_LINK = 12,        -- those this close to each other are one bunch
    FLOCK_TIGHT = 5,              -- metres from the middle of the flock: further than this it starts to close up,
    FLOCK_STRAY = 14,             -- further than this it is a stray, and goes straight back to the others,
    FLOCK_REJOIN = 2.4,           -- at this speed,
    FLOCK_CALM_MARGIN = 10,       -- but not back toward you, this far outside where it feels you
    FLOCK_COHESION = 1.2,
    FLOCK_SPACING = 1.4,          -- they keep this far apart
    FLOCK_SEPARATE = 1.2,
    FLOCK_PERSONAL = 4,           -- this close to you it hurries
    FLOCK_SPOOK_SPEED = 6,        -- metres per second (about 22 km/h): a vehicle faster than this
    FLOCK_SPOOK_RADIUS = 14,      -- this close frightens them: they scatter,
    FLOCK_SPOOK_MS = 4000,        -- for this long after it,
    FLOCK_SPOOK_SPREAD = 1.2,     -- each up to this many radians off straight away from it
    FLOCK_WOBBLE = 0.3,           -- radians: how far off the line each one wanders,
    FLOCK_WOBBLE_MS = 3000,       -- changing its mind about this often,
    FLOCK_WOBBLE_EASE_MS = 800,   -- and not all at once
    FLOCK_BREAK_PRESSURE = 0.75,  -- one pressed this hard (about 10 m from a vehicle)
    FLOCK_BREAK_CHANCE = 0.025,    -- breaks away this often, per second,
    FLOCK_BREAK_ANGLE = { 0.6, 1.2 }, -- this many radians off straight away from you,
    FLOCK_BREAK_MS = 2500,        -- for this long
    FLOCK_SPEED_SANE = 40,        -- metres per second: faster than this is a jump, not driving
    FLOCK_HORN_RADIUS = 30,       -- your horn reaches this far,
    FLOCK_HORN_PRESSURE = 0.6,    -- and presses on them this hard,
    FLOCK_HORN_MS = 2500,         -- for this long: a nudge, not a way to drive them (Z just kept honking and they went in a line),
    FLOCK_HORN_REST_MS = 12000,   -- and pushes again only this long after the last honk that pushed; honks between don't count against you,
    FLOCK_HORN_TOO_MANY = 6,      -- but this many honks
    FLOCK_HORN_SCARE_MS = 8000,   -- within this long scatters them: leaning on the horn, not honking now and then (Z: more than 3 before they scatter)
    FLOCK_HORN_HUDDLE_RADIUS = 40, -- a honk heard this far off, further than it pushes, so the whole bunch hears it,
    FLOCK_HORN_STEP_GAP_MS = 3000, -- a honk at least this long after the last that did
    FLOCK_HORN_STEP_SHARE = 0.45, -- moves each one this share of the way in toward the middle of those it can see at that moment (Z: one step together
                                  -- per honk, not a hold; then a little more than 0.3),
    FLOCK_HORN_STEP_MAX = 3,      -- metres at most,
    FLOCK_HORN_STEP_MS = 5000,    -- and it gives up on a step it hasn't made in this long,
    FLOCK_HORN_TIGHT = 2,         -- counting only what is further than this from that middle,
    FLOCK_HORN_GATHER = 0.8,      -- at this speed, along to where that middle is now,
    FLOCK_HORN_RAMP = 0.5,        -- slowing within this of being close enough,
    FLOCK_HORN_STEADY = 0.6,      -- and wandering off the line this much less while it steps
    FLOCK_HORN_CALL_RADIUS = 70,  -- metres: and each one this close to you that isn't with the biggest bunch heads for it (Z: the bigger picture, all of the
                                  -- flock, not five bunches),
    FLOCK_HORN_JOINED = 7,        -- until it is this close to its middle,
    FLOCK_HORN_JOIN_MS = 40000,   -- or has tried this long
    FLOCK_HALF = 0.5,             -- you hear when this share is in
    FLOCK_GATE_DRAW = 6,          -- metres from the gate, with others already in, it wants to join them:
    FLOCK_DRAW_WEIGHT = 0.25,     -- this much when pressed,
    FLOCK_JOIN_SPEED = 1,         -- at this speed when not
    FLOCK_LEASH = 230,            -- metres from the pen: past this it starts to turn back however you press,
    FLOCK_LEASH_SOFT = 40,        -- and has turned right back this much further on
    FLOCK_SLIDE = 1.2,            -- radians: something in the way, it turns this far and goes along it,
    FLOCK_SLIDE_GROW = 0.8,       -- this much further each second it stays blocked,
    FLOCK_SLIDE_MOST = 1.6,       -- this far at most: sideways, never back toward you,
    FLOCK_FEELER = 1,             -- radians: how far to each side it looks, to see which way is open,
    FLOCK_SLIDE_HOLD_MS = 700,    -- past it, it keeps going that way this long,
    FLOCK_CORNER_MS = 1500,       -- still blocked after this long, it is in a corner: it keeps turning, back past you if it must
                                  -- (Z: stuck on fences and corners),
    FLOCK_CORNER_MOST = 3.0,      -- radians, this far round at most,
    FLOCK_CORNER_HOLD_MS = 2500,  -- and once out, keeps going that way this long
    FLOCK_SLIDE_KEEP_MS = 3000,   -- the flock keeps to that side this long after the last one met anything,
    FLOCK_SLIDE_SWAP_MS = 25000,  -- and tries the other side after this long
    FLOCK_ALONG_SHARE = 0.7,      -- along a hurdle or the truck it keeps this share of the speed it would otherwise lose,
    FLOCK_ALONG_SURE = 0.25,      -- if it was at least this share of its way going along it anyway; closer to straight at it, it stands and presses,
                                  -- but crowded there (you within FLOCK_PUSH_FULL) it is pinned, and gets out along it:
    FLOCK_PIN_LEAN = 0.05,        -- it goes along to the side it leant toward by at least this share of its way, or else
    FLOCK_PIN_OFFSET = 1,         -- metres: away from you, when you are within FLOCK_PUSH_FULL and this far off to one side, or else the flock's way round,
    FLOCK_PIN_KEEP_MS = 2000,     -- and keeps to that side this long after it was last pinned (Z: two pinned against the pen by the buggy stood still)
    FLOCK_IDLE_MS = 9000,         -- left alone, it takes a few steps about this often,
    FLOCK_IDLE_WALK_MS = 2500,    -- for this long
    FLOCK_STUCK_MS = 15000,       -- trying and getting nowhere for this long, it joins the others again,
    FLOCK_UNSEEN = 30,            -- if you are at least this far from it
    FLOCK_CHECK_MS = 200,         -- how often it looks ahead: it moves faster than the crash's animals, and answers at once
    FLOCK_BLOCKER_ROAD = 6,       -- metres from a lane: further off it has no hidden cone, and needs none
    FLOCK_ROAD_LOOKS = 5,         -- it works that out at every this many looks ahead
    FLOCK_GROUP_APART = 55,       -- where they start: in bunches this far apart along the road, out of sight of each other, to round up first,
    FLOCK_GROUP_THREE = 9,        -- three bunches with this many sheep, two with fewer,
    FLOCK_SPAN = 6,               -- each this far along the road either way,
    FLOCK_WIDTH = 3,              -- this far across it,
    FLOCK_GAP = 1.2,              -- and this far apart
    FLOCK_LAMB_CHANCE = 0.2,      -- some of them are lambs, for the look of it
    FLOCK_LAMB_SCALE = 0.62,
    FLOCK_PEN_RADIUS = 9,         -- the pen: this big,
    FLOCK_GATE_HALF = 0.33,       -- radians either side of the middle of its gate: about 5.8 m wide, less than a flock's width, so few go in at one pass
    FLOCK_GATE_TURN = { 0.5, 1.2 }, -- radians: how far off the way to the flock it looks
    FLOCK_HURDLE_LENGTH = 1.8,    -- metres: a hurdle is this long (measured in the game on 0.9.5.6), until the first pen measures one (Flock.lua),
    FLOCK_HURDLE_SHARE = 0.9,     -- and they stand this share of that apart, so they overlap a little and the ring has no gaps (Z)
    FLOCK_HURDLE_MEASURE_MS = 1000, -- the first hurdle is measured this long after the pen goes up,
    FLOCK_HURDLE_REACH = 2.5,     -- looking for its ends up to this far from its middle,
    FLOCK_HURDLE_STEP = 0.05,     -- in steps of this,
    FLOCK_HURDLE_REDO = 0.15,     -- and if it is this much longer or shorter than was thought, the pen goes up again with the right spacing
    FLOCK_IN_MARGIN = 0.8,        -- this far inside the ring counts as in
    FLOCK_PEN_AVOID = 2,          -- closer than this to the ring from outside, it goes along it
    FLOCK_RING_EDGE = 0.4,        -- and it can't come closer than this
    FLOCK_OBSTACLE_AVOID = 1.5,   -- the same for the farmer's truck
    FLOCK_TRUCK_MARGIN = 1,       -- which counts as a circle: half its length and this much
    FLOCK_HURDLE = "barricade",   -- the kit item the hurdles are
    FLOCK_TRUCK_AWAY = 12,        -- the farmer's truck: this far outside the ring, so a flock going round the pen has room to pass inside it,
    FLOCK_TRUCK_ANGLE = 0.9,      -- and this far round from the gate
    FLOCK_TRUCK_ROAD = 5,         -- and this far from any lane
    FLOCK_GATE_ROOM = 10,         -- metres clear in front of the gate, to line a flock up
    FLOCK_TREE_GAP = 5,           -- no tree inside the pen or this close to its fence, all the way round, nor in front of the gate this far either side of
                                  -- the opening, out to FLOCK_GATE_ROOM past it (Z: a small tree in the pen, the woods against it, trees by the opening)
    FLOCK_TREE_RISE = 6,          -- looking for trees this far above or below the pen too
    FLOCK_PEN_DISTANCES = { 130, 110, 150, 90, 70, 55 }, -- metres from the flock to try for a pen, best first: the walk there is the job (Z: longer),
    FLOCK_PEN_ANGLES = 16,        -- this many ways round at each
    FLOCK_PEN_ROAD = 3,           -- clear of every lane by this much
    FLOCK_PEN_RISE = 1.5,         -- metres: the most the ground may differ across the pen
    FLOCK_PATH_STEP = 3,          -- the way there, looked at in steps of this,
    FLOCK_PATH_RISE = 1.0,        -- the most a step may rise or fall,
    FLOCK_PATH_WIDTH = 3,         -- and this wide either side
    FLOCK_RAY_HEIGHT = 0.8,       -- metres above the ground: what would be in their way
    FLOCK_WET_DEPTH = 0.1,        -- water deeper than this is no place for sheep
    FLOCK_ROAD_RADIUS = 220,      -- lanes this close are measured, as far as a pen can be
    FLOCK_SCAN_TRIES = 2000,      -- where a flock call can come from (FlockPlaces.lua): as a map loads, this many road spots are looked at,
    FLOCK_SCAN_PER_FRAME = 8,     -- this many a frame at a glance, and at most one a frame all the way (rays),
    FLOCK_SCAN_PENS_PER_FRAME = 6, -- and of its pens, this many a frame: near a town, each one measures against a lot of road
    FLOCK_PLACES_MAX = 40,        -- until this many places are found,
    FLOCK_PLACE_GAP = 250,        -- this far apart
    FLOCK_COUNTRY_AWAY = { 10, 18, 26 }, -- metres either side of the road at each bunch: the ground there has to be open country (no town, yard or station),
    FLOCK_RAIL_CLEAR = 80,        -- and the railroad at least this far from every bunch and from the pen (Z: a pen on the tracks),
    FLOCK_RAIL_STEP = 10,         -- read in pieces this long
    FLOCK_PEN_AROUND = { 25, 40 }, -- round the pen, the ground this far out has to be open country too,
    FLOCK_PEN_AROUND_WAYS = 12,   -- looked at this many ways round,
    FLOCK_PEN_WOODS = 30,         -- and out to this far, no more than
    FLOCK_PEN_TREES = 3,          -- this many of those ways meet a tree: a meadow by a tree line, not a clearing in the woods
    FLOCK_VEHICLE_CLEAR = 30,     -- a call doesn't come from a place with a vehicle this close to the flock or the pen
    FLOCK_START_RAYS = 8,         -- where a bunch would stand, it looks this many ways round,
    FLOCK_START_REACH = 12,       -- this far,
    FLOCK_START_BLOCKED = 3,      -- and more than this many meeting a fence, a wall or a building is a hemmed-in place (Z: a fenced corridor behind the shop)
    FLOCK_MARKER_MS = 1000,       -- how often the flock's map marker moves
    FLOCK_BLEATS = { "$data/sounds/animals/sheep/anmlSheepYell_01.ogg", "$data/sounds/animals/sheep/anmlSheepYell_02.ogg",
        "$data/sounds/animals/sheep/anmlSheepYell_03.ogg", "$data/sounds/animals/sheep/anmlSheepYell_04.ogg" },
    FLOCK_BLEAT_MS = { 3000, 9000 }, -- how often one of them calls; more often when pressed
    FLOCK_BLEAT_RANGE = 120,
    FLOCK_BLEAT_VOLUME = 0.8,
    SOUND_INNER = 0.25,           -- a sound is full strength within this share of its range
    SURVIVOR_REACH = 3,           -- how close you must be to catch a loose animal
    POINT_MARKER_RANGE = 40,      -- drop-off points show on the map while you are this close to an animal you have loaded, strapped or in hand
    MARKER_SCALE = 0.5,           -- our map markers against the game's size (Z: they hid where things are)
    JOB_PENALTY_SHARE = 0.1,      -- a job you said yes to that ends with no pay costs this part of that pay (Z: small; the number is mine)
    PAGER_CHECK_MS = 700,         -- this long after asking for a call, we look whether the pager's text has our fields in it
    PAGER_PAY_STEP = 50,          -- the pager's "about" pay, to the nearest this many (the job's own figures may move a little)
    PAGER_NEAR = 150,             -- metres: closer than this, the pager says the call is close by
    PLAN_MAX_MS = 180000,         -- a call's plan is only used this long after it was made (CallPlan.lua)
    PACK_NOTICE_DELAY_MS = 2000,  -- without the Emergency Pack, the dialog comes this long after you are in the world
    PANEL_IDLE_MS = 120000,       -- the settings panel closes by itself after this long without input
    GUIDE_INTRO_DELAY_MS = 4000,  -- the guide opens by itself this long after you are in a new savegame, once you are on foot
    SURVIVOR_LOAD_RANGE = 8,      -- how close to your livestock trailer you must walk it to load it
    CRASH_HANDOVER_MS = 10 * 60 * 1000,      -- one part done: another contractor takes the other after this long without progress
    CRASH_HANDOVER_WARN_MS = 2 * 60 * 1000,
    HERD_WANDER_SPEED = 0.4,      -- metres per second: pretty slowly (Z)
    HERD_ACCEL = 1.2,             -- metres per second per second: it eases into a walk and out of it
    HERD_LEAD_ACCEL = 4,          -- quicker on a lead, to keep up with you
    HERD_GAIT_FULL = 0.2,         -- the legs are fully walking from this speed
    HERD_WALK_MS = { 5000, 12000 },
    HERD_PAUSE_MS = { 5000, 14000 },
    HERD_SPREAD = 1,              -- radians either side of straight away from the scene
    HERD_LEASH = 120,             -- turns back this far from the scene
    HERD_TURN_SPEED = 1,          -- radians per second
    HERD_SPOOK_RADIUS = 5,        -- shies away when you come this close; it doesn't mind someone standing still
    HERD_STILL_MS = 800,          -- you count as standing still after this long without moving
    HERD_SPOOK_SPEED = 1.1,       -- slower than a person walks, so you can always catch it
    HERD_LEAD_LENGTH = 2.5,
    HERD_LEAD_TURN = 3,
    HERD_LEAD_CATCH_UP = 1.5,
    HERD_LEAD_SPEED_MAX = 7,
    HERD_LEAD_BREAK = 25,         -- it gets away if you are further ahead than this
    HERD_LOOK_AHEAD = 1.5,
    HERD_MAX_RISE = 1,            -- metres over HERD_LOOK_AHEAD: too steep to walk
    HERD_BLOCKER_STEP = 1.5,      -- the hidden cone that stops traffic for it follows once it has walked this far
    HERD_MAX_STEP = 0.6,          -- metres: the ground under it can't jump up by more than this (a fence rail isn't the ground)
    HERD_DECK = 1,                -- metres: ground this far above the terrain is a deck (a bridge): it keeps to the deck's height, not the terrain's far below,
                                  -- and a drop at its edge stops it like a wall (Z, 0.9.10.2: sheep driven onto a bridge fell through the road). Back on the
                                  -- terrain's height once the ground is within half of this of it
    HERD_EDGE_SLOPE = 1.4,        -- a step that takes it down more than this per metre is over an edge, and isn't taken: pressed against a drop, it crept
                                  -- over (twice the slope the look-ahead lets it walk, so a bumpy hillside is still a hillside)
    HERD_EDGE_JUMP = 3,           -- metres in one frame: more than this is a straggler put back with the flock, not a step
    HERD_SMOOTH_MS = 300,         -- how quickly it settles to the ground, a slope or a stop
    HERD_MODEL_YAW = 0,           -- added to the heading if a model faces another way
    -- the walk on a model's bones (GaitRules.lua)
    GAIT_DUTY = 0.62,             -- the share of a cycle each foot spends on the ground
    GAIT_CYCLES_BASE = 0.55,      -- cycles per second standing still
    GAIT_CYCLES_PER_SPEED = 0.9,  -- and more per metre per second
    GAIT_CYCLES_MIN = 0.5,
    GAIT_CYCLES_MAX = 3.0,        -- at a run, quick short steps; at 2.2 a running sheep's front leg had to reach further than a shoulder can (the log)
    GAIT_REFERENCE_LEG = 0.8,     -- a leg this long takes those cycles; a longer one steps more slowly
    GAIT_STRIDE_MAX = 0.6,        -- half a foot's reach, at most, against the leg's length
    GAIT_LIFT_PER_STRIDE = 0.6,   -- how high a foot lifts against that reach
    GAIT_LIFT_MAX = 0.14,         -- at most, against the leg's length
    GAIT_CANNON_LEAN = 0.8,       -- how much the lower leg leans with the foot's place under the body
    GAIT_CANNON_FOLD = { front = 0.9, hind = 0.55 },  -- radians: the lower leg trailing at the top of a step
    GAIT_HOOF_FOLD = 0.6,         -- radians: the hoof trailing at the top of a step
    GAIT_NOD = 0.03,              -- the head nods with the steps
    GAIT_GRAZE = 1.35,            -- radians down over the whole neck, to graze
    GAIT_GRAZE_TILT = 0.1,        -- radians: the body leans forward a little as well
    GAIT_GRAZE_CHEW = 0.035,      -- radians: the head moving while it eats
    GAIT_GRAZE_CHANCE = 0.75,     -- how often it grazes when it stops
    GAIT_GRAZE_MS = 1200,
    GAIT_TAIL = 0.12,             -- radians side to side, over the whole tail, swinging with the hips,
    GAIT_TAIL_IDLE = 0.3,         -- and this share of that, slowly, standing
    GAIT_TAIL_JOINTS = 3,         -- tail bones turned, from the root
    GAIT_FOLD_FULL = 0.3,         -- a step reaching this share of the leg's length folds the lower leg fully; a shorter one less (a shuffle doesn't high-step)
    GAIT_JOINT_LIMITS = { { -0.8, 0.9 }, { -1.4, 1.4 }, { -1.0, 1.8 }, { -1.0, 1.0 } }, -- radians from rest, hip or shoulder down to the hoof:
                                  -- what a leg can do, whatever the numbers say (Z's pictures: a leg flung out)
    GAIT_JOINT_RATE = 60,         -- radians per second: a joint turns no faster than this, so nothing flicks for a frame; the walk itself needs up to
                                  -- about 46 at a run (the real legs, with GAIT_SOFT_REACH); at 25 it held back ordinary steps
    GAIT_SOFT_REACH = 0.92,       -- a leg eases off reaching from this share of its full reach on, so a nearly straight knee or elbow doesn't snap
    GAIT_SPINE = 0.025,           -- radians, the spine bending side to side with the steps
    GAIT_ROLL = 0.02,             -- radians, hips and shoulders rolling against each other
    GAIT_LOOK = 0.25,             -- radians, looking around while it stands
    GAIT_BREATH = 0.006,          -- radians, the back rising and falling while it stands
    GAIT_BOB = 0.012,             -- metres, the body rising with each step
    GAIT_CROUCH = 0.02,           -- the body lower while walking, against the leg's length: the legs bend and have room to reach
    GAIT_SWAY = 0.012,            -- radians, the body rolling with each step
    GAIT_RANGE = 150,             -- metres: past this nobody can see the legs
    -- a model without usable bones rocks a little with each step instead
    HERD_STEP_RATE = 0.015,       -- radians per millisecond at 1 metre per second
    HERD_STEP_MIN = 0.005,
    HERD_STEP_MAX = 0.014,
    HERD_STEP_BOB = 0.03,         -- metres up and down
    HERD_STEP_ROCK = 0.025,       -- radians, nose up and down
    HERD_STEP_SWAY = 0.02,        -- radians, side to side
    STORM_ROAD_RANGE = 200,       -- storm calls come from a road this close to where the twister ended
    -- a downed power line (LineRules.lua, PowerLine.lua)
    LINE_POWER_CUT_MS = 90000,    -- after you arrive, the utility crew has cut the power this much later, if no crew truck can come
    LINE_CREW_BACKSTOP_MS = 180000, -- with a crew truck on its way: the power goes off by then anyway, if it is held up somewhere
    -- the utility crew's truck (CrewRules.lua, UtilityCrew.lua): it comes along the road from out of sight, parks short of the scene and cuts the power
    CREW_VEHICLE = "$data/vehicles/lizard/pickup2017/pickup2017.xml", -- a base-game pickup, hazards on: none of the base pickups has beacons
    CREW_ROUTE_MAX = 700,         -- metres of road looked at back from the scene
    CREW_LANE_REACH = 15,         -- metres: the lane it drives to is the nearest one within this of the scene
    CREW_ROUTE_STEP = 5,          -- metres between route points
    CREW_SPAWN_MIN = 250,         -- it appears at least this far along the road from the scene,
    CREW_SPAWN_CLEAR = 150,       -- this far from you,
    CREW_UNSEEN_DISTANCE = 450,   -- and where you can't see it: further than this, or outside
    CREW_VIEW_HALF_ANGLE = 1.2,   -- radians either side of where you look (about 70 degrees)
    CREW_SPAWN_SHORTEST = 80,     -- a road shorter than this to come along: no truck, the timer cuts the power
    CREW_STOP_BEFORE = 25,        -- metres short of the scene it parks,
    CREW_SHOULDER = 2.2,          -- this far over to the side of its lane, away from the other lanes,
    CREW_SHOULDER_ALONG = 35,     -- easing over during the last this many metres
    CREW_STOP_REACH = 3,          -- close enough to the end of the route counts as there
    CREW_LOOK_AHEAD = 9,          -- metres: the point it steers at
    CREW_SPEED = 50,              -- km/h on the way
    CREW_SLOW_DISTANCE = 60,      -- slower for the last this many metres,
    CREW_SLOW_SPEED = 25,
    CREW_CREEP_DISTANCE = 15,     -- and creeping for the last few
    CREW_CREEP_SPEED = 8,
    CREW_ETA_SPEED = 11,          -- metres per second on average, for the panel's clock
    CREW_MOVING_SPEED = 2,        -- km/h: slower than this it isn't going anywhere
    CREW_HELD_MS = 5000,          -- held up this long once under way: it parks where it is (a queue of traffic at the scene)
    CREW_START_MS = 25000,        -- never moving off in this long: something is wrong, and the timer cuts the power
    CREW_AHEAD = 11,              -- metres: something this close in front stops it (traffic, you, cones, the wreck)
    CREW_AHEAD_CHECK_MS = 100,
    CREW_WORK_MS = 30000,         -- parked, the crew needs this long to cut the power
    CREW_LEAVE_DISTANCE = 120,    -- after the job, the truck goes once you are this far away,
    CREW_LEAVE_MAX_MS = 300000,   -- or after this long anyway
    CREW_DRIVER_SHOW_MS = 1500,   -- the driver shows once the character has loaded (as a wreck's, P9b)
    LINE_DANGER_RADIUS = 20,      -- metres from the scene: too close to live wires
    LINE_DANGER_GRACE_MS = 8000,  -- this long in there in all, after the warning, and it costs you
    LINE_DANGER_CUT = 0.1,        -- of the pay
    LINE_STANDING_SIDE = 8,       -- metres to the side of the lane: the poles still standing
    LINE_STANDING_ALONG = { -26, 26 }, -- metres along the road from the scene, either way
    -- where the poles may go (Z: one stood inside a building in a town street). Each layout tried in turn, either side of the road; a spot where none fits
    -- isn't used, and the call comes from another road (PowerLine.lua, pickSpot)
    LINE_STANDING_SIDES = { 8, 6.5, 5.5, 10.5 }, -- metres from the lane (5.5: a narrow verge between the road and a field)
    LINE_STANDING_ALONGS = { 26, 22, 30 },  -- metres along the road, either way
    LINE_STANDING_ROAD_CLEAR = 4.5, -- a standing pole stays at least this far from every lane centre
    LINE_STANDING_ROOM = 1.2,     -- and has this much room round it: no wall, fence post or sign right against it
    LINE_ROOF_RAY = 40,           -- metres: a ray from this high straight down finds a roof (or anything built) over a spot
    LINE_SPOT_TRIES = 8,          -- road spots tried for one call
    LINE_POLE_ALONG = 9,          -- the fallen pole, this far along the road from the car
    LINE_POLE_FOOT_SIDE = 6,      -- its foot at the roadside
    LINE_POLE_SKEW = 0.25,        -- it doesn't lie quite square across the road
    LINE_POLE_LENGTH = 9,
    LINE_POLE_DROP = 0.6,         -- metres above the ground when it appears: it falls the rest of the way
    LINE_POLE_TOP = 8,            -- metres up a standing pole, where the wires hang from
    LINE_POLE_FILE = "$data/maps/mapUS/textures/props/utilityPoles.i3d", -- the base game's US poles, by path
    LINE_POLE_PIECE = "utilityPole04",
    LINE_POLE_TREES = { "TRANSPORT", "LODGEPOLEPINE", "PINE" }, -- the fallen pole is a real log of the first of these the map has
    LINE_WIRE_FILE = "xml/wireRope.xml",
    LINE_WIRE_GROUND = 0.05,      -- metres above the ground, where a wire ends
    LINE_WIRE_REACH = 4,          -- how close you must be to a wire, anywhere along it, to roll it up
    LINE_WARN_MS = 15000,         -- the "not yet" message comes at most this often (P12: one message per situation),
    LINE_QUIET_MS = 8000,         -- and not within this long of any other live-wire message
    LINE_WIRE_ROLL_MS = 6000,     -- how long that takes
    LINE_COIL_RINGS = 3,          -- what it winds up into: this many loops lying flat, one on top of the other
    LINE_COIL_POINTS = 10,        -- each made of this many short pieces of wire
    LINE_COIL_RADIUS = 0.35,      -- metres, the first loop
    LINE_COIL_STEP = 0.02,        -- each loop this much smaller
    LINE_COIL_RISE = 0.025,       -- and this much higher
    LINE_WIRE_SPOTS = { { -7, -1 }, { 5, 1.5 }, { -12, 2 }, { 13, -2 } }, -- where wires end, along the road and across it from the scene
    LINE_SEARCH_RADIUS = 6,       -- a saved job: how far from where a piece of the pole lay to look for it
    LINE_SEARCH_MS = 1500,        -- and how often
    LINE_SEARCH_TRIES = 4,
    LINE_TREE_MATCH = 1,          -- the game's record of the tree a pole came from stands this close to where the pole was asked for
    LINE_LOST_MS = 400,           -- a piece gone with no cut message: wait this long, then look around where it lay
    LINE_OWN_RADIUS = 40,         -- a loose log of the pole's kind this close to the scene counts as the pole, for the chainsaw
    -- the game moves its twister 150 m an hour, too slow to see (Z). It travels instead, its damage with it (Z), but stays near where it appeared, so that
    -- however long it lasts, it wrecks one area and not the whole map (TwisterTravel.lua)
    TWISTER_WANDER_SPEED = 2,     -- metres per second, about a walking pace
    TWISTER_WANDER_RADIUS = 80,   -- metres from where it appeared before it turns back
    TWISTER_TURN_MAX = 0.12,      -- radians per second: its long curves
    TWISTER_TURN_DRIFT = 0.3,     -- how quickly a curve changes
    TWISTER_TURN_BACK = 0.2,      -- radians per second, turning back
    WRECK_HEIGHT = 0.5,           -- spawned this far above the ground, to settle on its wheels
    WRECK_TIPPED_HEIGHT = 1.2,    -- on its side
    WRECK_LONG = 6.5,             -- longer than this, it lies across the road at an angle, or its ends would be in the ditches
    WRECK_SMOKE_FILE = "$data/effects/smoke/smokeParticles.i3d", -- the game's own smoke, by path
    WRECK_SMOKE_HEIGHT = 0.55,    -- of the vehicle's height, above its origin: about the top of its hood
    WRECK_SMOKE_BACK = 0.9,       -- metres back from its front end: over the engine
    WRECK_PIN_MS = 2500,          -- pinned once it has settled (P3b)
    WRECK_HELD_PIN_MS = 1000,     -- a vehicle stalled on the tracks sooner: traffic on the crossing shoved one off before its pin (Z)
    WRECK_DRIFT_MAX = 1.5,        -- metres: moved further than this before its pin (shoved, rolled), it is put back where it was placed
    WRECK_PULL_MOVED = 0.3,       -- one on its side lets go once the vehicle on its strap has moved this far
    WRECK_PULL_SLACK = 0.3,       -- with the strap this close to tight
    -- (one on its side is held at once, or it rights itself (P9b)
    WRECK_DRIVER_SHOW_MS = 1500,  -- the seated person shows once the character has loaded (P9b)
    WRECK_REACH = 7,              -- how close you must be to prepare it
    WRECK_UPRIGHT = 0.85,         -- counts as back on its wheels (1 = upright, 0 = on its side)
    WRECK_DITCH_OFFSET = 5,       -- a rollover lies this far off the lane
    WRECK_PAY_PER_KM = 500,       -- on top of a wreck's pay: per kilometre, in a straight line, from the scene to the nearest recovery point
    -- What a spilled load is, picked per call (Z: big bales alone ask for a big loader and slow trips). Small ones go by hand into a pickup bed or the righted
    -- trailer, big ones need a machine and pay for it. weight: how often; size: width, height, length of a base-game square bale; count: by job size; pay:
    -- dollars for each one brought in; gap: how far apart they lie.
    -- pay: per bale when you also bring in the trailer; payAlone: per bale when the bales are all you bring in (Z), and on a storm job, which has no trailer
    WRECK_LOADS = {
        { id = "small", weight = 0.7, size = { 0.45, 0.35, 1.2 }, count = { min = 6, max = 12 }, pay = 45, payAlone = 75, gap = 1.4 },
        { id = "big", needsLift = true, weight = 0.3, size = { 1.2, 0.9, 1.8 }, count = { min = 3, max = 8 }, pay = 220, payAlone = 300, gap = 2.8 }
    },
    WRECK_BALE_FILL = "STRAW",
    WRECK_BALE_SPREAD = 9,        -- spilled this far along the road either way
    WRECK_BALE_WIDTH = 3,         -- and this far across it
    WRECK_BALE_CLEAR = 4,         -- no closer than this to the wreck

    -- a job nobody reaches in time goes to another contractor: no pay, and a small charge (JobRules.lua, JOB_PENALTY_SHARE)
    JOB_EXPIRE_MS = 20 * 60000,   -- of play
    JOB_EXPIRE_WARN_MS = 5 * 60000, -- a warning this long before

    -- the call panel (PanelRules.lua, CallPanel.lua): the job's steps, its clock and its pay, at the right of the screen while a job runs
    PANEL_URGENT_SECONDS = 120,   -- a clock that can lose you the job turns red this close to the end (the train has CROSSING_CLOCK_URGENT)
    PANEL_NEAR = 60,              -- metres: at the scene, the panel shows no way to it
    PANEL_UPDATE_MS = 250,        -- how often it looks at the scene again (the arrow turns every frame)

    -- calls from county dispatch (living-world trigger; CallPlanner.lua)
    CALLS_ENABLED_DEFAULT = true,
    CALL_FIRST_MS = 5 * 60000,    -- the first call can come this long after the game is loaded
    CALL_GAP_MS = 12 * 60000,     -- at least this long between calls (play time), from when the last job ended; the setting chooses from CALL_GAPS
    -- Normal gives a big job about every 64 minutes if you take every call (Z asked for 1h to 1h15), by simulating the planner with all 18 kinds
    CALL_GAPS = { rare = 30 * 60000, normal = 12 * 60000, often = 6 * 60000 },
    CALL_BIG_GAP_MS = 30 * 60000, -- wreck-group calls come no closer than this at any frequency (Z: no money spam). Longer than this skews the equal odds
    CALL_CHECK_MS = 2 * 60000,    -- how often a call may come
    CALL_CHANCE = 0.2,            -- chance per check, once the gap has passed
    DUSK_DAWN_HOURS = { 5, 6, 7, 18, 19, 20, 21 },
    FLEET_PULL_MASS = 1,          -- tonnes: a motorized vehicle this heavy can pull with a strap: a pickup truck, not a quad
    FLEET_HEAVY_MASS = 3,         -- and this heavy can take on a big wreck: the same line as `heavy` on a wreck's vehicles
    FLEET_CHECK_MS = 10000,       -- how often dispatch looks over the farm's vehicles
    EMERGENCIES = {               -- id: the pool is rse_<id>; weight: how often, relative; needs: "pull" if it takes a vehicle; group: wreck, else an animal
        -- every call as likely as any other (Z). An entry can also have duskFactor and autumnFactor, which none has now.
        -- wreck: the vehicle to be towed (WRECKS), which the pager names before you say yes
        { id = "deer", weight = 1 },
        { id = "boar", weight = 1 },
        { id = "cow", weight = 1, needs = "pull" },
        { id = "sheep", weight = 1 },
        { id = "pig", weight = 1 },
        { id = "goat", weight = 1 },
        { id = "horse", weight = 1, needs = "pull" },
        { id = "buffalo", weight = 1, needs = "pull" },
        { id = "wreck", weight = 1, needs = "pull", group = "wreck", wreck = "truck" },
        { id = "rollover", weight = 1, needs = "pull", group = "wreck", wreck = "tractor" },
        { id = "trailer", weight = 1, needs = "pull", group = "wreck", wreck = "trailer" },
        { id = "livestock", weight = 1, needs = "livestock", group = "wreck", wreck = "livestock" },
        { id = "powerline", weight = 1, needs = "pull", group = "wreck", wreck = "powerline" },
        { id = "logging", weight = 1, needs = "pull", group = "wreck" },
        { id = "crossing", weight = 1, needs = "pull", group = "wreck", wreck = "crossing" },
        { id = "river", weight = 1, needs = "pull", group = "wreck", wreck = "river" },
        { id = "tree", weight = 1, needs = "pull", group = "wreck", wreck = "tree" },
        { id = "flock", weight = 1, group = "wreck" },
        { id = "storm", weight = 0, needs = "carry", group = "wreck" } -- only after a twister (Calls.lua), or rseStart
    },

    -- our keys as modDesc binds them, for a text the game can't name a key for (RseText.keyName)
    KEY_DEFAULTS = { RSE_STRAP = "K", RSE_STRAP_IN = "N", RSE_STRAP_OUT = "M", RSE_KIT_MENU = "U", RSE_KIT_USE = "L", RSE_KIT_TURN = "O",
        RSE_KIT_NEXT = "I", RSE_SETTINGS = "H" },

    -- saving
    SAVE_FILENAME = "roadsideEmergencies.xml",
    PLACE_DELAY_MS = 1000,        -- saved carcasses go back this long after the map is running
    BELT_REFRESH_DELAY_MS = 1500, -- then, once they have settled, belts near them are refreshed
    BELT_REFRESH_RANGE = 12,      -- metres (x + z) between a vehicle and a carcass on it
    SAVE_VERSION = 1
}
