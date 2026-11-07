describe("RseSettings", function()
    it("cycles a row's values and starts over at the end", function()
        local row = RseSettings.row("jobSize")
        expectEqual(RseSettings.nextValue(row, "normal"), "large")
        expectEqual(RseSettings.nextValue(row, "random"), "small")
        expectEqual(RseSettings.nextValue(row, "nonsense"), "small")
    end)

    it("goes back through a row's values too", function()
        local row = RseSettings.row("jobSize")
        expectEqual(RseSettings.previousValue(row, "large"), "normal")
        expectEqual(RseSettings.previousValue(row, "small"), "random", "round to the end")
        expectEqual(RseSettings.previousValue(row, "nonsense"), "small")
    end)

    it("has a valid default for every row, so return to default can't fail", function()
        for _, row in ipairs(RseSettings.ROWS) do
            expectTrue(RseSettings.isValid(row, row.default), row.key)
        end
    end)

    it("reads saved values back in their own type", function()
        expectEqual(RseSettings.parse(RseSettings.row("payFactor"), "1.5"), 1.5)
        expectEqual(RseSettings.parse(RseSettings.row("wreckCalls"), "false"), false)
        expectEqual(RseSettings.parse(RseSettings.row("wreckCalls"), false), false)
        expectEqual(RseSettings.parse(RseSettings.row("leftMinutes"), "45"), 45)
    end)

    it("falls back to the default for anything it doesn't know", function()
        expectEqual(RseSettings.parse(RseSettings.row("payFactor"), "99"), 1)
        expectEqual(RseSettings.parse(RseSettings.row("markersEnabled"), nil), true)
    end)

    it("fills in defaults without touching what is set", function()
        local settings = RseSettings.fillDefaults({ payFactor = 2 })
        expectEqual(settings.payFactor, 2)
        expectEqual(settings.leftMinutes, 30)
        expectEqual(settings.jobSize, "normal")
    end)

    it("puts the time settings where the rules read them", function()
        local config = { CALL_GAPS = RseConfig.CALL_GAPS }
        RseSettings.applyTimes({ leftMinutes = 45, expireMinutes = 10 }, config)
        expectEqual(config.LEFT_COLLECT_MS, 45 * 60000)
        expectEqual(config.JOB_EXPIRE_MS, 10 * 60000)
    end)

    it("has defaults that match the config's", function()
        expectEqual(RseSettings.row("leftMinutes").default * 60000, RseConfig.LEFT_COLLECT_MS)
        expectEqual(RseSettings.row("expireMinutes").default * 60000, RseConfig.JOB_EXPIRE_MS)
    end)

    it("sets the time between calls from how often they should come", function()
        local config = { CALL_GAPS = RseConfig.CALL_GAPS }
        RseSettings.applyTimes({ callFrequency = "often" }, config)
        expectEqual(config.CALL_GAP_MS, RseConfig.CALL_GAPS.often)
        RseSettings.applyTimes({ callFrequency = "rare" }, config)
        expectEqual(config.CALL_GAP_MS, RseConfig.CALL_GAPS.rare)
        RseSettings.applyTimes({}, config)
        expectEqual(config.CALL_GAP_MS, RseConfig.CALL_GAPS.normal)
        expectEqual(RseSettings.parse(RseSettings.row("callFrequency"), "often"), "often")
        expectEqual(RseSettings.parse(RseSettings.row("callFrequency"), nil), "normal", "a save from before the setting")
    end)
end)
