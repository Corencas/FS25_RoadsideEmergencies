describe("RseLogRules", function()
    local def = { pay = 1000, payPerLog = 100 }
    -- a road along the x axis
    local scene = { x = 0, z = 0, segments = { { -100, 0, 100, 0 } } }

    it("counts what is clear of the road, and what has gone, towards the job", function()
        expectEqual(RseLogRules.share(0, 0, 0), 0, "nothing there yet")
        expectEqual(RseLogRules.share(0, 0, 4), 0)
        expectEqual(RseLogRules.share(2, 0, 4), 0.5)
        expectEqual(RseLogRules.share(1, 1, 3), 0.5, "one clear, one sold, two still out")
        expectEqual(RseLogRules.share(3, 1, 3), 1)
    end)

    it("pays the job and every log when all are clear, and only the logs when handed over", function()
        expectEqual(RseLogRules.pay(def, 6, 1), 1600)
        expectEqual(RseLogRules.pay(def, 6, 0), 0)
        expectEqual(RseLogRules.pay(def, 6, 0.5), 300)
        expectEqual(RseLogRules.pay(def, 6, 0.01), 100, "a log you have started on counts")
    end)

    it("knows a log on a car from one beside it", function()
        local car = { width = 2, length = 4.8, offsetZ = 0 }
        local function on(ax, ay, az, bx, by, bz)
            return RseLogRules.onCar({ x = ax, y = ay, z = az }, { x = bx, y = by, z = bz }, car, RseConfig)
        end
        expectTrue(on(-5, 0.25, 0, 4, 3.4, 0), "leaning across the roof, foot on the ground")
        expectTrue(on(-0.5, 1.6, 1, 0.5, 1.6, 1), "a cut piece left on the roof")
        expectTrue(on(-0.5, 0.9, 2.3, 0.5, 0.9, 2.3), "or on the bonnet")
        expectTrue(not on(-5, 0.25, 0, -1.5, 0.25, 0), "on the ground, pointing at the door")
        expectTrue(not on(1.5, 0.25, -3, 1.5, 0.25, 3), "on the ground along its side")
        expectTrue(not on(-0.5, 0.25, 0, 0.5, 0.25, 0), "under it: too low to be on it")
        expectTrue(not on(1.6, 1.2, -2, 1.6, 1.2, 2), "up on something, but not over the car")
        expectTrue(not on(-0.5, 1.6, 4, 0.5, 1.6, 4), "in the air, ahead of it")
        local stretched = { width = 2, length = 4.8, offsetZ = 1 }
        expectTrue(RseLogRules.onCar({ x = 0, y = 1, z = 3.2 }, { x = 0, y = 1, z = 3.2 }, stretched, RseConfig),
            "the outline isn't always centred on the car's foot")
    end)

    it("counts a log on a vehicle, wherever that is", function()
        expectEqual(RseLogRules.status({ x = 1, z = 0, loaded = true }, scene, RseConfig), "loaded")
    end)

    it("counts a log lying still well off the road, and only then", function()
        expectEqual(RseLogRules.status({ x = 5, z = 8, atRest = true }, scene, RseConfig), "verge")
        expectEqual(RseLogRules.status({ x = 5, z = 8, atRest = false }, scene, RseConfig), "onRoad", "still moving")
        expectEqual(RseLogRules.status({ x = 5, z = 1, atRest = true }, scene, RseConfig), "onRoad", "in the lane")
    end)

    it("doesn't count a long log with one end in the lane", function()
        local across = { x = 5, z = 5, atRest = true, ends = { { x = 5, z = 1 }, { x = 5, z = 9 } } }
        expectEqual(RseLogRules.status(across, scene, RseConfig), "onRoad")
        local alongside = { x = 5, z = 5, atRest = true, ends = { { x = 1, z = 5 }, { x = 9, z = 5 } } }
        expectEqual(RseLogRules.status(alongside, scene, RseConfig), "verge")
    end)

    it("counts a log taken far from the scene, and judges by distance when no road was measured", function()
        expectEqual(RseLogRules.status({ x = RseConfig.SCENE_RADIUS + 1, z = 0 }, scene, RseConfig), "away")
        local noRoad = { x = 0, z = 0, segments = {} }
        expectEqual(RseLogRules.status({ x = RseConfig.CLEAR_FALLBACK_RADIUS, z = 0, atRest = true, ends = { { x = 1, z = 0 } } }, noRoad, RseConfig), "verge")
    end)

    it("wants a loaded log to have come to rest once, and then lets the truck drive off", function()
        local rest = RseConfig.CLEAR_REST_MS
        expectEqual(RseLogRules.counts("loaded", false, rest - 1, RseConfig), false, "swung across the bed")
        expectEqual(RseLogRules.counts("loaded", false, rest, RseConfig), true, "lying on it")
        expectEqual(RseLogRules.counts("loaded", true, 0, RseConfig), true, "on the road with it")
        expectEqual(RseLogRules.counts("onRoad", true, rest * 10, RseConfig), false, "tipped back into the road")
        expectEqual(RseLogRules.counts("verge", false, 0, RseConfig), true, "the verge has waited already")
        expectEqual(RseLogRules.counts("away", false, 0, RseConfig), true)
    end)

    it("knows a piece that is still where it was saved", function()
        local saved = { { x = 10, y = 50, z = 10 }, { x = 20, y = 50, z = 20 } }
        local found = { { x = 20.5, y = 50, z = 20, lx = 1, lz = 1 }, { x = 10, y = 49.5, z = 10.5, lx = 1, lz = 1 } }
        local match = RseLogRules.matchSaved(found, saved, RseConfig.LOG_SAVED_NEAR)
        expectEqual(match[1].saved, 2)
        expectTrue(match[1].inPlace)
        expectEqual(match[2].saved, 1)
        expectTrue(match[2].inPlace)
    end)

    it("finds a piece's place by its position against its parent when it has been put somewhere else", function()
        -- as if the game had added the tree's own position to each saved one
        local saved = { { x = 10, y = 50, z = 10 }, { x = 20, y = 50, z = 20 } }
        local found = { { x = 40, y = 90, z = 40, lx = 20, lz = 20 }, { x = 20, y = 90, z = 20, lx = 10, lz = 10 } }
        local match = RseLogRules.matchSaved(found, saved, RseConfig.LOG_SAVED_NEAR)
        expectEqual(match[1].saved, 2)
        expectEqual(match[1].inPlace, false)
        expectEqual(match[2].saved, 1)
        expectEqual(match[2].inPlace, false)
    end)

    it("doesn't call a piece that fell through the ground still there", function()
        local match = RseLogRules.matchSaved({ { x = 10, y = 20, z = 10, lx = 0, lz = 0 } }, { { x = 10, y = 50, z = 10 } }, RseConfig.LOG_SAVED_NEAR)
        expectEqual(match[1].inPlace, false)
    end)

    it("gives the two halves of a cut log a place each, and leaves a piece with no place alone", function()
        local saved = { { x = 10, y = 50, z = 10 }, { x = 10.01, y = 50, z = 10 } }
        local found = { { x = 10, y = 50, z = 10, lx = 0, lz = 0 }, { x = 10, y = 50, z = 10, lx = 0, lz = 0 }, { x = 90, y = 50, z = 90, lx = 0, lz = 0 } }
        local match = RseLogRules.matchSaved(found, saved, RseConfig.LOG_SAVED_NEAR)
        expectTrue(match[1].inPlace and match[2].inPlace)
        expectTrue(match[1].saved ~= match[2].saved)
        expectNil(match[3], "no place left for the third")
        local empty = RseLogRules.matchSaved({ { x = 1, y = 1, z = 1 } }, {}, RseConfig.LOG_SAVED_NEAR)
        expectNil(empty[1])
    end)

    it("has a logging crash the trailer of which is only scenery", function()
        local logging = RseConfig.WRECKS.logging
        expectTrue(logging.scenery and logging.tipped and logging.logs.min > 1, "several logs, always")
        expectEqual(RseLogRules.pay(logging, logging.logs.min, 1), logging.pay + logging.payPerLog * logging.logs.min)
        expectNil(RseWreckRules.pickLoad(logging, 0.5, RseConfig), "no bales")
        expectEqual(RseWreckRules.haulPay(logging, 5000, RseConfig), 0, "nothing is hauled")
    end)

    it("keeps a saved job's logs, with their turn when the save has it", function()
        local function normalized(pieces)
            local data = RseSaveCodec.normalize({ scene = { id = "logging", x = 1, y = 2, z = 3, wreck = { kind = "logging", state = "locked", bales = {} },
                logs = { total = "6", gone = "1", dirX = "1", dirZ = "0", splitType = "24", trees = { { x = "1", z = "2" }, { x = "bad" } },
                    pieces = pieces } } }, RseConfig)
            return data.scene.logs
        end
        local logs = normalized({ { x = "1", y = "2", z = "3", rx = "0.1", ry = "0.2", rz = "0.3" } })
        expectEqual(logs.total, 6)
        expectEqual(logs.gone, 1)
        expectEqual(logs.splitType, 24)
        expectEqual(#logs.trees, 1, "the broken one is left out")
        expectEqual(#logs.pieces, 1)
        expectEqual(logs.pieces[1].ry, 0.2)
        local older = normalized({ { x = "1", y = "2", z = "3" } })
        expectEqual(#older.pieces, 1, "a save from before keeps its pieces")
        expectNil(older.pieces[1].ry)
        local none = RseSaveCodec.normalize({ scene = { id = "logging", x = 1, y = 2, z = 3, wreck = { kind = "logging", state = "locked", bales = {} },
            logs = { gone = "1" } } }, RseConfig)
        expectNil(none.scene.logs, "without a count there is nothing to bring back")
    end)

    it("still reads a save with the landing the job used to have", function()
        local data = RseSaveCodec.normalize({ scene = { id = "logging", x = 1, y = 2, z = 3, wreck = { kind = "logging", state = "locked", bales = {} },
            logs = { total = "7", gone = "0", landingX = "174", landingZ = "-777", dirX = "1", dirZ = "0", pieces = {} } } }, RseConfig)
        expectEqual(data.scene.logs.total, 7)
    end)
end)
