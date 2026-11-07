-- Roadside Emergencies: the look, in one place (P11 in docs/UI_RESEARCH.md; the same names as docs/mockups/tokens.css). Look B, Z's pick at Gate U:
-- the game's dark panels and font, the hazard orange of the mod icon as the accent, red only for what is urgent. Engine-free: colours are { r, g, b, a }.
-- Contrast on the game's dialog grey (#222222): accent 5.5:1, urgent text 5.4:1, muted text 7.6:1. White on orange fails (2.8:1), so text on an orange
-- fill is dark, and a selected row is an orange edge on a dark tint with white text.

RseTheme = {
    PANEL = { 0, 0, 0, 0.78 },                -- drawn panels over the world
    ACCENT = { 1, 0.439, 0.118, 1 },          -- #FF701E, the icon's orange
    ACCENT_TINT = { 1, 0.439, 0.118, 0.22 },  -- behind a selected row, under white text
    TEXT_ON_ACCENT = { 0.078, 0.078, 0.078, 1 },
    URGENT_FILL = { 0.808, 0.086, 0.11, 1 },  -- #CE161C, the icon's red: a fill, with white text on it
    URGENT_TEXT = { 1, 0.42, 0.42, 1 },       -- #FF6B6B: red text on dark
    DONE = { 0.529, 0.706, 0, 1 },            -- the game's own green, always with a mark and a word
    TEXT = { 1, 1, 1, 1 },
    TEXT_MUTED = { 0.722, 0.722, 0.722, 1 },  -- #B8B8B8
    EDGE = 4,                                 -- pixels at 1920 x 1080: a selected row's orange edge

    -- words and marks
    F1_PREFIX = "RSE: ",                      -- every line of ours in the F1 help (Z: it matches the console commands)
    -- every warning carries a word in front (rse_warning), as well as the game's orange (Z). The ⚠ Z asked for can't be drawn in text: the game's font
    -- (shared/font/defaultFont.font) has no warning sign, no triangle and no bullet, and leaves it out without a gap. Our own panels can draw it as a picture
}
