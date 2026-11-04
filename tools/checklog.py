"""Archive FS25's log.txt and print the lines that matter.

Saves a timestamped copy to _logs/ (log.txt is overwritten on every launch), then prints
the game version, every line with one of our prefixes or a watched keyword, Lua call
stacks, and errors/warnings (those mentioning our mods first, the rest summarised).

Usage: python tools/checklog.py [--prefix TEXT ...] [--watch TEXT ...] [--all-warnings]
"""
import argparse
import datetime
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_PREFIXES = ["[RoadsideProbe]", "[FS25_RoadsideEmergencies]"]
DEFAULT_WATCH = ["FS25_RoadsideProbe", "Roadside Probe", "FS25_RoadsideEmergencies", "emergency", "Emergency"]
ISSUE = re.compile(r"\b(error|warning)\b", re.IGNORECASE)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", nargs="*", default=DEFAULT_PREFIXES)
    parser.add_argument("--watch", nargs="*", default=DEFAULT_WATCH)
    parser.add_argument("--all-warnings", action="store_true", help="print every error/warning, not just ours")
    args = parser.parse_args()

    config = json.loads((ROOT / "local.config.json").read_text(encoding="utf-8"))
    log_path = pathlib.Path(config["logPath"])
    if not log_path.exists():
        sys.exit("no log at %s" % log_path)

    logs_dir = ROOT / "_logs"
    logs_dir.mkdir(exist_ok=True)
    stamp = datetime.datetime.fromtimestamp(log_path.stat().st_mtime).strftime("%Y%m%d-%H%M%S")
    archived = logs_dir / ("log_%s.txt" % stamp)
    if not archived.exists():
        shutil.copy2(log_path, archived)

    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    print("log: %s (archived as %s, %d lines)" % (log_path, archived.relative_to(ROOT), len(lines)))
    for line in lines[:200]:
        if "Game-Version" in line or "GIANTS Engine Runtime" in line or "ModDesc Version" in line:
            print("  " + line.strip())

    print("\n== our lines and watched keywords")
    for number, line in enumerate(lines, 1):
        if any(p in line for p in args.prefix) or any(w in line for w in args.watch):
            if "Available mod:" not in line:
                print("%6d  %s" % (number, line))

    print("\n== Lua call stacks")
    stacks = 0
    for number, line in enumerate(lines, 1):
        if "LUA call stack" in line:
            stacks += 1
            print("%6d  %s" % (number, line))
            for follow in lines[number:number + 8]:
                if not follow.startswith("  "):
                    break
                print("        " + follow)
    if stacks == 0:
        print("  none")

    ours, others = [], []
    for number, line in enumerate(lines, 1):
        if ISSUE.search(line):
            target = ours if any(w in line for w in args.prefix + args.watch) else others
            target.append((number, line))
    print("\n== errors/warnings mentioning our mods: %d" % len(ours))
    for number, line in ours:
        print("%6d  %s" % (number, line))
    # mods load with dozens of unrelated warnings; what goes wrong during play comes after our mod has loaded
    loaded_at = next((n for n, line in enumerate(lines, 1) if "] loaded version" in line), None)
    during_play = [(n, line) for n, line in others if loaded_at is not None and n > loaded_at and "(performance)" not in line]
    print("\n== other errors/warnings during play (after our mod loaded): %d" % len(during_play))
    for number, line in during_play[:40]:
        print("%6d  %s" % (number, line))
    print("\n== other errors/warnings: %d%s" % (len(others), "" if args.all_warnings else " (first 15; --all-warnings for all)"))
    for number, line in (others if args.all_warnings else others[:15]):
        print("%6d  %s" % (number, line))
    return 0


if __name__ == "__main__":
    sys.exit(main())
