local ADDON = ...

-- Profile export / import: your whole setup as one copyable string.
--
--   WID1:<base64 of the payload>:<8-hex checksum of the payload>
--
-- The payload is plain `key=<type><value>;` entries, never Lua source, so pasting a profile can
-- never run code. Only keys named in SCHEMA are read, each value is checked against its type and
-- range, and anything else is counted and ignored. An import resets every profile setting to its
-- default first, so the result is the exported setup and not a blend of it with what was there.
--
-- Covered: every behaviour and appearance setting, the minimap button, the saved window
-- positions, and the two keybinds (which the game keeps, not the SavedVariables).
-- Left out on purpose: defaultBindApplied and optionsPage, which are internal state, not settings.

local TAG = "WID1"
local SCHEMA_VERSION = 1
local MAX_LEN = 20000

local function db()
    WhatItDropsDB = WhatItDropsDB or {}
    return WhatItDropsDB
end

--------------------------------------------------------------------------
-- 1. SCHEMA: the one list of what a profile holds
--------------------------------------------------------------------------
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
local THEMES = set({ "blizzard", "elvui", "slate", "parchment" })
local ROWSIZES = set({ "compact", "normal", "roomy" })
local ACCENTS = {}
for k in pairs(WhatItDrops_Accents or { gold = true }) do ACCENTS[k] = true end

local POS = { min = -20000, max = 20000 }
local SCHEMA = {
    { key = "auto",              t = "bool" },
    { key = "useMouseover",      t = "bool" },
    { key = "hideJunk",          t = "bool" },
    { key = "showWorldDrops",    t = "bool" },
    { key = "clearSearchOnOpen", t = "bool" },
    { key = "theme",             t = "enum", values = THEMES },
    { key = "accent",            t = "enum", values = ACCENTS },
    { key = "rowSize",           t = "enum", values = ROWSIZES },
    { key = "opacity",           t = "num",  min = 0.4, max = 1 },
    { key = "uiScale",           t = "num",  min = 0.7, max = 1.4 },
    { key = "fxBars",            t = "bool" },
    { key = "fxBorders",         t = "bool" },
    { key = "fxSparkle",         t = "bool" },
    { key = "fxFade",            t = "bool" },
    { key = "fxModel",           t = "bool" },
    { key = "minimap.hide",      t = "bool" },
    { key = "minimap.minimapPos", t = "num", min = 0, max = 360 },
    { key = "pos.loot.1",        t = "num",  min = POS.min, max = POS.max },
    { key = "pos.loot.2",        t = "num",  min = POS.min, max = POS.max },
    { key = "pos.browser.1",     t = "num",  min = POS.min, max = POS.max },
    { key = "pos.browser.2",     t = "num",  min = POS.min, max = POS.max },
    { key = "pos.options.1",     t = "num",  min = POS.min, max = POS.max },
    { key = "pos.options.2",     t = "num",  min = POS.min, max = POS.max },
    -- keybinds live in the game's binding store; set separately when applied
    { key = "bind.FULLLOOKUP",   t = "key",  action = "WHATITDROPS_FULLLOOKUP" },
    { key = "bind.LOOKUP",       t = "key",  action = "WHATITDROPS_LOOKUP" },
}
local byKey = {}
for _, e in ipairs(SCHEMA) do byKey[e.key] = e end

