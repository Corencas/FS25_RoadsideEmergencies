"""Check a mod folder and copy it into the FS25 mods folder.

Replaces only the folder with the same name (FS25_<Name>) in the mods folder; never
touches anything else there. Paths come from local.config.json (gitignored).

Usage: python tools/deploy.py [mod-folder]   (default: mod/)
"""
import json
import pathlib
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import lua_check  # noqa: E402
import project  # noqa: E402

SKIP_SUFFIXES = {".png", ".psd", ".xcf", ".md", ".bak"}
# Optional local tools (gitignored _tools/); without them the structural check is used instead.
LUAC = ROOT / "_tools" / "lua51" / "luac5.1.exe"
LUACHECK = ROOT / "_tools" / "luacheck" / "luacheck.exe"


def load_config():
    path = ROOT / "local.config.json"
    if not path.exists():
        sys.exit("local.config.json missing: copy local.config.example.json and fill in your paths")
    return json.loads(path.read_text(encoding="utf-8"))


def game_is_running():
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    return "FarmingSimulator2025" in out


def check(source):
    problems = 0
    for xml_file in sorted(source.rglob("*.xml")):
        try:
            ET.parse(xml_file)
        except ET.ParseError as err:
            print("XML error: %s: %s" % (xml_file, err))
            problems += 1
    lua_files = sorted(source.rglob("*.lua"))
    for lua_file in lua_files:
        if LUAC.exists():
            result = subprocess.run([str(LUAC), "-p", str(lua_file)], capture_output=True, text=True)
            if result.returncode != 0:
                print(result.stderr.strip() or "luac failed: %s" % lua_file)
                problems += 1
        else:
            for line, message in lua_check.check_source(lua_file.read_text(encoding="utf-8")):
                print("%s:%d: %s" % (lua_file, line, message))
                problems += 1
    if lua_files and LUACHECK.exists():
        # run from the repo root so .luacheckrc applies; any warning counts (the brief wants zero)
        result = subprocess.run([str(LUACHECK), str(source.relative_to(ROOT))], capture_output=True, text=True, cwd=ROOT)
        if result.returncode != 0:
            print(result.stdout.strip())
            problems += 1
    print("checks: %d xml, %d lua (%s%s)" % (len(list(source.rglob("*.xml"))), len(lua_files),
          "luac" if LUAC.exists() else "structural", " + luacheck" if LUACHECK.exists() else ""))
    if not (source / "modDesc.xml").exists():
        print("missing modDesc.xml in %s" % source)
        problems += 1
    return problems


def main(argv):
    source = (ROOT / (argv[1] if len(argv) > 1 else "mod")).resolve()
    if not source.is_dir():
        sys.exit("not a folder: %s" % source)
    # mod/ ships as FS25_RoadsideEmergencies; probe folders carry their own FS25_ name
    name = project.MOD_NAME if source == project.MOD_SOURCE else source.name
    if not name.startswith("FS25_"):
        sys.exit("refusing to deploy '%s': mod folder names must start with FS25_" % name)

    if check(source):
        sys.exit("checks failed; nothing deployed")

    mods_dir = pathlib.Path(load_config()["modsDir"])
    if (mods_dir / (name + ".zip")).exists():
        sys.exit("%s.zip already exists in the mods folder; remove it first so the game doesn't load two copies" % name)
    if game_is_running():
        print("warning: FS25 appears to be running; changes take effect after a restart")

    target = mods_dir / name
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, ignore=lambda _d, files: [f for f in files if pathlib.Path(f).suffix.lower() in SKIP_SUFFIXES])
    copied = sum(1 for p in target.rglob("*") if p.is_file())
    print("deployed %s -> %s (%d files)" % (source.relative_to(ROOT), target, copied))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
