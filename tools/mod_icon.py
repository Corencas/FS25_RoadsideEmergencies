"""The mod's icon, drawn with Pillow: 512x512, the size nearly every installed mod uses.

Everything is drawn at four times the size and scaled down, so edges stay clean. One function per design; DESIGNS lists them and
CHOICE is the one the mod ships.

Usage: python tools/mod_icon.py <folder>     writes every design as a PNG there, plus a sheet to compare them, at full size and as small as the game lists them
       python tools/mod_icon.py --ship       writes CHOICE into the mod: the PNG as a source, and the DDS (BC1, no mipmaps, like nearly every installed mod)
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 512
SCALE = 4
FULL = SIZE * SCALE


def curve(points, closed=True, steps=14):
    """A smooth line through points (Catmull-Rom). A point given twice in a row makes a sharp corner."""
    count = len(points)
    line = []
    last = count if closed else count - 1
    for i in range(last):
        if closed:
            p0, p1, p2, p3 = points[(i - 1) % count], points[i], points[(i + 1) % count], points[(i + 2) % count]
        else:
            p0, p1, p2, p3 = points[max(i - 1, 0)], points[i], points[i + 1], points[min(i + 2, count - 1)]
        for step in range(steps):
            t = step / steps
            t2, t3 = t * t, t * t * t
            line.append(tuple(0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                     + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    if not closed:
        line.append(points[-1])
    return line


def placed(points, x, y, size):
    """Points given in a box of 100 units, placed at x, y (top left, in icon pixels), size pixels wide."""
    return [((x + px * size / 100) * SCALE, (y + py * size / 100) * SCALE) for px, py in points]


def taper(d, points, w0, w1, color):
    """A line through points, narrowing from width w0 to w1, for antlers. Widths in pixels of the full canvas."""
    line = curve(points, closed=False)
    for i, (x, y) in enumerate(line):
        w = w0 + (w1 - w0) * i / max(len(line) - 1, 1)
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=color)


LEAPING_BODY = [
    # nose, forehead, ear
    (91.5, 27), (91.5, 27), (88, 23.5), (83, 20), (78, 18), (71, 13), (71, 13), (73, 18), (75, 21),
    # neck, back, rump, tail
    (71, 27), (66, 33.5), (60, 38), (50, 41.5), (40, 44), (31, 45.5), (25, 46), (21, 44), (15, 38), (15, 38), (17, 44), (19, 48),
    # the rear hind leg, stretched out behind
    (19, 53), (15, 59), (9, 67), (4, 76), (0, 84), (0, 84), (3, 85.5), (3, 85.5), (8, 77), (14, 69), (20, 63), (23, 61),
    # the other hind leg
    (19, 70), (13, 79), (8, 88), (5, 96), (5, 96), (8.5, 97), (8.5, 97), (13, 89), (19, 81), (26, 70), (32, 60),
    # belly
    (42, 55.5), (52, 54), (58, 54.5),
    # the lower foreleg, tucked up
    (62, 60), (66, 66), (74, 70), (84, 70), (84, 70), (84.5, 66.5), (84.5, 66.5), (75, 66), (69, 61), (66, 55.5),
    # the upper foreleg
    (72, 56.5), (78, 58), (90, 55), (90, 55), (90, 51.5), (90, 51.5), (80, 53.5), (73, 51), (70, 47),
    # chest, throat, chin
    (71, 41), (75, 34), (80, 29.5), (85, 29.5), (90, 29),
]
LEAPING_ANTLERS = [
    [(77, 18), (76, 11), (71, 5), (64, 2)],
    [(75.6, 10), (79, 5), (79.5, 0.5)],
    [(71, 5), (71.5, 1.5), (73, -1.5)],
    [(80, 18), (83, 12.5), (88, 9.5), (93, 9.5)],
    [(84, 11.5), (86, 7), (88.5, 4.5)],
]


def leaping_deer(d, x, y, size, color):
    """A leaping buck facing right, as on a crossing sign."""
    d.polygon(curve(placed(LEAPING_BODY, x, y, size)), fill=color)
    unit = size * SCALE / 100
    for antler in LEAPING_ANTLERS:
        taper(d, placed(antler, x, y, size), 1.9 * unit, 0.8 * unit, color)


def scaled(*values):
    return [value * SCALE for value in values]


def gradient(stops):
    """A full canvas fading down through stops: [(share of the height, colour), ...]."""
    column = Image.new("RGB", (1, FULL))
    pixels = column.load()
    for y in range(FULL):
        share = y / (FULL - 1)
        for (s0, c0), (s1, c1) in zip(stops, stops[1:]):
            if s0 <= share <= s1:
                t = (share - s0) / max(s1 - s0, 1e-6)
                pixels[0, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(3))
                break
    return column.resize((FULL, FULL))


def glow(img, x, y, radius, color, strength=1.0):
    """A soft round light at x, y, added to the image. The game's radial gradient reaches white at 181 of its 256, hence the 181."""
    side = int(radius * 2 * SCALE)
    table = [int(255 * strength * max(0.0, 1 - v / 181) ** 2) for v in range(256)]
    mask = Image.radial_gradient("L").resize((side, side), Image.BICUBIC).point(table)
    img.paste(Image.new("RGB", (side, side), color), (int((x - radius) * SCALE), int((y - radius) * SCALE)), mask)


