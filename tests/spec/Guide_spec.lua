describe("RseGuide", function()
    it("has a title and text on every page", function()
        expectTrue(#RseGuide.PAGES > 1, "more than one page")
        for i, page in ipairs(RseGuide.PAGES) do
            expectTrue(type(page.title) == "string", "title of page " .. i)
            expectTrue(#page.lines > 0, "text on page " .. i)
        end
    end)

    it("stops at the first and the last page", function()
        expectEqual(RseGuide.turn(1, -1), 1)
        expectEqual(RseGuide.turn(1, 1), 2)
        expectEqual(RseGuide.turn(#RseGuide.PAGES, 1), #RseGuide.PAGES)
    end)

    it("remembers that the guide has been shown, in the store and the savegame", function()
        local store = RseStore.new(RseConfig)
        store:apply("setGuideSeen", { seen = true })
        expectEqual(store.settings.guideSeen, true)
        expectEqual(RseSaveCodec.normalize({ settings = { guideSeen = true } }, RseConfig).settings.guideSeen, true)
        expectEqual(RseSaveCodec.normalize({ settings = {} }, RseConfig).settings.guideSeen, false, "a new savegame sees it")
    end)
end)
