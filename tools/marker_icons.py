"""Draw the map marker images: a coloured disc with a dark ring and a white symbol, readable at minimap size. The colour is in the picture: the game's map
draws every marker in the colour stored on it and overrides anything set on the image (M4 round 3: they came out black and white).

  mod/icons/marker_point_1 .. 9   your own drop-off points, by number
  mod/icons/marker_point_x        a point past number 9
  mod/icons/marker_loose          a loose animal
  mod/icons/marker_left           a dead animal left behind
  mod/icons/marker_kit            your cones and barricades

  mod/icons/map_dropoff           the picture in a drop-off point's map box

Written straight to DDS by Pillow, no textureTool window. The PNGs stay in the repo as sources; deploy and build skip them.

Usage: python tools/marker_icons.py
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import project  # noqa: E402

SIZE = 64
SCALE = 4
DARK = (22, 24, 28, 255)
WHITE = (255, 255, 255, 255)
BLUE = (41, 117, 245, 255)
GREEN = (60, 175, 50, 255)
RED = (225, 45, 45, 255)
ORANGE = (245, 140, 20, 255)


def limb(d, points, w0, w1, fill=WHITE):
    for i in range(len(points) - 1):
        (x0, y0), (x1, y1) = points[i], points[i + 1]
        a = w0 + (w1 - w0) * i / (len(points) - 1)
        b = w0 + (w1 - w0) * (i + 1) / (len(points) - 1)
        length = max(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5, 1e-6)
        nx, ny = -(y1 - y0) / length, (x1 - x0) / length
        d.polygon([(x0 + nx * a / 2, y0 + ny * a / 2), (x1 + nx * b / 2, y1 + ny * b / 2),
                   (x1 - nx * b / 2, y1 - ny * b / 2), (x0 - nx * a / 2, y0 - ny * a / 2)], fill=fill)
        d.ellipse((x0 - a / 2, y0 - a / 2, x0 + a / 2, y0 + a / 2), fill=fill)
        d.ellipse((x1 - b / 2, y1 - b / 2, x1 + b / 2, y1 + b / 2), fill=fill)


def disc(color):
    size = SIZE * SCALE
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, size - 1, size - 1), fill=DARK)
    ring = size * 0.075
    d.ellipse((ring, ring, size - 1 - ring, size - 1 - ring), fill=color)
    return img, d, size


def letter(text, color):
    img, d, size = disc(color)
    font = ImageFont.truetype("arialbd.ttf", int(size * 0.66))
    box = d.textbbox((0, 0), text, font=font)
    d.text(((size - (box[2] - box[0])) / 2 - box[0], (size - (box[3] - box[1])) / 2 - box[1]), text, font=font, fill=WHITE)
    return img


def animal():
    """A standing farm animal in profile, facing right."""
    img, d, size = disc(GREEN)

    def p(*values):
        return [(values[i] * size, values[i + 1] * size) for i in range(0, len(values), 2)]

    limb(d, p(0.30, 0.46, 0.60, 0.46), size * 0.21, size * 0.20)  # body
    limb(d, p(0.66, 0.42, 0.76, 0.32), size * 0.11, size * 0.09)  # neck
    limb(d, p(0.75, 0.31, 0.86, 0.36), size * 0.12, size * 0.07)  # head
    limb(d, p(0.71, 0.26, 0.66, 0.22), size * 0.05, size * 0.03)  # ear
    limb(d, p(0.25, 0.50, 0.23, 0.76), size * 0.08, size * 0.05)  # legs
    limb(d, p(0.36, 0.52, 0.36, 0.78), size * 0.08, size * 0.05)
    limb(d, p(0.56, 0.52, 0.56, 0.78), size * 0.08, size * 0.05)
    limb(d, p(0.66, 0.50, 0.68, 0.76), size * 0.08, size * 0.05)
    limb(d, p(0.20, 0.42, 0.14, 0.52), size * 0.05, size * 0.03)  # tail
    return img


def cone():
    img, d, size = disc(ORANGE)
    d.polygon([(size * 0.5, size * 0.16), (size * 0.66, size * 0.70), (size * 0.34, size * 0.70)], fill=WHITE)
    d.polygon([(size * 0.44, size * 0.38), (size * 0.56, size * 0.38), (size * 0.595, size * 0.50), (size * 0.405, size * 0.50)], fill=ORANGE)
    d.rounded_rectangle((size * 0.22, size * 0.70, size * 0.78, size * 0.80), radius=size * 0.03, fill=WHITE)
    return img


def dropoff_picture():
    """The picture in a drop-off point's map box: a container with an arrow going in."""
    size = 256 * SCALE
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def p(*values):
        return [(values[i] * size, values[i + 1] * size) for i in range(0, len(values), 2)]

    d.ellipse((size * 0.08, size * 0.80, size * 0.92, size * 0.94), fill=(0, 0, 0, 70))
    d.polygon(p(0.12, 0.48, 0.88, 0.48, 0.80, 0.86, 0.20, 0.86), fill=(41, 117, 245, 255))
    d.polygon(p(0.12, 0.48, 0.88, 0.48, 0.865, 0.55, 0.135, 0.55), fill=(26, 82, 180, 255))
    for x0, x1 in ((0.30, 0.34), (0.48, 0.52), (0.66, 0.70)):
        d.polygon(p(x0, 0.58, x1, 0.58, x1 - 0.005, 0.80, x0 + 0.005, 0.80), fill=(26, 82, 180, 255))
    d.rounded_rectangle((size * 0.08, size * 0.44, size * 0.92, size * 0.50), radius=size * 0.015, fill=(22, 24, 28, 255))
    d.polygon(p(0.42, 0.08, 0.58, 0.08, 0.58, 0.24, 0.70, 0.24, 0.50, 0.42, 0.30, 0.24, 0.42, 0.24), fill=(245, 140, 20, 255))
    return img.resize((256, 256), Image.LANCZOS)


def images():
    jobs = {"point_%d" % n: letter(str(n), BLUE) for n in range(1, 10)}
    jobs["point_x"] = letter("+", BLUE)
    jobs["left"] = letter("!", RED)
    jobs["loose"] = animal()
    jobs["kit"] = cone()
    return jobs


def main():
    folder = project.MOD_SOURCE / "icons"
    for name, image in images().items():
        small = image.resize((SIZE, SIZE), Image.LANCZOS)
        small.save(folder / ("marker_%s.png" % name))
        small.save(folder / ("marker_%s.dds" % name), pixel_format="DXT5")
        print("wrote", "marker_%s.dds" % name)
    picture = dropoff_picture()
    picture.save(folder / "map_dropoff.png")
    picture.save(folder / "map_dropoff.dds", pixel_format="DXT5")
    print("wrote", "map_dropoff.dds")


if __name__ == "__main__":
    main()
