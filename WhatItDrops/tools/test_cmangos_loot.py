"""Checks for cmangos_loot.py on a tiny made-up CMaNGOS dump.

    python tools/test_cmangos_loot.py

Every expectation below is worked out by hand from how the server rolls loot; if one of them
fails, the percentages shipped in the loot window are wrong.
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmangos_loot  # noqa: E402

COLUMNS = """  `entry` mediumint unsigned NOT NULL DEFAULT '0',
  `item` mediumint unsigned NOT NULL DEFAULT '0',
  `ChanceOrQuestChance` float NOT NULL DEFAULT '100',
  `groupid` tinyint unsigned NOT NULL DEFAULT '0',
  `mincountOrRef` mediumint NOT NULL DEFAULT '1',
  `maxcount` tinyint unsigned NOT NULL DEFAULT '1',
  `condition_id` mediumint unsigned NOT NULL DEFAULT '0',
  `comments` varchar(300) DEFAULT '',
"""


# (entry, item, chance, group, mincountOrRef, maxcount, comment)
CREATURE = [
    # loot id 1: independent rows, a quest drop, a group, a reference rolled twice, a dead row
    (1, 100, "50", 0, 1, 1, ""),
    (1, 101, "-25", 0, 1, 1, ""),                  # negative = quest-only drop, same 25%
    (1, 200, "30", 1, 1, 1, ""),                   # group 1: one winner. 30 explicit,
    (1, 201, "0", 1, 1, 1, ""),                    # the two zeros share the other 70
    (1, 202, "0", 1, 1, 1, ""),
    (1, 900, "10", 0, -5, 2, ""),                  # 10% to enter ref 5, which is rolled twice
    (1, 103, "0", 0, 1, 1, ""),                    # chance 0 outside a group never drops
    # loot id 2: a nested reference (ref 6 -> ref 5) and an item that also drops directly
    (2, 902, "100", 0, -6, 1, ""),
    (2, 300, "20", 0, 1, 1, ""),
    # loot id 3: a pool the database labels as a world drop, used by one creature only
    (3, 950, "100", 0, -8, 1, "NPC LOOT (Green World Drop) - (NPC Levels: 20-25)"),
    (3, 400, "40", 0, 1, 1, ""),
    # loot id 4: a boss pool, not labelled, used by one creature only: stays specific
    (4, 960, "100", 0, -9, 1, "Karazhan (Boss Loot) - Moroes - Epic Items"),
    # loot id 5: a group made only of references (each entered by its group share)
    (5, 970, "0", 1, -10, 1, ""),
    (5, 971, "60", 1, -10, 1, ""),
]
# thirty more creature tables that all use ref 7 make it a zone-wide pool
CREATURE += [(100 + n, 800 + n, "100", 0, -7, 1, "") for n in range(30)]

REFERENCE = [
    (5, 300, "50", 0, 1, 1, ""),
    (6, 901, "100", 0, -5, 1, ""),                 # ref 6 simply points at ref 5
    (7, 500, "80", 0, 1, 1, ""),
    (7, 400, "5", 0, 1, 1, ""),                    # also dropped directly by loot id 3 (40%)
    (8, 600, "25", 0, 1, 1, ""),
    (8, 400, "5", 0, 1, 1, ""),                    # also dropped directly by loot id 3
    (9, 700, "100", 0, 1, 1, ""),
    (10, 710, "100", 0, 1, 1, ""),
    (10, 711, "100", 0, 1, 1, ""),
]


def build():
    def sql_rows(name, rows):
        body = ",".join("(%d,%d,%s,%d,%d,%d,0,'%s')" % r for r in rows)
        nl = chr(10)
        return ("CREATE TABLE `%s` (" % name + nl + COLUMNS + "  PRIMARY KEY (`entry`,`item`)" + nl
                + ") ENGINE=MyISAM;" + nl
                + "INSERT INTO `%s` VALUES %s;" % (name, body) + nl)
    return sql_rows("creature_loot_template", CREATURE) + sql_rows("reference_loot_template", REFERENCE)


def close(a, b, eps=1e-6):
    return abs(a - b) < eps


def main():
    fails = []

    def check(cond, msg):
        if not cond:
            fails.append(msg)

    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "t.sql")
        with open(path, "w", encoding="utf-8") as f:
            f.write(build())
        loot = cmangos_loot.Loot(path)

        spec, world = loot.for_loot_id(1)
        check(close(spec[100], 50.0), "an independent row keeps its own chance (got %s)" % spec.get(100))
        check(close(spec[101], 25.0), "a quest drop (negative chance) uses the absolute chance (got %s)" % spec.get(101))
        check(close(spec[200], 30.0), "an explicit group chance is taken as given (got %s)" % spec.get(200))
        check(close(spec[201], 35.0) and close(spec[202], 35.0), "zero-chance group rows share the remaining 70%% equally (got %s, %s)" % (spec.get(201), spec.get(202)))
        check(103 not in spec, "chance 0 outside a group must never drop")
        # ref 5 holds item 300 at 50% per roll; entered with 10%, rolled twice: 10% * (1 - 0.5^2) = 7.5%
        check(close(spec[300], 7.5), "a reference rolled twice: 10%% * (1-0.5^2) = 7.5%% (got %s)" % spec.get(300))
        check(not world, "nothing in loot id 1 is a world pool")

        spec, world = loot.for_loot_id(2)
        # nested: 100% -> ref 6 -> 100% -> ref 5 (item 300 at 50%) once, plus a direct 20% row
        # independent sources combine: 1 - (1-0.5)(1-0.2) = 0.6
        check(close(spec[300], 60.0), "independent sources of one item combine as 1-(1-a)(1-b) (got %s)" % spec.get(300))

        spec, world = loot.for_loot_id(3)
        check(close(world[600], 25.0) and 600 not in spec, "a pool the database labels 'NPC LOOT' is a world drop (got %s)" % world.get(600))
        check(close(spec[400], 40.0), "a direct row stays specific (got %s)" % spec.get(400))

        spec, world = loot.for_loot_id(4)
        check(close(spec[700], 100.0) and not world, "an unlabelled boss pool used once stays specific (got %s / %s)" % (spec.get(700), world))

        spec, world = loot.for_loot_id(5)
        # group 1 holds two rows that both point at ref 10 (items 710 and 711 at 100% each): the 60%
        # row enters it 60% of the time, the zero row gets the other 40%; one kill can use either
        # row, so each item shows up with 1 - (1-0.6)(1-0.4) = 76%
        check(close(spec[710], 76.0) and close(spec[711], 76.0), "a group made of references resolves (got %s, %s)" % (spec.get(710), spec.get(711)))

        spec, world = loot.for_loot_id(100)
        check(close(world[500], 80.0) and 500 not in spec, "a pool used by 30 creature tables is a world drop (got %s)" % world.get(500))
        # an item that is both specific somewhere and in a world pool is shown once, as specific
        spec3, world3 = loot.for_loot_id(3)
        check(400 not in world3, "an item that drops specifically is not repeated as a world drop")

    for f in fails:
        print("FAIL:", f)
    print("OK" if not fails else "%d failure(s)" % len(fails))
    sys.exit(1 if fails else 0)


main()
