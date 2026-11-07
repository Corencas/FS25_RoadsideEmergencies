"""Draw the mod's icons with Pillow and convert them to DDS.

  mod/icon_roadsideEmergencies.png/.dds   mod icon (512x512, drawn in mod_icon.py); BC1 without mipmaps, as nearly every installed
                                          mod has it, written by Pillow
  mod/icons/hud_fill_<animal>.png/.dds    one fill-type icon per carcass animal (256x256, flat illustrations from
                                          animal_icons.py)
  mod/icons/kit_<item>.png/.dds           one picture per scene kit item for the on-screen strip (kit_icons.py)
  mod/icons/ui_stripe.png/.dds            the thin hazard stripe of look B (docs/UI_RESEARCH.md), 1024x8, stretched along a dialog's top edge
  mod/icons/ui_<mark>.png/.dds            the call panel's marks: done, now, to do, warning, arrow (64x64, ui_icons.py)

The others go through GIANTS textureTool (textureToolPath in local.config.json). It writes the DDS next to the PNG but leaves its
window open, so the process is closed once the file exists. The PNGs stay in the repo as sources; deploy and build skip them.

Usage: python tools/make_icons.py        everything
       python tools/make_icons.py ui     only the call panel's marks
"""
import json
import subprocess
import sys
import time


sys.path.insert(0, __import__("pathlib").Path(__file__).resolve().parent.as_posix())
import animal_icons  # noqa: E402
import kit_icons  # noqa: E402
import marker_icons  # noqa: E402
import mod_icon  # noqa: E402
import project  # noqa: E402
import ui_icons  # noqa: E402

SIZE = 256
STRIPE_ORANGE = (255, 112, 30)   # RseTheme.ACCENT, the icon's orange
STRIPE_DARK = (20, 20, 20)


def hazard_stripe(width=1024, height=8, band=12):
    """Diagonal orange and dark bands, drawn by us; about the right shape once stretched to a 720 x 6 px edge."""
    from PIL import Image
    image = Image.new("RGB", (width, height))
    pixels = image.load()
    for x in range(width):
        for y in range(height):
            pixels[x, y] = STRIPE_ORANGE if ((x + y) // band) % 2 == 0 else STRIPE_DARK
    return image


def to_dds(texture_tool, png):
    dds = png.with_suffix(".dds")
    if dds.exists():
        dds.unlink()
    proc = subprocess.Popen([texture_tool, str(png)])
    try:
        for _ in range(100):
            if dds.exists() and dds.stat().st_size > 0:
                time.sleep(0.5)
                break
            time.sleep(0.2)
    finally:
        proc.kill()
    if not dds.exists():
        sys.exit("textureTool did not write %s" % dds.name)
    return dds


def ui_jobs():
    return [(project.MOD_SOURCE / "icons" / (name + ".png"), ui_icons.ui_icon(name)) for name in ui_icons.NAMES]


def main():
    config = json.loads((project.ROOT / "local.config.json").read_text(encoding="utf-8"))
    texture_tool = config["textureToolPath"]
    if sys.argv[1:] == ["ui"]:
        for path, image in ui_jobs():
            image.save(path)
            print("wrote", to_dds(texture_tool, path).relative_to(project.ROOT))
        return
    mod_icon.ship()
    jobs = []
    for kind in animal_icons.ANIMALS:
        jobs.append((project.MOD_SOURCE / "icons" / ("hud_fill_%s.png" % kind), animal_icons.animal_icon(kind, SIZE)))
    for item in kit_icons.KITS:
        jobs.append((project.MOD_SOURCE / "icons" / ("kit_%s.png" % item), kit_icons.kit_icon(item, SIZE)))
    jobs.append((project.MOD_SOURCE / "icons" / "ui_stripe.png", hazard_stripe()))
    jobs.extend(ui_jobs())
    for path, image in jobs:
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        print("wrote", to_dds(texture_tool, path).relative_to(project.ROOT))
    marker_icons.main()


if __name__ == "__main__":
    main()