--------------------------------------------------------------------------
-- 2. SMALL PIECES: paths, base64, checksum
--------------------------------------------------------------------------
local function split(path)
    local t = {}
    for tok in path:gmatch("[^.]+") do t[#t + 1] = tonumber(tok) or tok end
    return t
end
local function getPath(root, path)
    local node = root
    for _, k in ipairs(split(path)) do
        if type(node) ~= "table" then return nil end
        node = node[k]
    end
    return node
end
local function setPath(root, path, value)
    local keys = split(path)
    local node = root
    for i = 1, #keys - 1 do
        local k = keys[i]
        if type(node[k]) ~= "table" then
            if value == nil then return end
            node[k] = {}
        end
        node = node[k]
    end
    node[keys[#keys]] = value
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local REV = {}
for i = 1, 64 do REV[B64:sub(i, i)] = i - 1 end

-- Plain arithmetic rather than the bit library, which not every client or test runtime has.
local function b64encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v / 4096) % 64
        local c3 = math.floor(v / 64) % 64
        local c4 = v % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function b64decode(s)
    if #s == 0 or #s % 4 ~= 0 or s:find("[^A-Za-z0-9+/=]") then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local a, b = s:sub(i, i), s:sub(i + 1, i + 1)
        local c, d = s:sub(i + 2, i + 2), s:sub(i + 3, i + 3)
        local va, vb = REV[a], REV[b]
        if va == nil or vb == nil then return nil end
        if c == "=" and d ~= "=" then return nil end
        if (c == "=" or d == "=") and i + 3 ~= #s then return nil end   -- padding only at the very end
        local v = va * 262144 + vb * 4096 + (REV[c] or 0) * 64 + (REV[d] or 0)
        out[#out + 1] = string.char(math.floor(v / 65536) % 256)
        if c ~= "=" then out[#out + 1] = string.char(math.floor(v / 256) % 256) end
        if d ~= "=" then out[#out + 1] = string.char(v % 256) end
    end
    return table.concat(out)
end

local function checksum(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end
    return string.format("%08x", h)
end

local function appVersion()
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local v = meta and meta(ADDON, "Version")
    return (type(v) == "string" and v:gsub("[^%w%.]", ""):sub(1, 20)) or "?"
end

--------------------------------------------------------------------------
-- 3. VALUES: encode for export, validate on import
--------------------------------------------------------------------------
local function encodeValue(e, v)
    if e.t == "bool" then
        if type(v) ~= "boolean" then return nil end
        return "b" .. (v and "1" or "0")
    elseif e.t == "num" then
        if type(v) ~= "number" or v ~= v or v < e.min or v > e.max then return nil end
        return "n" .. string.format("%.8g", v)
    elseif e.t == "enum" then
        if type(v) ~= "string" or not e.values[v] then return nil end
        return "s" .. v
    elseif e.t == "key" then
        if type(v) ~= "string" or #v > 40 or not v:match("^[A-Z0-9%-]+$") then return nil end
        return "k" .. v
    end
end

-- text like "n1.2" back to a value, or nil when it isn't valid for this setting
local function decodeValue(e, text)
    local typ, val = text:sub(1, 1), text:sub(2)
    if e.t == "bool" then
        if typ == "b" and (val == "0" or val == "1") then return val == "1" end
    elseif e.t == "num" then
        if typ == "n" then
            local n = tonumber(val)
            if n and n == n and n >= e.min and n <= e.max then return n end
        end
    elseif e.t == "enum" then
        if typ == "s" and e.values[val] then return val end
    elseif e.t == "key" then
        if typ == "k" and #val <= 40 and val:match("^[A-Z0-9%-]+$") then return val end
    end
    return nil
end

--------------------------------------------------------------------------
-- 4. EXPORT
--------------------------------------------------------------------------
function WhatItDrops_ExportProfile()
    local d = db()
    local parts = { "v=" .. SCHEMA_VERSION, "app=" .. appVersion() }
    local have = {}
    for _, e in ipairs(SCHEMA) do
        local v
        if e.action then v = GetBindingKey and (GetBindingKey(e.action)) else v = getPath(d, e.key) end
        local enc = encodeValue(e, v)
        if enc then have[e.key] = enc end
    end
    -- a window position is only meaningful as a pair
    for _, name in ipairs({ "loot", "browser", "options" }) do
        local a, b = "pos." .. name .. ".1", "pos." .. name .. ".2"
        if not (have[a] and have[b]) then have[a], have[b] = nil, nil end
    end
    for _, e in ipairs(SCHEMA) do
        if have[e.key] then parts[#parts + 1] = e.key .. "=" .. have[e.key] end
    end
    local payload = table.concat(parts, ";")
    return TAG .. ":" .. b64encode(payload) .. ":" .. checksum(payload)
end

--------------------------------------------------------------------------
-- 5. IMPORT
--------------------------------------------------------------------------
-- Reads and checks a profile without changing anything.
-- Returns values, info on success (values: key -> value; info: count, ignored, app), or
-- nil, message on failure.
local function parse(text)
    if type(text) ~= "string" then return nil, "Paste a profile first." end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "Paste a profile first." end
    if #text > MAX_LEN then return nil, "That text is far too long to be a WhatItDrops profile." end

    local tag, body, sum = text:match("^(%w+):([^:]*):(%x+)$")
    if not tag then
        if text:find("^WID") then return nil, "That profile is damaged: it isn't in the expected shape." end
        return nil, "That doesn't look like a WhatItDrops profile. It should start with " .. TAG .. ":"
    end
    if tag ~= TAG then
        return nil, "That profile is from a different version of WhatItDrops (" .. tag .. "). Update the addon and export it again."
    end
    body = body:gsub("%s", "")      -- tolerate line wrapping from a chat window or a text file
    local payload = b64decode(body)
    if not payload then return nil, "That profile is damaged: it can't be decoded." end
    if checksum(payload) ~= sum:lower() then
        return nil, "That profile is damaged: it doesn't match its checksum, so part of it was lost or changed."
    end

    local values, count, ignored, version, app = {}, 0, 0, nil, nil
    for entry in payload:gmatch("[^;]+") do
        local k, rest = entry:match("^([%w_%.]+)=(.*)$")
        if not k then
            ignored = ignored + 1
        elseif k == "v" then
            version = tonumber(rest)
        elseif k == "app" then
            app = rest:sub(1, 20)
        else
            local e = byKey[k]
            local v = e and decodeValue(e, rest)
            if v == nil then
                ignored = ignored + 1
            else
                if values[k] == nil then count = count + 1 end
                values[k] = v
            end
        end
    end
    if not version then return nil, "That profile is damaged: it has no version." end
    if version > SCHEMA_VERSION then
        return nil, "That profile was made by a newer WhatItDrops. Update the addon, then import it."
    end
    if count == 0 then return nil, "That profile has no settings this version of WhatItDrops recognizes." end
    return values, { count = count, ignored = ignored, app = app }
end

-- Check a profile without applying it: ok, message.
function WhatItDrops_CheckProfile(text)
    local values, info = parse(text)
    if not values then return false, info end
    local msg = "Valid profile with " .. info.count .. " settings"
    if info.ignored > 0 then msg = msg .. " (" .. info.ignored .. " entries will be ignored)" end
    return true, msg .. "."
end

local function applyBinding(action, key)
    if InCombatLockdown and InCombatLockdown() then return false end
    local o1, o2 = GetBindingKey(action)
    if o1 then SetBinding(o1) end
    if o2 then SetBinding(o2) end
    if SetBinding(key, action) then
        if WhatItDrops_SaveBindings then WhatItDrops_SaveBindings() end
        return true
    end
    return false
end

-- Import a profile, replacing the exported settings. Returns ok, message.
function WhatItDrops_ImportProfile(text)
    local values, info = parse(text)
    if not values then return false, info end

    local d = db()
    local oldTheme = d.theme or "blizzard"
    -- every profile setting back to its default, then the imported ones on top
    for _, e in ipairs(SCHEMA) do
        if not e.action then setPath(d, e.key, nil) end
    end
    if WhatItDrops_SeedDB then WhatItDrops_SeedDB() end
    local skippedBinds = false
    for key, v in pairs(values) do
        local e = byKey[key]
        if e.action then
            if not applyBinding(e.action, v) then skippedBinds = true end
        else
            setPath(d, key, v)
        end
    end
    -- a position needs both coordinates; drop half-pairs rather than crash a SetPoint
    if type(d.pos) == "table" then
        for name, p in pairs(d.pos) do
            if type(p) ~= "table" or type(p[1]) ~= "number" or type(p[2]) ~= "number" then d.pos[name] = nil end
        end
    end

    -- show it
    if WhatItDrops_ApplyAppearance then WhatItDrops_ApplyAppearance() end
    if WhatItDrops_RestorePositions then WhatItDrops_RestorePositions() end
    if WhatItDrops_UpdateMinimapButton then WhatItDrops_UpdateMinimapButton() end
    if WhatItDrops_Refresh then WhatItDrops_Refresh() end
    if WhatItDrops_RefreshOptions then WhatItDrops_RefreshOptions() end

    local msg = "Imported " .. info.count .. " settings."
    if info.ignored > 0 then msg = msg .. " " .. info.ignored .. " entries weren't recognized and were skipped." end
    if skippedBinds then msg = msg .. " Keybinds weren't changed (you're in combat, or the key was refused)." end
    local newTheme = d.theme or "blizzard"
    if (oldTheme == "elvui") ~= (newTheme == "elvui") then
        msg = msg .. " Switching to or from ElvUI needs a /reload."
    end
    return true, msg
end
