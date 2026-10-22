"""Verify WhatItDrops' localization.

    python tools/check-locales.py <path to the WhatItDrops folder> [--keys]

Checks, and exits non-zero if any fails:
  * every L["..."] key used by the code appears in every locale file, and nothing else does
  * each translation keeps the key's printf placeholders (same count, kinds and order)
  * each translation keeps the key's colour/texture markup and newlines
  * no empty translations, no duplicate keys, no translation left identical to English
    (except the short allow-list of proper nouns)
  * locale files start with the right GetLocale() guard, are UTF-8 without a BOM
  * the TOC lists Locales\\Locale.lua and every locale file before any file that uses L
  * the TOC carries a Notes-xxXX line for every locale
  * no player-visible string literal is passed to SetText/AddLine/AddMessage/print unwrapped
  * every Lua file compiles (when the `lupa` package is installed)

--keys prints the key list instead (used to author the translations).
"""
import io
import os
import re
import sys

LOCALES = ["deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT"]
CODE = ["WhatItDrops.lua", "Names.lua", "Options.lua", "Profile.lua", "Settings.lua", "Theme.lua"]
# Words that are legitimately the same in a language (proper nouns, loanwords, or just the same
# word). Each is a deliberate decision: anything else equal to the English text is reported as
# an untranslated leftover.
SAME_OK = {
    "*": {"Blizzard", "ElvUI"},
    "deDE": {"Gold", "Normal", "Quest", "WhatItDrops — Browser"},
    "frFR": {"Compact", "Instance", "Normal", "Violet"},
    "esES": {"General", "Normal"},
    "esMX": {"General", "Normal"},
    "ptBR": {"Normal"},
    "koKR": {"NPC", "NPC %s"},
    "zhCN": {"NPC", "NPC %s"},
    "zhTW": {"NPC", "NPC %s"},
    "itIT": {"WhatItDrops — Browser"},
}

# Messages quote the offending line, which is often Chinese, Korean or Russian: print as UTF-8
# whatever the console or pipe encoding is (a cp1252 pipe on Windows would otherwise crash here,
# hiding exactly the failures this script exists to report).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

root = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "."
errors = []


def err(msg):
    errors.append(msg)


def read(path):
    raw = open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"):
        err("%s: has a UTF-8 BOM" % os.path.basename(path))
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as e:
        err("%s: not valid UTF-8 (%s)" % (os.path.basename(path), e))
        return raw.decode("utf-8", "replace")


ESC = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'", "r": "\r"}


def unescape(s):
    return re.sub(r"\\(.)", lambda m: ESC.get(m.group(1), m.group(1)), s)


STR = r'"((?:[^"\\\n]|\\.)*)"'
KEY_USE = re.compile(r"\bL\[" + STR + r"\](\s*:\s*format\()?")
ENTRY = re.compile(r"^L\[" + STR + r"\]\s*=\s*" + STR + r"\s*$")
# A printf placeholder: %s %d %.1f %02x ... The space flag is deliberately NOT recognised: no
# string here uses it, and "1.8% drop" / "2 % of" are percentages, not "% d" / "% o". A literal
# percent sign is therefore fine in any key that never goes through :format, and must be written
# %% in one that does (see stray_percent).
PLACEHOLDER = re.compile(r"%(?!%)[-+#0]*\d*(?:\.\d+)?[sdioxXcfgeEu]")
MARKUP = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|n")
FORMATTED = set()      # keys the code runs through :format


def placeholders(s):
    return PLACEHOLDER.findall(s.replace("%%", ""))


def stray_percent(s):
    """A % that is neither a placeholder nor %% -- a crash waiting in a formatted string."""
    return PLACEHOLDER.sub("", s.replace("%%", "")).count("%")


def markup(s):
    return MARKUP.findall(s)


def used_keys():
    keys = {}
    for name in CODE:
        path = os.path.join(root, name)
        if not os.path.exists(path):
            continue
        src = read(path)
        for no, line in enumerate(src.splitlines(), 1):
            if line.lstrip().startswith("--"):
                continue
            for m in KEY_USE.finditer(line):
                key = unescape(m.group(1))
                keys.setdefault(key, (name, no))
                if m.group(2):
                    FORMATTED.add(key)
    return keys


KEYS = used_keys()
if "--keys" in sys.argv:
    for i, k in enumerate(sorted(KEYS), 1):
        print("%3d  %s" % (i, k.replace("\n", "\\n")))
    sys.exit(0)