def road(d, horizon, top_half, surface, line, edge=None):
    """A road running away to the horizon, with a dashed centre line that shrinks with the distance."""
    d.polygon(scaled(256 - top_half, horizon, 256 + top_half, horizon, 512 + 90, 512, -90, 512), fill=surface)
    if edge is not None:
        for side in (-1, 1):
            d.polygon(scaled(256 + side * (top_half - 1), horizon, 256 + side * top_half, horizon, 256 + side * 346, 512, 256 + side * 316, 512), fill=edge)
    depth = 512 - horizon
    for start, end in ((0.04, 0.09), (0.16, 0.26), (0.38, 0.56), (0.76, 1.0)):
        y0, y1 = horizon + depth * start, horizon + depth * end
        w0, w1 = 1 + 13 * start, 1 + 13 * end
        d.polygon(scaled(256 - w0, y0, 256 + w0, y0, 256 + w1, y1, 256 - w1, y1), fill=line)


def tree_line(d, horizon, color):
    """A dark line of trees along the horizon."""
    xs = [-10, 18, 40, 66, 92, 120, 150, 176, 204, 228, 284, 310, 338, 362, 392, 420, 446, 472, 500, 524]
    heights = [24, 38, 26, 44, 30, 36, 24, 40, 28, 18, 18, 32, 42, 26, 38, 28, 46, 30, 40, 26]
    points = [(-10, horizon)]
    for x, h in zip(xs, heights):
        points.extend([(x - 12, horizon - h * 0.55), (x, horizon - h), (x + 12, horizon - h * 0.55)])
    points.append((524, horizon))
    d.polygon(scaled(*[v for p in points for v in p]), fill=color)


def dusk(horizon):
    """The sky at dusk down to the horizon, dark farmland below it."""
    share = horizon / 512
    return gradient([(0, (18, 28, 56)), (share * 0.68, (66, 62, 96)), (share, (236, 134, 64)), (share + 0.001, (46, 60, 44)), (1, (26, 36, 28))])


def cone(d, x, base_y, height, body=(242, 106, 26), shade=(198, 76, 16), band=(244, 244, 238)):
    """A traffic cone: its base plate, its body, and two reflective bands."""
    half = height * 0.31
    top = base_y - height
    plate = half * 1.45
    d.rounded_rectangle(scaled(x - plate, base_y - height * 0.075, x + plate, base_y), radius=height * 0.03 * SCALE, fill=(22, 22, 24))

    def edge(share):
        return half * 0.14 + (half - half * 0.14) * share

    bottom = base_y - height * 0.06
    d.polygon(scaled(x - edge(0), top, x + edge(0), top, x + edge(1), bottom, x - edge(1), bottom), fill=body)
    d.polygon(scaled(x + edge(0) * 0.3, top, x + edge(0), top, x + edge(1), bottom, x + edge(1) * 0.32, bottom), fill=shade)
    d.ellipse(scaled(x - edge(0), top - edge(0) * 0.5, x + edge(0), top + edge(0) * 0.5), fill=body)
    for a, b in ((0.3, 0.46), (0.62, 0.78)):
        ya, yb = top + (bottom - top) * a, top + (bottom - top) * b
        d.polygon(scaled(x - edge(a), ya, x + edge(a), ya, x + edge(b), yb, x - edge(b), yb), fill=band)
        d.polygon(scaled(x + edge(a) * 0.32, ya, x + edge(a), ya, x + edge(b), yb, x + edge(b) * 0.32, yb), fill=(208, 208, 204))


def rounded_triangle(d, points, radius, color):
    """A filled triangle with round corners: the points are the centres of the corner circles."""
    d.polygon([v for p in points for v in p], fill=color)
    for i in range(3):
        a, b = points[i], points[(i + 1) % 3]
        d.line([a, b], fill=color, width=int(radius * 2))
        d.ellipse((a[0] - radius, a[1] - radius, a[0] + radius, a[1] + radius), fill=color)


