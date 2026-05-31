# LootLink

Target any enemy in World of Warcraft (TBC Classic / Anniversary) and see its loot table.

## Addons in this repo

| Addon | Loads | Purpose |
|-------|-------|---------|
| **LootLink** | always (~930 KB) | UI, slash commands, keybinds, item browser, the region loader, and baked item/NPC names + quality. |
| **LootLink_EasternKingdoms / _Kalimdor / _Outland / _Instances / _Misc** | LoadOnDemand (~0.3–1.5 MB each) | Per-continent / per-instance loot data, loaded only for the region you're in. |

## Commands

- `/loot` (or `/fullloot`) — loot table for your current target.
- `/loot browse [text]` — **browser**: search **items _or_ NPCs** by name. Click an item to see which NPCs drop it; click an NPC (or an NPC result) to open its loot table.
- `/loot auto` — toggle auto-show on target.
- `/loot config` — settings & keybinds.

In the window: **Hide common loot** drops greys/whites; **Show world drops** includes the generic world/common-drop pool. **Ctrl+C** reveals the Wowhead link, again copies & closes. **Ctrl-click** an item to preview it in the dressing room; **Shift-click** to link it in chat.

**Keybinds** (default **CTRL-L** = loot for target; second bindable action = open item browser).

## Data

Loot **rates, items, world-drop flags, names, and quality** come from the
[**LootCodex**](https://github.com/) addon's Wowhead-cache-derived database
(by Coldnova, **GPL v3** — itself derived from `cmangos/tbc-db`). Rates are
**Wowhead-measured** (crowd-sourced from live TBC Classic), so they're accurate
and complete, not emulator approximations.

NPCs are bucketed into per-continent / per-instance partitions using the
`cmangos/tbc-db` `creature` spawn table, so the client only parses the region
you're in. Names/quality are baked inline (no `GetItemInfo` flicker, offline,
and they power the search).

### License / credit

This project incorporates data generated from **LootCodex** (GPL v3) and
**cmangos/tbc-db** (GPL v3). As a derivative it is distributed under **GPL v3**;
see those projects for their licenses. Credit to **Coldnova** (LootCodex) and
the **CMaNGOS** project.

## Regenerating data (dev)

From `LootLink/tools/` (PowerShell), with LootCodex installed and the CMaNGOS
world DB available (auto-downloaded/decompressed under `tools/cmangos/`):

```powershell
./generate-from-lootcodex.ps1
```

This rebuilds the partition addons and `Data/LootLinkItems.lua`. The multi-MB
SQL build input under `tools/cmangos/` is git-ignored.
