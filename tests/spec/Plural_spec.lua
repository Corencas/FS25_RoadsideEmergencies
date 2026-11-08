describe("RsePlural", function()
    local function forms(rule, numbers)
        local list = {}
        for _, n in ipairs(numbers) do
            table.insert(list, RsePlural.form(rule, n))
        end
        return table.concat(list, " ")
    end

    it("English and the like: one for 1, many otherwise", function()
        expectEqual(forms("default", { 0, 1, 2, 5, 21 }), "many one many many many")
        expectEqual(forms(nil, { 1, 3 }), "one many", "no rule is the default")
        expectEqual(forms("klingon", { 1, 3 }), "one many", "an unknown rule is the default")
    end)

    it("Russian and Ukrainian: 1 and 21 one, 2 to 4 and 22 to 24 few, 11 to 14 and 5 up many", function()
        expectEqual(forms("eastSlavic", { 0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 112 }),
            "many one few few many many many many one few many one many many")
    end)

    it("Polish: only 1 is one; 22 to 24 few, but 12 to 14 and 21 many", function()
        expectEqual(forms("polish", { 0, 1, 2, 4, 5, 12, 21, 22, 25, 102 }), "many one few few many many many few many few")
    end)

    it("Czech: 1 one, 2 to 4 few, everything else many", function()
        expectEqual(forms("czech", { 0, 1, 2, 4, 5, 22 }), "many one few few many many")
    end)

    it("takes the whole part of a fill level", function()
        expectEqual(RsePlural.form("eastSlavic", 2.0), "few")
        expectEqual(RsePlural.form("default", 1.0), "one")
    end)
end)
