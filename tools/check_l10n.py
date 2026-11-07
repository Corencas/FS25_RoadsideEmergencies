"""Check that every text key the mod uses exists in every translation, and list keys nobody uses.

Keys used: string literals starting with "rse_" or "input_RSE_" in mod Lua files, "$l10n_rse_..." references and
description/hint/postMessage attributes in mod XML files, and "input_<ACTION>" for every input action in modDesc.
Exit code 1 if a used key is missing from a translation, a key is there twice, or a hint is too long: past HINT_MAX characters it runs under the
game's F1 list (seen in M2 round 9).

Usage: python tools/check_l10n.py
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import project  # noqa: E402

LUA_KEY = re.compile(r"""["']((?:rse_|input_RSE_)[A-Za-z0-9_]+)["']""")
XML_REF = re.compile(r"\$l10n_((?:rse_|input_RSE_)[A-Za-z0-9_]+)")
XML_ATTRS = ("description", "hint", "postMessage")
HINT_MAX = 225


def translation_keys(lang):
    path = project.MOD_SOURCE / "translations" / ("translation_%s.xml" % lang)
    if not path.exists():
        return None
    root = ET.parse(path).getroot()
    # <l10n><texts><text name=".." text=".."/></texts></l10n>, the format FS25 mods use
    return {t.get("name") for t in root.iter("text")}


def shown(text):
    """The length on screen: a {key:...} is one key's name, a {mass:...} or {distance:...} a few characters (RseText.get fills them in)."""
    text = re.sub(r"\{key:[A-Z_]+\}", "K", text)
    text = re.sub(r"\{distance:[0-9.]+\}", "131 ft", text)
    return re.sub(r"\{mass:[0-9.]+\}", "3 t", text)


def long_hints(lang):
    path = project.MOD_SOURCE / "translations" / ("translation_%s.xml" % lang)
    if not path.exists():
        return []
    return [(t.get("name"), len(shown(t.get("text")))) for t in ET.parse(path).getroot().iter("text")
            if "_hint" in t.get("name") and len(shown(t.get("text"))) > HINT_MAX]


def duplicates(lang):
    """Keys defined more than once (the game uses the first and logs a warning; 0.9.7.1 left an old guide line behind)."""
    path = project.MOD_SOURCE / "translations" / ("translation_%s.xml" % lang)
    if not path.exists():
        return []
    seen, twice = set(), []
    for t in ET.parse(path).getroot().iter("text"):
        name = t.get("name")
        if name in seen and name not in twice:
            twice.append(name)
        seen.add(name)
    return twice


def used_keys():
    used = {}
    for lua in project.MOD_SOURCE.rglob("*.lua"):
        for match in LUA_KEY.finditer(lua.read_text(encoding="utf-8")):
            used.setdefault(match.group(1), lua.name)
    for xml in project.MOD_SOURCE.rglob("*.xml"):
        if xml.parent.name == "translations":
            continue
        text = xml.read_text(encoding="utf-8")
        for match in XML_REF.finditer(text):
            used.setdefault(match.group(1), xml.name)
        root = ET.fromstring(text)
        for element in root.iter():
            for attr in XML_ATTRS:
                value = element.get(attr)
                if value and value.startswith("rse_"):
                    used.setdefault(value, xml.name)
        if xml.name == "modDesc.xml":
            for action in root.iter("action"):
                used.setdefault("input_" + action.get("name"), xml.name)
    return used


def main():
    used = used_keys()
    # a literal ending in "_" is a prefix the code completes at runtime ("rse_animal_" .. kind): it counts every key that
    # starts with it as used, and isn't a key itself
    prefixes = [key for key in used if key.endswith("_")]
    for prefix in prefixes:
        del used[prefix]
    problems = 0
    for lang in project.TRANSLATIONS:
        keys = translation_keys(lang)
        if keys is None:
            print("missing translation file for '%s'" % lang)
            problems += 1
            continue
        for key in sorted(set(used) - keys):
            print("[%s] missing key %s (used in %s)" % (lang, key, used[key]))
            problems += 1
        for key in sorted(keys - set(used)):
            if not any(key.startswith(prefix) for prefix in prefixes):
                print("[%s] unused key %s" % (lang, key))
        for prefix in prefixes:
            if not any(key.startswith(prefix) for key in keys):
                print("[%s] no keys for prefix %s" % (lang, prefix))
                problems += 1
        for name in duplicates(lang):
            print("[%s] key %s is there more than once: the game keeps the first and warns" % (lang, name))
            problems += 1
        for name, length in long_hints(lang):
            print("[%s] hint %s is too long: %d characters, at most %d" % (lang, name, length, HINT_MAX))
            problems += 1
    print("l10n: %d key(s) used, %d problem(s)" % (len(used), problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
