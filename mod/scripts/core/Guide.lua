-- Roadside Emergencies: the in-game guide (Z, 2026-11-02): what the mod does and how to use it, in the settings panel's style. It opens once by itself
-- the first time you are on foot in a savegame, and comes back any time from the panel (H). Engine-free: only which texts go on which page.

RseGuide = {
    PAGES = {
        { title = "rse_guide_title_welcome", lines = { "rse_guide_welcome_1", "rse_guide_welcome_2", "rse_guide_welcome_3" } },
        { title = "rse_guide_title_calls", lines = { "rse_guide_calls_1", "rse_guide_calls_2", "rse_guide_calls_3", "rse_guide_calls_4" } },
        { title = "rse_guide_title_animals", lines = { "rse_guide_animals_1", "rse_guide_animals_2", "rse_guide_animals_3", "rse_guide_animals_4" } },
        { title = "rse_guide_title_strap", lines = { "rse_guide_strap_1", "rse_guide_strap_2", "rse_guide_strap_3" } },
        { title = "rse_guide_title_wrecks", lines = { "rse_guide_wrecks_1", "rse_guide_wrecks_2", "rse_guide_wrecks_3", "rse_guide_wrecks_4" } },
        { title = "rse_guide_title_loads", lines = { "rse_guide_loads_1", "rse_guide_loads_2", "rse_guide_loads_3" } },
        { title = "rse_guide_title_line", lines = { "rse_guide_line_1", "rse_guide_line_2", "rse_guide_line_3" } },
        { title = "rse_guide_title_loose", lines = { "rse_guide_loose_1", "rse_guide_loose_2", "rse_guide_loose_3" } },
        { title = "rse_guide_title_kit", lines = { "rse_guide_kit_1", "rse_guide_kit_2" } },
        { title = "rse_guide_title_markers", lines = { "rse_guide_markers_1", "rse_guide_markers_2", "rse_guide_markers_3" } },
        { title = "rse_guide_title_mods", lines = { "rse_guide_mods_1", "rse_guide_mods_2", "rse_guide_mods_3", "rse_guide_mods_4" } }
    }
}

-- the page `step` on from `page`, stopping at the first and the last
function RseGuide.turn(page, step)
    return math.max(1, math.min(#RseGuide.PAGES, page + step))
end
