"""Streaming reader for mysqldump-style TDB files. Treats the dump as DATA only."""
import re

# One parenthesised row: anything that isn't a paren/quote, or a quoted string
# (backslash escapes and doubled quotes allowed).
_ROW = re.compile(r"\((?:[^()'\"]|'(?:[^'\\]|\\.|'')*')*\)")
# One field inside a row: a quoted string or a run of non-commas.
_FLD = re.compile(r"'(?:[^'\\]|\\.|'')*'|[^,]+")
_ESC = {"n": "\n", "r": "\r", "t": "\t", "0": "\0"}


def _unq(s):
    if s.startswith("'"):
        body = s[1:-1].replace("''", "'")
        return re.sub(r"\\(.)", lambda m: _ESC.get(m.group(1), m.group(1)), body)
    if s == "NULL":
        return None
    try:
        return int(s)
    except ValueError:
        try:
            return float(s)
        except ValueError:
            return s


def columns(path, table):
    """Column names of `table`, in declared order."""
    cols, on = [], False
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not on:
                on = line.startswith("CREATE TABLE `%s` (" % table)
                continue
            m = re.match(r"\s+`(\w+)`\s", line)
            if m:
                cols.append(m.group(1))
            elif line.startswith(")"):
                break
    return cols


def rows(path, table, want=None):
    """Yield dict rows of `table`; `want` limits which columns are decoded."""
    cols = columns(path, table)
    idx = {c: i for i, c in enumerate(cols)}
    pick = [(c, idx[c]) for c in (want or cols)]
    head = "INSERT INTO `%s` VALUES " % table
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith(head):
                continue
            for m in _ROW.finditer(line, len(head)):
                fields = _FLD.findall(m.group(0)[1:-1])
                yield {c: _unq(fields[i]) for c, i in pick}