# ---- locale files
for loc in LOCALES:
    path = os.path.join(root, "Locales", loc + ".lua")
    if not os.path.exists(path):
        err("%s: missing" % loc)
        continue
    src = read(path)
    lines = src.splitlines()
    head = [l for l in lines if l.strip() and not l.strip().startswith("--")][:3]
    if head != ["local _, ns = ...", 'if GetLocale() ~= "%s" then return end' % loc, "local L = ns.L"]:
        err("%s: header must be `local _, ns = ...`, the GetLocale guard for %s, `local L = ns.L`; got %r" % (loc, loc, head))
    entries, seen = {}, set()
    for no, line in enumerate(lines, 1):
        if not line.startswith("L["):
            continue
        m = ENTRY.match(line)
        if not m:
            err("%s:%d: cannot parse %r" % (loc, no, line[:70]))
            continue
        k, v = unescape(m.group(1)), unescape(m.group(2))
        if k in seen:
            err("%s:%d: duplicate key %r" % (loc, no, k[:50]))
        seen.add(k)
        entries[k] = v
    for k in sorted(set(KEYS) - set(entries)):
        err("%s: missing key %r" % (loc, k[:60]))
    for k in sorted(set(entries) - set(KEYS)):
        err("%s: extra key %r (not used by the code)" % (loc, k[:60]))
    for k, v in entries.items():
        if k not in KEYS:
            continue
        if not v.strip():
            err("%s: empty translation for %r" % (loc, k[:50]))
        if v == k and k not in SAME_OK["*"] and k not in SAME_OK.get(loc, ()):
            err("%s: translation identical to English for %r" % (loc, k[:50]))
        if placeholders(k) != placeholders(v):
            err("%s: placeholders %s -> %s for %r" % (loc, placeholders(k), placeholders(v), k[:50]))
        if k in FORMATTED and (stray_percent(k) or stray_percent(v)):
            err("%s: a bare %% in a string that goes through :format (write %%%%) for %r" % (loc, k[:50]))
        if markup(k) != markup(v):
            err("%s: markup differs for %r" % (loc, k[:50]))
        if k.count("\n") != v.count("\n"):
            err("%s: newline count differs for %r" % (loc, k[:50]))
        if k.startswith(" ") != v.startswith(" ") or k.endswith(" ") != v.endswith(" "):
            err("%s: leading/trailing space differs for %r" % (loc, k[:50]))

# ---- TOC
toc_path = os.path.join(root, "WhatItDrops.toc")
toc = read(toc_path)
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
order = [f.replace("\\", "/") for f in files]
want = ["Locales/Locale.lua"] + ["Locales/%s.lua" % l for l in LOCALES]
first_user = min((order.index(c) for c in CODE if c in order), default=None)
for w in want:
    if w not in order:
        err("TOC: %s is not listed" % w)
    elif first_user is not None and order.index(w) > first_user:
        err("TOC: %s is listed after a file that uses L" % w)
for loc in LOCALES:
    if not re.search(r"^## Notes-%s:" % loc, toc, re.M):
        err("TOC: no Notes-%s line" % loc)

# ---- unwrapped player-visible literals
CALL = re.compile(r'(SetText|AddLine|AddMessage|print)\(\s*(?:\w+\s*\.\.\s*)?"([^"]*[A-Za-z]{3,}[^"]*)"')
ALLOW = re.compile(r"^(\|c[0-9a-f]{8}WhatItDrops\|r|WhatItDrops|Wowhead|\||%)", re.I)
for name in CODE:
    path = os.path.join(root, name)
    if not os.path.exists(path):
        continue
    for no, line in enumerate(read(path).splitlines(), 1):
        if line.lstrip().startswith("--") or "L[" in line:
            continue
        for m in CALL.finditer(line):
            text = m.group(2)
            if re.fullmatch(r"[\s|c0-9a-fA-F]*", text) or ALLOW.match(text):
                continue
            err("%s:%d: possibly unwrapped player-visible string: %r" % (name, no, text[:60]))

# ---- compile
try:
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime()
    compile_ = lua.eval("function(s, n) local f, e = loadstring(s, n); return f ~= nil, e end")
    targets = [os.path.join("Locales", f) for f in sorted(os.listdir(os.path.join(root, "Locales"))) if f.endswith(".lua")]
    for rel in targets + CODE:
        p = os.path.join(root, rel)
        if os.path.exists(p):
            try:
                ok, e = compile_(open(p, encoding="utf-8").read(), "@" + rel)
            except Exception as ex:      # Lua's own message can hold a raw byte (a BOM, say)
                ok, e = False, "unreadable (%s)" % type(ex).__name__
            if not ok:
                err("%s: does not compile: %s" % (rel, e))
except ImportError:
    print("(lupa not installed: skipping the compile check)")

print("keys used by the code: %d   locales checked: %d" % (len(KEYS), len(LOCALES)))
for e in errors:
    print("  " + e)
print("OK" if not errors else "%d problem(s)" % len(errors))
sys.exit(1 if errors else 0)
