-- Roadside Emergencies: the in-game guide (Z, 2026-11-02): everything a player needs to know, in the settings panel's style. The welcome dialog offers it,
-- and it comes back any time from the first row of the panel. Engine-free: which texts go on which page, and how pages split over screens.

RseGuide = {
    -- the guide's pages, in order: a title and its lines (text keys). SettingsPanel.lua lays them out on screen, and a page with more than
    -- fits goes on over as many screens as it needs
    PAGES = {
        { title = "rse_guide_title_welcome", lines = { "rse_guide_welcome_1", "rse_guide_welcome_2", "rse_guide_welcome_3", "rse_guide_welcome_4",
            "rse_guide_welcome_5" } },
        { title = "rse_guide_title_tools", lines = { "rse_guide_tools_1", "rse_guide_tools_2", "rse_guide_tools_3", "rse_guide_tools_4",
            "rse_guide_tools_5", "rse_guide_tools_6" } },
        { title = "rse_guide_title_calls", lines = { "rse_guide_calls_1", "rse_guide_calls_2", "rse_guide_calls_3", "rse_guide_calls_4",
            "rse_guide_calls_5", "rse_guide_calls_6", "rse_guide_calls_7" } },
        { title = "rse_guide_title_timing", lines = { "rse_guide_timing_1", "rse_guide_timing_2", "rse_guide_timing_3", "rse_guide_timing_4" } },
        { title = "rse_guide_title_pay", lines = { "rse_guide_pay_1", "rse_guide_pay_2", "rse_guide_pay_3", "rse_guide_pay_4", "rse_guide_pay_5",
            "rse_guide_pay_6", "rse_guide_pay_7" } },
        { title = "rse_guide_title_animals", lines = { "rse_guide_animals_1", "rse_guide_animals_2", "rse_guide_animals_3", "rse_guide_animals_4",
            "rse_guide_animals_5" } },
        { title = "rse_guide_title_points", lines = { "rse_guide_points_1", "rse_guide_points_2", "rse_guide_points_3" } },
        { title = "rse_guide_title_strap", lines = { "rse_guide_strap_1", "rse_guide_strap_2", "rse_guide_strap_3", "rse_guide_strap_4" } },
        { title = "rse_guide_title_wrecks", lines = { "rse_guide_wrecks_1", "rse_guide_wrecks_2", "rse_guide_wrecks_3", "rse_guide_wrecks_4" } },
        { title = "rse_guide_title_loads", lines = { "rse_guide_loads_1", "rse_guide_loads_2", "rse_guide_loads_3" } },
        { title = "rse_guide_title_loose", lines = { "rse_guide_loose_0", "rse_guide_loose_1", "rse_guide_loose_2", "rse_guide_loose_3" } },
        { title = "rse_guide_title_line", lines = { "rse_guide_line_1", "rse_guide_line_2", "rse_guide_line_3" } },
        { title = "rse_guide_title_logs", lines = { "rse_guide_logs_1", "rse_guide_logs_2", "rse_guide_logs_3" } },
        { title = "rse_guide_title_crossing", lines = { "rse_guide_crossing_1", "rse_guide_crossing_2" } },
        { title = "rse_guide_title_river", lines = { "rse_guide_river_1", "rse_guide_river_2", "rse_guide_river_3" } },
        { title = "rse_guide_title_tree", lines = { "rse_guide_tree_1", "rse_guide_tree_2" } },
        { title = "rse_guide_title_flock", lines = { "rse_guide_flock_1", "rse_guide_flock_2", "rse_guide_flock_3" } },
        { title = "rse_guide_title_kit", lines = { "rse_guide_kit_1", "rse_guide_kit_2", "rse_guide_kit_3" } },
        { title = "rse_guide_title_markers", lines = { "rse_guide_markers_1", "rse_guide_markers_2", "rse_guide_markers_3", "rse_guide_markers_4" } },
        { title = "rse_guide_title_settings", lines = { "rse_guide_settings_1", "rse_guide_settings_2", "rse_guide_settings_3" } },
        { title = "rse_guide_title_mods", lines = { "rse_guide_mods_1", "rse_guide_mods_2", "rse_guide_mods_3", "rse_guide_mods_4" } }
    }
}

-- How the pages fit on screens. heights: for each page, the height of each of its lines; room: how much height a screen has for lines; gap: between two
-- lines. A page that doesn't fit goes on over the next screen, never splitting a line (a line taller than a screen gets one to itself). Returns the
-- screens in order: { page, first, last, part, parts }, with part 1 of parts for a page that fits.
function RseGuide.layout(heights, room, gap)
    local screens = {}
    for pageIndex, lineHeights in ipairs(heights) do
        local parts, first, used = {}, 1, 0
        for i, height in ipairs(lineHeights) do
            local need = i > first and gap + height or height
            if i > first and used + need > room then
                table.insert(parts, { page = pageIndex, first = first, last = i - 1 })
                first, used = i, height
            else
                used = used + need
            end
        end
        table.insert(parts, { page = pageIndex, first = first, last = #lineHeights })
        for n, part in ipairs(parts) do
            part.part, part.parts = n, #parts
            table.insert(screens, part)
        end
    end
    return screens
end

-- the screen `step` on from `screen`, stopping at the first and the last of `count` (the pages, before they have been laid out)
function RseGuide.turn(screen, step, count)
    return math.max(1, math.min(count or #RseGuide.PAGES, screen + step))
end
