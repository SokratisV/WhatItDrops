# LootLink

Target any enemy in World of Warcraft (TBC Classic / Anniversary) and see its loot.

## Addons in this repo

| Addon | Loads | Purpose |
|-------|-------|---------|
| **LootLink** | always (~280 KB) | UI, slash commands, keybinds, and the whole-game **Wowhead** drop table (via Questie). Powers `/loot`. |
| **LootLink_Full** | engine, LoadOnDemand | Loader + shared logic for the complete **CMaNGOS-TBC** loot tables. |
| **LootLink_EasternKingdoms / _Kalimdor / _Outland / _Instances / _Misc** | LoadOnDemand | Per-continent / per-instance CMaNGOS data, loaded only for where you are. |

## Commands

- `/loot` — notable / quest-relevant drops for your target (Wowhead %).
- `/fullloot` — complete loot table for your target (CMaNGOS %, with Wowhead % shown alongside when known).
- `/loot auto` — toggle auto-show on target.
- `/loot config` — settings & keybinds.
- Default keybind **CTRL-L** = full loot for target.

In the window: tick **Hide common loot** to drop greys/whites; tick **Show world drops** to include the generic world-drop pool. Press **Ctrl+C** to reveal the Wowhead link, again to copy & close.

## Data sources

- **Wowhead %** — baked from Questie's bundled `wowheadData` (quest-relevant items). No Questie runtime dependency.
- **Full tables** — CMaNGOS-TBC world DB (`creature_loot_template` + `reference_loot_template`), with effective per-kill % computed from mangos group/equal-chance rules. Approximate, not Wowhead-exact.

## Regenerating data (dev)

From `LootLink/tools/` (PowerShell):

```powershell
# Wowhead overlay (needs Questie installed):
./generate-wowhead.ps1
# Full CMaNGOS tables (auto-downloads + decompresses the world DB):
./generate-full.ps1
```

Generated data files are committed; the multi-MB SQL build inputs under `tools/cmangos/` are git-ignored and re-downloaded on demand.
