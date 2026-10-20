# Offline test

Loads the addon (Theme, WhatItDrops, Options, Settings) against a permissive WoW stub in a real
**Lua 5.1** runtime (the version WoW uses), then drives it: opens the loot window, flips every
appearance setting, shows a player's gear, opens the settings window and clicks every control.
It runs three client/template combinations (Retail with modern templates, Retail with the
mid-generation ones, Forever with only the legacy ones).

    python -m pip install lupa
    python tools/offline-test/run_harness.py <path to the WhatItDrops folder> tools/offline-test/harness.lua

Exit code 0 means no Lua errors. It checks that code *runs*, not that it *looks right*: layout and
art still need the real game. To confirm it can fail, plant a typo (for example call a function that
doesn't exist inside a click handler) and rerun; it should report it.