def sign():
    """The deer-crossing sign: it fills the icon, and the deer is a smooth outline."""
    img = gradient([(0, (58, 72, 82)), (1, (24, 30, 35))])
    layer = Image.new("RGBA", (FULL, FULL), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    half = 176 * SCALE
    centre = FULL // 2
    for inset, radius, color in ((0, 28, (14, 14, 14, 255)), (8, 23, (254, 204, 18, 255)), (19, 14, (14, 14, 14, 255)), (25, 10, (254, 204, 18, 255))):
        h = half - inset * SCALE
        d.rounded_rectangle((centre - h, centre - h, centre + h, centre + h), radius=radius * SCALE, fill=color)
    layer = layer.rotate(45, resample=Image.BICUBIC, center=(centre, centre))
    img.paste(layer, (0, 0), layer)
    leaping_deer(ImageDraw.Draw(img), 136, 131, 248, (14, 14, 14))
    return img


def cones():
    """A lane being closed at dusk: a line of cones running away down the road, an amber beacon at the far end."""
    horizon = 226
    img = dusk(horizon)
    d = ImageDraw.Draw(img)
    tree_line(d, horizon, (20, 22, 36))
    road(d, horizon, 22, (40, 43, 52), (238, 196, 70), (214, 214, 206))
    glow(img, 262, horizon - 3, 64, (255, 176, 40), 0.95)
    glow(img, 262, horizon - 3, 16, (255, 244, 200), 1.0)
    d = ImageDraw.Draw(img)
    for x, base, height in ((246, 248, 16), (232, 268, 28), (208, 306, 52), (164, 372, 100), (92, 490, 196)):
        cone(d, x, base, height)
    return img


def triangle():
    """The red warning triangle every driver knows, standing in the road at dusk."""
    horizon = 256
    img = dusk(horizon)
    d = ImageDraw.Draw(img)
    tree_line(d, horizon, (20, 22, 36))
    road(d, horizon, 26, (42, 45, 54), (238, 196, 70), (214, 214, 206))
    glow(img, 256, horizon - 2, 110, (255, 170, 50), 0.6)
    d = ImageDraw.Draw(img)
    # the stand
    d.polygon(scaled(214, 424, 298, 424, 324, 448, 188, 448), fill=(26, 26, 28))
    d.polygon(scaled(160, 440, 352, 440, 352, 452, 160, 452), fill=(26, 26, 28))
    # the frame: red, with an orange reflective stripe, hollow inside
    outer = [(256 * SCALE, 94 * SCALE), (416 * SCALE, 408 * SCALE), (96 * SCALE, 408 * SCALE)]
    rounded_triangle(d, outer, 16 * SCALE, (206, 22, 28))
    stripe = [(256 * SCALE, 130 * SCALE), (390 * SCALE, 394 * SCALE), (122 * SCALE, 394 * SCALE)]
    rounded_triangle(d, stripe, 9 * SCALE, (255, 112, 30))
    # the hollow middle shows what is behind it
    behind = dusk(horizon)
    behind_draw = ImageDraw.Draw(behind)
    tree_line(behind_draw, horizon, (20, 22, 36))
    road(behind_draw, horizon, 26, (42, 45, 54), (238, 196, 70), (214, 214, 206))
    glow(behind, 256, horizon - 2, 110, (255, 170, 50), 0.6)
    mask = Image.new("L", (FULL, FULL), 0)
    rounded_triangle(ImageDraw.Draw(mask), [(256 * SCALE, 196 * SCALE), (340 * SCALE, 360 * SCALE), (172 * SCALE, 360 * SCALE)], 5 * SCALE, 255)
    img.paste(behind, (0, 0), mask)
    return img


DESIGNS = {"sign": sign, "cones": cones, "triangle": triangle}
CHOICE = "triangle"


def finished(name):
    return DESIGNS[name]().resize((SIZE, SIZE), Image.LANCZOS)


def ship():
    target = Path(__file__).resolve().parent.parent / "mod" / "icon_roadsideEmergencies"
    image = finished(CHOICE)
    image.save(target.with_suffix(".png"))
    image.convert("RGB").save(target.with_suffix(".dds"), pixel_format="DXT1")
    print("shipped", CHOICE, "to", target.with_suffix(".dds"))


def main():
    if sys.argv[1] == "--ship":
        ship()
        return
    folder = Path(sys.argv[1])
    folder.mkdir(parents=True, exist_ok=True)
    small = 128
    sheet = Image.new("RGB", ((SIZE + 24) * len(DESIGNS) + 24, SIZE + small + 72), (64, 64, 64))
    for i, name in enumerate(DESIGNS):
        image = finished(name)
        image.save(folder / ("icon_%s.png" % name))
        sheet.paste(image, (24 + i * (SIZE + 24), 24))
        sheet.paste(image.resize((small, small), Image.LANCZOS), (24 + i * (SIZE + 24), SIZE + 48))
    sheet.save(folder / "icon_options.png")
    print("wrote", folder / "icon_options.png")


if __name__ == "__main__":
    main()
