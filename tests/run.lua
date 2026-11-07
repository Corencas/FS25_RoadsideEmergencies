-- Minimal test runner for the engine-free core (Lua 5.1, no dependencies).
-- Usage, from the repo root: lua5.1 tests/run.lua    (exit code 1 if a test fails)

local passed, failed = 0, 0
local current = ""

function describe(name, fn)
    local previous = current
    current = name
    fn()
    current = previous
end

function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL %s: %s\n     %s", current, name, tostring(err)))
    end
end

local function fail(message, detail)
    error((message and (message .. ": ") or "") .. detail, 3)
end

function expectEqual(actual, expected, message)
    if actual ~= expected then
        fail(message, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
    end
end

function expectNear(actual, expected, tolerance, message)
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        fail(message, string.format("expected %s (+/- %s), got %s", tostring(expected), tostring(tolerance), tostring(actual)))
    end
end

function expectTrue(value, message)
    if not value then
        fail(message, "expected true, got " .. tostring(value))
    end
end

function expectNil(value, message)
    if value ~= nil then
        fail(message, "expected nil, got " .. tostring(value))
    end
end

-- the core, in the same order as modDesc
for _, name in ipairs({ "Config", "Log", "AnimalCatalog", "PayRules", "PointRegistry", "SaveCodec", "Settings", "Store", "RoadClearRule",
    "SceneSpec", "CallPlanner", "KitRules", "SpotRules", "LeftBehindRule", "JobRules", "Guide", "ProgressRules", "HerdRules", "FlockRules",
    "GroundRules", "GaitRules", "WreckRules", "TwisterRules", "LineRules", "LogRules", "WaterRules", "CrossingRules", "ToolRules", "PanelRules",
    "CrewRules", "PagerRules" }) do
    dofile("mod/scripts/core/" .. name .. ".lua")
end

for _, name in ipairs({ "AnimalCatalog", "PayRules", "PointRegistry", "SaveCodec", "Store", "RoadClearRule", "SceneSpec",
    "CallPlanner", "KitRules", "SpotRules", "LeftBehindRule", "JobRules", "Guide", "ProgressRules", "HerdRules", "FlockRules", "GroundRules", "GaitRules",
    "WreckRules", "TwisterRules", "LineRules", "LogRules", "WaterRules", "CrossingRules", "ToolRules", "Settings", "PanelRules", "CrewRules", "PagerRules" }) do
    dofile("tests/spec/" .. name .. "_spec.lua")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
