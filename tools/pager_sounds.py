"""Pager sound candidates, to listen to side by side (Z, 2026-11-07: a noise when the pager goes off).

Writes reports/pager_sounds/ (gitignored): our own tones, synthesized here (original, no licence to worry about), as WAV to listen to and OGG for the
game, and WAV copies of a few of the game's own interface sounds, which the mod would refer to by path instead of shipping them.
Needs soundfile and numpy: python -m pip install --target _tools/pylibs soundfile numpy, then run with PYTHONPATH=_tools/pylibs.

Usage: python tools/pager_sounds.py            all the candidates
       python tools/pager_sounds.py --ship     only the chosen one (CHOICE), into mod/sounds/pager.ogg
"""
import json
import pathlib
import sys

import numpy as np
import soundfile as sf

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "reports" / "pager_sounds"
RATE = 44100


def game_dir():
    config = json.loads((ROOT / "local.config.json").read_text(encoding="utf-8"))
    for value in config.values():
        if isinstance(value, str) and value.endswith("Farming Simulator 25"):
            return pathlib.Path(value)
    raise SystemExit("local.config.json has no game folder")


def tone(freq, seconds, harmonics=((1, 1.0),), fade=0.006, glide_to=None):
    """One tone with short fades (no clicks); harmonics: (multiple, level); glide_to: end frequency for a sweep."""
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    f = np.full(n, float(freq)) if glide_to is None else np.linspace(freq, glide_to, n)
    phase = 2 * np.pi * np.cumsum(f) / RATE
    wave = sum(level * np.sin(multiple * phase) for multiple, level in harmonics)
    ramp = np.minimum(1.0, np.minimum(t, seconds - t) / fade)
    return (wave / sum(level for _, level in harmonics) * ramp).astype(np.float32)


def gap(seconds):
    return np.zeros(int(RATE * seconds), dtype=np.float32)


PIEZO = ((1, 1.0), (3, 0.22), (5, 0.08))  # a small pager speaker: bright, a little square


def classic():
    beep = tone(2900, 0.11, PIEZO)
    burst = np.concatenate([beep, gap(0.07), beep, gap(0.07), beep])
    return np.concatenate([burst, gap(0.35), burst])


def two_tone():
    """A dispatch page: one tone, a second higher tone, then the alert beeps, as a county's fire pagers do."""
    a = tone(1011.6, 0.8, ((1, 1.0), (2, 0.15)), fade=0.01)
    b = tone(1153.4, 1.4, ((1, 1.0), (2, 0.15)), fade=0.01)
    beep = tone(2900, 0.09, PIEZO)
    return np.concatenate([a, b, gap(0.25), beep, gap(0.06), beep, gap(0.06), beep])


def soft():
    chirp = tone(880, 0.16, ((1, 1.0), (2, 0.3)), glide_to=1320)
    hold = tone(1320, 0.35, ((1, 1.0), (2, 0.3)), fade=0.12)
    return np.concatenate([chirp, gap(0.1), chirp, gap(0.1), hold])


def rms(samples):
    return float(np.sqrt(np.mean(np.square(samples)))) if len(samples) else 0.0


CHOICE = "classic"  # Z, 2026-11-07: "1-classic-beeps"
TONES = {"classic": ("1-classic-beeps", lambda: classic()), "two_tone": ("2-two-tone-dispatch", lambda: two_tone()), "soft": ("3-soft-alert", lambda: soft())}


def game_levels(game):
    """How loud the game's own interface sounds are, to match."""
    levels = []
    for file in ("uiNotification.ogg", "uiQuery.ogg", "gps/gpsLineEnd.ogg", "gps/gpsEngage.ogg"):
        data, _ = sf.read(str(game / file), dtype="float32")
        mono = data.mean(axis=1) if data.ndim > 1 else data
        levels.append(rms(mono[np.abs(mono) > 0.01]))
    return float(np.median(levels))


def matched(samples, target):
    loud = samples[np.abs(samples) > 0.01]
    return samples * min(target / rms(loud), 0.89 / float(np.abs(samples).max()))


def ship():
    target = game_levels(game_dir() / "data" / "sounds" / "ui")
    samples = matched(TONES[CHOICE][1](), target)
    out = ROOT / "mod" / "sounds"
    out.mkdir(parents=True, exist_ok=True)
    sf.write(str(out / "pager.ogg"), samples, RATE, format="OGG", subtype="VORBIS")
    print("mod/sounds/pager.ogg: %s, %.2f s" % (TONES[CHOICE][0], len(samples) / RATE))


def main():
    if "--ship" in sys.argv:
        ship()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    game = game_dir() / "data" / "sounds" / "ui"
    picks = [("4-game-notification", "uiNotification.ogg"), ("5-game-query", "uiQuery.ogg"), ("6-game-gps-row-end", "gps/gpsLineEnd.ogg"),
             ("7-game-gps-engage", "gps/gpsEngage.ogg")]
    levels = []
    for name, file in picks:
        data, rate = sf.read(str(game / file), dtype="float32")
        sf.write(str(OUT / (name + ".wav")), data, rate)
        mono = data.mean(axis=1) if data.ndim > 1 else data
        levels.append(rms(mono[np.abs(mono) > 0.01]))
        print("%-22s %.2f s, %s, peak %.2f, from $data/sounds/ui/%s" % (name, len(data) / rate, "stereo" if data.ndim > 1 else "mono",
                                                                       float(np.abs(data).max()), file))
    target = float(np.median(levels))  # ours about as loud as the game's own interface sounds
    for name, make in (("1-classic-beeps", classic), ("2-two-tone-dispatch", two_tone), ("3-soft-alert", soft)):
        samples = make()
        loud = samples[np.abs(samples) > 0.01]
        samples = samples * min(target / rms(loud), 0.89 / float(np.abs(samples).max()))
        sf.write(str(OUT / (name + ".wav")), samples, RATE)
        sf.write(str(OUT / (name + ".ogg")), samples, RATE, format="OGG", subtype="VORBIS")
        print("%-22s %.2f s, mono, peak %.2f, ours" % (name, len(samples) / RATE, float(np.abs(samples).max())))
    print("written to", OUT)


if __name__ == "__main__":
    main()
