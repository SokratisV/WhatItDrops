# WhatItDrops

Target any enemy in World of Warcraft (Retail, WoW: Forever or TBC Classic) and see its loot table.

> **WoW: Forever accuracy.** The bundled Classic-side loot data comes from a TBC-era database,
> but Forever's content is Vanilla. Drop rates, which creatures drop what, and which items exist
> can therefore be **inaccurate on WoW: Forever**. Treat the lists there as a guide, not gospel.
> Retail uses retail data and is not affected.

> **Client support.** Runs on **Retail** (interface `120100`), **WoW Forever** (`16001`) and the
> **TBC Classic / Anniversary** client (`20505`) from the same files. Retail reads creature loot
> from the bundled `WhatItDrops_Retail` pack (TrinityCore database, GPL v3) and current
> dungeon/raid bosses from the in-game Encounter Journal (no drop rates there, so rows show the
> item slot). Forever serves Classic content from the Midnight 12.x client, so it reports a
> Classic project id but only exposes the modern namespaced API; every call that moved is
> feature-detected rather than switched on project id.

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
- `/loot quest`: items the **selected quest** needs, and where they drop. Also a **"Loot Needed"** button in the quest log.
- `/loot auto`: toggle auto-show on target.
- `/wid` (or `/loot config`): open the settings window. `/wid appearance` opens it on the Appearance page.
- `/wid export` / `/wid import`: copy your whole setup (every setting, window positions, the minimap button and your two keybinds) as one line of text, or paste one back. Also on the settings window's **Profile** page.
- `/loot journal [boss]`: Retail only. Reports whether the Encounter Journal source works and what it indexed; with a name, which encounters match it.

In the window: quest-item drops are flagged with a yellow **!**. **Hide common loot** drops greys and whites; **Show world drops** includes the generic world-drop pool (Classic data only). **Ctrl+C** reveals the Wowhead link, again copies and closes. **Ctrl-click** an item to preview it in the dressing room; **Shift-click** to link it in chat.

**Keybinds** (default **CTRL-L**, set once and only if that key is free): looks up your target; with no target inside a dungeon or raid it lists that instance's bosses; otherwise it opens the item browser. Rebind it on the Keybinds page.

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

**Classic clients (TBC Classic and WoW: Forever).** Loot rates, items, world-drop flags, names and
quality come from the **LootCodex** addon's Wowhead-derived database (by Coldnova, **GPL v3**,
itself derived from `cmangos/tbc-db`). Rates are Wowhead measurements from TBC Classic, so they
fit TBC Classic well. They are TBC data, not Vanilla, which is why they can be inaccurate on
WoW: Forever. Creatures are bucketed into per-continent and per-instance partitions using the
`cmangos/tbc-db` `creature` spawn table, so the client only parses the region you are in. Names
and quality are baked inline (no `GetItemInfo` flicker, offline, and they power the search).

**Retail creatures.** Loot and chances come from the **TrinityCore** `TDB` world database
(**GPL v3**), about 8,400 creatures. It has no loot for current instanced bosses (Retail builds
that from the Encounter Journal), and it carries almost no item names, so item names and quality
come from the game at runtime.

**Retail bosses.** Read live from the in-game Encounter Journal: always current, items only.

### License / credit

This project incorporates data generated from **LootCodex**, **cmangos/tbc-db** and the
**TrinityCore** TDB (all GPL v3). As a derivative it is distributed under **GPL v3**; see those
projects for their licenses. Credit to **Coldnova** (LootCodex), the **CMaNGOS** project and the
**TrinityCore** project.

## Regenerating data (dev)

### Classic packs

From `WhatItDrops/tools/` (PowerShell), with LootCodex installed and the CMaNGOS world DB
available (auto-downloaded and decompressed under `tools/cmangos/`):

```powershell
./generate-from-lootcodex.ps1
```

This rebuilds the Classic partition addons and `Data/WhatItDropsItems.lua`. The multi-MB SQL
build input under `tools/cmangos/` is git-ignored.

```powershell
./generate-bosses.ps1
```

This rebuilds `Data/WhatItDropsBosses.lua` (instance map id to boss NPC ids) from the same
CMaNGOS `creature` / `creature_template` tables plus LootCodex item quality.

```powershell
./generate-questitems.ps1
```

This rebuilds `Data/WhatItDropsQuestItems.lua` (item ids that are Quest-class in
`item_template`), used to flag quest drops with a marker in the loot window.

### Retail pack

Download a TrinityCore `TDB_full` release matching the current Retail build (from the TrinityCore
GitHub releases), extract the `TDB_full_world_*.sql` file, then:

```
python tools/generate-retail-from-tdb.py <TDB_full_world_*.sql> <your AddOns folder>
```

This writes the `WhatItDrops_Retail` addon (a `.lua` and a `.toc`). Group rolls are resolved into
real percentages, and one loot table is kept per creature (the base difficulty when there is one).
Bump the version string in the script when you cut a release, so a regeneration can't roll it back.

### Offline test

`tools/offline-test/` loads the addon against a stub WoW client in a real Lua 5.1 runtime and
clicks every control; see its README. It checks that code runs, not how it looks.
