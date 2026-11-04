"""Project constants shared by the tools."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_NAME = "FS25_RoadsideEmergencies"   # folder and zip name in the mods folder
MOD_SOURCE = ROOT / "mod"               # what ships
TRANSLATIONS = ("en", "de")             # every player-facing text exists in both (ModHub requires them)
