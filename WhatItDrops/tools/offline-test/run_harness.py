import io
import sys

from lupa.lua51 import LuaRuntime

addon_dir = sys.argv[1]
harness = sys.argv[2]
src = io.open(harness, encoding="utf-8").read()

total = 0
for client, templates in (("retail", "modern"), ("retail", "mid"), ("forever", "legacy")):
    lua = LuaRuntime(unpack_returned_tuples=False)
    g = lua.globals()
    g.ADDON_DIR = addon_dir
    g.CLIENT = client
    g.TEMPLATES = templates
    print("=== client=%s templates=%s" % (client, templates))
    try:
        res = lua.execute(src)
    except Exception as e:  # the harness itself blew up
        print("HARNESS ERROR:", str(e)[:600])
        total += 1
        continue
    fails = int(res["fails"])
    total += fails
    print("frames created: %d   failures: %d" % (int(res["frames"]), fails))
    for i in range(1, len(res["notes"]) + 1):
        print("  " + str(res["notes"][i]))
print("TOTAL FAILURES:", total)
sys.exit(1 if total else 0)
