describe("RseGaitRules", function()
    it("keeps a foot moving steadily back on the ground, then swings it forward in the air", function()
        local duty = RseConfig.GAIT_DUTY
        local swing, lift = RseGaitRules.leg(0, duty)
        expectEqual(swing, -1, "starts reaching forward")
        expectEqual(lift, 0)
        swing, lift = RseGaitRules.leg(duty / 2, duty)
        expectNear(swing, 0, 0.001, "under the body halfway")
        expectEqual(lift, 0, "still on the ground")
        swing, lift = RseGaitRules.leg((1 + duty) / 2, duty)
        expectNear(swing, 0, 0.001, "under the body again, on the way forward")
        expectNear(lift, 1, 0.001, "highest in the air")
    end)

    it("joins up at the end of the cycle, with no jump", function()
        local duty = RseConfig.GAIT_DUTY
        expectNear(RseGaitRules.leg(0.9999, duty), RseGaitRules.leg(0, duty), 0.01)
        expectNear(RseGaitRules.leg(duty - 0.0001, duty), RseGaitRules.leg(duty, duty), 0.01, "from ground to air")
    end)

    it("has no snap in speed where a foot lifts or lands", function()
        local duty = RseConfig.GAIT_DUTY
        local e = 0.00002
        local onGround = (RseGaitRules.leg(duty - e, duty) - RseGaitRules.leg(duty - 2 * e, duty)) / e
        local lifting = (RseGaitRules.leg(duty + e, duty) - RseGaitRules.leg(duty, duty)) / e
        expectNear(lifting, onGround, 0.05, "lifting")
        local landing = (RseGaitRules.leg(1 - e, duty) - RseGaitRules.leg(1 - 2 * e, duty)) / e
        expectNear(landing, onGround, 0.05, "landing")
    end)

    it("lifts a foot gently: barely off the ground at the start of the swing", function()
        local duty = RseConfig.GAIT_DUTY
        local _, lift = RseGaitRules.leg(duty + 0.01, duty)
        expectTrue(lift < 0.02, "gently")
    end)

    it("moves the legs one after another, a quarter of a cycle apart", function()
        local phases = RseGaitRules.PHASES
        expectEqual(phases.frontLeft - phases.hindLeft, 0.25)
        expectEqual(phases.hindRight - phases.frontLeft, 0.25)
        expectEqual(phases.frontRight - phases.hindRight, 0.25)
    end)

    it("takes longer steps when faster, within what a leg can do", function()
        local _, slow = RseGaitRules.stride(0.4, 0.8, RseConfig)
        local _, walking = RseGaitRules.stride(1.2, 0.8, RseConfig)
        local _, flatOut = RseGaitRules.stride(7, 0.8, RseConfig)
        expectTrue(slow > 0 and walking > slow, "longer")
        expectNear(flatOut, 0.8 * RseConfig.GAIT_STRIDE_MAX, 0.001, "limited")
        expectEqual((RseGaitRules.stride(7, 0.8, RseConfig)), RseConfig.GAIT_CYCLES_MAX, "and limited in speed")
    end)

    it("doesn't slide: a foot on the ground moves back as fast as the body moves forward", function()
        for _, speed in ipairs({ 0.4, 1.1 }) do
            local cycles, reach = RseGaitRules.stride(speed, 0.8, RseConfig)
            local secondsDown = RseConfig.GAIT_DUTY / cycles
            expectNear(2 * reach / secondsDown, speed, 0.001, tostring(speed))
        end
    end)

    it("gives a big animal slower, longer steps", function()
        local sheepCycles, sheepReach = RseGaitRules.stride(0.4, 0.8, RseConfig)
        local cowCycles, cowReach = RseGaitRules.stride(0.4, 1.15, RseConfig)
        expectTrue(cowCycles < sheepCycles, "slower")
        expectTrue(cowReach > sheepReach, "longer")
    end)

    -- where the joints end up in the side view, turning as the game does: +a moves what lies below backward
    local function turned(z, y, angle)
        local c, s = math.cos(angle), math.sin(angle)
        return y * s + z * c, y * c - z * s
    end

    local function forward(points, a1, a2, a3)
        local x1, y1 = points[1][1], points[1][2]
        local z, y = turned(points[2][1] - x1, points[2][2] - y1, a1)
        local kz, ky = x1 + z, y1 + y
        z, y = turned(points[3][1] - points[2][1], points[3][2] - points[2][2], a1 + a2)
        local hz, hy = kz + z, ky + y
        z, y = turned(points[4][1] - points[3][1], points[4][2] - points[3][2], a1 + a2 + a3)
        return hz + z, hy + y
    end

    local hind = { { -0.5, 0.8 }, { -0.42, 0.52 }, { -0.56, 0.3 }, { -0.52, 0.08 } }
    local front = { { 0.5, 0.75 }, { 0.36, 0.5 }, { 0.47, 0.28 }, { 0.47, 0.08 } }

    it("stays at rest when nothing moves the foot", function()
        for _, points in ipairs({ hind, front }) do
            local a1, a2, a3, a4 = RseGaitRules.solveLeg(RseGaitRules.restLeg(points, points == front), 0, 0, 0, 0)
            expectNear(a1, 0, 0.0001)
            expectNear(a2, 0, 0.0001)
            expectNear(a3, 0, 0.0001)
            expectNear(a4, 0, 0.0001)
        end
    end)

    it("puts the foot where it was asked to go", function()
        for _, points in ipairs({ hind, front }) do
            local rest = RseGaitRules.restLeg(points, points == front)
            for _, offset in ipairs({ { 0.1, 0 }, { -0.1, 0 }, { 0.05, 0.08 }, { -0.12, 0.03 }, { 0, 0.1 } }) do
                for _, cannon in ipairs({ 0, 0.3, -0.2 }) do
                    local a1, a2, a3 = RseGaitRules.solveLeg(rest, offset[1], offset[2], cannon, 0)
                    local z, y = forward(points, a1, a2, a3)
                    expectNear(z, points[4][1] + offset[1], 0.0001, "forward")
                    expectNear(y, points[4][2] + offset[2], 0.0001, "up")
                end
            end
        end
    end)

    it("keeps the hoof flat on the ground, whatever the leg above it does", function()
        local rest = RseGaitRules.restLeg(hind, false)
        local a1, a2, a3, a4 = RseGaitRules.solveLeg(rest, 0.12, 0, 0.2, 0)
        expectNear(a1 + a2 + a3 + a4, 0, 0.0001)
    end)

    it("bends the middle joint the way the rest pose does, and by default a knee forward and an elbow back", function()
        local a1 = RseGaitRules.solveLeg(RseGaitRules.restLeg(hind, false), 0, 0.1, 0, 0)
        local b1 = RseGaitRules.solveLeg(RseGaitRules.restLeg(hind, true), 0, 0.1, 0, 0)
        expectNear(a1, b1, 0.0001, "the rest pose decides")
        local straight = { { 0, 0.8 }, { 0, 0.5 }, { 0, 0.2 }, { 0, 0 } }
        expectEqual(RseGaitRules.restLeg(straight, false).side, 1)
        expectEqual(RseGaitRules.restLeg(straight, true).side, -1)
    end)

    it("doesn't break on a foot out of reach", function()
        local a1, a2, a3, a4 = RseGaitRules.solveLeg(RseGaitRules.restLeg(hind, false), 5, -5, 0, 0)
        for _, angle in ipairs({ a1, a2, a3, a4 }) do
            expectTrue(angle == angle and math.abs(angle) < 10, "a real number")
        end
    end)

    it("leaves a joint alone at no angle", function()
        local x, y, z, w = RseGaitRules.axisAngle(1, 0, 0, 0)
        expectEqual(x, 0)
        expectEqual(y, 0)
        expectEqual(z, 0)
        expectEqual(w, 1)
        local rx, ry, rz, rw = RseGaitRules.multiply(0.1, 0.2, 0.3, 0.9, x, y, z, w)
        expectNear(rx, 0.1, 0.0001)
        expectNear(ry, 0.2, 0.0001)
        expectNear(rz, 0.3, 0.0001)
        expectNear(rw, 0.9, 0.0001)
    end)

    it("adds up turns about the same axis", function()
        local ax, ay, az, aw = RseGaitRules.axisAngle(0, 1, 0, 0.3)
        local bx, by, bz, bw = RseGaitRules.axisAngle(0, 1, 0, 0.5)
        local x, y, z, w = RseGaitRules.multiply(ax, ay, az, aw, bx, by, bz, bw)
        local ex, ey, ez, ew = RseGaitRules.axisAngle(0, 1, 0, 0.8)
        expectNear(x, ex, 0.0001)
        expectNear(y, ey, 0.0001)
        expectNear(z, ez, 0.0001)
        expectNear(w, ew, 0.0001)
    end)

    it("turns in the right order: a quarter turn about x, then about y within it", function()
        local q = math.sqrt(0.5)
        local x, y, z, w = RseGaitRules.multiply(q, 0, 0, q, 0, q, 0, q)
        expectNear(x, 0.5, 0.0001)
        expectNear(y, 0.5, 0.0001)
        expectNear(z, 0.5, 0.0001)
        expectNear(w, 0.5, 0.0001)
    end)
end)
