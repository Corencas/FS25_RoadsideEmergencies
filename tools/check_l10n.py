"""Check that every text key the mod uses exists in every translation, and list keys nobody uses.

Keys used: string literals starting with "rse_" or "input_RSE_" in mod Lua files, "$l10n_rse_..." references and
description/hint/postMessage attributes in mod XML files, and "input_<ACTION>" for every input action in modDesc.
Exit code 1 if a used key is missing from a translation, a key is there twice, or a hint is too long: past HINT_MAX characters it runs under the
game's F1 list (seen in M2 round 9). Also if a translation loses or reorders a placeholder, names an unknown plural rule (core/Plural.lua) or lacks the
2-to-4 forms its rule needs, and, where the game is installed, uses a character the game's font doesn't have or is wider than the widest English text in
a place where text has to fit (WIDTH_GROUPS).

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


def texts_of(lang):
    path = project.MOD_SOURCE / "translations" / ("translation_%s.xml" % lang)
    if not path.exists():
        return {}
    return {t.get("name"): t.get("text") or "" for t in ET.parse(path).getroot().iter("text")}


PLACEHOLDER = re.compile(r"%(?:%|[-0-9.]*[sdif])")
BRACED = re.compile(r"\{(?:key|distance|mass):[A-Za-z0-9_.]+\}")


def placeholder_problems(lang, english, texts):
    """The game fills %s and %d in order, and {key:..}, {distance:..}, {mass:..} by name: a translation keeps every one, the % ones in English's order."""
    found = []
    for key, text in texts.items():
        source = english.get(key)
        if source is None:
            continue
        if PLACEHOLDER.findall(text) != PLACEHOLDER.findall(source):
            found.append("[%s] %s: placeholders %s, English has %s" % (lang, key, PLACEHOLDER.findall(text), PLACEHOLDER.findall(source)))
        if sorted(BRACED.findall(text)) != sorted(BRACED.findall(source)):
            found.append("[%s] %s: %s, English has %s" % (lang, key, sorted(BRACED.findall(text)), sorted(BRACED.findall(source))))
    return found


PLURAL_RULES = ("default", "eastSlavic", "polish", "czech")
ANIMALS = ("deer", "boar", "pig", "sheep", "goat", "cow", "buffalo", "horse")


def plural_problems(lang, texts):
    rule = texts.get("rse_plural_rule")
    if rule not in PLURAL_RULES:
        return ["[%s] rse_plural_rule is %r, not one of %s" % (lang, rule, ", ".join(PLURAL_RULES))]
    if rule == "default":
        return []
    # a language with a 2-to-4 form also has its plain plural for the call panel's title (RseText.animalTitle)
    return ["[%s] rule %s needs rse_unit_%s_%s" % (lang, rule, kind, form) for kind in ANIMALS for form in ("few", "plural")
            if "rse_unit_%s_%s" % (kind, form) not in texts]


# ---------------------------------------------------------------------------------------------------------------------------------------------------------
# The game's font: which characters it has, and how wide each is (shared/font/defaultFont.font: a 12-byte header, then 28 bytes a character: its code
# point, then its regular and bold glyphs, each ending in its advance). Only on a machine with the game; CI skips these checks.
# ---------------------------------------------------------------------------------------------------------------------------------------------------------

# On-screen pixels at 1920 x 1080 = font units x text size x 1080 x PX_PER_UNIT. Measured on Z's screenshot of the call panel (three step texts at
# 2560 x 1440 agreed to within 1%).
PX_PER_UNIT = 0.027


class Font:
    def __init__(self, regular, bold):
        self.regular, self.bold = regular, bold

    def px(self, text, size, bold=False):
        table = self.bold if bold else self.regular
        return sum(table.get(ord(ch), 18.0) for ch in text) * size * 1080 * PX_PER_UNIT


def load_font():
    config = project.ROOT / "local.config.json"
    if not config.exists():
        return None
    import json
    import struct
    for value in json.loads(config.read_text(encoding="utf-8")).values():
        if isinstance(value, str) and value.endswith("Farming Simulator 25"):
            path = pathlib.Path(value) / "shared" / "font" / "defaultFont.font"
            if path.exists():
                data = path.read_bytes()
                regular, bold = {}, {}
                for i in range(struct.unpack_from("<I", data, 8)[0]):
                    at = 12 + 28 * i
                    code = struct.unpack_from("<I", data, at)[0]
                    regular[code] = struct.unpack_from("<f", data, at + 12)[0]
                    bold[code] = struct.unpack_from("<f", data, at + 24)[0]
                return Font(regular, bold)
    return None


