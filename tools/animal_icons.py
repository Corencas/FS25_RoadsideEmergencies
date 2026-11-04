"""Flat illustrations of each carcass animal, for the per-animal fill-type icons (make_icons.py).

Every animal lies on its side, head on the ground to the left, eye closed, legs stretched out, on a soft shadow: the same
calm, readable style as the game's own fill-type icons, nothing gory. Drawn at 1024 px, fitted to the canvas, scaled down.
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter

BIG = 1024


def smooth(points, steps=16):
    """Closed Catmull-Rom curve through the control points (smooth outlines)."""
    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % n], points[(i + 2) % n]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    return out


def stroke(d, x0, y0, x1, y1, w, color):
    """A rounded bar (legs, horns, tails)."""
    d.line((x0, y0, x1, y1), fill=color, width=int(w))
    for x, y in ((x0, y0), (x1, y1)):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=color)


def leg(d, x0, y0, x1, y1, w, color, hoof, hoof_len=26):
    stroke(d, x0, y0, x1, y1, w, color)
    dx, dy = x1 - x0, y1 - y0
    length = (dx * dx + dy * dy) ** 0.5
    stroke(d, x1, y1, x1 + dx / length * hoof_len, y1 + dy / length * hoof_len, w + 2, hoof)


def closed_eye(d, x, y, r=20, color=(50, 36, 26, 255), width=7):
    d.arc((x - r, y - r * 0.75, x + r, y + r * 0.75), start=200, end=340, fill=color, width=width)


def new_canvas():
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((140, 705, 910, 805), fill=(0, 0, 0, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    return img, ImageDraw.Draw(img)


def patches_inside(img, outline, patches, color):
    """Draws the patch shapes, but only where they overlap the outline polygon (cow markings)."""
    layer = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for patch in patches:
        ld.polygon(smooth(patch, 10), fill=color)
    mask = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    alpha = ImageChops.multiply(layer.getchannel("A"), mask)
    layer.putalpha(alpha)
    img.alpha_composite(layer)


def fit(img, size):
    cropped = img.crop(img.getbbox())
    w, h = cropped.size
    side = int(max(w, h) * 1.12)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(cropped, ((side - w) // 2, (side - h) // 2))
    return square.resize((size, size), Image.LANCZOS)


# --- the animals -------------------------------------------------------------------------------------------------------

def deer():
    brown, dark, belly, hoof = (150, 98, 52, 255), (112, 70, 34, 255), (232, 208, 168, 255), (52, 38, 28, 255)
    img, d = new_canvas()
    leg(d, 420, 620, 260, 740, 34, dark, hoof)
    leg(d, 700, 620, 860, 735, 34, dark, hoof)
    d.polygon(smooth([(330, 500), (450, 462), (620, 455), (760, 470), (835, 515), (845, 590), (790, 650), (640, 678),
                      (470, 678), (380, 662), (300, 668), (230, 704), (150, 722), (110, 702), (122, 660), (190, 620),
                      (262, 575)]), fill=brown)
    d.polygon(smooth([(430, 640), (560, 625), (700, 630), (780, 610), (760, 655), (640, 678), (480, 676)]), fill=belly)
    d.polygon(smooth([(205, 605), (250, 560), (290, 545), (270, 590), (235, 615)], 10), fill=dark)
    closed_eye(d, 185, 655)
    d.ellipse((108, 683, 132, 705), fill=hoof)
    d.polygon(smooth([(815, 500), (865, 478), (880, 506), (845, 530)], 8), fill=belly)
    leg(d, 450, 640, 300, 760, 40, brown, hoof)
    leg(d, 740, 630, 900, 750, 40, brown, hoof)
    return img


def boar():
    fur, dark, ridge, hoof, snout = (104, 82, 66, 255), (78, 60, 48, 255), (58, 44, 36, 255), (40, 30, 24, 255), (150, 120, 110, 255)
    img, d = new_canvas()
    leg(d, 430, 640, 340, 735, 44, dark, hoof, 22)
    leg(d, 700, 640, 800, 730, 44, dark, hoof, 22)
    outline = smooth([(330, 520), (470, 470), (640, 462), (770, 490), (835, 545), (835, 620), (770, 672), (620, 690),
                      (460, 688), (360, 672), (260, 690), (170, 715), (110, 705), (115, 668), (190, 630), (270, 585)])
    d.polygon(outline, fill=fur)
    # bristly ridge along the back
    ridge_points = [(300, 560)]
    for i, x in enumerate(range(330, 800, 36)):
        ridge_points.append((x, 478 - 14 + (10 if i % 2 else -4) + (0 if x < 700 else (x - 700) * 0.35)))
    ridge_points += [(800, 510), (330, 540)]
    d.polygon(ridge_points, fill=ridge)
    d.ellipse((90, 676, 140, 726), fill=snout)                    # snout disc
    d.ellipse((104, 692, 112, 700), fill=ridge)
    d.ellipse((118, 692, 126, 700), fill=ridge)
    d.polygon([(150, 690), (178, 668), (168, 700)], fill=(245, 240, 225, 255))   # tusk
    d.polygon(smooth([(230, 610), (262, 568), (290, 560), (280, 600)], 8), fill=ridge)   # ear
    closed_eye(d, 200, 655, 16)
    stroke(d, 835, 560, 880, 600, 12, ridge)                       # thin tail
    leg(d, 460, 660, 380, 760, 50, fur, hoof, 22)
    leg(d, 730, 660, 820, 755, 50, fur, hoof, 22)
    return img


def pig():
    pink, dark, hoof, snout = (240, 168, 168, 255), (214, 138, 142, 255), (170, 100, 100, 255), (226, 140, 146, 255)
    img, d = new_canvas()
    leg(d, 430, 650, 360, 735, 46, dark, hoof, 18)
    leg(d, 690, 650, 770, 735, 46, dark, hoof, 18)
    d.polygon(smooth([(300, 540), (430, 470), (620, 455), (760, 480), (840, 545), (845, 625), (780, 680), (620, 700),
                      (450, 698), (330, 680), (240, 700), (160, 712), (120, 690), (130, 640), (200, 600)]), fill=pink)
    d.ellipse((92, 650, 150, 720), fill=snout)                     # snout disc
    d.ellipse((108, 672, 118, 690), fill=hoof)
    d.ellipse((124, 672, 134, 690), fill=hoof)
    d.polygon(smooth([(210, 600), (270, 560), (300, 600), (255, 640)], 10), fill=dark)   # floppy ear
    closed_eye(d, 190, 650, 16, (120, 70, 70, 255))
    d.arc((820, 500, 900, 580), start=180, end=470, fill=dark, width=14)     # curly tail
    leg(d, 460, 670, 400, 765, 52, pink, hoof, 18)
    leg(d, 720, 670, 790, 760, 52, pink, hoof, 18)
    return img


def sheep():
    wool, wool_dark, face, hoof = (240, 238, 228, 255), (214, 210, 196, 255), (58, 52, 48, 255), (40, 36, 32, 255)
    img, d = new_canvas()
    leg(d, 450, 650, 340, 745, 30, face, hoof, 18)
    leg(d, 700, 650, 810, 742, 30, face, hoof, 18)
    # woolly body: overlapping puffs
    for cx, cy, r in ((420, 560, 100), (530, 520, 110), (650, 520, 110), (760, 560, 95), (470, 630, 90), (600, 640, 95),
                      (720, 630, 90), (360, 610, 80)):
        d.ellipse((cx - r - 6, cy - r - 6, cx + r + 6, cy + r + 6), fill=wool_dark)
    for cx, cy, r in ((420, 560, 100), (530, 520, 110), (650, 520, 110), (760, 560, 95), (470, 630, 90), (600, 640, 95),
                      (720, 630, 90), (360, 610, 80)):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=wool)
    # dark face lying on the ground: a rounded, tapering head tucked against the wool
    d.polygon(smooth([(345, 585), (330, 650), (270, 690), (190, 718), (122, 722), (100, 700), (128, 668), (200, 628),
                      (270, 595)]), fill=face)
    d.polygon(smooth([(262, 598), (310, 560), (338, 572), (300, 615)], 8), fill=face)     # ear
    closed_eye(d, 210, 655, 16, (230, 225, 215, 255), 6)
    d.ellipse((112, 700, 128, 714), fill=(30, 26, 24, 255))                                 # nose
    leg(d, 480, 680, 380, 765, 34, face, hoof, 18)
    leg(d, 730, 680, 840, 762, 34, face, hoof, 18)
    return img


def goat():
    coat, dark, belly, hoof, horn = (226, 214, 190, 255), (186, 172, 148, 255), (246, 240, 226, 255), (60, 50, 44, 255), (150, 140, 128, 255)
    img, d = new_canvas()
    leg(d, 430, 630, 280, 742, 30, dark, hoof)
    leg(d, 700, 630, 850, 738, 30, dark, hoof)
    d.polygon(smooth([(330, 510), (450, 472), (620, 466), (750, 480), (820, 525), (828, 595), (775, 650), (630, 675),
                      (470, 675), (380, 660), (300, 668), (230, 700), (150, 718), (112, 698), (124, 658), (190, 618),
                      (262, 575)]), fill=coat)
    d.polygon(smooth([(440, 642), (570, 630), (700, 632), (770, 615), (750, 655), (630, 674), (480, 672)]), fill=belly)
    # horns sweeping back, a beard and an ear
    d.arc((200, 520, 330, 640), start=200, end=300, fill=horn, width=18)
    d.polygon(smooth([(120, 700), (100, 740), (125, 760), (140, 720)], 8), fill=dark)      # beard
    d.polygon(smooth([(215, 612), (262, 590), (285, 612), (240, 628)], 8), fill=dark)      # ear
    closed_eye(d, 185, 652)
    d.ellipse((108, 680, 128, 698), fill=hoof)
    d.polygon(smooth([(812, 512), (850, 470), (868, 488), (835, 525)], 8), fill=dark)     # short tail up
    leg(d, 460, 645, 320, 762, 36, coat, hoof)
    leg(d, 730, 640, 880, 752, 36, coat, hoof)
    return img


def cow():
    white, shade, black, hoof, muzzle, horn = ((246, 244, 238, 255), (210, 206, 198, 255), (36, 34, 34, 255), (44, 40, 38, 255),
                                              (238, 176, 170, 255), (200, 192, 176, 255))
    img, d = new_canvas()
    leg(d, 420, 650, 270, 752, 40, shade, hoof)
    leg(d, 720, 650, 860, 748, 40, shade, hoof)
    outline = smooth([(320, 500), (450, 448), (630, 440), (780, 460), (860, 520), (868, 610), (805, 675), (640, 698),
                      (460, 698), (360, 680), (285, 690), (215, 720), (140, 735), (100, 712), (112, 664), (190, 618),
                      (255, 568)])
    d.polygon(outline, fill=white)
    patches_inside(img, outline, [
        [(480, 450), (600, 440), (640, 520), (560, 580), (470, 540)],
        [(700, 470), (820, 480), (850, 560), (760, 600), (690, 540)],
        [(330, 520), (400, 500), (420, 600), (350, 640), (300, 590)],
        [(560, 640), (650, 630), (680, 700), (560, 700)]], black)
    d = ImageDraw.Draw(img)
    d.ellipse((86, 676, 150, 740), fill=muzzle)                                                  # muzzle
    d.polygon(smooth([(200, 600), (232, 560), (262, 548), (254, 590)], 8), fill=black)          # ear
    stroke(d, 262, 600, 300, 578, 14, horn)                                                     # small horn
    closed_eye(d, 182, 650)
    stroke(d, 860, 540, 905, 640, 12, shade)                                                    # tail
    d.polygon(smooth([(890, 625), (925, 640), (915, 690), (885, 670)], 8), fill=black)          # tail tuft
    leg(d, 450, 670, 300, 775, 46, white, hoof)
    leg(d, 750, 665, 900, 765, 46, white, hoof)
    return img


def buffalo():
    hide, dark, hoof, horn = (74, 76, 80, 255), (54, 56, 60, 255), (30, 30, 32, 255), (196, 188, 172, 255)
    img, d = new_canvas()
    leg(d, 420, 650, 280, 750, 44, dark, hoof)
    leg(d, 720, 650, 850, 746, 44, dark, hoof)
    d.polygon(smooth([(310, 495), (450, 440), (640, 432), (790, 455), (870, 520), (875, 612), (810, 678), (640, 700),
                      (460, 700), (360, 682), (285, 692), (215, 722), (140, 738), (100, 715), (112, 664), (190, 615),
                      (250, 560)]), fill=hide)
    # big horns curving back over the head
    d.arc((160, 470, 380, 690), start=190, end=300, fill=horn, width=30)
    d.ellipse((92, 680, 146, 734), fill=dark)                                                   # muzzle
    closed_eye(d, 190, 652, 18, (170, 170, 172, 255))
    stroke(d, 865, 540, 905, 640, 12, dark)                                                     # tail
    leg(d, 450, 670, 310, 772, 50, hide, hoof)
    leg(d, 750, 665, 890, 762, 50, hide, hoof)
    return img


def horse():
    coat, dark, mane, hoof = (156, 88, 46, 255), (122, 66, 34, 255), (70, 40, 24, 255), (40, 32, 28, 255)
    img, d = new_canvas()
    leg(d, 420, 630, 230, 745, 34, dark, hoof)
    leg(d, 730, 630, 900, 742, 34, dark, hoof)
    d.polygon(smooth([(360, 495), (480, 462), (650, 458), (790, 475), (860, 525), (866, 600), (810, 655), (660, 680),
                      (490, 680), (400, 665), (320, 670), (240, 704), (140, 726), (96, 704), (112, 660), (190, 612),
                      (280, 560)]), fill=coat)
    # mane along the neck, flowing tail
    d.polygon(smooth([(280, 548), (330, 505), (370, 492), (350, 540), (300, 575)], 8), fill=mane)
    d.polygon(smooth([(860, 520), (930, 560), (960, 650), (925, 700), (900, 620), (855, 570)], 10), fill=mane)
    d.polygon(smooth([(230, 600), (262, 570), (282, 575), (262, 610)], 8), fill=dark)           # ear
    closed_eye(d, 200, 642)
    d.ellipse((98, 690, 118, 708), fill=hoof)
    leg(d, 450, 645, 260, 770, 40, coat, hoof)
    leg(d, 760, 640, 940, 760, 40, coat, hoof)
    return img


ANIMALS = {"deer": deer, "boar": boar, "pig": pig, "sheep": sheep, "goat": goat, "cow": cow, "buffalo": buffalo, "horse": horse}


def animal_icon(kind, size=256):
    return fit(ANIMALS[kind](), size)
