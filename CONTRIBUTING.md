# Contributing to WhatItDrops

Thanks for your interest! Bug reports, feature ideas, and pull requests are all welcome.

## Reporting bugs

Open an [issue](https://github.com/SokratisV/WhatItDrops/issues/new/choose) using the **Bug
report** template. The most useful things to include:

- Your **WoW flavor/build** (TBC Classic / Anniversary) and **WhatItDrops version**
  (`/loot config` shows it, or see the `.toc`).
- Exact **steps to reproduce**.
- Any **Lua errors** — install [BugSack](https://www.curseforge.com/wow/addons/bugsack)
  + BugGrabber and paste the full error + stack.
- Whether it still happens with **only WhatItDrops enabled** (rules out addon conflicts).

> Note: changes to a `.toc` file only take effect after a **full game restart**, not a
> `/reload`.

## Development notes

- **Code** is plain Lua + a little XML, targeting the TBC Classic API (Interface
  `20505`). Keep new APIs guarded for that client (no Retail‑only calls).
- **Indentation is tabs** (see `.editorconfig`).
- The repo lives in a shared `Interface/AddOns` folder; only the `WhatItDrops*` addons are
  tracked (everything else is ignored). Each addon must be a **direct child** of
  `AddOns/`.
- The big **loot data files are generated**, not hand‑edited — see the regeneration
  scripts documented in [`WhatItDrops/README.md`](WhatItDrops/README.md)
  (`tools/*.ps1`). Don't edit `Data/WhatItDrops*Items.lua` / `WhatItDropsBosses.lua` by hand.

## Pull requests

- Branch off `master`, keep commits focused, and write a clear summary.
- Bump the `## Version:` in the affected `.toc` files and add a `CHANGELOG.md` entry.
- By contributing you agree your changes are licensed under **GPL‑3.0** (this project is
  a GPL v3 derivative of LootCodex / cmangos/tbc-db and cannot be relicensed).
