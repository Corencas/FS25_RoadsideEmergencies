"""Check the mod and zip it for release.

Checks: every XML parses, modDesc has a four-part version, EN and DE title and description, and an existing icon, and every
text key exists in every translation (check_l10n.py). Then mod/ is zipped to dist/FS25_RoadsideEmergencies.zip with the
files at the zip root.

Usage: python tools/build.py           check and zip
       python tools/build.py --check   check only (CI)
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_l10n  # noqa: E402
import project  # noqa: E402

SKIP_SUFFIXES = {".png", ".psd", ".xcf", ".md", ".bak"}


def check():
    problems = 0
    for xml_file in sorted(project.MOD_SOURCE.rglob("*.xml")):
        try:
            ET.parse(xml_file)
        except ET.ParseError as err:
            print("XML error: %s: %s" % (xml_file.relative_to(project.ROOT), err))
            problems += 1
    mod_desc = project.MOD_SOURCE / "modDesc.xml"
    if not mod_desc.exists():
        print("missing mod/modDesc.xml")
        return problems + 1
    root = ET.parse(mod_desc).getroot()
    version = (root.findtext("version") or "").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", version):
        print("modDesc version '%s' is not four-part (like 0.1.0.0)" % version)
        problems += 1
    for field in ("title", "description"):
        for lang in project.TRANSLATIONS:
            if not (root.findtext("%s/%s" % (field, lang)) or "").strip():
                print("modDesc %s has no '%s' text" % (field, lang))
                problems += 1
    icon = (root.findtext("iconFilename") or "").strip()
    if not icon or not (project.MOD_SOURCE / icon).exists():
        print("modDesc icon '%s' not found" % icon)
        problems += 1
    if check_l10n.main() != 0:
        problems += 1
    print("build check: version %s, %d problem(s)" % (version, problems))
    return problems


def build():
    dist = project.ROOT / "dist"
    dist.mkdir(exist_ok=True)
    target = dist / (project.MOD_NAME + ".zip")
    count = 0
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(project.MOD_SOURCE.rglob("*")):
            if path.is_file() and path.suffix.lower() not in SKIP_SUFFIXES:
                archive.write(path, path.relative_to(project.MOD_SOURCE).as_posix())
                count += 1
    print("built %s (%d files)" % (target.relative_to(project.ROOT), count))


def main(argv):
    if check() != 0:
        return 1
    if "--check" not in argv:
        build()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
