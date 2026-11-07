-- Roadside Emergencies: drawing in the theme's colours (RseTheme), for the panels the mod draws itself (settings and guide, the kit strip). One overlay for
-- the hazard stripe, made once and reused every frame.

RseDraw = {
    stripe = nil,
    stripeFailed = false,
    images = {}        -- file -> its overlay, made the first time it is drawn; false if it could not be made
}

function RseDraw.rect(color, x, y, width, height)
    drawFilledRect(x, y, width, height, color[1], color[2], color[3], color[4])
end

function RseDraw.textColor(color, alpha)
    setTextColor(color[1], color[2], color[3], alpha or color[4])
end

-- the thin hazard stripe of look B along a panel's top edge
function RseDraw.stripeAt(x, y, width, height)
    if RseDraw.stripeFailed then
        return
    end
    if RseDraw.stripe == nil then
        local ok, overlay = pcall(Overlay.new, Utils.getFilename("icons/ui_stripe.dds", RoadsideEmergencies.MOD_DIR), 0, 0, 0, 0)
        if not ok or overlay == nil then
            RseDraw.stripeFailed = true
            return
        end
        RseDraw.stripe = overlay
    end
    RseDraw.stripe:setPosition(x, y)
    RseDraw.stripe:setDimension(width, height)
    RseDraw.stripe:render()
end

-- a selected row: an orange edge on a dark orange tint, so white text on it stays readable (white on orange fails)
function RseDraw.selectedRow(x, y, width, height, pixelX)
    RseDraw.rect(RseTheme.ACCENT_TINT, x, y, width, height)
    RseDraw.rect(RseTheme.ACCENT, x, y, RseTheme.EDGE * pixelX, height)
end

-- A picture of the mod's (a file under the mod folder), its lower left corner at x, y, tinted by color, turned by rotation radians about its middle
-- (Overlay:setRotation; counterclockwise, as angles on screen go: unproven until the call panel's arrow is seen). Returns false if it can't be drawn, so
-- the caller can leave room for it or not.
function RseDraw.image(file, x, y, width, height, color, rotation)
    local overlay = RseDraw.images[file]
    if overlay == false then
        return false
    end
    if overlay == nil then
        local ok, made = pcall(Overlay.new, Utils.getFilename(file, RoadsideEmergencies.MOD_DIR), 0, 0, 0, 0)
        if not ok or made == nil then
            RseDraw.images[file] = false
            RseLog.problem("could not load the picture %s", file)
            return false
        end
        overlay = made
        RseDraw.images[file] = overlay
    end
    overlay:setPosition(x, y)
    overlay:setDimension(width, height)
    color = color or { 1, 1, 1, 1 }
    overlay:setColor(color[1], color[2], color[3], color[4])
    if overlay.setRotation ~= nil then
        overlay:setRotation(rotation or 0, width / 2, height / 2)
    end
    overlay:render()
    return true
end

-- A warning that stays on the screen while it applies (Z: the whole time you are too close to live wires): a red banner across the upper middle of the
-- screen, look B's hazard stripe along its top, the big warning sign at its left (a picture: the game's font has none), a bold title and a second line.
-- Sizes in pixels at 1920 x 1080.
local BANNER_WIDTH, BANNER_HEIGHT, BANNER_TOP, BANNER_PAD, BANNER_SIGN, BANNER_STRIPE = 860, 84, 200, 18, 56, 6
local BANNER_TITLE_SIZE, BANNER_LINE_SIZE = 0.024, 0.0165

function RseDraw.warningBanner(title, line)
    local sx, sy = (1 / 1920) * ((16 / 9) / g_screenAspectRatio), 1 / 1080
    local width, height = BANNER_WIDTH * sx, BANNER_HEIGHT * sy
    local left, top = 0.5 - width / 2, 1 - BANNER_TOP * sy
    local bottom = top - height
    RseDraw.rect({ RseTheme.URGENT_FILL[1], RseTheme.URGENT_FILL[2], RseTheme.URGENT_FILL[3], 0.94 }, left, bottom, width, height)
    RseDraw.stripeAt(left, top - BANNER_STRIPE * sy, width, BANNER_STRIPE * sy)
    local textX = left + BANNER_PAD * sx
    local signY = bottom + (height - BANNER_STRIPE * sy - BANNER_SIGN * sy) / 2
    if RseDraw.image("icons/ui_warning.dds", textX, signY, BANNER_SIGN * sx, BANNER_SIGN * sy, { 1, 1, 1, 1 }) then
        textX = textX + (BANNER_SIGN + 16) * sx
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    RseDraw.textColor(RseTheme.TEXT)
    setTextBold(true)
    renderText(textX, bottom + 40 * sy, BANNER_TITLE_SIZE, title)
    setTextBold(false)
    renderText(textX, bottom + 14 * sy, BANNER_LINE_SIZE, line)
    setTextColor(1, 1, 1, 1)
end

function RseDraw.unload()
    if RseDraw.stripe ~= nil and RseDraw.stripe.delete ~= nil then
        pcall(RseDraw.stripe.delete, RseDraw.stripe)
    end
    for _, overlay in pairs(RseDraw.images) do
        if overlay and overlay.delete ~= nil then
            pcall(overlay.delete, overlay)
        end
    end
    RseDraw.stripe, RseDraw.stripeFailed, RseDraw.images = nil, false, {}
end
