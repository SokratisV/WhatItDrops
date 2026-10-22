# WhatItDrops

**Target any enemy in World of Warcraft (Retail, WoW: Forever or TBC Classic) and instantly see its loot table.**

[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/SokratisV/WhatItDrops)](https://github.com/SokratisV/WhatItDrops/releases/latest)
![WoW](https://img.shields.io/badge/WoW-Retail%20%2F%20Forever%20%2F%20TBC%20Classic-f8b700)
![Interface](https://img.shields.io/badge/interface-120100%20%7C%2016001%20%7C%2020505-555)

> **WoW: Forever accuracy.** The bundled Classic-side loot data comes from a TBC-era database,
> but Forever's content is Vanilla. Drop rates, which creatures drop what, and which items exist
> can therefore be **inaccurate on WoW: Forever**. Treat the lists there as a guide, not gospel.
> Retail uses retail data and is not affected.

> **Client support.** One download runs on **Retail** (interface `120100`), **WoW Forever**
> (`16001`) and the **TBC Classic / Anniversary** client (`20505`). Forever serves Classic content
> from the Midnight 12.x client, so it reports a Classic project id but only exposes the modern
> namespaced API; every call that moved is feature-detected rather than switched on project id.

WhatItDrops shows you what whatever you are looking at drops, with no website and no alt-tab.
Target a mob, open the window, and see its loot and how often it drops. Search items or creatures
by name, drill into "who drops this", list the bosses of the instance you are standing in, and see
which items a quest needs and where they come from.

<!--
Screenshots: drop images into docs/ and reference them here, e.g.
![Loot window](docs/loot-window.png)
![Item browser](docs/browser.png)
-->

## Features

- 🎯 **Loot table for your target**, via `/loot`, a keybind, or auto-show on target.
- 🔎 **Item and creature browser.** Search by name; click an item to see every creature that
  drops it, or click a creature to open its loot table.
- 🐉 **Instance boss list.** With no target inside a dungeon or raid, the keybind lists that
  instance's bosses, each clickable to its loot.
- 📜 **Quest loot.** A **"Loot Needed"** button in the quest log shows the items the selected
  quest needs and where they drop. Quest-class drops are flagged with a yellow **!**.
- 🧍 **Player gear.** Target another player to see what they have equipped.
- 🗺️ **Retail bosses from the Encounter Journal.** Current dungeon and raid bosses are read from
  the game itself, so they stay current. The Journal has no drop rates, so those rows show the
  item slot instead.
- ✨ **Loot window polish.** A drop-rate bar behind each row, quality-coloured icon borders, a
  sparkle on rare-or-better drops under 2%, rows that fade in, and an optional 3D model of the
  target. Each effect has its own switch.
- 🎨 **Settings window.** Themes (Blizzard, ElvUI, Slate, Parchment), accent colour, opacity,
  scale and row height, all applied live. Every setting is explained in a panel as you hover it.
- 🗺️ **Minimap button.** Left-click reloads the UI, right-click does a loot lookup, drag to
  reposition. Toggle it in the settings.
- 🪶 **Lightweight.** Per-region data loads **on demand**, so memory tracks where you actually
  play. On the Classic clients, item and creature names are baked in (no `GetItemInfo`
  flicker); on Retail they come from the game.

## Usage

| Command | What it does |
|---|---|
| `/loot` (or `/fullloot`) | Loot table for your current target. |
| `/loot browse [text]` | Search items **or** creatures by name. |
| `/loot bosses` | The bosses of the instance you are in. |
| `/loot quest` | Items the selected quest needs, and where they drop. |
| `/loot auto` | Toggle auto-show on target. |
| `/wid` (or `/loot config`) | Open the settings window. |
| `/wid appearance` | Open it on the Appearance page. |
| `/wid export` / `/wid import` | Copy your whole setup as one line of text, or paste one back. |
| `/loot journal [boss]` | Retail: say whether the Encounter Journal source is working and what it found. Useful when a boss is missing. |

**Keybind** (default **CTRL-L**, set once and only if that key is free): looks up your target.
With no target inside a dungeon or raid it lists that instance's bosses; otherwise it opens the
item browser. Rebind it on the Keybinds page.

In the loot window: **Hide common loot** drops greys and whites, **Show world drops** includes
the generic world-drop pool (Classic data only), **Ctrl+C** reveals the Wowhead link (press again
to copy and close), **Ctrl-click** previews an item in the dressing room, and **Shift-click**
links it in chat.

## What's in this repo

A small **family of addons**: one always-loaded UI addon plus data packs that load on demand.

| Addon | Loads | Purpose |
|---|---|---|
| **WhatItDrops** | always (about 1 MB) | The windows, slash commands, keybinds, settings, item browser, the data loader, and (on Classic clients) baked item and creature names. |
| **WhatItDrops_EasternKingdoms** / **_Kalimdor** / **_Outland** / **_Instances** / **_Misc** | on demand (about 0.3 to 1.5 MB each) | Classic-side loot data per continent or instance, loaded only for the region you are in. |
| **WhatItDrops_Retail** | on demand (about 3 MB) | Retail creature loot, loaded only on Retail. |

> ⚠️ All the folders must sit **directly** under `Interface/AddOns/`. The data packs are separate
> `LoadOnDemand` addons that the main addon loads by name, so they can't be nested inside one
> folder. The download contains all of them; the ones your client doesn't use simply stay unloaded.

## Data and accuracy

- **Classic clients (TBC Classic and WoW: Forever).** Loot rates, items, world-drop flags, names
  and quality come from the **LootCodex** addon's Wowhead-derived database (by Coldnova, GPL v3,
  itself derived from `cmangos/tbc-db`). Rates are Wowhead measurements from TBC Classic, so they
  fit TBC Classic well. **They are TBC data, not Vanilla**, which is why they can be wrong on
  WoW: Forever. Creatures are bucketed into per-continent and per-instance packs using the
  `cmangos/tbc-db` spawn table.
- **Retail creatures.** Loot and chances come from the **TrinityCore** `TDB` world database
  (GPL v3), covering about 8,400 creatures. It has no loot for current instanced bosses, because
  Retail builds that from the Encounter Journal.
- **Retail bosses.** Read live from the in-game Encounter Journal: always current, but items only,
  with no drop rates.

> **Boss list note (Classic clients):** there is no Encounter Journal API there, so bosses are
> derived from the world database (a single-spawn rare-or-better dropper, or a Rank 3 elite). That
> covers 5-man rosters well; the gap is script-**summoned** raid bosses (Ragnaros, Majordomo,
> Nefarian), which have no spawn point to map to an instance.

Regenerating the bundled data is documented in [`WhatItDrops/README.md`](WhatItDrops/README.md).

## Contributing

Bug reports and feature ideas are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and open an
[issue](https://github.com/SokratisV/WhatItDrops/issues). Changes are tracked in
[CHANGELOG.md](CHANGELOG.md).

## License and credits

Distributed under the **GNU General Public License v3.0**; see [LICENSE](LICENSE).

This project incorporates data generated from **LootCodex** (GPL v3), **cmangos/tbc-db**
(GPL v3) and the **TrinityCore** TDB (GPL v3); as a derivative work it is necessarily GPL v3.
Credit to **Coldnova** (LootCodex), the **CMaNGOS** project and the **TrinityCore** project.
The settings window is in the style of **FlareUI** by Malkkav (MIT).
