"""Copy the addon from this repo into another game install's AddOns folder for in-game testing.

    python tools/deploy.py              Retail (and Forever, if the repo is not already there)
    python tools/deploy.py --retail     only Retail
    python tools/deploy.py --dry-run    say what would change, change nothing

The repo itself lives in WoW Forever's AddOns folder, so Forever already runs it as it is; a
target that is the repo's own folder is skipped. What another game install needs is only what the
release zip holds: no tools/, no logo.png, no .claude/ or __pycache__. Retail gets the main addon
and the Retail data pack (the classic packs mean nothing there). Only files whose content differs
are written, and files the repo no longer has are removed again.
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = r"E:\World of Warcraft"
CLASSIC_PACKS = ["WhatItDrops_EasternKingdoms", "WhatItDrops_Instances", "WhatItDrops_Kalimdor",
                 "WhatItDrops_Misc", "WhatItDrops_Outland"]
TARGETS = {
    "forever": (os.path.join(GAME, "_forever_", "Interface", "AddOns"), ["WhatItDrops"] + CLASSIC_PACKS + ["WhatItDrops_Retail"]),
    "retail": (os.path.join(GAME, "_retail_", "Interface", "AddOns"), ["WhatItDrops", "WhatItDrops_Retail"]),
}
SKIP_DIRS = {"tools", ".claude", "__pycache__", ".git"}
SKIP_FILES = {"logo.png"}
TEXT = (".lua", ".toc", ".xml", ".md", ".txt")
CRLF, LF = bytes([13, 10]), bytes([10])


def content(path):
    """The bytes the game should get: text files with LF endings, as the release zip has them (a
    Windows checkout with autocrlf turns them into CRLF)."""
    with open(path, "rb") as f:
        data = f.read()
    return data.replace(CRLF, LF) if path.lower().endswith(TEXT) or os.path.basename(path) == "LICENSE" else data


def wanted(folder):
    """(relative path, absolute path) of every file the release zip would hold for one folder."""
    base = os.path.join(REPO, folder)
    for dirpath, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f in SKIP_FILES or f.endswith((".pyc", ".bak", ".tmp")):
                continue
            full = os.path.join(dirpath, f)
            yield os.path.relpath(full, REPO), full


def deploy(name, dry):
    dest_root, folders = TARGETS[name]
    if os.path.normcase(os.path.abspath(dest_root)) == os.path.normcase(os.path.abspath(REPO)):
        print("%s: this is the repo's own folder, nothing to copy" % name)
        return
    if not os.path.isdir(dest_root):
        print("%s: %s does not exist, skipped" % (name, dest_root))
        return
    copied = removed = 0
    for folder in folders:
        keep = set()
        for rel, src in wanted(folder):
            dst = os.path.join(dest_root, rel)
            keep.add(os.path.normcase(dst))
            data = content(src)
            if os.path.exists(dst) and open(dst, "rb").read() == data:
                continue
            copied += 1
            print("  %s %s" % ("would copy" if dry else "copy", rel))
            if not dry:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, "wb") as f:
                    f.write(data)
        # files the repo no longer has (a renamed or dropped file) must not linger and load
        base = os.path.join(dest_root, folder)
        for dirpath, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                full = os.path.join(dirpath, f)
                if os.path.normcase(full) not in keep and f not in SKIP_FILES:
                    removed += 1
                    print("  %s %s" % ("would remove" if dry else "remove", os.path.relpath(full, dest_root)))
                    if not dry:
                        os.remove(full)
    print("%s: %d file(s) %s, %d removed%s" % (name, copied, "to copy" if dry else "copied", removed, " (dry run)" if dry else ""))


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    names = [a[2:] for a in args if a in ("--forever", "--retail")] or ["forever", "retail"]
    for n in names:
        deploy(n, dry)


main()
