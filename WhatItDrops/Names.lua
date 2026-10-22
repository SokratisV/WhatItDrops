local ADDON, ns = ...

-- Names in the player's own language.
--
-- The bundled data names items and creatures in English. On an English client that is exactly
-- right and nothing here runs. On any other language this module asks the client for the real
-- names, keeps them (per language, in WhatItDropsDB.l10n, so they are not asked for again next
-- session), and offers:
--
--   Names.Item(id)            an item's name in the client's language, or nil
--   Names.MatchItems(q)       items whose client-language name contains q (q already folded)
--   Names.QuestItemByName(s)  the quest-class item whose client-language name is s
--   Names.Npc(id)             a creature's name in the client's language, or nil
--   Names.MatchNpcs(q)        creatures whose known client-language name contains q
--   Names.Progress()          have, total, complete   (for the browser's status line)
--
-- Item names come from C_Item / GetItemInfo, requested in small throttled batches and only once
-- somebody needs them (the browser, the quest view), never at login. Creature names come from
-- C_TooltipInfo where the client has it, one lazy lookup per creature shown, plus every name a
-- target of yours reports for free. A creature the client can't name stays in English.

local Names = {}
ns.Names = Names

local LOCALE = GetLocale()
Names.english = (LOCALE == "enUS" or LOCALE == "enGB")

local baked = _G.WhatItDropsItemName        -- the English item table; nil on Retail (names come from the game there)
local issecret = _G.issecretvalue
local function IsSecret(v) return issecret ~= nil and issecret(v) end

----------------------------------------------------------------------
-- Case folding that understands more than ASCII
----------------------------------------------------------------------
-- string.lower only maps A-Z, so "Ärztliche" would never match "ärztliche" and "Хоггер" never
-- "хоггер". This folds the Latin-1 letters (German, French, Spanish, Portuguese, Italian) and
-- Cyrillic (Russian) on top of it. Korean and Chinese have no case.
local function Fold(s)
    if not s then return "" end
    s = s:lower()
    if not s:find("[\195\208]") then return s end
    s = s:gsub("\195([\128-\158])", function(c)
        if c ~= "\151" then return "\195" .. string.char(c:byte() + 32) end   -- not the multiplication sign
    end)
    s = s:gsub("\208([\128-\175])", function(c)
        local b = c:byte()
        if b >= 160 then return "\209" .. string.char(b - 32)        -- Р..Я
        elseif b >= 144 then return "\208" .. string.char(b + 32)    -- А..П
        else return "\209" .. string.char(b + 16) end                -- Ѐ..Џ (includes Ё)
    end)
    return s
end
Names.Fold = Fold

----------------------------------------------------------------------
-- The per-language store
----------------------------------------------------------------------
local function Store()
    local db = _G.WhatItDropsDB
    if not db then return nil end
    db.l10n = db.l10n or {}
    local t = db.l10n[LOCALE]
    if not t then t = {}; db.l10n[LOCALE] = t end
    t.items = t.items or {}
    t.npc = t.npc or {}
    return t
end

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------
local getName = (C_Item and C_Item.GetItemNameByID) or function(id)
    local gi = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    return gi and (gi(id)) or nil
end
local requestLoad = C_Item and C_Item.RequestLoadItemDataByID

local started, queue, qpos = false, nil, 1
local wanted = {}                  -- ids somebody asked about outside the bulk pass (the item rows on screen)
local fold = {}                    -- id -> folded name, for searching (session only)
local have, total, complete = 0, 0, false
local version = 0                  -- bumped whenever a name arrives; lets the lookup tables know to rebuild
local notifyPending = false

local function Notify()
    if notifyPending then return end
    notifyPending = true
    C_Timer.After(1.0, function()
        notifyPending = false
        if Names.onProgress then Names.onProgress(have, total, complete) end
    end)
end

-- Take the client's name for an item if it has one. Returns true when we now hold a name.
local function Record(id)
    local t = Store()
    if not t then return false end
    if t.items[id] then return true end
    local name = getName(id)
    if name and not IsSecret(name) and type(name) == "string" and name ~= "" then
        t.items[id] = name
        have = have + 1
        version = version + 1
        return true
    end
    return false
end

local BATCH, DELAY = 40, 0.25          -- about 160 requests a second at the very most

local function Pump()
    if not queue then return end
    if InCombatLockdown and InCombatLockdown() then C_Timer.After(2, Pump); return end
    local t = Store()
    if not t then C_Timer.After(2, Pump); return end
    local n = 0
    while qpos <= #queue and n < BATCH do
        local id = queue[qpos]
        qpos = qpos + 1
        if not t.items[id] and not Record(id) and not t.passed and requestLoad then
            requestLoad(id)
        end
        n = n + 1
    end
    Notify()
    if qpos <= #queue then
        C_Timer.After(DELAY, Pump)
    else
        -- everything has been asked for; give the stragglers a moment, then call it done
        C_Timer.After(15, function()
            complete = true
            local s = Store()
            if s then s.passed = true end     -- a whole pass is done: later sessions only read the client's cache
            Notify()
        end)
    end
end

-- Begin building the item index (once). Quest-class items go first: they are few, and the
-- quest view needs them before anything else.
function Names.StartItemIndex()
    if started or Names.english or not baked then return end
    local t = Store()
    if not t then return end
    started = true
    local order, seen = {}, {}
    for id in pairs(_G.WhatItDropsQuestItem or {}) do
        if baked[id] then order[#order + 1] = id; seen[id] = true end
    end
    table.sort(order)
    local rest = {}
    for id in pairs(baked) do
        if not seen[id] then rest[#rest + 1] = id end
    end
    table.sort(rest)
    for _, id in ipairs(rest) do order[#order + 1] = id end
    queue, qpos = order, 1
    total = #order
    have = 0
    for _, id in ipairs(order) do if t.items[id] then have = have + 1 end end
    complete = (have >= total)
    if complete then Notify() else Pump() end
end

function Names.Progress()
    return have, total, complete or not started
end

-- A client-language item name, or nil (always nil on English clients and on Retail, where the
-- item table already holds client names).
function Names.Item(id)
    if Names.english or not baked or not id then return nil end
    local t = Store()
    if not t then return nil end
    if t.items[id] then return t.items[id] end
    if Record(id) then return t.items[id] end
    -- Not cached by the client yet: ask once, and the answer is picked up in OnItemInfo.
    if requestLoad and not wanted[id] and baked[id] then
        wanted[id] = true
        requestLoad(id)
    end
    return nil
end

-- Only what is already held; never asks the client.
function Names.ItemCached(id)
    if Names.english or not baked or not id then return nil end
    local t = Store()
    return t and t.items[id] or nil
end

-- The client answered a request: take the name if it is one we are collecting.
-- Returns true when the item was one somebody on screen was waiting for (so the caller redraws).
function Names.OnItemInfo(id)
    if not id or not baked or not (started or wanted[id]) or not baked[id] then return false end
    local t = Store()
    if t and not t.items[id] and Record(id) then
        local asked = wanted[id]
        wanted[id] = nil
        Notify()
        return asked and true or false
    end
    return false
end

function Names.MatchItems(q)
    local out = {}
    if Names.english or not baked then return out end
    local t = Store()
    if not t then return out end
    for id, name in pairs(t.items) do
        local f = fold[id]
        if not f then f = Fold(name); fold[id] = f end
        if f:find(q, 1, true) then out[#out + 1] = { id = id, name = name } end
    end
    return out
end

-- Quest objectives are written with the client-language item name. Match them against the
-- client-language names of the quest-class items first (a short list), then any item.
local qmap, qmapVersion, amap, amapVersion
function Names.QuestItemByName(text)
    if Names.english or not baked or not text or text == "" then return nil end
    Names.StartItemIndex()
    local t = Store()
    if not t then return nil end
    local key = Fold(text)
    if qmapVersion ~= version then
        qmap, qmapVersion = {}, version
        for id in pairs(_G.WhatItDropsQuestItem or {}) do
            local name = t.items[id]
            if name then
                local k = Fold(name)
                if not qmap[k] or id < qmap[k] then qmap[k] = id end     -- same name twice: the lowest id, so it is stable
            end
        end
    end
    if qmap[key] then return qmap[key] end
    if amapVersion ~= version then
        amap, amapVersion = {}, version
        for id, name in pairs(t.items) do
            local k = Fold(name)
            if not amap[k] or id < amap[k] then amap[k] = id end
        end
    end
    return amap[key]
end

----------------------------------------------------------------------
-- Creatures
----------------------------------------------------------------------
-- Words a tooltip shows while it has nothing real to say; never store these as a name.
local PLACEHOLDERS = {}
for _, g in ipairs({ "UNKNOWNOBJECT", "UNKNOWN", "RETRIEVING_DATA", "LOADING", "SEARCH_LOADING_TEXT" }) do
    local v = _G[g]
    if type(v) == "string" then PLACEHOLDERS[v] = true end
end

local tried = {}                       -- id -> last time we asked, so a miss is not retried every redraw
local RETRY = 30
local budget, budgetAt = 20, 0            -- at most 20 asks a second, so a page of results can't flood the client
-- Tell the window to redraw (once per burst) so names that arrived, or were put off, show up.
local npcPending = false
local function NpcChanged()
    if npcPending or not Names.onNpcName then return end
    npcPending = true
    C_Timer.After(1.0, function()
        npcPending = false
        if Names.onNpcName then Names.onNpcName() end
    end)
end

local function Spend()
    local now = GetTime()
    if now - budgetAt >= 1 then budget, budgetAt = 20, now end
    if budget <= 0 then return false end
    budget = budget - 1
    return true
end

local function AskClient(id)
    local api = _G.C_TooltipInfo
    if not (api and api.GetHyperlink) then return nil end
    local ok, data = pcall(api.GetHyperlink, "unit:Creature-0-0-0-0-" .. id .. "-0")
    if not ok or type(data) ~= "table" then return nil end
    local line = data.lines and data.lines[1]
    local text = line and line.leftText
    if text == nil or IsSecret(text) or type(text) ~= "string" or text == "" then return nil end
    if PLACEHOLDERS[text] or text:find("^Creature%-") then return nil end
    return text
end

function Names.HasTooltipAPI()
    local api = _G.C_TooltipInfo
    return (api and api.GetHyperlink) and true or false
end

-- What the client calls this creature, without caching anything (for the /loot npc check).
function Names.AskClientForNpc(id)
    return AskClient(id)
end

-- A client-language creature name, or nil. A creature we know nothing about is asked for once
-- every RETRY seconds while it is on screen, never in bulk.
function Names.Npc(id)
    if Names.english or not id then return nil end
    local t = Store()
    if not t then return nil end
    local known = t.npc[id]
    if known then return known end
    local now = GetTime()
    if (tried[id] or -1e9) + RETRY > now then return nil end
    if not Names.HasTooltipAPI() then return nil end
    if not Spend() then NpcChanged(); return nil end      -- over budget: come back to it shortly
    tried[id] = now
    local name = AskClient(id)
    if name then
        t.npc[id] = name
        NpcChanged()
        return name
    end
    return nil
end

-- Only what is already known; never asks the client (for long lists of creatures).
function Names.NpcCached(id)
    if Names.english or not id then return nil end
    local t = Store()
    return t and t.npc[id] or nil
end

-- A name the client gave us for free (the name of a unit you targeted).
function Names.RememberNpc(id, name)
    if Names.english or not id or not name or IsSecret(name) or type(name) ~= "string" or name == "" then return end
    local t = Store()
    if t then t.npc[id] = name end
end

function Names.MatchNpcs(q)
    local out = {}
    if Names.english then return out end
    local t = Store()
    if not t then return out end
    for id, name in pairs(t.npc) do
        if Fold(name):find(q, 1, true) then out[#out + 1] = { id = id, name = name } end
    end
    return out
end

-- Numbers for /loot names.
function Names.Stats()
    local items, npcs = 0, 0
    local t = Store()
    if t then
        for _ in pairs(t.items) do items = items + 1 end
        for _ in pairs(t.npc) do npcs = npcs + 1 end
    end
    return items, total, npcs
end
