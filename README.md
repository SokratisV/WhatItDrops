# LootLink

**Target any enemy in World of Warcraft (TBC Classic / Anniversary) and instantly see its loot table.**

[![License: GPL v3](https://img.shields.io/github/license/SokratisV/LootLink?color=blue)](LICENSE)
[![Version](https://img.shields.io/github/v/tag/SokratisV/LootLink?label=version&sort=semver&color=brightgreen)](https://github.com/SokratisV/LootLink/releases)
[![Last commit](https://img.shields.io/github/last-commit/SokratisV/LootLink)](https://github.com/SokratisV/LootLink/commits/master)
![WoW](https://img.shields.io/badge/WoW-TBC%20Classic%20%2F%20Anniversary-f8b700)
![Interface](https://img.shields.io/badge/interface-20505-555)

LootLink shows **Wowhead‑accurate** drop rates for whatever you're looking at — no
website, no alt‑tab. Target a mob, open the window, and see exactly what it drops and
how often. Search items or NPCs by name, drill into "who drops this", list the bosses
of the instance you're standing in, and see which items a quest needs and where they
come from.

> **Drop rates are crowd‑sourced Wowhead measurements** (via the LootCodex database),
> so they reflect live TBC Classic — not emulator approximations.

<!--
Screenshots: drop images into docs/ and reference them here, e.g.
![Loot window](docs/loot-window.png)
![Item browser](docs/browser.png)
-->

## Features

- 🎯 **Loot table for your target** — `/loot`, a keybind, or auto‑show on target.
- 🔎 **Item & NPC browser** — search by name; click an item to see every NPC that
  drops it, or click an NPC to open its loot table.
- 🐉 **Instance boss list** — `/loot bosses` (or the keybind with no target inside a
  dungeon/raid) lists that instance's bosses, each clickable to its loot.
- 📜 **Quest loot** — `/loot quest` (and a **"Loot Needed"** button in the quest log)
  shows the items the selected quest needs and where they drop. Quest‑class drops are
  flagged with a yellow **!** in the loot window.
- 🗺️ **Minimap button** — left‑click reloads the UI, right‑click does a loot lookup,
  drag to reposition. Toggle it in `/loot config`.
- 🎨 **Theming** — Blizzard default or a flat / ElvUI skin.
- 🪶 **Lightweight & offline** — item/NPC names and quality are baked in (no
  `GetItemInfo` flicker), and per‑region data is **loaded on demand** so memory tracks
  where you actually play.

## Installation

1. Download the latest [release](https://github.com/SokratisV/LootLink/releases) (or the
   repository ZIP).
2. Extract it so the **`LootLink*` folders sit directly inside** your
   `World of Warcraft/_classic_/Interface/AddOns/` directory:
   ```
   Interface/AddOns/
     LootLink/
     LootLink_EasternKingdoms/
     LootLink_Instances/
     LootLink_Kalimdor/
     LootLink_Misc/
     LootLink_Outland/
   ```
3. Restart the game (a full restart, not just `/reload`, so the new `.toc` files are
   read) and enable **LootLink** in the AddOns list.

## Usage

| Command | What it does |
|---|---|
| `/loot` (or `/fullloot`) | Loot table for your current target. |
| `/loot browse [text]` | Open the browser; search items **or** NPCs by name. |
| `/loot bosses` | List the bosses of the instance you're in. |
| `/loot quest` | Items the selected quest needs, and where they drop. |
| `/loot auto` | Toggle auto‑showing the window on target. |
| `/loot config` | Open settings & keybinds. |

**Keybind** (default **CTRL‑L**): looks up your target; with no target inside a
dungeon/raid it lists that instance's bosses; otherwise it opens the item browser.

In the loot window: **Hide common loot** drops greys/whites, **Show world drops**
includes the generic world‑drop pool, **Ctrl‑click** an item previews it in the
dressing room, and **Shift‑click** links it in chat.

## What's in this repo

This is a small **family of addons** — one always‑loaded UI addon plus per‑region data
packs that load on demand:

| Addon | Loads | Purpose |
|---|---|---|
| **LootLink** | always (~930 KB) | UI, slash commands, keybinds, item browser, the region loader, and baked item/NPC names + quality. |
| **LootLink_EasternKingdoms** / **_Kalimdor** / **_Outland** / **_Instances** / **_Misc** | LoadOnDemand (~0.3–1.5 MB each) | Per‑continent / per‑instance loot data, loaded only for the region you're in. |

> ⚠️ All six folders must sit **directly** under `Interface/AddOns/` — the data packs
> are separate `LoadOnDemand` addons that the main addon loads via `LoadAddOn`, so they
> can't be nested inside one folder.

## Data & accuracy

Loot **rates, items, world‑drop flags, names, and quality** come from the
**LootCodex** addon's Wowhead‑cache‑derived database (by **Coldnova**, GPL v3 — itself
derived from `cmangos/tbc-db`). NPCs are bucketed into per‑continent / per‑instance
partitions using the `cmangos/tbc-db` `creature` spawn table, so the client only parses
the region you're in.

> **Boss list note:** the Classic/Anniversary client has no Encounter Journal API, so
> bosses are derived from the world DB (a single‑spawn rare+ dropper, or a Rank‑3 elite).
> This nails 5‑man rosters; the gap is script‑**summoned** raid bosses (Ragnaros,
> Majordomo, Nefarian), which have no spawn point to map to an instance.

Regenerating the bundled data is documented in [`LootLink/README.md`](LootLink/README.md).

## Contributing

Bug reports and feature ideas are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and
open an [issue](https://github.com/SokratisV/LootLink/issues). Changes are tracked in
[CHANGELOG.md](CHANGELOG.md).

## License & credits

Distributed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).

This project incorporates data generated from **LootCodex** (GPL v3) and
**cmangos/tbc-db** (GPL v3); as a derivative work it is necessarily GPL v3. Credit to
**Coldnova** (LootCodex) and the **CMaNGOS** project.
