# Contributing

Bug reports, and reports on how it works with other mods and maps, are the most useful things right now. Corrections to any of the translations are welcome too.

**Reporting a bug:** use the [bug form](https://github.com/zeyadrabie/FS25_RoadsideEmergencies/issues/new/choose). Say what you did, what you expected and what happened, and attach your `log.txt` from
`Documents/My Games/FarmingSimulator2025`, copied **before you restart the game**. Lines from this mod start with `[FS25_RoadsideEmergencies]`.

**Sending a fix or a translation:** the mod is all rights reserved (see [LICENSE](LICENSE)). By sending one, you agree that it can be used in the mod, with credit.

**Working on the code:**

- Lua 5.1 only. Rules that don't need the game go in `mod/scripts/core/` with tests in `tests/spec/`; anything that touches the game goes in `mod/scripts/game/`.
- Every state change goes through `RseStore:apply`, so multiplayer can wrap it later.
- Hooks only pass through or add to the game's functions. List each one in `docs/HOOKS.md`.
- Every player-facing text goes in every `mod/translations/` file, as full sentences that fit any count. `python tools/check_l10n.py` checks each language for missing texts, lost placeholders and, where the game is installed, characters the game's font lacks and texts too wide for their place.
- Before a pull request: `lua5.1 tests/run.lua`, `luacheck mod tests` with no warnings, and `python tools/build.py --check`.
- Use Conventional Commits. Never commit game code or assets; refer to base-game models by their `$data/...` path.