def font_problems(lang, texts, font):
    missing = {}
    for key, text in texts.items():
        for ch in text:
            if ch not in "\n\r\t" and ord(ch) not in font.regular:
                missing.setdefault(ch, key)
    return ["[%s] the game's font has no %r (U+%04X), first in %s" % (lang, ch, ord(ch), key) for ch, key in sorted(missing.items())]


def filled(text, *values):
    """A text as shown: {key:..} as one key's name, {distance:..} and {mass:..} as their usual length, then %d and %s in order."""
    text = re.sub(r"\{key:[A-Z_]+\}", "K", text)
    text = re.sub(r"\{distance:[0-9.]+\}", "131 ft", text)
    text = re.sub(r"\{mass:[0-9.]+\}", "3 t", text)
    values = list(values)

    def one(match):
        spec = match.group(0)
        if spec == "%%":
            return "%"
        if values:
            return str(values.pop(0))
        return "12" if spec.endswith("d") else "Water buffalo"
    return PLACEHOLDER.sub(one, text)


def longest(font, size, candidates, bold=False):
    return max((font.px(c, size, bold) for c in candidates), default=0.0)


def settings_kinds():
    """textKey -> kind, from core/Settings.lua's rows"""
    source = (project.MOD_SOURCE / "scripts" / "core" / "Settings.lua").read_text(encoding="utf-8")
    return dict(re.findall(r'textKey = "(rse_set_[A-Za-z]+)", kind = "([a-zA-Z]+)"', source))


STEP = re.compile(r"rse_panel_(reach|animals|power|treeLog|tracks|driver|prepare|upright|logs|wires|pole|bales|survivors|flock|deliver|deliverCar|"
                  r"deliverTrailer)$")


def room_problems(lang, texts, font):
    """Each place that has to hold a text, with its room in pixels at 1920 x 1080 (sizes and widths from the drawing code)."""
    def t(key, *values):
        return filled(texts.get(key, ""), *values)

    found = []

    def need(where, key, used, room):
        if used > room:
            found.append("[%s] %s doesn't fit the %s: %.0f px of %.0f (%r)" % (lang, key, where, used, room, texts.get(key)))

    # settings panel (SettingsPanel.lua): 680 wide, 18 margins, label left and value right at 0.0135, "< value >" on the selected row
    size = 0.0135
    values = {
        "onOff": [t("rse_set_on"), t("rse_set_off")],
        "frequency": [t(k) for k in texts if k.startswith("rse_set_frequency_")],
        "size": [t(k) for k in texts if k.startswith("rse_set_size_")],
        "percent": ["200 %"],
        "minutes": [t("rse_unit_minutes", 60)],
    }
    for key, kind in settings_kinds().items():
        value = longest(font, size, ["< %s >" % v for v in values.get(kind, [""])])
        need("settings row (with its value)", key, font.px(t(key), size) + value + 16, 680 - 36)
    hand_over = longest(font, size, [t("rse_set_handOverPaid"), t("rse_set_handOverNone"), t("rse_set_handOverFee", "$1,250")])
    for key in ("rse_set_handOver", "rse_set_removePoint"):
        need("settings row (with its value)", key, font.px(t(key), size) + hand_over + 16, 680 - 36)
    for key in ("rse_set_guide", "rse_set_addPoint", "rse_set_defaults"):
        need("settings row", key, font.px(t(key), size), 680 - 36)
    need("settings panel title", "rse_set_title", font.px(t("rse_set_title"), 0.017, True), 680 - 36)
    need("settings help line", "rse_set_help", font.px(t("rse_set_help"), 0.0115), 680 - 36)

    # call panel (CallPanel.lua): 430 wide, 16 pads; a step or the title shrinks to 75% before it overflows
    inner = 430 - 32
    rights = [t("rse_panel_now").upper(), t("rse_panel_done").upper(), t("rse_panel_left", 12).upper(), "1267 M", "+1,320 $"]
    right = longest(font, 0.0115, rights, True)
    step_room = (inner - 30 - right - 10) / 0.75
    for key in [k for k in texts if STEP.match(k)]:
        need("call panel step (at 75%)", key, font.px(t(key), 0.0145, True), step_room)
    many = [t(k) for k in texts if re.match(r"rse_unit_[a-z]+_(many|few|plural)$", k)] or ["Water buffalo"]
    title_room = (inner - font.px("1267 m", 0.0175, True) - 24 - 12) / 0.75
    for key in [k for k in texts if k.startswith("rse_panel_title_")]:
        text = max((filled(texts[key], m).upper() for m in many), key=lambda x: font.px(x, 0.0175, True))
        need("call panel title (at 75%)", key, font.px(text, 0.0175, True), title_room)
    clock = font.px("12:34", 0.0175, True)
    for key in [k for k in texts if k.startswith("rse_panel_clock")]:
        need("call panel clock", key, font.px(t("rse_panel_hurry", t(key)), 0.0125) + 28, inner - clock - 8)
    pay = font.px(t("rse_panel_pay", "$12,345"), 0.0125)
    for key, shown in (("rse_panel_lightsOff", (7,)), ("rse_panel_lightsEarned", (7,)), ("rse_panel_lightsCounting", (7, "0:20"))):
        need("call panel bonus line (with the pay)", key, font.px(filled(texts.get(key, ""), *shown), 0.0125) + 24 + pay + 10, inner)

    # scene kit strip (Kit.lua): tiles 168 wide, names centred at 0.012
    for key in ("rse_kit_cone", "rse_kit_barricade", "rse_kit_coneTape"):
        need("scene kit tile", key, font.px(t(key), 0.012), 168 - 8)

    # live wires banner (Draw.lua): 860 wide, 18 pads, the sign 56 + 16; title at 0.024, the line at 0.0165
    banner = 860 - 36 - 72
    need("warning banner title", "rse_line_dangerTitle", font.px(t("rse_line_dangerTitle"), 0.024, True), banner)
    for key in ("rse_line_dangerPay", "rse_line_dangerPaid"):
        need("warning banner line", key, font.px(t(key), 0.0165), banner)

    # the guide's page heading (SettingsPanel.lua): 940 wide, with "(2 of 2)" after a split page and the page number at the right
    heading_room = 940 - 36 - font.px(t("rse_guide_page", 21, 21), 0.0115) - 20
    for key in [k for k in texts if k.startswith("rse_guide_title_")]:
        need("guide page heading", key, font.px(t("rse_guide_part", t(key), 2, 2), 0.0175, True), heading_room)
    return found


