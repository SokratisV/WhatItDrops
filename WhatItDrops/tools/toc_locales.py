"""Localized `## Title-xxXX` / `## Notes-xxXX` lines for every WhatItDrops TOC.

One table, used by generate-retail-from-tdb.py (so a regenerated retail TOC keeps its
translations) and by localize-tocs.py (which rewrites the TOCs of the other six addons).
Region names are the terms the WoW client uses for those zones.
"""

LOCALES = ["deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT"]

MAIN_TITLE = "WhatItDrops |cff66ccffWowhead|r"

NOTES_MAIN = {
    "deDE": "Beutelisten für jeden Gegner: /loot, /fullloot, /loot browse. Namen direkt in der Liste plus Gegenstandssuche.",
    "frFR": "Tables de butin pour n'importe quel monstre : /loot, /fullloot, /loot browse. Noms intégrés et recherche d'objets.",
    "esES": "Tablas de botín de cualquier monstruo: /loot, /fullloot, /loot browse. Nombres integrados y búsqueda de objetos.",
    "esMX": "Tablas de botín de cualquier monstruo: /loot, /fullloot, /loot browse. Nombres integrados y búsqueda de objetos.",
    "ptBR": "Tabelas de saque de qualquer monstro: /loot, /fullloot, /loot browse. Nomes incluídos e busca de itens.",
    "ruRU": "Таблицы добычи любого монстра: /loot, /fullloot, /loot browse. Встроенные названия и поиск предметов.",
    "koKR": "모든 몬스터의 전리품 목록: /loot, /fullloot, /loot browse. 이름 내장 및 아이템 검색.",
    "zhCN": "任意怪物的战利品表：/loot、/fullloot、/loot browse。内置名称和物品搜索。",
    "zhTW": "任何怪物的戰利品表：/loot、/fullloot、/loot browse。內建名稱與物品搜尋。",
    "itIT": "Tabelle del bottino di qualsiasi mostro: /loot, /fullloot, /loot browse. Nomi incorporati e ricerca oggetti.",
}

# "<region> <data>" as it appears in a pack's title
DATA_WORD = {
    "deDE": "Daten", "frFR": "Données", "esES": "Datos", "esMX": "Datos", "ptBR": "Dados",
    "ruRU": "Данные", "koKR": "데이터", "zhCN": "数据", "zhTW": "資料", "itIT": "Dati",
}
JOINER = {loc: " " for loc in LOCALES}
JOINER["zhCN"] = JOINER["zhTW"] = ""

REGION = {
    "EasternKingdoms": {
        "deDE": "Östliche Königreiche", "frFR": "Royaumes de l'Est", "esES": "Reinos del Este",
        "esMX": "Reinos del Este", "ptBR": "Reinos do Leste", "ruRU": "Восточные королевства",
        "koKR": "동부 왕국", "zhCN": "东部王国", "zhTW": "東部王國", "itIT": "Regni Orientali",
    },
    "Kalimdor": {
        "deDE": "Kalimdor", "frFR": "Kalimdor", "esES": "Kalimdor", "esMX": "Kalimdor", "ptBR": "Kalimdor",
        "ruRU": "Калимдор", "koKR": "칼림도어", "zhCN": "卡利姆多", "zhTW": "卡林多", "itIT": "Kalimdor",
    },
    "Outland": {
        "deDE": "Scherbenwelt", "frFR": "Outreterre", "esES": "Terrallende", "esMX": "Terrallende",
        "ptBR": "Terralém", "ruRU": "Запределье", "koKR": "아웃랜드", "zhCN": "外域", "zhTW": "外域",
        "itIT": "Terre Esterne",
    },
    "Instances": {
        "deDE": "Instanzen", "frFR": "Instances", "esES": "Instancias", "esMX": "Instancias",
        "ptBR": "Instâncias", "ruRU": "Подземелья", "koKR": "인스턴스", "zhCN": "副本", "zhTW": "副本",
        "itIT": "Istanze",
    },
    "Misc": {
        "deDE": "Sonstiges", "frFR": "Divers", "esES": "Varios", "esMX": "Varios", "ptBR": "Diversos",
        "ruRU": "Разное", "koKR": "기타", "zhCN": "杂项", "zhTW": "其他", "itIT": "Varie",
    },
    "Retail": {
        "deDE": "Retail", "frFR": "Retail", "esES": "Retail", "esMX": "Retail", "ptBR": "Retail",
        "ruRU": "Retail", "koKR": "Retail", "zhCN": "正式服", "zhTW": "正式服", "itIT": "Retail",
    },
}

