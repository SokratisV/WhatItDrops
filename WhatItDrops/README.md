# WhatItDrops

Target any enemy in World of Warcraft (Retail, WoW: Forever or TBC Classic) and see its loot table.

> **WoW: Forever data.** Forever loads its own database, the CMaNGOS **Vanilla 1.12** one, chosen by its own `_Forever.toc` files; the TBC clients load the TBC one. Forever is Vanilla-based but not identical to the 1.12 server data, so some drop rates and items can still differ from the game. Treat the lists as a guide, not gospel. `/loot data` says which database your client loaded.

> **Client support.** Runs on **Retail** (interface `120100`), **WoW Forever** (`16001`) and the
> **TBC Classic / Anniversary** client (`20505`) from the same files. Retail reads creature loot
> from the bundled `WhatItDrops_Retail` pack (TrinityCore database, GPL v3) and current
> dungeon/raid bosses from the in-game Encounter Journal (no drop rates there, so rows show the
> item slot). Forever serves Classic content from the Midnight 12.x client, so it reports a
> Classic project id but only exposes the modern namespaced API; every call that moved is
> feature-detected rather than switched on project id.

> **Languages.** The interface is translated into English, Deutsch, Español (España and México), Français, Italiano, Português (Brasil), Русский, 한국어, 简体中文 and 繁體中文; the game client's own language is used automatically. On a non-English Classic client the browser's search and the quest view also work in the client's language, and creature names follow it where the client can give them (see `Names.lua`); searching in English still works.

## Addons in this repo

| Addon | Loads | Purpose |
|-------|-------|---------|
| **WhatItDrops** | always (about 1 MB) | Windows, slash commands, keybinds, settings, item browser, the data loader, and (Classic clients) baked item and creature names. |
| **WhatItDrops_EasternKingdoms / _Kalimdor / _Outland / _Instances / _Misc** | on demand (about 0.3 to 1.5 MB each) | Per-continent and per-instance Classic loot data, loaded only for the region you are in. |
| **WhatItDrops_Retail** | on demand (about 3 MB) | Retail creature loot. |

All the folders must sit directly under `Interface/AddOns/`.

## Commands

- `/loot` (or `/fullloot`): loot table for your current target; for a player, their equipped gear.
- `/loot browse [text]`: **browser**. Search **items or NPCs** by name. Click an item to see which NPCs drop it; click an NPC to open its loot table.
- `/loot bosses`: list the **bosses of the instance you are in** (each clickable to its loot). This is also what the loot keybind does with no target inside a dungeon or raid.
- `/loot quest`: items the **selected quest** needs, and where they drop. Also a **"Loot Needed"** button in the quest log (turn it off, make it round, or Shift-drag it elsewhere; see the settings).
- `/loot names`: non-English clients: how many item and creature names the client has given us so far, and what it answers for your target.
- `/loot auto`: toggle auto-show on target.
- `/wid` (or `/loot config`): open the settings window. `/wid appearance` opens it on the Appearance page.
- `/wid export` / `/wid import`: copy your whole setup (every setting, window positions, the minimap button and your two keybinds) as one line of text, or paste one back. Also on the settings window's **Profile** page.
- `/loot journal [boss]`: Retail only. Reports whether the Encounter Journal source works and what it indexed; with a name, which encounters match it.

In the window: quest-item drops are flagged with a yellow **!**. **Hide common loot** drops greys and whites; **Show world drops** includes the generic world-drop pool (Classic data only). With the mouse over the window **Ctrl+C** reveals the Wowhead link, again copies and closes. **Ctrl-click** an item to preview it in the dressing room; **Shift-click** to link it in chat.

**Keybinds** (default **CTRL-L**, set once and only if that key is free; pressing it again closes the window it opened, unless your target changed): looks up your target; with no target inside a dungeon or raid it lists that instance's bosses; otherwise it opens the item browser. Rebind it on the Keybinds page.

**Minimap button:** left-click **reloads the UI**, right-click does a loot lookup (same as the keybind), drag to move it around the minimap. Toggle it in the settings.

## Settings

`/wid` opens a window with three pages: **General** (lookup behaviour and the minimap button),
**Appearance** (theme, accent colour, opacity, scale, row height, and a switch for each loot-window
effect) and **Keybinds**. Hover any setting to see what it does in the panel on the right. Changes
apply to open windows straight away; only switching to or from the ElvUI theme needs a `/reload`.

The effects are drop-rate bars, quality-coloured icon borders, a sparkle on rare-or-better drops
under 2%, rows that fade in, and an optional 3D model of the target. The window is in the style of
FlareUI by Malkkav (MIT).

> **Boss list note (Classic clients):** there is no Encounter Journal API there, so bosses are derived from the world DB (a single-spawn rare-or-better dropper, or a Rank 3 elite). This covers 5-man rosters well; the gap is script-**summoned** raid bosses (Ragnaros, Majordomo, Nefarian), which have no spawn point to map to an instance. On Retail the roster comes from the Encounter Journal.

## Data

**Classic clients.** Everything comes from the **CMaNGOS** world databases (GPL v3): the loot
tables are resolved into plain drop chances (groups, references and quest drops included), and
item names, quality, creature names, the boss list and the quest-item flags come from the same
dump. **TBC Classic** uses `cmangos/tbc-db` (TBC 2.4.3); **WoW: Forever** uses `cmangos/classic-db`
(Vanilla 1.12). Each client loads only its own: the main addon and the five data packs ship a
default TOC (TBC) and `_Forever.toc` / `_Camelot.toc` variants (Vanilla), and the client picks
the one matching its game type. These are a server emulator's numbers, not live measurements.
Zone-wide pools (green and blue world drops) are listed after the creature's own drops, limited
to chances of 0.1% or more. Creatures are bucketed into per-continent and per-instance
partitions using the `creature` spawn tables, so the client only parses the region you are in.
Names and quality are baked inline (no `GetItemInfo` flicker, offline, and they power the
search).

