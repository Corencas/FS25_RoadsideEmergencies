"""Project constants shared by the tools."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD_NAME = "FS25_RoadsideEmergencies"   # folder and zip name in the mods folder
MOD_SOURCE = ROOT / "mod"               # what ships
TRANSLATIONS = ("en", "de", "fr", "es", "it", "br", "pl", "cz", "ru", "uk") # every player-facing text exists in each (ModHub requires en and de)
