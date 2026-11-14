"""Resolve CMaNGOS loot templates into plain drop percentages (DEV ONLY).

Input is a CMaNGOS world-database dump (cmangos/tbc-db, GPL-3.0). This module turns the loot
tables the server rolls at kill time into "this item drops from this creature N% of the time":

  * creature_template.LootId names a row set in creature_loot_template
  * groupid 0: every row is rolled on its own with its chance
  * groupid > 0: exactly one row of the group can win; explicit chances are taken as given and
    the rows left at 0 share what remains of 100% equally
  * mincountOrRef < 0: the row is a reference to reference_loot_template entry -mincountOrRef,
    rolled `maxcount` times with the row's chance as the chance of entering it at all
  * a negative chance is a quest-only drop with the same chance

Sources that appear in many creatures' tables (zone-wide green/blue/grey pools) are kept apart
as "world drops", the way the addon's loot window shows them.
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tdbparse as t  # noqa: E402

MAX_DEPTH = 8
SHARED_MIN = 30          # a reference used by this many creature tables is a zone/world pool
# Reference pools the database itself labels as world drops (its own comments on the creature rows).
WORLD_COMMENT = re.compile(r"^(NPC LOOT|LOOT \(World|Darkmoon Cards|\d+ Slot Bag|Scrolls|Super (Healing|Mana))", re.I)


def _by_entry(sql, table):
    out = collections.defaultdict(list)
    for r in t.rows(sql, table, ["entry", "item", "ChanceOrQuestChance", "groupid", "mincountOrRef", "maxcount", "comments"]):
        out[r["entry"]].append(r)
    return out


class Loot:
    def __init__(self, sql):
        self.creature = _by_entry(sql, "creature_loot_template")
        self.reference = _by_entry(sql, "reference_loot_template")
        self._memo = {}
        # how many creature tables name each reference (directly)
        users = collections.defaultdict(set)
        labelled = set()
        for entry, rows in self.creature.items():
            for r in rows:
                if r["mincountOrRef"] < 0:
                    users[-r["mincountOrRef"]].add(entry)
                    if WORLD_COMMENT.match(r["comments"] or ""):
                        labelled.add(-r["mincountOrRef"])
        self.shared = labelled | {ref for ref, u in users.items() if len(u) >= SHARED_MIN}

    # ---- one pass through a template: item -> probability (0..1) that it appears
    def _process(self, rows, depth, ref_probs):
        """rows: the rows of one template. ref_probs(ref) -> dict item -> prob for one roll of ref."""
        out = {}

        def add(item, p):
            if p <= 0:
                return
            out[item] = 1.0 - (1.0 - out.get(item, 0.0)) * (1.0 - min(p, 1.0))

        def emit(row, p):
            ref = row["mincountOrRef"]
            if ref < 0:
                rolls = max(1, row["maxcount"])
                for item, q in ref_probs(-ref).items():
                    add(item, p * (1.0 - (1.0 - q) ** rolls))
            else:
                add(row["item"], p)

        groups = collections.defaultdict(list)
        for r in rows:
            groups[r["groupid"]].append(r)
        for gid, grp in groups.items():
            if gid == 0:
                for r in grp:
                    c = abs(r["ChanceOrQuestChance"])
                    if c > 0:
                        emit(r, min(c, 100.0) / 100.0)
                continue
            explicit = sum(abs(r["ChanceOrQuestChance"]) for r in grp if r["ChanceOrQuestChance"])
            zeros = [r for r in grp if not r["ChanceOrQuestChance"]]
            share = max(0.0, 100.0 - explicit) / len(zeros) if zeros else 0.0
            for r in grp:
                c = abs(r["ChanceOrQuestChance"]) or share
                emit(r, min(c, 100.0) / 100.0)
        return out

    def _ref(self, ref, depth=0):
        if ref in self._memo:
            return self._memo[ref]
        if depth > MAX_DEPTH:
            return {}
        self._memo[ref] = {}         # cycle guard
        res = self._process(self.reference.get(ref, []), depth,
                            lambda r: self._ref(r, depth + 1))
        self._memo[ref] = res
        return res

    def for_loot_id(self, lid):
        """-> (specific, world): two dicts item -> percent."""
        rows = self.creature.get(lid, [])
        spec_rows, world_rows = [], []
        for r in rows:
            (world_rows if (r["mincountOrRef"] < 0 and -r["mincountOrRef"] in self.shared) else spec_rows).append(r)
        spec = self._process(spec_rows, 0, self._ref)
        world = self._process(world_rows, 0, self._ref)
        for item in list(world):
            if item in spec:
                del world[item]
        return ({i: p * 100.0 for i, p in spec.items()}, {i: p * 100.0 for i, p in world.items()})
