describe("RseSaveCodec", function()
    it("remembers whether the player had reached the call", function()
        local reached = RseSaveCodec.normalize({ scene = { id = "deer", x = 1, y = 2, z = 3, arrived = true } }, RseConfig)
        expectEqual(reached.scene.arrived, true)
        local notYet = RseSaveCodec.normalize({ scene = { id = "deer", x = 1, y = 2, z = 3 } }, RseConfig)
        expectEqual(notYet.scene.arrived, false, "a save from an older version")
    end)

    it("keeps the live animals and the pay of a wreck job, and drops bad animals", function()
        local data = RseSaveCodec.normalize({ scene = { id = "livestock", x = 1, y = 2, z = 3, reward = 2300,
            wreck = { kind = "livestock", state = "locked", bales = {} },
            survivors = { { kind = "sheep", x = 4, y = 5, z = 6, yaw = 1 }, { kind = "dragon", x = 4, y = 5, z = 6 }, { kind = "pig", x = 4 } } } }, RseConfig)
        expectEqual(data.scene.reward, 2300)
        expectEqual(data.scene.led, 0, "none yet")
        expectEqual(#data.scene.survivors, 1)
        expectEqual(data.scene.survivors[1].kind, "sheep")
        expectEqual(data.scene.survivors[1].yaw, 1)
    end)

    it("keeps a driver already out, so that the bonus isn't paid twice", function()
        local data = RseSaveCodec.normalize({ scene = { id = "tree", x = 1, y = 2, z = 3, reward = 3000, rescueMs = "1500", rescueNoted = "true",
            rescueEarned = "500",
            wreck = { kind = "tree", state = "ready", x = 1, y = 2, z = 3, rx = 0, ry = 0, rz = 0 } } }, RseConfig)
        expectEqual(data.scene.rescueMs, 1500)
        expectEqual(data.scene.rescueNoted, true)
        expectEqual(data.scene.rescueEarned, 500)
        local none = RseSaveCodec.normalize({ scene = { id = "tree", x = 1, y = 2, z = 3 } }, RseConfig)
        expectEqual(none.scene.rescueNoted, nil, "a save from before this has none")
    end)

    it("keeps good data", function()
        local data, warnings = RseSaveCodec.normalize({
            version = 1,
            settings = { feeFactor = 1.5 },
            points = { { name = "Yard", kind = "disposal", x = 1, z = 2 } },
            carcasses = { { kind = "cow", x = 1, y = 2, z = 3, rx = 0, ry = 1.5, rz = 1.57 } }
        }, RseConfig)
        expectEqual(#warnings, 0)
        expectEqual(data.settings.feeFactor, 1.5)
        expectEqual(data.points[1].name, "Yard")
        expectEqual(data.carcasses[1].kind, "cow")
        expectEqual(data.carcasses[1].ry, 1.5)
        expectEqual(data.settings.callsEnabled, RseConfig.CALLS_ENABLED_DEFAULT)
    end)

    it("keeps a power line's state and places, and drops broken places", function()
        local data = RseSaveCodec.normalize({ settings = {}, points = {}, carcasses = {}, straps = {}, kit = {},
            scene = { id = "powerline", x = 1, y = 2, z = 3,
            wreck = { kind = "powerline", state = "locked", bales = {} }, line = { powerOff = true, liveMs = 500, wiresIn = 2, poleIn = false, yaw = 1.5,
            standing = { { x = 1, z = 2 }, { x = 3 } }, wires = { { x = 1, y = 2, z = 3, topX = 4, topY = 5, topZ = 6 } },
            pieces = { { x = 1, y = 2, z = 3 } } } } }, RseConfig)
        local line = data.scene.line
        expectTrue(line.powerOff)
        expectEqual(line.wiresIn, 2)
        expectEqual(#line.standing, 1, "the one without all its numbers goes")
        expectEqual(#line.wires, 1)
        expectEqual(line.wires[1].topY, 5)
        expectEqual(#line.pieces, 1)
    end)

    it("keeps straps, follows their carcass when broken carcasses are dropped, and drops broken straps", function()
        local strap = { carcass = 2, vehicle = "vehicle4d2f", component = 1, hx = 0.1, hy = 0.2, hz = 0.3, vx = 1, vy = 0,
            vz = -2, length = 99 }
        local data, warnings = RseSaveCodec.normalize({
            carcasses = { { kind = "dragon", x = 1, y = 2, z = 3 }, { kind = "cow", x = 4, y = 5, z = 6 } },
            straps = { strap, { carcass = 1, vehicle = "x", hx = 0, hy = 0, hz = 0, vx = 0, vy = 0, vz = 0, length = 2 },
                { carcass = 2, vehicle = "y" } }
        }, RseConfig)
        expectEqual(#data.straps, 1)
        expectEqual(data.straps[1].carcass, 1, "the cow is the first carcass once the dragon is dropped")
        expectEqual(data.straps[1].vehicle, "vehicle4d2f")
        expectEqual(data.straps[1].length, RseConfig.STRAP_MAX_LENGTH, "capped")
        expectEqual(#warnings, 3, "the dragon and two straps")
    end)

    it("keeps kit items and the job size, and drops what it doesn't know", function()
        local data, warnings = RseSaveCodec.normalize({
            settings = { jobSize = "large" },
            kit = { { item = "cone", x = 1, y = 2, z = 3, yaw = 0.5, owed = true }, { item = "concrete", x = 1, y = 2, z = 3 },
                { item = "cone", x = 1 } }
        }, RseConfig)
        expectEqual(data.settings.jobSize, "large")
        expectEqual(#data.kit, 1)
        expectEqual(data.kit[1].owed, true)
        expectEqual(data.kit[1].yaw, 0.5)
        expectEqual(#warnings, 2)
        expectEqual(RseSaveCodec.normalize({ settings = { jobSize = "huge" } }, RseConfig).settings.jobSize, "normal")
    end)

    it("keeps the call in progress with its animals and items", function()
        local data, warnings = RseSaveCodec.normalize({
            scene = { id = "sheep", label = "sheep:2-5", x = 1, y = 2, z = 3, kinds = "sheep sheep dragon" },
            carcasses = { { kind = "sheep", x = 1, y = 2, z = 3, scene = true }, { kind = "cow", x = 9, y = 2, z = 9 } },
            kit = { { item = "cone", x = 1, y = 2, z = 3, job = true } }
        }, RseConfig)
        expectEqual(#warnings, 0)
        expectEqual(data.scene.id, "sheep")
        expectEqual(#data.scene.kinds, 2, "only known animals")
        expectEqual(data.carcasses[1].scene, true)
        expectEqual(data.carcasses[2].scene, false)
        expectEqual(data.kit[1].job, true)
        expectEqual(data.kit[1].owed, false)
    end)

    it("keeps a wreck of the call in progress, with its state and bales", function()
        local data = RseSaveCodec.normalize({
            scene = { id = "trailer", x = 1, y = 2, z = 3, wreck = { kind = "trailer", state = "tipped", x = 1, y = 2, z = 3, rx = 0, ry = 1, rz = 1.5,
                load = "small", bales = { { x = 5, y = 6, z = 7, ry = 2 }, { x = 5 } } } }
        }, RseConfig)
        expectEqual(data.scene.wreck.kind, "trailer")
        expectEqual(data.scene.wreck.state, "tipped")
        expectEqual(data.scene.wreck.rz, 1.5)
        expectEqual(data.scene.wreck.load, "small")
        expectEqual(#data.scene.wreck.bales, 1, "a bale without a position is dropped")
        expectEqual(data.scene.wreck.bales[1].ry, 2)
        expectNil(RseSaveCodec.normalize({ scene = { id = "x", x = 1, y = 2, z = 3, wreck = { kind = "ufo" } } }, RseConfig).scene.wreck)
    end)

    it("without a usable call, drops its animals and owes its items", function()
        local data, warnings = RseSaveCodec.normalize({
            scene = { id = "sheep" },
            carcasses = { { kind = "sheep", x = 1, y = 2, z = 3, scene = true } },
            kit = { { item = "cone", x = 1, y = 2, z = 3, job = true } }
        }, RseConfig)
        expectNil(data.scene)
        expectEqual(#data.carcasses, 0)
        expectEqual(data.kit[1].job, false)
        expectEqual(data.kit[1].owed, true)
        expectEqual(#warnings, 1)
    end)

    it("keeps the pay to take back, never negative", function()
        local data = RseSaveCodec.normalize({
            carcasses = { { kind = "deer", x = 1, y = 2, z = 3, unearned = 570 }, { kind = "deer", x = 1, y = 2, z = 3, unearned = -5 },
                { kind = "deer", x = 1, y = 2, z = 3 } }
        }, RseConfig)
        expectEqual(data.carcasses[1].unearned, 570)
        expectEqual(data.carcasses[2].unearned, 0)
        expectEqual(data.carcasses[3].unearned, 0)
    end)

    it("keeps how long a carcass has been left lying", function()
        local data = RseSaveCodec.normalize({
            carcasses = { { kind = "deer", x = 1, y = 2, z = 3, leftMs = 5000 }, { kind = "deer", x = 1, y = 2, z = 3, leftMs = 1e12 },
                { kind = "deer", x = 1, y = 2, z = 3 } }
        }, RseConfig)
        expectEqual(data.carcasses[1].leftMs, 5000)
        expectEqual(data.carcasses[2].leftMs, RseConfig.LEFT_COLLECT_MS, "capped")
        expectEqual(data.carcasses[3].leftMs, 0)
    end)

    it("keeps the panel's settings, and defaults what is missing or wrong", function()
        local data = RseSaveCodec.normalize({ settings = { payFactor = "1.5", wreckCalls = "false", leftMinutes = "999" } }, RseConfig)
        expectEqual(data.settings.payFactor, 1.5)
        expectEqual(data.settings.wreckCalls, false)
        expectEqual(data.settings.leftMinutes, 30)
        expectEqual(data.settings.markersEnabled, true)
        expectEqual(RseSaveCodec.normalize(nil, RseConfig).settings.payFactor, 1)
    end)

    it("keeps the calls setting", function()
        expectEqual(RseSaveCodec.normalize({ settings = { callsEnabled = false } }, RseConfig).settings.callsEnabled, false)
    end)

    it("drops broken entries with a warning", function()
        local data, warnings = RseSaveCodec.normalize({
            points = { { name = "No position", kind = "both" }, { kind = "weird", x = 5, z = 6 } },
            carcasses = { { kind = "dragon", x = 1, y = 2, z = 3 }, { kind = "deer", x = 1, z = 3 } }
        }, RseConfig)
        expectEqual(#data.points, 1)
        expectEqual(data.points[1].kind, "both", "an unknown kind becomes both")
        expectEqual(data.points[1].name, "Point 2")
        expectEqual(#data.carcasses, 0)
        expectEqual(#warnings, 3)
    end)

    it("warns about a newer save file and clamps the fee setting", function()
        local data, warnings = RseSaveCodec.normalize({ version = 99, settings = { feeFactor = 50 } }, RseConfig)
        expectEqual(#warnings, 1)
        expectEqual(data.settings.feeFactor, RseConfig.FEE_FACTOR_MAX)
    end)

    it("starts clean without a save file", function()
        local data, warnings = RseSaveCodec.normalize(nil, RseConfig)
        expectEqual(#warnings, 0)
        expectEqual(data.settings.feeFactor, RseConfig.FEE_FACTOR_DEFAULT)
        expectEqual(#data.carcasses, 0)
    end)

    it("keeps which vehicle a saved wreck is", function()
        local data = RseSaveCodec.normalize({ scene = { id = "wreck", x = 1, y = 2, z = 3,
            wreck = { kind = "truck", state = "locked", file = "some/truck.xml", bales = {} } } }, RseConfig)
        expectEqual(data.scene.wreck.file, "some/truck.xml")
    end)

    it("keeps the middle of a twister's area, when it is whole", function()
        local data = RseSaveCodec.normalize({ twister = { x = 12.5, z = -3 } }, RseConfig)
        expectEqual(data.twister.x, 12.5)
        expectEqual(data.twister.z, -3)
        expectEqual(RseSaveCodec.normalize({ twister = { x = 1 } }, RseConfig).twister, nil)
        expectEqual(RseSaveCodec.normalize({}, RseConfig).twister, nil)
    end)

    it("keeps the logs of a job that is over, to be cleared after the load", function()
        local data, warnings = RseSaveCodec.normalize({ cleanup = { { x = 10, z = -4, logs = { { x = 1, y = 2, z = 3 }, { x = 1 } } },
            { x = 5, z = 5, logs = {} }, { z = 1, logs = { { x = 1, y = 2, z = 3 } } } } }, RseConfig)
        expectEqual(#data.cleanup, 1, "only the one with a place and a whole log")
        expectEqual(data.cleanup[1].x, 10)
        expectEqual(#data.cleanup[1].logs, 1, "the log with no height is dropped")
        expectEqual(data.cleanup[1].logs[1].z, 3)
        expectEqual(#warnings, 2)
        expectEqual(#RseSaveCodec.normalize({}, RseConfig).cleanup, 0, "an older save has none")
        expectEqual(#RseSaveCodec.normalize(nil, RseConfig).cleanup, 0, "no save at all")
    end)

    it("keeps where our own log trees stand, and tells an older save (no list) from one with none", function()
        local data, warnings = RseSaveCodec.normalize({ ownLogs = { { x = 1.5, z = -2 }, { x = 3 }, { x = "4", z = "5" } } }, RseConfig)
        expectEqual(#data.ownLogs, 2, "the one with no place is dropped")
        expectEqual(data.ownLogs[1].x, 1.5)
        expectEqual(data.ownLogs[2].z, 5)
        expectEqual(#warnings, 1)
        expectEqual(#RseSaveCodec.normalize({ ownLogs = {} }, RseConfig).ownLogs, 0, "a save with the list, but none of our logs left")
        expectEqual(RseSaveCodec.normalize({}, RseConfig).ownLogs, nil, "a save from before the list")
        expectEqual(RseSaveCodec.normalize(nil, RseConfig).ownLogs, nil, "no save at all")
    end)
end)
