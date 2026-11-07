"""The call panel's marks (CallPanel.lua), drawn with Pillow: the game's font has no tick, triangle or warning sign (shared/font/defaultFont.font), so
each mark is a small picture, always drawn with a word beside it. Colours are look B's (core/Theme.lua). 64x64 RGBA, drawn four times larger and scaled
down for smooth edges.

  ui_done     the game's green circle with a dark tick
  ui_now      the orange circle with a dark arrowhead
  ui_todo     a grey ring
  ui_warning  a white warning triangle with a red exclamation mark, for the red clock row
  ui_arrow    a white arrow pointing up; the panel tints it orange and turns it toward where to go
"""
from PIL import Image, ImageDraw

SIZE = 64
SCALE = 4
GREEN = (135, 180, 0, 255)      # RseTheme.DONE
ORANGE = (255, 112, 30, 255)    # RseTheme.ACCENT
DARK = (20, 20, 20, 255)        # RseTheme.TEXT_ON_ACCENT
GREY = (184, 184, 184, 255)     # RseTheme.TEXT_MUTED
RED = (206, 22, 28, 255)        # RseTheme.URGENT_FILL
WHITE = (255, 255, 255, 255)

NAMES = ("ui_done", "ui_now", "ui_todo", "ui_warning", "ui_arrow")


def _canvas():
    big = SIZE * SCALE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image), big


def _finish(image):
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def _p(big, x, y):
    """A point given as a share of the picture (0 to 1)."""
    return (x * big, y * big)


def done():
    image, draw, big = _canvas()
    draw.ellipse([_p(big, 0.04, 0.04), _p(big, 0.96, 0.96)], fill=GREEN)
    draw.line([_p(big, 0.27, 0.52), _p(big, 0.43, 0.68), _p(big, 0.74, 0.34)], fill=DARK, width=int(big * 0.11), joint="curve")
    return _finish(image)


def now():
    image, draw, big = _canvas()
    draw.ellipse([_p(big, 0.04, 0.04), _p(big, 0.96, 0.96)], fill=ORANGE)
    draw.polygon([_p(big, 0.38, 0.27), _p(big, 0.38, 0.73), _p(big, 0.74, 0.50)], fill=DARK)
    return _finish(image)


def todo():
    image, draw, big = _canvas()
    draw.ellipse([_p(big, 0.08, 0.08), _p(big, 0.92, 0.92)], outline=GREY, width=int(big * 0.09))
    return _finish(image)


def warning():
    image, draw, big = _canvas()
    draw.polygon([_p(big, 0.50, 0.06), _p(big, 0.97, 0.92), _p(big, 0.03, 0.92)], fill=WHITE)
    draw.rounded_rectangle([_p(big, 0.445, 0.33), _p(big, 0.555, 0.67)], radius=int(big * 0.04), fill=RED)
    draw.ellipse([_p(big, 0.44, 0.73), _p(big, 0.56, 0.85)], fill=RED)
    return _finish(image)


def arrow():
    image, draw, big = _canvas()
    draw.polygon([_p(big, 0.50, 0.04), _p(big, 0.92, 0.52), _p(big, 0.64, 0.52), _p(big, 0.64, 0.96), _p(big, 0.36, 0.96), _p(big, 0.36, 0.52),
                  _p(big, 0.08, 0.52)], fill=WHITE)
    return _finish(image)


def ui_icon(name):
    return {"ui_done": done, "ui_now": now, "ui_todo": todo, "ui_warning": warning, "ui_arrow": arrow}[name]()
