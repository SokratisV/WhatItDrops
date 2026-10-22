import io
import locale
import sys

from lupa.lua51 import LuaRuntime

# Python adopts the machine's locale (cp1252 on a Western Windows), and the embedded Lua's
# string.lower follows it: "Ä" (C3 84) would come back as E3 84, corrupting UTF-8. WoW's Lua
# runs in the C locale, where lower() only touches A-Z, so the tests must too.
locale.setlocale(locale.LC_CTYPE, "C")

addon_dir = sys.argv[1]
harness = sys.argv[2]
src = io.open(harness, encoding="utf-8").read()

LOCALES = ["enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT"]

# every client/template combination in English, then the whole UI session under each language
RUNS = [("retail", "modern", "enUS"), ("retail", "mid", "enUS"), ("forever", "legacy", "enUS")]
RUNS += [("retail", "modern", loc) for loc in LOCALES if loc != "enUS"]
RUNS += [("forever", "legacy", loc) for loc in ("deDE", "ruRU", "zhCN", "koKR")]

total = 0
for client, templates, locale in RUNS:
    lua = LuaRuntime(unpack_returned_tuples=False)
    g = lua.globals()
    g.ADDON_DIR = addon_dir
    g.CLIENT = client
    g.TEMPLATES = templates
    g.LOCALE = locale
    label = "client=%s templates=%s locale=%s" % (client, templates, locale)
    try:
        res = lua.execute(src)
    except Exception as e:  # the harness itself blew up
        print("=== %s\nHARNESS ERROR: %s" % (label, str(e)[:600]))
        total += 1
        continue
    fails = int(res["fails"])
    total += fails
    print("=== %s   frames: %d   failures: %d" % (label, int(res["frames"]), fails))
    for i in range(1, len(res["notes"]) + 1):
        note = str(res["notes"][i])
        if fails or not note.startswith(("coverage", "chat:")):
            print("  " + note.encode("ascii", "replace").decode())
print("TOTAL FAILURES:", total)
sys.exit(1 if total else 0)
