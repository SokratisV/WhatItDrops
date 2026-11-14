"""Check the per-client TOC files and that each client loads only its own loot database.

    python tools/check-tocs.py <AddOns folder>

The default TOCs list the TBC data (TBC Anniversary, and the fallback for any client without its
own TOC); <Folder>_Forever.toc / <Folder>_Camelot.toc list the vanilla data for WoW Forever. For
each of the two it reads the TOC file lists, "loads" the listed data files in a fresh Lua 5.1
state the way the client would, and checks:

  * every listed file exists, and the Forever and Camelot variants are identical
  * the Forever TOCs name only vanilla data and the default TOCs only TBC data (never both)
  * the loaded database is the right one (WhatItDropsDataSource) and holds the right creatures
    (Doomwalker, an Outland boss, only in the TBC set; Hogger, a vanilla one, in both)
"""
import os
import re
import sys

from lupa.lua51 import LuaRuntime

root = sys.argv[1] if len(sys.argv) > 1 else "."
PACKS = ["EasternKingdoms", "Kalimdor", "Outland", "Instances", "Misc"]
errors = []


def err(msg):
    errors.append(msg)


def listed_files(path):
    out = []
    for line in open(path, encoding="utf-8").read().splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            out.append(s.replace("\\", "/"))
    return out


def toc_path(folder, suffix=""):
    return os.path.join(root, folder, folder + (("_" + suffix) if suffix else "") + ".toc")


# ---- file-level checks
for folder in ["WhatItDrops"] + ["WhatItDrops_" + p for p in PACKS]:
    for suffix in ("", "Forever", "Camelot"):
        p = toc_path(folder, suffix)
        if not os.path.exists(p):
            err("%s: missing" % os.path.relpath(p, root))
            continue
        for f in listed_files(p):
            if not os.path.exists(os.path.join(root, folder, f)):
                err("%s lists %s, which does not exist" % (os.path.relpath(p, root), f))
    pf, pc = toc_path(folder, "Forever"), toc_path(folder, "Camelot")
    if os.path.exists(pf) and os.path.exists(pc) and open(pf, "rb").read() != open(pc, "rb").read():
        err("%s: the Forever and Camelot TOCs differ" % folder)
    d = listed_files(toc_path(folder)) if os.path.exists(toc_path(folder)) else []
    f = listed_files(pf) if os.path.exists(pf) else []
    if any("Forever/" in x or "_Vanilla" in x for x in d):
        err("%s: the default TOC lists vanilla data" % folder)
    if f and not any("Forever/" in x or "_Vanilla" in x for x in f):
        err("%s: the Forever TOC lists no vanilla data" % folder)
    if any(re.match(r"Data/WhatItDrops(Items|Bosses|QuestItems)\.lua$", x) or (folder != "WhatItDrops" and x == folder + ".lua") for x in f):
        err("%s: the Forever TOC still lists TBC data" % folder)

# ---- load each client's data the way the client would and look at the result
lua = LuaRuntime(unpack_returned_tuples=True)
LOAD = lua.eval("""function(files, readfile)
    WOW_PROJECT_ID, WOW_PROJECT_CLASSIC, WOW_PROJECT_MAINLINE = 2, 2, 1
    WhatItDropsFull, WhatItDropsNpcName, WhatItDropsDataSource = nil, nil, nil
    WhatItDropsItemName, WhatItDropsInstanceBoss, WhatItDropsQuestItem = nil, nil, nil
    for i = 1, #files do
        local f, e = loadstring(readfile(files[i]), "@" .. files[i])
        if not f then return nil, e end
        f()
    end
    local function has(npc) return WhatItDropsFull and WhatItDropsFull[npc] ~= nil end
    return WhatItDropsDataSource, has(17711), has(448), WhatItDropsInstanceBoss ~= nil, WhatItDropsQuestItem ~= nil
end""")


def readfile(rel):
    return open(os.path.join(root, rel), encoding="utf-8").read()


def load(suffix):
    files = []
    for folder, is_main in [("WhatItDrops", True)] + [("WhatItDrops_" + p, False) for p in PACKS]:
        for f in listed_files(toc_path(folder, suffix)):
            if f.startswith("Data/") or (not is_main and f.endswith(".lua")):
                files.append(folder + "/" + f)
    return LOAD(lua.table_from(files), readfile)


for suffix, source, doomwalker in (("", "tbc-db", True), ("Forever", "classic-db", False)):
    res = load(suffix)
    if res[0] is None and len(res) > 1 and isinstance(res[1], str):
        err("%s data does not load: %s" % (suffix or "default", res[1]))
        continue
    src, has_doomwalker, has_hogger, has_bosses, has_quest = res
    label = suffix or "default"
    if not (src and source in src):
        err("%s TOCs load the wrong database: %r (expected %s)" % (label, src, source))
    if bool(has_doomwalker) != doomwalker:
        err("%s TOCs: Doomwalker (Outland) %s, expected %s" % (label, "present" if has_doomwalker else "absent", "present" if doomwalker else "absent"))
    if not has_hogger:
        err("%s TOCs: Hogger is missing" % label)
    if not (has_bosses and has_quest):
        err("%s TOCs: boss or quest-item table missing" % label)
    print("%-8s -> %s" % (label, src))

print("OK" if not errors else "%d problem(s)" % len(errors))
for e in errors:
    print("  " + e)
sys.exit(1 if errors else 0)
