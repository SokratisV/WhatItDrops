# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-06-07

Bug-fix release.

- **Fixed a client freeze/crash** when selecting "Don Carlos (1)" in the browser. That
  NPC carried a corrupted loot table (~8,700 items, all at 100%) that tried to render
  thousands of rows in a single frame. Removed the bad entry, added a hard cap on
  rendered rows, and added a guard in the data generator so an oversized reference dump
  can never be shipped again.
- The loot/item window now always sits **above** the browser, instead of being hidden
  behind the browser it was launched from.
- **Flat / ElvUI skin:** fixed leftover empty boxes (the hidden Back button and URL box
  left orphaned backdrops floating in the window) and skinned the previously-unstyled
  scrollbar.

## [1.0] - 2026-06-07

Initial release as **WhatItDrops**. This is the addon previously published as
**LootLink** (versions 1.0–1.4), rebranded under a new name — same features, same data.

- Targetable loot tables with Wowhead-accurate drop rates (via the **LootCodex** GPLv3
  database, derived from `cmangos/tbc-db`).
- Item & NPC browser, "who drops this" lookups, and instance boss lists.
- Quest-loot view ("Loot Needed" in the quest log) and a yellow **!** marker on
  quest-class drops.
- Per-region **LoadOnDemand** data packs, so memory tracks where you actually play.
- Minimap button, Blizzard / ElvUI theming, settings panel, and keybinds.

Commands: `/loot` (target lookup), `/loot config`, `/loot browse`, `/fullloot`, and
`/whatitdrops`.

[1.0.1]: https://github.com/SokratisV/WhatItDrops/compare/v1.0...v1.0.1
[1.0]: https://github.com/SokratisV/WhatItDrops/commits/master
