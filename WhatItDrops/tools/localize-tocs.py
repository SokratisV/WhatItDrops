"""Write the localized Title-xx / Notes-xx lines into every WhatItDrops TOC (idempotent).

    python tools/localize-tocs.py <AddOns dir>

The main addon's TOC also gets its Locales file list (Locale.lua first, then one file per
language) ahead of everything that uses L. Existing Title-xx/Notes-xx lines are replaced, so
rerunning after editing toc_locales.py updates them.
"""
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toc_locales as tl  # noqa: E402

root = sys.argv[1]
PACKS = {
    "WhatItDrops_EasternKingdoms": "EasternKingdoms",
    "WhatItDrops_Kalimdor": "Kalimdor",
    "WhatItDrops_Outland": "Outland",
    "WhatItDrops_Instances": "Instances",
    "WhatItDrops_Misc": "Misc",
    "WhatItDrops_Retail": "Retail",
}
LOCALE_FILES = ["Locales\\Locale.lua"] + ["Locales\\%s.lua" % l for l in tl.LOCALES]


def rewrite(path, region, add_locale_files):
    src = io.open(path, encoding="utf-8", newline="").read()
    eol = "\r\n" if "\r\n" in src else "\n"
    lines = src.replace("\r\n", "\n").split("\n")
    lines = [l for l in lines if not re.match(r"## (Title|Notes)-[a-zA-Z]{4}:", l)]
    at = next(i for i, l in enumerate(lines) if l.startswith("## Notes:")) + 1
    lines[at:at] = tl.lines_for(region)
    if add_locale_files:
        lines = [l for l in lines if l.replace("/", "\\") not in LOCALE_FILES]
        at = next(i for i, l in enumerate(lines) if l.strip() == "embeds.xml") + 1
        lines[at:at] = LOCALE_FILES
    io.open(path, "w", encoding="utf-8", newline="").write(eol.join(lines))
    print("localized", os.path.relpath(path, root))


rewrite(os.path.join(root, "WhatItDrops", "WhatItDrops.toc"), None, True)
for folder, region in PACKS.items():
    p = os.path.join(root, folder, folder + ".toc")
    if os.path.exists(p):
        rewrite(p, region, False)