# Places whose room isn't known from our code: the game's F1 list (Z: about 20 characters show), its fill display and its map buttons. A translation may be
# as wide as the widest English text there, times the slack. %s is the longest short name in that language.
RELATIVE_GROUPS = [
    ("F1 line", re.compile(r"rse_(action_(drag|letGo|tooHeavyShort)|strap_(hook|attach|drop|remove|reelIn|reelOut)|kit_(place|pickup|turn|next|stop|open)|"
                           r"survivor_(catch|load)|wreck_(prepare|driver)|line_rollUp|set_open)$"), 1.05),
    ("fill display", re.compile(r"rse_(unit_[a-z]+_(one|few|many|plural)|animalName_[a-z]+)$"), 1.3),
    ("map button", re.compile(r"rse_map_[a-zA-Z]+$"), 1.2),
]


def relative_problems(lang, english, texts, font):
    found = []

    def short(source, key):
        """what goes in the %s of that line: a kit item's short name on a kit line, an animal's on the others"""
        kind = "rse_kitShort_" if key.startswith("rse_kit_") else "rse_animalShort_"
        shorts = [v for k, v in source.items() if k.startswith(kind)]
        return max(shorts, key=len) if shorts else "buffalo"

    for name, pattern, slack in RELATIVE_GROUPS:
        keys = [k for k in english if pattern.match(k)]
        prefix = "RSE: " if name == "F1 line" else ""
        budget = max(font.px(prefix + filled(english[k], short(english, k)), 0.0135) for k in keys) * slack
        for key in [k for k in texts if pattern.match(k)]:
            w = font.px(prefix + filled(texts[key], short(texts, key)), 0.0135)
            if w > budget:
                found.append("[%s] %s is too wide for the %s: %.0f%% of the widest English one (%r)" % (lang, key, name, 100 * w * slack / budget,
                                                                                                       texts[key]))
    return found


def main():
    used = used_keys()
    # a literal ending in "_" is a prefix the code completes at runtime ("rse_animal_" .. kind): it counts every key that
    # starts with it as used, and isn't a key itself
    prefixes = [key for key in used if key.endswith("_")]
    for prefix in prefixes:
        del used[prefix]
    problems = 0
    english = texts_of("en")
    font = load_font()
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
        texts = texts_of(lang)
        found = plural_problems(lang, texts)
        if lang != "en":
            found += placeholder_problems(lang, english, texts)
        if font is not None:
            found += font_problems(lang, texts, font)
            found += room_problems(lang, texts, font)
            if lang != "en":
                found += relative_problems(lang, english, texts, font)
        for line in found:
            print(line)
        problems += len(found)
    if font is None:
        print("l10n: the game's font isn't here (local.config.json), so characters and widths weren't checked")
    print("l10n: %d key(s) used, %d problem(s)" % (len(used), problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