# "%s" is the region name
NOTES_CLASSIC_PACK = {
    "deDE": "Wowhead-Beute für %s (über LootCodex, GPLv3). Wird bei Bedarf von WhatItDrops geladen.",
    "frFR": "Butin Wowhead pour %s (via LootCodex, GPLv3). Chargé à la demande par WhatItDrops.",
    "esES": "Botín de Wowhead para %s (vía LootCodex, GPLv3). WhatItDrops lo carga bajo demanda.",
    "esMX": "Botín de Wowhead para %s (vía LootCodex, GPLv3). WhatItDrops lo carga bajo demanda.",
    "ptBR": "Saque do Wowhead para %s (via LootCodex, GPLv3). Carregado sob demanda pelo WhatItDrops.",
    "ruRU": "Добыча Wowhead для региона «%s» (через LootCodex, GPLv3). Загружается по требованию WhatItDrops.",
    "koKR": "%s의 Wowhead 전리품 (LootCodex 경유, GPLv3). WhatItDrops가 필요할 때 불러옵니다.",
    "zhCN": "%s的 Wowhead 战利品（来自 LootCodex，GPLv3）。由 WhatItDrops 按需加载。",
    "zhTW": "%s的 Wowhead 戰利品（來自 LootCodex，GPLv3）。由 WhatItDrops 按需載入。",
    "itIT": "Bottino di Wowhead per %s (tramite LootCodex, GPLv3). Caricato su richiesta da WhatItDrops.",
}
NOTES_RETAIL_PACK = {
    "deDE": "Retail-Kreaturenbeute aus der TrinityCore-TDB (GPLv3). Wird bei Bedarf von WhatItDrops geladen.",
    "frFR": "Butin des créatures Retail issu de la TDB de TrinityCore (GPLv3). Chargé à la demande par WhatItDrops.",
    "esES": "Botín de criaturas de Retail de la TDB de TrinityCore (GPLv3). WhatItDrops lo carga bajo demanda.",
    "esMX": "Botín de criaturas de Retail de la TDB de TrinityCore (GPLv3). WhatItDrops lo carga bajo demanda.",
    "ptBR": "Saque de criaturas do Retail da TDB do TrinityCore (GPLv3). Carregado sob demanda pelo WhatItDrops.",
    "ruRU": "Добыча существ Retail из TDB TrinityCore (GPLv3). Загружается по требованию WhatItDrops.",
    "koKR": "TrinityCore TDB 기반 Retail 생물 전리품 (GPLv3). WhatItDrops가 필요할 때 불러옵니다.",
    "zhCN": "来自 TrinityCore TDB 的正式服生物战利品（GPLv3）。由 WhatItDrops 按需加载。",
    "zhTW": "來自 TrinityCore TDB 的正式服生物戰利品（GPLv3）。由 WhatItDrops 按需載入。",
    "itIT": "Bottino delle creature Retail dalla TDB di TrinityCore (GPLv3). Caricato su richiesta da WhatItDrops.",
}


def lines_for(region=None):
    """TOC lines for the main addon (region=None) or for one data pack ("Outland", "Retail", ...)."""
    out = []
    for loc in LOCALES:
        if region is None:
            title, notes = MAIN_TITLE, NOTES_MAIN[loc]
        else:
            name = REGION[region][loc]
            title = "WhatItDrops |cff66ccff%s%s%s|r" % (name, JOINER[loc], DATA_WORD[loc])
            template = NOTES_RETAIL_PACK if region == "Retail" else NOTES_CLASSIC_PACK
            notes = template[loc] if region == "Retail" else template[loc] % name
        out.append("## Title-%s: %s" % (loc, title))
        out.append("## Notes-%s: %s" % (loc, notes))
    return out
