describe("RseToolRules", function()
    local tools = { "hands", "flashlight", "chainsaw" }

    it("goes round the tools you carry, either way", function()
        expectEqual(RseToolRules.next(tools, "hands", 1), "flashlight")
        expectEqual(RseToolRules.next(tools, "chainsaw", 1), "hands", "round to the start")
        expectEqual(RseToolRules.next(tools, "hands", -1), "chainsaw", "round to the end")
        expectEqual(RseToolRules.next(tools, "flashlight", -1), "hands")
        expectEqual(RseToolRules.next(tools, "something else", 1), "hands", "a tool it doesn't know")
        expectEqual(RseToolRules.next({}, "hands", 1), nil)
    end)

    it("takes a tool back to bare hands", function()
        expectEqual(RseToolRules.toggle(tools, "chainsaw", "hands", "chainsaw"), "hands")
        expectEqual(RseToolRules.toggle(tools, "flashlight", "hands", nil), "hands")
    end)

    it("from bare hands, takes out the tool used last, or else the first one", function()
        expectEqual(RseToolRules.toggle(tools, "hands", "hands", "chainsaw"), "chainsaw")
        expectEqual(RseToolRules.toggle(tools, "hands", "hands", nil), "flashlight")
        expectEqual(RseToolRules.toggle(tools, "hands", "hands", "sold"), "flashlight", "you no longer carry it")
        expectEqual(RseToolRules.toggle({ "hands" }, "hands", "hands", nil), nil, "nothing else to take out")
    end)
end)
