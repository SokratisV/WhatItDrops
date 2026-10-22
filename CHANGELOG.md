# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] - 2026-10-22

- **Profile export and import.** A new **Profile** page in the settings window (and `/wid export`,
  `/wid import`) turns your whole setup into one line of text, `WID1:...`, and restores it on
  another character or install. It covers every setting, the loot window, browser and settings
  window positions, the minimap button's angle, and your two keybinds. Imports are checked first
  (format, version, checksum, and every value's type and range), never run any code from the text,
  skip anything they don't recognise and say so, and ask for a second click before replacing your
  settings. Anything the profile leaves out goes back to its default.
- **Translations for every WoW client language:** Deutsch, Français, Español (España and
  México), Português (Brasil), Русский, 한국어, 简体中文, 繁體中文 and Italiano. All windows, settings,
  messages, tooltips and key-binding names are translated; gear slot names and the "Search" and
  "Settings" labels use the client's own words. Item names in the loot list now come from the game
  first, so they follow your language. Layouts were loosened for longer languages (labels stop short
  of their controls, buttons widen to fit).
- **Item and creature names in your language on non-English clients.** Searching items in the
  browser and the quest view (which matches a quest's "collect" objectives to items) now work in
  the client's language on Classic and WoW: Forever; before, both only understood English. The first
  search starts collecting the item names in the background (about 50 server requests a second,
  so a cold cache takes around ten minutes; quest items first; paused in combat), says how far it has got, refreshes the results as names arrive, and remembers
  them for next time (roughly 1 MB of saved variables for one language). Searching in English still
  works. Creature names are asked of the client one at a time as they appear (the browser's
  results, the loot window title) and the name of every creature you target is kept; where the client
  can't name a creature it stays English. English clients are untouched. `/loot names` shows what
  your client has given so far. Case-insensitive search now understands accented and Cyrillic
  capitals, not just A-Z.
- **The settings window now remembers where you left it**, like the loot window and browser do.

## [1.3.1] - 2026-10-20

Documentation only; the addon itself is unchanged.

- **READMEs rewritten** for what the addon is now: Retail support (the TrinityCore pack and the
  Encounter Journal bosses), the settings window and loot-window effects, player gear, `/loot
  journal`, and the seven-folder layout.
- **Accuracy claims corrected.** The old "accurate and complete" wording for the Classic data now
  says plainly that it is TBC-era Wowhead data, which suits TBC Classic and can be inaccurate on
  WoW: Forever.
- Developer notes now cover regenerating the Retail pack and running the offline test.

## [1.3.0] - 2026-10-20

- **Loot window polish.** Each row gets a drop-rate bar behind it (width = the chance), a
  quality-coloured border around its icon, and a sparkle beside rare-or-better drops under 2%.
  Rows fade in when a list opens. Optionally, a 3D model of the target sits in a portrait card
  beside the window (off by default).
- **A new settings window**, in the style of FlareUI by Malkkav (MIT): bronze trim, a page
  list on the left, foldable sections in the middle, and a panel on the right that explains
  whatever you hover. Pages: General, Appearance and Keybinds. `/wid` toggles it, `/wid appearance`
  opens that page, and the gear in either window opens it too. The game's own AddOns settings
  keep a small entry with an "Open settings" button.
- **Appearance:** theme swatches (Blizzard, ElvUI, and the new Slate and Parchment), accent
  colour, window opacity and scale, row height (compact, normal, roomy), a switch for each loot
  list effect, and a two-click "Reset appearance". Changes apply to open windows straight away;
  only switching to or from ElvUI needs a `/reload`.
- **Docs:** the READMEs now say plainly that the bundled loot data is TBC-era, so it can be
  inaccurate on WoW: Forever, whose content is Vanilla.

## [1.2.1] - 2026-10-18

- **`/wid`** opens the settings panel directly (same as `/loot config`).
- **Fixed: a player's gear list was incomplete the first time it opened.** Gear was read
  before the inspect reply arrived and never again once the worn items' data loaded, so only
  a second press showed everything. Slots are now kept by item id while their data loads, and
  the list is re-read when inspect data arrives, when item data arrives, and on a short
  timer after the request.
- **One collapsible entry in the AddOns list.** All parts (the main addon, the five Classic
  data packs and the Retail pack) now share `## Group: WhatItDrops`, so they fold under a single
  "WhatItDrops" header the way multi-part addons like Spoken do.
- **Addon icon**: the treasure-chest logo, shipped as `icon.tga` and used for every part.

## [1.2.0] - 2026-10-09

Retail (Midnight 12.1) support.

- **Retail creature loot** from the TrinityCore TDB world database: a new
  `WhatItDrops_Retail` LoadOnDemand pack (8,399 creatures, real drop chances). Item names
  and quality come from the client at runtime.
- **Current dungeon and raid bosses** are read from the Encounter Journal, matched to your
  target by name (the instance you are standing in wins). The Journal has no drop rates, so
  rows show the item slot instead. The Journal's own class/spec filter and difficulty are
  borrowed for the lookup and put back afterwards.
- `/loot bosses` lists the Journal's encounters for the current instance; the browser
  searches Journal bosses alongside creatures.
- `/loot journal [boss]` reports whether the Journal source is available and what it indexed,
  for when a boss goes missing.
- All TOCs now list interface `120100` alongside `16001` and `20505`.

## [1.1.0] - 2026-10-09

WoW Forever support.

- **Runs on WoW Forever** (interface `16001`) alongside the TBC Classic / Anniversary
  client, from one set of files. Forever serves Classic content from the Midnight 12.x
  client, so it reports a Classic project id while exposing only the modern API.
- Item lookups moved to `C_Item.GetItemInfo` / `C_Item.GetItemIconByID`; the loose
  `GetItemInfo` / `GetItemIcon` globals no longer exist on Midnight. Icon lookups are
  now nil-guarded, because `C_Item.GetItemIconByID` raises on a nil id where the old
  global returned nothing (quest objectives that never resolved to an item hit this).
- **Quest required-items view** reads the modern quest log when that's what the client
  has: quests are addressed by questID via `C_QuestLog.GetSelectedQuest`, and objectives
  come from `C_QuestLog.GetNumQuestObjectives` + `GetQuestObjectiveInfo`, using the
  reported fulfilled/required counts instead of re-parsing the localised text. The
  classic leader-board path is kept and still wins on clients that have it.
- The **Loot Needed** button attaches to `QuestMapFrame` when there's no standalone
  `QuestLogFrame`, and is skipped quietly if neither exists (`/loot quest` still works).
- Wowhead links resolve to the **classic** database on Forever.
- **Settings survive login on WoW Forever.** Forever hands over SavedVariables after
  `ADDON_LOADED`, so defaults seeded there could be discarded moments later. Defaults are
  now seeded again at `PLAYER_LOGIN`.
- Quality colouring, shift-click chat links and ctrl-click dressing-room previews no longer
  depend on a single legacy global each; a missing one degrades to a plain row / no-op
  instead of raising.

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

[1.4.0]: https://github.com/SokratisV/WhatItDrops/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/SokratisV/WhatItDrops/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/SokratisV/WhatItDrops/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/SokratisV/WhatItDrops/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SokratisV/WhatItDrops/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SokratisV/WhatItDrops/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/SokratisV/WhatItDrops/compare/v1.0...v1.0.1
[1.0]: https://github.com/SokratisV/WhatItDrops/commits/master
