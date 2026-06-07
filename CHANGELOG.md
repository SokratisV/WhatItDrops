# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4] - 2026-06-07

### Added
- **Quest‑item markers** — quest‑class drops are flagged with a yellow **!** in the
  loot window, backed by a generated `Data/LootLinkQuestItems.lua`.
- **Minimap button** via embedded LibDBIcon‑1.0: left‑click reloads the UI, right‑click
  does a loot lookup, drag to move; toggle it in `/loot config`.
- `tools/bundle.ps1` to build the shareable install ZIP.
- **GPL‑3.0 LICENSE** file (the project is a GPL v3 derivative of LootCodex /
  cmangos/tbc-db).

### Fixed
- Removed `Bindings.xml` from the `.toc` so it's no longer parsed twice — clears the
  "Unrecognized XML" warnings on login (the client auto‑loads it).

## [1.3] - 2026-06-06

### Added
- **Instance boss list** — `/loot bosses`, and the keybind with no target inside a
  dungeon/raid lists that instance's bosses.

### Fixed
- Hardened the URL‑copy keyboard capture so `Esc` can't get stranded.

## [1.2] - 2026-06-01

### Fixed
- Quest‑item nil‑ID crash.
- Browser keyboard capture.

## [1.1] - 2026-06-01

### Added
- Quest‑log **"Loot Needed"** button.

### Fixed
- Combat keyboard taint.

## [1.0] - 2026-05-31

- Initial public release: targetable loot tables with Wowhead‑accurate (LootCodex)
  data, item & NPC browser, inline names/quality, per‑region LoadOnDemand data packs,
  theming, settings, and keybinds.

[1.4]: https://github.com/SokratisV/LootLink/compare/v1.3...v1.4
[1.3]: https://github.com/SokratisV/LootLink/compare/v1.2...v1.3
[1.2]: https://github.com/SokratisV/LootLink/compare/v1.1...v1.2
[1.1]: https://github.com/SokratisV/LootLink/releases/tag/v1.1
[1.0]: https://github.com/SokratisV/LootLink/commits/master
