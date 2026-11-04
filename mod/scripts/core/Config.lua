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
    STRAP_MIN_LENGTH = 1.5,
    STRAP_HOOK_SLACK = 0.05,      -- metres of slack when it is attached, so that hooking up pulls nothing
    STRAP_AIM_TOLERANCE = 0.02,   -- metres off the line before the joint is turned to follow it
    STRAP_CENTRE_RANGE = 0.5,     -- a hook this close to the middle of a wreck's end already sits right for towing
    STRAP_SNAP = 1.0,             -- aim this close to a hitch and the strap goes on the hitch
    STRAP_REEL_SPEED = 0.6,       -- metres per second, reeling a strap in or out by hand
    STRAP_REEL_NEAR = 15,         -- how close to a strap you must be to reel it
    TOW_LENGTH = 3.5,             -- towing a wreck, the strap shortens to this by itself
    TOW_LATERAL = 1.5,            -- and the wreck stays this close to straight behind the vehicle
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
    WRECKS = {
        truck = { file = "$data/vehicles/lizard/multiPurposeTruck/multiPurposeTruck.xml", pay = 3500, damage = 0.9, smoke = true },
        tractor = { file = "$data/vehicles/fendt/vario300/vario300.xml", pay = 4500, damage = 0.7, tipped = true, driver = true, ditch = true, smoke = true },
        -- two parts as well (Z): the trailer (pay) and the bales (each one brought in pays, WRECK_LOADS); both earn bothBonus
        trailer = { file = "$data/vehicles/farmtech/edk650/edk650.xml", pay = 3000, damage = 0.6, tipped = true, twoParts = true, bothBonus = 0.25,
            spills = true, loadLimit = { big = 4 } }, -- it spilled no more than it can carry (Z: about 4 big bales fit)
        -- a livestock trailer on its side, with two parts to the job (Z): the trailer (pay) and the animals (dead ones as on an animal call, plus
        -- payPerSurvivor for each one caught and loaded). Doing both earns bothBonus on top. kinds: one is picked per call
        livestock = { file = "$data/vehicles/fliegl/noahTTW140/noahTTW140.xml", pay = 3000, damage = 0.6, tipped = true, twoParts = true, payPerSurvivor = 75,
            bothBonus = 0.25, kinds = { "sheep", "pig", "cow" }, dead = { min = 1, max = 2 }, survivors = { min = 2, max = 5 } },
        -- bales blown across the road by a twister: no vehicle at all
        -- a car has hit a utility pole: two parts as well, the car (pay) and the pole and wires (polePay, wirePay each); both earn bothBonus (LineRules.lua)
        powerline = { file = "$data/vehicles/lizard/pickup2017/pickup2017.xml", pay = 2500, damage = 0.9, driver = true, twoParts = true, bothBonus = 0.25,
            line = true, hazards = true, smoke = true, polePay = 1200, wirePay = 100, wires = { min = 2, max = 4 } },
        storm = { noVehicle = true, pay = 1200, spills = true }
    },
    SURVIVOR_REACH = 3,           -- how close you must be to catch a loose animal
    POINT_MARKER_RANGE = 40,      -- drop-off points show on the map while you are this close to an animal you have loaded, strapped or in hand
    MARKER_SCALE = 0.5,           -- our map markers against the game's size (Z: they hid where things are)
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
    HERD_SMOOTH_MS = 300,         -- how quickly it settles to the ground, a slope or a stop
    HERD_MODEL_YAW = 0,           -- added to the heading if a model faces another way
    -- the walk on a model's bones (GaitRules.lua)
    GAIT_DUTY = 0.62,             -- the share of a cycle each foot spends on the ground
    GAIT_CYCLES_BASE = 0.55,      -- cycles per second standing still
    GAIT_CYCLES_PER_SPEED = 0.9,  -- and more per metre per second
    GAIT_CYCLES_MIN = 0.5,
    GAIT_CYCLES_MAX = 2.2,
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
    GAIT_TAIL = 0.15,             -- radians side to side
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
    LINE_POWER_CUT_MS = 90000,    -- after you arrive, the utility crew has cut the power this much later
    LINE_DANGER_RADIUS = 20,      -- metres from the scene: too close to live wires
    LINE_DANGER_GRACE_MS = 8000,  -- this long in there in all, after the warning, and it costs you
    LINE_DANGER_CUT = 0.1,        -- of the pay
    LINE_STANDING_SIDE = 8,       -- metres to the side of the lane: the poles still standing
    LINE_STANDING_ALONG = { -26, 26 }, -- metres along the road from the scene, either way
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
    LINE_WARN_MS = 3000,          -- the "not yet" message comes at most this often
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
    WRECK_SMOKE_FILE = "$data/effects/smoke/smokeParticles.i3d", -- the game's own smoke, by path
    WRECK_SMOKE_HEIGHT = 0.55,    -- of the vehicle's height, above its origin: about the top of its hood
    WRECK_SMOKE_BACK = 0.9,       -- metres back from its front end: over the engine
    WRECK_PIN_MS = 2500,          -- pinned once it has settled (P3b)
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
        { id = "big", weight = 0.3, size = { 1.2, 0.9, 1.8 }, count = { min = 3, max = 8 }, pay = 220, payAlone = 300, gap = 2.8 }
    },
    WRECK_BALE_FILL = "STRAW",
    WRECK_BALE_SPREAD = 9,        -- spilled this far along the road either way
    WRECK_BALE_WIDTH = 3,         -- and this far across it
    WRECK_BALE_CLEAR = 4,         -- no closer than this to the wreck

    -- a job nobody reaches in time goes to another contractor: no pay, no penalty (JobRules.lua)
    JOB_EXPIRE_MS = 20 * 60000,   -- of play
    JOB_EXPIRE_WARN_MS = 5 * 60000, -- a warning this long before

    -- calls from county dispatch (living-world trigger; CallPlanner.lua)
    CALLS_ENABLED_DEFAULT = true,
    CALL_FIRST_MS = 5 * 60000,    -- the first call can come this long after the game is loaded
    CALL_GAP_MS = 20 * 60000,     -- at least this long between calls (play time)
    CALL_CHECK_MS = 2 * 60000,    -- how often a call may come
    CALL_CHANCE = 0.2,            -- chance per check, once the gap has passed
    DUSK_DAWN_HOURS = { 5, 6, 7, 18, 19, 20, 21 },
    EMERGENCIES = {               -- id: the pool is rse_<id>; weight: how often, relative; needs: "pull" if it takes a vehicle; group: wreck, else an animal
        { id = "deer", weight = 4, duskFactor = 2, autumnFactor = 1.5 },
        { id = "boar", weight = 2, duskFactor = 1.5 },
        { id = "cow", weight = 1.5, needs = "pull" },
        { id = "sheep", weight = 1.5 },
        { id = "pig", weight = 1 },
        { id = "goat", weight = 1 },
        { id = "horse", weight = 0.7, needs = "pull" },
        { id = "buffalo", weight = 0.5, needs = "pull" },
        { id = "wreck", weight = 1.2, needs = "pull", group = "wreck" },
        { id = "rollover", weight = 1, needs = "pull", group = "wreck" },
        { id = "trailer", weight = 1, needs = "pull", group = "wreck" },
        { id = "livestock", weight = 0.8, needs = "pull", group = "wreck" },
        { id = "powerline", weight = 0.8, needs = "pull", group = "wreck" },
        { id = "storm", weight = 0, group = "wreck" } -- only after a twister (Calls.lua), or rseStart
    },

    -- saving
    SAVE_FILENAME = "roadsideEmergencies.xml",
    PLACE_DELAY_MS = 1000,        -- saved carcasses go back this long after the map is running
    BELT_REFRESH_DELAY_MS = 1500, -- then, once they have settled, belts near them are refreshed
    BELT_REFRESH_RANGE = 12,      -- metres (x + z) between a vehicle and a carcass on it
    SAVE_VERSION = 1
}
