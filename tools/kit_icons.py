"""Flat pictures of the scene kit items, for the on-screen strip (make_icons.py).

Same approach as animal_icons.py: drawn large on a transparent canvas with a soft ground shadow, scaled down. Simple and
readable at the small size the strip shows them.
"""
from PIL import Image, ImageDraw, ImageFilter

BIG = 1024
ORANGE = (236, 96, 28, 255)
ORANGE_DARK = (192, 70, 18, 255)
WHITE = (244, 244, 240, 255)
WOOD = (224, 190, 134, 255)
WOOD_DARK = (178, 140, 90, 255)
TAPE_RED = (222, 72, 34, 255)
TAPE_WHITE = (238, 238, 232, 255)


def canvas(shadow_box):
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(shadow_box, fill=(0, 0, 0, 110))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(26)))
    return img, ImageDraw.Draw(img)


def draw_cone(d, cx, base_y, scale=1.0):
    """A traffic cone: square foot, tapering body, two white bands."""
    def s(value):
        return value * scale

    d.rounded_rectangle((cx - s(250), base_y - s(62), cx + s(250), base_y), radius=int(s(26)), fill=ORANGE_DARK)
    top_y, top_w, bottom_y, bottom_w = base_y - s(700), s(42), base_y - s(44), s(182)

    def width_at(y):
        return top_w + (bottom_w - top_w) * (y - top_y) / (bottom_y - top_y)

    d.polygon([(cx - top_w, top_y), (cx + top_w, top_y), (cx + bottom_w, bottom_y), (cx - bottom_w, bottom_y)], fill=ORANGE)
    d.rounded_rectangle((cx - top_w, top_y - s(16), cx + top_w, top_y + s(30)), radius=int(s(16)), fill=ORANGE)
    for band_top, band_bottom in ((top_y + s(160), top_y + s(270)), (top_y + s(380), top_y + s(490))):
        d.polygon([(cx - width_at(band_top), band_top), (cx + width_at(band_top), band_top),
                   (cx + width_at(band_bottom), band_bottom), (cx - width_at(band_bottom), band_bottom)], fill=WHITE)


def cone():
    img, d = canvas((222, 820, 802, 930))
    draw_cone(d, 512, 880)
    return img


def barricade():
    """A wooden barricade from the front: two crossed leg pairs and two planks."""
    img, d = canvas((90, 830, 934, 930))
    for cx in (250, 774):
        d.line((cx - 120, 880, cx + 120, 300), fill=WOOD_DARK, width=64)
        d.line((cx + 120, 880, cx - 120, 300), fill=WOOD, width=64)
    d.rounded_rectangle((70, 400, 954, 490), radius=12, fill=WOOD)
    d.rounded_rectangle((70, 400, 954, 412), radius=6, fill=(240, 212, 164, 255))
    d.rounded_rectangle((70, 530, 954, 610), radius=12, fill=WOOD_DARK)
    for x in (250, 774):
        for y in (445, 570):
            d.ellipse((x - 13, y - 13, x + 13, y + 13), fill=(116, 88, 54, 255))
    return img


def cone_tape():
    """A cone with barrier tape running out to both sides."""
    img, d = canvas((262, 830, 762, 930))
    y = 440
    segments = 10
    width = 1000 / segments
    for i in range(segments):
        x0 = 12 + i * width
        d.rectangle((x0, y, x0 + width, y + 66), fill=TAPE_RED if i % 2 == 0 else TAPE_WHITE)
    draw_cone(d, 512, 880, 0.86)
    d.rectangle((512 - 96, y, 512 + 96, y + 66), fill=TAPE_RED)
    return img


KITS = {"cone": cone, "barricade": barricade, "coneTape": cone_tape}


def kit_icon(item, size=256):
    return KITS[item]().resize((size, size), Image.LANCZOS)