**Retail creatures.** Loot and chances come from the **TrinityCore** `TDB` world database
(**GPL v3**), about 8,400 creatures. It has no loot for current instanced bosses (Retail builds
that from the Encounter Journal), and it carries almost no item names, so item names and quality
come from the game at runtime.

**Retail bosses.** Read live from the in-game Encounter Journal: always current, items only.

### License / credit

This project incorporates data generated from **cmangos/tbc-db** and the **TrinityCore** TDB
(both GPL v3). As a derivative it is distributed under **GPL v3**; see those projects for their
licenses. Credit to the **CMaNGOS** project and the **TrinityCore** project.

## Working copy and testing in game (dev)

The repository is kept **outside** the game folders (it lives at `E:/Projects/WhatItDrops`) so the
CurseForge app never sees it as an installed addon and never offers to "update" over your work. To try a
change in game, copy it in:

```
python tools/deploy.py              # WoW Forever and Retail
python tools/deploy.py --forever    # only Forever
python tools/deploy.py --dry-run    # show what would change
```

It copies only what the release zip holds (no `tools/`, no `logo.png`), with LF line endings, and
removes files the repo no longer has. The CurseForge app may then offer to restore the released
version over your test build; just deploy again.

## Regenerating data (dev)

### Classic packs

Download a base dump from the CMaNGOS repos' `Full_DB/` folders and decompress it (the `.sql` files
are git-ignored): `cmangos/tbc-db` `TBCDB_*.sql.gz` to `tools/cmangos/tbcdb.sql`, and
`cmangos/classic-db` `ClassicDB_*.sql.gz` to `tools/cmangos/classic/classicdb.sql`. Then:

```
python tools/generate-from-cmangos.py tools/cmangos/tbcdb.sql <your AddOns folder>
python tools/generate-from-cmangos.py tools/cmangos/classic/classicdb.sql <your AddOns folder> --vanilla
python tools/localize-tocs.py <your AddOns folder>
python tools/check-tocs.py <your AddOns folder>
```

The first rebuilds the five regional packs (`WhatItDrops_<Region>.lua`) and
`Data/WhatItDrops{Items,Bosses,QuestItems}.lua`; with `--vanilla` the packs are
`WhatItDrops_<Region>_Vanilla.lua` and the data goes to `Data/Forever/`. A boss is a
single-spawn creature that drops a rare-or-better item, or a Rank 3 creature. `localize-tocs.py`
writes the localized TOC lines and the `_Forever.toc` / `_Camelot.toc` variants, and
`check-tocs.py` loads each client's TOC file list in a fresh Lua state to prove it gets only its
own database. `tools/cmangos_loot.py` does the loot maths and `python tools/test_cmangos_loot.py`
checks it against hand-worked examples.

### Retail pack

Download a TrinityCore `TDB_full` release matching the current Retail build (from the TrinityCore
GitHub releases), extract the `TDB_full_world_*.sql` file, then:

```
python tools/generate-retail-from-tdb.py <TDB_full_world_*.sql> <your AddOns folder>
```

This writes the `WhatItDrops_Retail` addon (a `.lua` and a `.toc`). Group rolls are resolved into
real percentages, and one loot table is kept per creature (the base difficulty when there is one).
Bump the version string in the script when you cut a release, so a regeneration can't roll it back.

### Translations

Every player-visible string is `L["English text"]`; the English text is the key, so a missing
translation falls back to English. `Locales/Locale.lua` creates `ns.L`, and `Locales/<code>.lua`
adds one language each (deDE, frFR, esES, esMX, ptBR, ruRU, koKR, zhCN, zhTW, itIT). Add a string
by wrapping it in `L[...]` and adding a line to every locale file, then run:

```
python tools/check-locales.py <path to the WhatItDrops folder>
```

It checks that every key is present in every language and nothing extra is, that each translation
keeps the placeholders (`%s`, `%d`) in order and the colour markup, that no English was left in,
that the TOC loads the locale files before the code and has a `Notes-xxXX` line per language, that
no player-visible string is left unwrapped, and that every file compiles (with `lupa` installed).
`tools/toc_locales.py` holds the translated TOC titles and notes; `tools/localize-tocs.py <AddOns
folder>` writes them into all seven TOCs. Slash-command words, saved-variable names and the
profile format are never translated.

A literal `%` is fine in a key that is only ever passed to `SetText`; in a key that goes through
`:format` write `%%` (the check enforces both, and translations use each language's own
percentage style, such as `1,8 %` or `1.8%`).

### Names in the player's language

The bundled data is English. `Names.lua` is inert on English clients (and on Retail items, which already come from the game). On any other language it asks the client: item names through `C_Item.GetItemNameByID` / `RequestLoadItemDataByID` (started by the first browser search or quest view, quest-class items first; at most about 50 server requests a second, names the client already has are read freely; paused in combat. Later sessions ask again only for names still missing, stop once a pass finds nothing new, and start over when the game build changes) and creature names through `C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-<id>-0")` (one lazy lookup per creature shown, at most 20 a second, never a hidden tooltip), plus the name of every creature you target. Results are kept per language in `WhatItDropsDB.l10n`, and a name the client cannot give stays English. Search text is folded with a UTF-8 aware lower-casing, because `string.lower` only handles ASCII.

### Offline test

`tools/offline-test/` loads the addon against a stub WoW client in a real Lua 5.1 runtime and
clicks every control; see its README. It checks that code runs, not how it looks.
