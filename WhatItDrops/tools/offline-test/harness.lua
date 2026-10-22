-- Offline harness: loads WhatItDrops against a permissive WoW stub (Lua 5.1) and drives it.
-- Globals set by the runner: ADDON_DIR, CLIENT ("retail"|"forever"), TEMPLATES ("modern"|"mid"|"legacy").

local fails, notes = 0, {}
local function note(s) notes[#notes + 1] = s end
local function try(label, fn, ...)
	local args = { ... }
	local n = select("#", ...)
	local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end,
		function(e) return debug.traceback(tostring(e), 2) end)
	if not ok then
		fails = fails + 1
		local short = {}
		for line in tostring(err):gmatch("[^\n]+") do
			short[#short + 1] = line
			if #short >= 7 then break end
		end
		note("FAIL [" .. label .. "] " .. table.concat(short, "\n      "))
	end
	return ok
end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
strsplit = function(sep, s)
	local out, i = {}, 1
	while true do
		local a, b = s:find(sep, i, true)
		if not a then out[#out + 1] = s:sub(i); break end
		out[#out + 1] = s:sub(i, a - 1); i = b + 1
	end
	return unpack(out)
end
local clock, timers = 0, {}
function GetTime() return clock end
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end }
local function runTimers(advance)
	clock = clock + (advance or 5)
	for _ = 1, 20 do
		local due, rest = {}, {}
		for _, t in ipairs(timers) do if t.at <= clock then due[#due + 1] = t else rest[#rest + 1] = t end end
		timers = rest
		if #due == 0 then return end
		for _, t in ipairs(due) do try("timer", t.fn) end
	end
end

-- ---------------------------------------------------------------- frames
local frames, methods = {}, {}
local FrameMT = {}
local function newObject(kind, parent)
	local o = setmetatable({ __kind = kind, __parent = parent, __scripts = {}, __hooks = {}, __events = {},
		__shown = true, __scale = 1, __text = "", __checked = false, __value = 0, __w = 100, __h = 20 }, FrameMT)
	frames[#frames + 1] = o
	return o
end
FrameMT.__index = function(self, k)
	if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
	local m = methods[k]
	if m then return m end
	if k:find("^Get.*Texture$") or k:find("^Get.*FontString$") then return function() return newObject("Texture", self) end end
	if k:find("^Get") then return function() return 0 end end
	if k:find("^Is") or k:find("^Has") then return function() return false end end
	return function(s) return s end
end
function methods.SetScript(self, n, fn) self.__scripts[n] = fn end
function methods.GetScript(self, n) return self.__scripts[n] end
function methods.HookScript(self, n, fn) self.__hooks[n] = self.__hooks[n] or {}; table.insert(self.__hooks[n], fn) end
function methods.RegisterEvent(self, e) self.__events[e] = true end
function methods.UnregisterEvent(self, e) self.__events[e] = nil end
function methods.Show(self) self.__shown = true; if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function methods.Hide(self)
	local was = self.__shown
	self.__shown = false
	if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function methods.SetShown(self, b) if b then self:Show() else self:Hide() end end
function methods.IsShown(self) return self.__shown end
function methods.SetText(self, t) self.__text = t end
function methods.GetText(self) return self.__text end
function methods.GetStringWidth(self) return 50 end
function methods.SetChecked(self, b) self.__checked = b and true or false end
function methods.GetChecked(self) return self.__checked end
function methods.SetValue(self, v)
	self.__value = v
	if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
end
function methods.GetValue(self) return self.__value end
function methods.SetScale(self, s) self.__scale = s end
function methods.GetScale(self) return self.__scale end
function methods.GetEffectiveScale(self) return 1 end
function methods.GetParent(self) return self.__parent end
function methods.GetName(self) return self.__name end
function methods.SetSize(self, w, h) self.__w, self.__h = w, h end
function methods.SetWidth(self, w) self.__w = w end
function methods.SetHeight(self, h) self.__h = h end
function methods.GetWidth(self) return self.__w end
function methods.GetHeight(self) return self.__h end
function methods.CreateTexture(self) return newObject("Texture", self) end
function methods.CreateFontString(self) return newObject("FontString", self) end
function methods.CreateAnimationGroup(self) return newObject("AnimationGroup", self) end
function methods.CreateAnimation(self) return newObject("Animation", self) end
function methods.GetNumPoints() return 1 end

-- templates that a given client may not have
local MISSING = {}
if TEMPLATES == "legacy" then
	MISSING.SettingsDropdownWithButtonsTemplate = true
	MISSING.MinimalSliderWithSteppersTemplate = true
	MISSING.WowStyle1DropdownTemplate = true
elseif TEMPLATES == "mid" then
	MISSING.SettingsDropdownWithButtonsTemplate = true
	MISSING.MinimalSliderWithSteppersTemplate = true
end
if TEMPLATES ~= "legacy" then MenuUtil = {} end
if TEMPLATES == "modern" then
	MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = "OnValueChanged" } }
end

local function newDropdown(parent)
	local d = newObject("DropdownButton", parent)
	rawset(d, "SetupMenu", function(self, fn) self.__menu = fn end)
	rawset(d, "GenerateMenu", function(self)
		self.__radios = {}
		if self.__menu then
			self.__menu(self, { CreateRadio = function(_, text, isSel, setSel, value)
				table.insert(self.__radios, { text = text, isSel = isSel, setSel = setSel, value = value })
			end })
		end
	end)
	return d
end

function CreateFrame(kind, name, parent, template)
	if template then
		for t in template:gmatch("[^,%s]+") do
			if MISSING[t] then error("template " .. t .. " does not exist", 2) end
		end
	end
	local o = newObject(kind, parent)
	o.__name = name
	if name then _G[name] = o end
	if template and template:find("SettingsDropdownWithButtonsTemplate", 1, true) then
		rawset(o, "Dropdown", newDropdown(o))
		rawset(o, "IncrementButton", newObject("Button", o))
		rawset(o, "DecrementButton", newObject("Button", o))
		rawset(o, "Label", newObject("FontString", o))
	elseif template and template:find("WowStyle1DropdownTemplate", 1, true) then
		local d = newDropdown(parent)
		d.__shown = true
		return d
	elseif template and template:find("MinimalSliderWithSteppersTemplate", 1, true) then
		rawset(o, "Init", function(self, v, lo, hi, steps, fmt) self.__sliderinit = { v, lo, hi, steps } end)
		rawset(o, "RegisterCallback", function(self, ev, fn, owner) self.__cb, self.__owner = fn, owner end)
		rawset(o, "Slider", newObject("Slider", o))
		rawset(o, "MinText", newObject("FontString", o))
		rawset(o, "MaxText", newObject("FontString", o))
	end
	return o
end

-- legacy dropdown API
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(dd, t) dd.__text = t end
function UIDropDownMenu_Initialize(dd, fn) dd.__init = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) LEGACY_INFOS = LEGACY_INFOS or {}; table.insert(LEGACY_INFOS, info) end
function CloseDropDownMenus() end

-- ---------------------------------------------------------------- client globals
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
print = function(...)                       -- collected, so the tests can read what /loot help prints
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	chat[#chat + 1] = table.concat(parts, " ")
end
UIParent = newObject("Frame")
GameTooltip = newObject("GameTooltip")
SlashCmdList, UISpecialFrames = {}, {}
function ReloadUI() RELOADED = true end
function InCombatLockdown() return IN_COMBAT and true or false end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return false end
function IsModifiedClick() return false end
function PlaySound() end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_CHARACTER_INFO_OPEN = 2 }
function HideUIPanel() end
function wipeX() end
ITEM_QUALITY_COLORS = {}
for q = 0, 6 do ITEM_QUALITY_COLORS[q] = { r = q / 6, g = 0.5, b = 1 - q / 6, hex = "|cff" .. string.format("%02x%02x%02x", q * 40, 128, 200 - q * 30) } end
local QUAL = { [1] = 0, [2] = 5, [3] = 4, [4] = 3, [5] = 2, [6] = 1 }
local function qualityOf(id) return id % 5 end
C_Item = {
	GetItemInfo = function(id)
		if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) or 1 end
		return "Item " .. id, "|cff0070dd|Hitem:" .. id .. "::::::::|h[Item " .. id .. "]|h|r", qualityOf(id), 20, 1, "Armor", "Cloth", 1, "INVTYPE_HEAD", 134400
	end,
	GetItemIconByID = function(id) if not id then error("nil id") end return 134400 end,
	RequestLoadItemDataByID = function() end,
	GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "INVTYPE_HEAD", 134400, 4, 1 end,
}
-- What a non-English client knows: item names in its own language, handed out only once an item
-- has been requested and "loaded" (the test decides when). CALLS counts every use of those APIs,
-- so an English client can be shown never to touch them.
CALLS = { name = 0, request = 0, tip = 0 }
LOCALNAME = {
	deDE = { [1000] = "Wolfspelz", [1001] = "Wolfspelz", [1002] = "Eberhauer", [1003] = "Leichtes Leder", [1004] = "Ärztliche Kräuter" },
	ruRU = { [1000] = "Волчья шкура", [1001] = "Волчья шкура", [1002] = "Клык кабана", [1003] = "Тонкая кожа", [1004] = "Целебные травы" },
	koKR = { [1000] = "늑대 가죽", [1001] = "늑대 가죽", [1002] = "멧돼지 엄니", [1003] = "가벼운 가죽", [1004] = "치유 약초" },
	zhCN = { [1000] = "狼皮", [1001] = "狼皮", [1002] = "野猪獠牙", [1003] = "轻皮", [1004] = "治疗草药" },
}
LOCALNAME.default = LOCALNAME.deDE
local function localNames() return LOCALNAME[LOCALE] or LOCALNAME.default end
REQUESTED, LOADED = {}, {}
C_Item.GetItemNameByID = function(id)
	CALLS.name = CALLS.name + 1
	if LOADED[id] then return localNames()[id] or (id >= 5000 and id < 6000 and ("F\195\188ller " .. id)) or nil end
end
C_Item.RequestLoadItemDataByID = function(id) CALLS.request = CALLS.request + 1; REQUESTED[id] = true end
-- creature names: C_TooltipInfo answers a unit link with the creature's name in the client's language
LOCALNPC = { [1234] = "Moroes-LOC", [5555] = "Kobold-LOC" }
UNKNOWNOBJECT = "Unbekanntes Objekt"
TIP_MODE = "normal"
C_TooltipInfo = { GetHyperlink = function(link)
	CALLS.tip = CALLS.tip + 1
	local id = tonumber(link:match("^unit:Creature%-0%-0%-0%-0%-(%d+)%-0$"))
	if not id then return nil end
	if TIP_MODE == "secret" then return { lines = { { leftText = "<<secret>>" } } } end
	if TIP_MODE == "error" then error("tooltip data unavailable") end
	if id == 9999 then return { lines = { { leftText = UNKNOWNOBJECT } } } end
	local n = LOCALNPC[id]
	return n and { lines = { { leftText = n } } } or { lines = {} }
end }
-- a quest log with one quest that needs 3 of item 1001 (a quest-class item) and 3 of item 1003 (an
-- ordinary one); the objective text is in the client's language
C_QuestLog = {
	GetSelectedQuest = function() return 77 end,
	GetNumQuestObjectives = function() return 2 end,
	GetTitleForQuestID = function() return "Wolf Hunt" end,
}
function GetQuestObjectiveInfo(_, i)
	local english = (LOCALE == "enUS" or QUEST_ENGLISH)
	local id = (i == 2) and 1003 or 1001
	local name = english and ((i == 2) and "Light Leather" or "Wolf Pelt") or localNames()[id]
	return "0/3 " .. name, "item", false, 0, 3
end
C_AddOns = { LoadAddOn = function() return true end, GetAddOnMetadata = function() return "9.9.9" end }
GetBuildInfo = function()
	if CLIENT == "forever" then return "1.60.1", "70291", "x", 16001 end
	return "12.1.0", "69933", "x", 120100
end
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_ID = (CLIENT == "forever") and WOW_PROJECT_CLASSIC or WOW_PROJECT_MAINLINE
issecretvalue = function(v) return v == "<<secret>>" end
function GetInstanceInfo() return "World", "none", 0, "", 0, 0, false, 530 end
function IsInInstance() return false end
local boundKey = {}
function GetBindingKey(a) return boundKey[a] end
function SetBinding(key, action) if action then boundKey[action] = key end return true end
function GetBindingAction() return "" end
function GetCurrentBindingSet() return 1 end
function SaveBindings() end
-- units
local unit = { guid = "Creature-0-0-0-0-1234-0000", name = "Moroes", player = false }
function UnitExists() return true end
function UnitGUID() return unit.guid end
function UnitName() return unit.name end
function UnitIsPlayer() return unit.player end
function UnitIsUnit() return false end
function UnitCanAttack() return true end
function CanInspect() return true end
function NotifyInspect() end
function GetInventoryItemLink(_, slot) if slot == 1 or slot == 5 then return "|cff0070dd|Hitem:" .. (100 + slot) .. "::::|h[Gear " .. slot .. "]|h|r" end end
function GetInventoryItemID(_, slot) if slot == 1 or slot == 5 or slot == 7 then return 100 + slot end end
SOUNDKIT = SOUNDKIT
tinsert(UISpecialFrames, "x")
UISpecialFrames = {}

-- ---------------------------------------------------------------- load the addon
local function readfile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a"); f:close()
	return s
end
function GetLocale() return LOCALE or "enUS" end
-- the client's own slot-name globals: the gear list must use these, not its English fallbacks
HEADSLOT, CHESTSLOT, LEGSSLOT, SETTINGS, SEARCH = "HEADSLOT-GLOBAL", "CHESTSLOT-GLOBAL", "LEGSSLOT-GLOBAL", "SETTINGS-GLOBAL", "SEARCH-GLOBAL"

local NS = {}                              -- the second argument every addon file receives
function TextsContain(text)
	for _, f in ipairs(frames) do
		if f.__kind == "FontString" and f.__text == text then return true end
		if f.__text == text and (f.__kind == "Button" or f.__kind == "CheckButton") then return true end
	end
	return false
end

local function loadAddonFile(rel)
	local src = readfile(ADDON_DIR .. "/" .. rel)
	local fn, err = loadstring(src, "@" .. rel)
	if not fn then error(err) end
	return fn("WhatItDrops", NS)
end
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.__events[event] and f.__scripts.OnEvent then
			try("event " .. event, f.__scripts.OnEvent, f, event, ...)
		end
	end
end

-- a small fake database for the loot window
WhatItDropsFull = { [1234] = { 5, 1001, 1.8, 1002, 6.5, 1003, 22, 1004, 54, 1005, 100, 1006, 0.5 } }
WhatItDropsNpcName = { [1234] = "Moroes" }
if CLIENT == "forever" then      -- the bundled Classic tables (Retail has none of these)
	WhatItDropsItemName = { [1000] = "Wolf Pelt Copy", [1001] = "Wolf Pelt", [1002] = "Boar Tusk", [1003] = "Light Leather", [1004] = "Healing Herbs",
		[1005] = "Plain Cloth", [1006] = "Strange Gem", [1007] = "Distant Trinket" }   -- 1007 is on no loot table
	WhatItDropsQuestItem = { [1001] = true, [1002] = true }
end

for _, rel in ipairs({ "Locales/Locale.lua", "Locales/deDE.lua", "Locales/frFR.lua", "Locales/esES.lua", "Locales/esMX.lua", "Locales/ptBR.lua", "Locales/ruRU.lua", "Locales/koKR.lua", "Locales/zhCN.lua", "Locales/zhTW.lua", "Locales/itIT.lua", "Names.lua", "Theme.lua", "WhatItDrops.lua", "Profile.lua", "Options.lua", "Settings.lua" }) do
	try("load " .. rel, loadAddonFile, rel)
end
WhatItDropsDB = nil                      -- first login: nothing saved
fire("ADDON_LOADED", "WhatItDrops")
fire("PLAYER_LOGIN")
runTimers()
local db = WhatItDropsDB
if not db then note("FAIL WhatItDropsDB was never created"); fails = fails + 1 end

-- ---------------------------------------------------------------- the loot window
local function lootWindow()
	try("slash /loot (creature)", SlashCmdList.WHATITDROPS, "")
	runTimers(0.1)
	local win = _G.WhatItDropsFrame
	if not (win and win.__shown) then note("FAIL loot window not shown"); fails = fails + 1 end
	for _, set in ipairs({ { "fxBars", false }, { "fxBorders", false }, { "fxSparkle", false }, { "fxFade", false },
		{ "fxModel", true }, { "rowSize", "roomy" }, { "rowSize", "compact" }, { "opacity", 0.5 }, { "uiScale", 1.2 },
		{ "accent", "blue" }, { "theme", "slate" }, { "theme", "parchment" }, { "theme", "elvui" }, { "theme", "blizzard" } }) do
		WhatItDropsDB[set[1]] = set[2]
		try("apply " .. set[1] .. "=" .. tostring(set[2]), WhatItDrops_ApplyAppearance)
		runTimers(0.1)
	end
	WhatItDropsDB.fxBars, WhatItDropsDB.fxBorders, WhatItDropsDB.fxSparkle, WhatItDropsDB.fxFade = true, true, true, true
	try("re-render", WhatItDrops_Render)
	-- a player's gear
	unit.guid, unit.player, unit.name = "Player-1-0000AAAA", true, "Someone"
	try("slash /loot (player)", SlashCmdList.WHATITDROPS, "")
	runTimers(1); try("gear refresh timers", function() fire("INSPECT_READY", unit.guid); fire("GET_ITEM_INFO_RECEIVED", 101, true) end)
	runTimers(1)
	unit.guid, unit.player, unit.name = "Creature-0-0-0-0-1234-0000", false, "Moroes"
	if not (TextsContain("HEADSLOT-GLOBAL") and TextsContain("CHESTSLOT-GLOBAL")) then
		fails = fails + 1; note("FAIL [l10n] the gear list does not use the client's slot-name globals")
	end
	try("slash /loot again", SlashCmdList.WHATITDROPS, "")
	try("/loot browse", SlashCmdList.WHATITDROPS, "browse moro")
	runTimers(1)
	try("/loot journal", SlashCmdList.WHATITDROPS, "journal moroes")
	-- /loot help runs the help text through :format, which is where a bare % would crash
	local before = #chat
	try("/loot help", SlashCmdList.WHATITDROPS, "help")
	if #chat <= before then fails = fails + 1; note("FAIL [l10n] /loot help printed nothing") end
	if LOCALE == "enUS" then
		local sawPercent = false
		for i = before + 1, #chat do if chat[i]:find("(Wowhead %, via LootCodex data)", 1, true) then sawPercent = true end end
		if not sawPercent then fails = fails + 1; note("FAIL [l10n] the help line lost its literal 'Wowhead %'") end
	end
end

-- ---------------------------------------------------------------- the options window
PRESSES = {}
local function press(f, script, ...)
	local fn = f.__scripts[script]
	if fn then PRESSES[script] = (PRESSES[script] or 0) + 1; try(script .. " on " .. tostring(f.__kind), fn, f, ...) end
	for _, h in ipairs(f.__hooks[script] or {}) do try("hook " .. script, h, f, ...) end
end
local function interact()
	-- hover and click everything that is on screen, then drive the controls
	local snapshot = {}
	for i, f in ipairs(frames) do snapshot[i] = f end
	for _, f in ipairs(snapshot) do
		if f.__shown then
			press(f, "OnEnter"); press(f, "OnLeave")
		end
	end
	for _, f in ipairs(snapshot) do
		-- skip the left-hand page buttons (they carry a .selected texture): pressing them would
		-- switch pages mid-sweep and leave the settings rows unclicked
		if f.__shown and f.__scripts.OnClick and f.__kind ~= "Frame" and not rawget(f, "selected") then
			if f.__kind == "CheckButton" then f.__checked = not f.__checked end
			CLICKED_ROWS = (CLICKED_ROWS or 0) + (rawget(f, "row") and 1 or 0)
			press(f, "OnClick", "LeftButton")
			runTimers(0.3)
		end
	end
	for _, f in ipairs(snapshot) do
		if f.__shown and f.__kind == "EditBox" then
			f.__text = "75"; press(f, "OnEditFocusGained"); press(f, "OnEnterPressed"); press(f, "OnEscapePressed")
		end
		if f.__shown and f.__cb then try("slider callback", f.__cb, f.__owner, 80) end
		if f.__shown and f.__kind == "Slider" and f.__scripts.OnValueChanged then press(f, "OnValueChanged", 90) end
		if f.__shown and f.__radios then
			for _, r in ipairs(f.__radios) do try("radio " .. tostring(r.text), r.setSel) end
		end
		if f.__shown and f.__init then try("legacy menu", f.__init, f, 1) end
	end
	-- key capture: any button now listening gets a key press, then a modifier-only press and Escape
	for _, f in ipairs(snapshot) do
		if f.__shown and f.__scripts.OnKeyDown and f.listening then
			press(f, "OnKeyDown", "LSHIFT"); press(f, "OnKeyDown", "K")
		end
	end
	for _, info in ipairs(LEGACY_INFOS or {}) do if info.func then try("legacy choice", info.func) end end
	runTimers(0.3)
end


-- ---------------------------------------------------------------- profile export / import
-- An independent base64 + checksum (so a symmetric mistake in the addon's own copy is caught).
local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function tb64(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i), s:byte(i + 1), s:byte(i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local q = { math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64 }
		local chunk = ""
		for k = 1, 4 do
			local use = (k == 1) or (k == 2) or (k == 3 and b) or (k == 4 and c)
			chunk = chunk .. (use and B:sub(q[k] + 1, q[k] + 1) or "=")
		end
		out[#out + 1] = chunk
	end
	return table.concat(out)
end
local function tb64d(s)
	local out = {}
	local rev = {}
	for i = 1, 64 do rev[B:sub(i, i)] = i - 1 end
	s = s:gsub("=", "")
	local bits, nb = 0, 0
	for i = 1, #s do
		bits = bits * 64 + rev[s:sub(i, i)]; nb = nb + 6
		if nb >= 8 then
			nb = nb - 8
			local div = 2 ^ nb
			out[#out + 1] = string.char(math.floor(bits / div) % 256)
			bits = bits % div
		end
	end
	return table.concat(out)
end
local function tsum(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end
	return string.format("%08x", h)
end
local function wrap(payload) return "WID1:" .. tb64(payload) .. ":" .. tsum(payload) end
local function expect(cond, msg) if not cond then fails = fails + 1; note("FAIL [profile] " .. msg) end end
local function approx(a, b) return a == b or (type(a) == "number" and type(b) == "number" and math.abs(a - b) <= 1e-4 * math.max(1, math.abs(a))) end

local function profileTests()
	-- standard base64 vectors, to prove the test's own encoder before relying on it
	expect(tb64("Man") == "TWFu" and tb64("Ma") == "TWE=" and tb64("M") == "TQ==", "test base64 encoder is wrong")
	expect(tb64d("TWFu") == "Man" and tb64d("TWE=") == "Ma", "test base64 decoder is wrong")

	local d = WhatItDropsDB
	d.theme, d.accent, d.opacity, d.uiScale, d.rowSize = "slate", "violet", 0.6, 1.2, "roomy"
	d.fxBars, d.fxFade, d.hideJunk, d.auto, d.fxModel = false, false, true, true, true
	d.pos = { loot = { 100.5, 200.25 }, browser = { 300, 400 }, options = { 50, 60 } }
	d.minimap = { hide = true, minimapPos = 123.456 }
	d.optionsPage, d.defaultBindApplied = "profile", true
	boundKey.WHATITDROPS_FULLLOOKUP, boundKey.WHATITDROPS_LOOKUP = "CTRL-SHIFT-K", "ALT-F9"

	local s = WhatItDrops_ExportProfile()
	expect(type(s) == "string" and s:sub(1, 5) == "WID1:", "export does not start with WID1:")
	expect(not s:find("[\r\n ]"), "export contains whitespace")
	expect(#s < 1500, "export is unexpectedly long: " .. #s)
	local body = s:match("^WID1:([^:]+):%x+$")
	local payload = body and tb64d(body) or ""
	for _, want in ipairs({ "theme=sslate", "accent=sviolet", "fxBars=b0", "hideJunk=b1", "minimap.hide=b1",
		"pos.loot.1=n100.5", "pos.options.2=n60", "bind.FULLLOOKUP=kCTRL-SHIFT-K", "bind.LOOKUP=kALT-F9", "v=1" }) do
		expect(payload:find(want, 1, true), "payload is missing " .. want)
	end
	expect(not payload:find("optionsPage") and not payload:find("defaultBindApplied"), "internal state leaked into the profile")

	-- wreck everything, then import
	d.theme, d.accent, d.opacity, d.uiScale, d.rowSize = "blizzard", "gold", 1, 1, "compact"
	d.fxBars, d.fxFade, d.hideJunk, d.auto, d.fxModel = true, true, false, false, false
	d.pos = { loot = { 1, 2 } }
	d.minimap = { hide = false, minimapPos = 5 }
	boundKey.WHATITDROPS_FULLLOOKUP, boundKey.WHATITDROPS_LOOKUP = "F1", nil
	local ok, msg = WhatItDrops_ImportProfile(s)
	expect(ok, "round-trip import failed: " .. tostring(msg))
	d = WhatItDropsDB
	expect(d.theme == "slate" and d.accent == "violet" and d.rowSize == "roomy", "enums did not round-trip")
	expect(approx(d.opacity, 0.6) and approx(d.uiScale, 1.2), "numbers did not round-trip")
	expect(d.fxBars == false and d.fxFade == false and d.hideJunk == true and d.auto == true and d.fxModel == true, "booleans did not round-trip")
	expect(d.pos and d.pos.loot and approx(d.pos.loot[1], 100.5) and approx(d.pos.loot[2], 200.25), "loot position did not round-trip")
	expect(d.pos and d.pos.browser and approx(d.pos.browser[1], 300) and d.pos.options and approx(d.pos.options[2], 60), "other positions did not round-trip")
	expect(d.minimap.hide == true and approx(d.minimap.minimapPos, 123.456), "minimap did not round-trip")
	expect(boundKey.WHATITDROPS_FULLLOOKUP == "CTRL-SHIFT-K" and boundKey.WHATITDROPS_LOOKUP == "ALT-F9", "keybinds did not round-trip")
	expect(d.optionsPage == "profile" and d.defaultBindApplied == true, "internal state was disturbed by an import")

	-- a profile with few keys: everything else must fall back to defaults, not keep the old value
	WhatItDropsDB.theme, WhatItDropsDB.fxBars, WhatItDropsDB.accent = "blizzard", false, "red"
	local ok2, msg2 = WhatItDrops_ImportProfile(wrap("v=1;theme=sparchment"))
	expect(ok2, "small profile rejected: " .. tostring(msg2))
	expect(WhatItDropsDB.theme == "parchment" and WhatItDropsDB.fxBars == true and WhatItDropsDB.accent == "gold",
		"keys missing from a profile were not reset to defaults")

	-- text pasted with line wrapping still imports
	local mid = math.floor(#s / 2)
	local wrapped = s:sub(1, mid) .. "\n  " .. s:sub(mid + 1)
	local okw = WhatItDrops_ImportProfile(wrapped)
	expect(okw, "a wrapped profile was rejected")

	-- things that must be refused, with a message and no Lua error
	local longJunk = string.rep("A", 30000)
	local tampered = s:sub(1, 12) .. (s:sub(13, 13) == "A" and "B" or "A") .. s:sub(14)
	local bad = {
		{ "empty", "" }, { "spaces", "   \n  " }, { "plain text", "hello world" },
		{ "tag only", "WID1:" }, { "no checksum", "WID1:abc" }, { "garbage body", "WID1:!!!!:00000000" },
		{ "wrong checksum", "WID1:" .. tb64("v=1;auto=b1") .. ":00000000" },
		{ "tampered body", tampered }, { "trailing junk", s .. "xyz" }, { "huge", longJunk },
		{ "newer tag", "WID2:" .. tb64("v=1;auto=b1") .. ":" .. tsum("v=1;auto=b1") },
		{ "no version", wrap("auto=b1") }, { "newer version", wrap("v=2;auto=b1") },
		{ "nothing recognised", wrap("v=1;evil=s1;theme=sevil;opacity=n99") },
		{ "only separators", wrap("v=1;;;;=;=") },
	}
	for _, c in ipairs(bad) do
		local before = WhatItDropsDB.theme
		local okb, mb = WhatItDrops_ImportProfile(c[2])
		expect(okb == false and type(mb) == "string" and #mb > 10, "should refuse '" .. c[1] .. "' with a message, got ok=" .. tostring(okb))
		expect(WhatItDropsDB.theme == before, "a refused import ('" .. c[1] .. "') still changed settings")
		local okc = WhatItDrops_CheckProfile(c[2])
		expect(okc == false, "CheckProfile accepted '" .. c[1] .. "'")
	end
	-- not even a string
	local okn, mn = WhatItDrops_ImportProfile(nil)
	expect(okn == false and type(mn) == "string", "a nil paste was not refused cleanly")

	-- a profile mixing good and hostile entries: take the good, skip the rest
	local mixed = wrap('v=1;auto=b1;theme=s");os.execute("x");--;opacity=nnan;uiScale=ninf;rowSize=sroomy;'
		.. 'pos.loot.1=n99999999;pos.browser.1=n10;fxBars=bmaybe;__index=s1;bind.LOOKUP=kctrl-x;minimap.minimapPos=n999')
	WhatItDropsDB.theme, WhatItDropsDB.auto, WhatItDropsDB.rowSize = "blizzard", false, "compact"
	local okm, mm = WhatItDrops_ImportProfile(mixed)
	expect(okm, "mixed profile rejected: " .. tostring(mm))
	expect(WhatItDropsDB.auto == true and WhatItDropsDB.rowSize == "roomy", "valid entries in a mixed profile were not applied")
	expect(WhatItDropsDB.theme == "blizzard", "a hostile theme value was applied")
	expect(type(mm) == "string" and (LOCALE ~= "enUS" or mm:find("skipped")), "a mixed profile did not report the skipped entries")
	expect(WhatItDropsDB.pos == nil or WhatItDropsDB.pos.browser == nil, "a half-pair position was kept")
	try("restore positions after half-pair", WhatItDrops_RestorePositions)

	-- in combat: settings apply, keybinds are left alone and the user is told
	IN_COMBAT = true
	boundKey.WHATITDROPS_LOOKUP = "F2"
	local okcb, mcb = WhatItDrops_ImportProfile(s)
	IN_COMBAT = false
	expect(okcb and boundKey.WHATITDROPS_LOOKUP == "F2", "keybinds changed during combat")
	expect(mcb and (LOCALE ~= "enUS" or mcb:find("Keybinds")), "no note about skipped keybinds in combat")

	-- an import that crosses ElvUI says it needs a reload
	WhatItDropsDB.theme = "blizzard"
	local _, mel = WhatItDrops_ImportProfile(wrap("v=1;theme=selvui"))
	expect(mel and mel:find("reload"), "no reload note when switching to ElvUI")
end

-- the same through the settings window and the slash command
local function profileUI()
	try("/wid export", SlashCmdList.WHATITDROPSWID, "export")
	runTimers(0.2)
	local box
	for _, f in ipairs(frames) do
		if f.__kind == "EditBox" and f.__text:sub(1, 5) == "WID1:" then box = f end
	end
	expect(box ~= nil, "/wid export did not fill the profile box")
	if not box then return end
	local exported = box.__text
	-- rows are recycled on every redraw, so look the button up again at each click, as a user
	-- clicking the spot where "Import" is would
	local function rowButton(label)
		for _, f in ipairs(frames) do
			if rawget(f, "label") and f.label.__text == label and rawget(f, "button") and rawget(f, "row") then return f.button end
		end
	end
	expect(rowButton(NS.L["Import"]) ~= nil, "Import button not found")
	if not rowButton(NS.L["Import"]) then return end
	WhatItDropsDB.theme = "blizzard"
	box.__text = "not a profile"
	press(rowButton(NS.L["Import"]), "OnClick", "LeftButton"); runTimers(0.2)
	expect(WhatItDropsDB.theme == "blizzard", "a bad paste changed settings")
	box.__text = exported
	local armedBefore = WhatItDropsDB.accent
	WhatItDropsDB.accent = "red"
	press(rowButton(NS.L["Import"]), "OnClick", "LeftButton"); runTimers(0.2)   -- first click only checks
	expect(WhatItDropsDB.accent == "red", "the first Import click already changed settings")
	press(rowButton(NS.L["Import"]), "OnClick", "LeftButton"); runTimers(0.2)   -- second click applies
	expect(WhatItDropsDB.accent == armedBefore, "the second Import click did not apply the profile")
	try("/wid import", SlashCmdList.WHATITDROPSWID, "import")
	try("/wid profile", SlashCmdList.WHATITDROPSWID, "profile")
end

local function optionsWindow()
	try("/wid toggle", SlashCmdList.WHATITDROPSWID, "")
	runTimers(0.1)
	local win = _G.WhatItDropsOptions
	if not win then note("FAIL options window was never built"); fails = fails + 1; return end
	if not win.__shown then note("FAIL options window not shown after /wid"); fails = fails + 1 end
	for _, key in ipairs({ "general", "appearance", "keybinds", "profile" }) do
		try("show page " .. key, WhatItDrops_ShowOptionsPage, key)
		runTimers(0.2)
		-- rebuild dropdown menus so radio entries exist before interacting
		for _, f in ipairs(frames) do if f.GenerateMenu and f.__menu then MENUS_BUILT = (MENUS_BUILT or 0) + 1; try("generate menu", f.GenerateMenu, f) end end
		try("interact " .. key, interact)
	end
	for _, key in ipairs({ "General", "Appearance", "Keybinds", "Profile" }) do
		local want = NS.L[key]
		if not TextsContain(want) then
			fails = fails + 1; note("FAIL [l10n] the settings window never showed '" .. key .. "' as '" .. tostring(want) .. "'")
		end
		if LOCALE ~= "enUS" and want == key and not (LOCALE == "esES" or LOCALE == "esMX") then
			fails = fails + 1; note("FAIL [l10n] '" .. key .. "' is untranslated under " .. LOCALE)
		end
	end
	if not TextsContain(NS.L["Hide common loot"]) then
		fails = fails + 1; note("FAIL [l10n] the loot window never showed its translated 'Hide common loot' label")
	end
	if LOCALE ~= "enUS" and NS.L["Hide common loot"] == "Hide common loot" then
		fails = fails + 1; note("FAIL [l10n] 'Hide common loot' is untranslated under " .. LOCALE)
	end
	try("/wid appearance", SlashCmdList.WHATITDROPSWID, "appearance")
	try("refresh", WhatItDrops_RefreshOptions)
	try("close", function() win:Hide() end)
	try("/wid toggle again", SlashCmdList.WHATITDROPSWID, "")
	if not win.__shown then note("FAIL second /wid did not reopen"); fails = fails + 1 end
end

-- ---------------------------------------------------------------- names in the client's language
local function nameTests()
	local function check(cond, msg) if not cond then fails = fails + 1; note("FAIL [names] " .. msg) end end
	local Names = NS.Names
	local ENGLISH = (LOCALE == "enUS")
	local requests0 = CALLS.request
	local function rowCount(win, id)
		local n = 0
		for _, f in ipairs(frames) do
			if f.__kind == "Button" and f.__parent == win.content and f.__shown and rawget(f, "itemID") == id then n = n + 1 end
		end
		return n
	end
	local function textHas(sub)
		for _, f in ipairs(frames) do
			if f.__kind == "FontString" and f.__shown ~= false and type(f.__text) == "string" and f.__text:find(sub, 1, true) then return true end
		end
		return false
	end
	local function browserHas(sub)
		local win = _G.WhatItDropsBrowserFrame
		for _, f in ipairs(frames) do
			if f.__kind == "FontString" and win and f.__parent and f.__parent.__parent == win.content and type(f.__text) == "string" and f.__text:find(sub, 1, true) then return true end
		end
		return false
	end
	local function said(sub)
		for _, m in ipairs(chat) do if tostring(m):find(sub, 1, true) then return true end end
		return false
	end
	local function save() return (WhatItDropsDB.l10n or {})[LOCALE] end

	-- case folding that goes beyond ASCII
	check(Names.Fold("ÄRZTLICHE KRÄUTER") == "ärztliche kräuter", "Fold does not lower Latin-1 capitals")
	check(Names.Fold("ВОЛЧЬЯ ШКУРА Ёж ЯЩИК") == "волчья шкура ёж ящик", "Fold does not lower Cyrillic capitals")
	check(Names.Fold("A×B Straße") == "a×b straße", "Fold changed the multiplication sign or the sharp s")
	check(Names.Fold("狼皮 늑대") == "狼皮 늑대", "Fold altered text that has no case")

	if ENGLISH then
		-- an English client must behave exactly as it always did: none of the new machinery runs
		if CLIENT == "forever" then
			QUEST_ENGLISH = nil
			WhatItDrops_ShowQuest(); runTimers(0.1)
			check(rowCount(_G.WhatItDropsFrame, 1001) == 1, "English quest view lost its item")
			SlashCmdList.WHATITDROPS("browse wolf"); runTimers(1.5)
			check(rowCount(_G.WhatItDropsBrowserFrame, 1001) == 1, "English search lost an item")
			SlashCmdList.WHATITDROPS("browse pelt"); runTimers(1.5)
			check(rowCount(_G.WhatItDropsBrowserFrame, 1001) == 1, "English search for 'pelt' lost an item")
			check(CALLS.request == requests0, "an English client asked for item data (" .. (CALLS.request - requests0) .. " requests)")
		end
		SlashCmdList.WHATITDROPS("names")
		check(said(NS.L["Your client is English: the bundled names are used as they are."]), "/loot names said nothing on an English client")
		check(CALLS.name == 0 and CALLS.tip == 0, "an English client used the name APIs (name=" .. CALLS.name .. " tip=" .. CALLS.tip .. ")")
		check(WhatItDropsDB.l10n == nil, "an English client wrote a language cache")
		check(Names.Npc(1234) == nil and Names.Item(1001) == nil and Names.Progress() == 0, "Names answered on an English client")
		return
	end

	-- Item names on a cold cache: the server is asked at a polite rate, later sessions ask only for
	-- what is still missing, and a session that learns nothing new stops asking until the game updates.
	local function coldCacheTests()
		local realGetLocale, realBuild = GetLocale, GetBuildInfo
		local savedNames, savedQuest = WhatItDropsItemName, WhatItDropsQuestItem
		WhatItDropsItemName, WhatItDropsQuestItem = {}, {}
		for id = 5000, 5299 do WhatItDropsItemName[id] = "Filler " .. id end
		for id = 5000, 5009 do WhatItDropsQuestItem[id] = true end
		local function session(locale)
			GetLocale = function() return locale end
			local M = {}
			assert(loadstring(readfile(ADDON_DIR .. "/Names.lua"), "@Names.lua"))("WhatItDrops", M)
			return M.Names
		end
		local function drive(M, seconds)       -- run one session's index; returns requests made, busiest tick, requests
			local before, busiest = CALLS.request, 0
			M.StartItemIndex()
			busiest = CALLS.request - before         -- the first tick runs inside StartItemIndex
			for _ = 1, seconds * 4 do
				local b = CALLS.request
				runTimers(0.25)
				busiest = math.max(busiest, CALLS.request - b)
			end
			return CALLS.request - before, busiest
		end
		local function deliver(M, from, to) for id = from, to do LOADED[id] = true; M.OnItemInfo(id) end end
		local function saved(loc) return WhatItDropsDB.l10n and WhatItDropsDB.l10n[loc] end

		-- session 1, nothing cached: all 300 are asked for, never more than 12 in a tick (50 a second)
		local M1 = session("xxXX")
		runTimers(0.1)
		local n, busiest = drive(M1, 8)
		check(n == 300, "a cold pass asked for " .. n .. " of 300 items")
		check(busiest <= 12, "a cold pass made " .. busiest .. " requests in one tick (limit 12, about 50 a second)")
		deliver(M1, 5000, 5149)                 -- the client answers for half of them
		runTimers(16)
		check(saved("xxXX").missingLast == 150 and not saved("xxXX").settled, "pass 1 did not record 150 still missing")
		-- session 2: only the 150 that are still missing are asked for again, and 50 more arrive
		local M2 = session("xxXX")
		n, busiest = drive(M2, 8)
		check(n == 150, "the next session asked for " .. n .. " items, not the 150 still missing")
		check(busiest <= 12, "the retry pass made " .. busiest .. " requests in one tick")
		deliver(M2, 5150, 5199)
		runTimers(16)
		check(saved("xxXX").missingLast == 100 and not saved("xxXX").settled, "pass 2 made progress and must not settle")
		-- session 3: nothing new arrives, so this pass settles
		local M3 = session("xxXX")
		n = drive(M3, 8)
		check(n == 100, "session 3 asked for " .. n .. " items, not the 100 still missing")
		runTimers(16)
		check(saved("xxXX").settled, "a pass that added nothing did not settle")
		-- session 4: settled, so the server is left alone (the client's cache is still read)
		local M4 = session("xxXX")
		n = drive(M4, 8)
		check(n == 0, "a settled index still made " .. n .. " requests")
		-- a new game build starts over
		GetBuildInfo = function() return "12.1.5", "70000", "x", 120105 end
		local M5 = session("xxXX")
		n = drive(M5, 8)
		check(n == 100, "after a game update the index asked for " .. n .. " items, not the 100 missing")
		check(not saved("xxXX").settled and saved("xxXX").build == "12.1.5-70000", "a game update did not reset the pass bookkeeping")
		GetBuildInfo = realBuild

		-- a warm cache is scanned freely: no requests, done in one tick
		for id = 5000, 5299 do LOADED[id] = true end
		local M6 = session("yyYY")
		n = drive(M6, 2)
		local have, total = M6.Progress()
		check(n == 0 and have == 300 and total == 300, "a warm cache made " .. n .. " requests and read " .. have .. "/" .. total)

		-- put everything back
		GetLocale, WhatItDropsItemName, WhatItDropsQuestItem = realGetLocale, savedNames, savedQuest
		for id = 5000, 5299 do LOADED[id], REQUESTED[id] = nil, nil end
		WhatItDropsDB.l10n.xxXX, WhatItDropsDB.l10n.yyYY = nil, nil
	end

	local function creatureTests()   -- run after the item tests on Classic: those need the index still unfinished
	local t0 = CALLS.tip
	check(Names.Npc(5555) == "Kobold-LOC", "the client's creature name was not taken from the tooltip")
	check(CALLS.tip == t0 + 1, "one creature cost " .. (CALLS.tip - t0) .. " lookups")
	check(Names.Npc(5555) == "Kobold-LOC" and CALLS.tip == t0 + 1, "a known creature was asked for again")
	check(save() and save().npc[5555] == "Kobold-LOC", "the creature name was not saved")
	t0 = CALLS.tip
	check(Names.Npc(9999) == nil and (save().npc[9999] == nil), "a placeholder word was taken as a creature name")
	check(Names.Npc(9999) == nil and CALLS.tip == t0 + 1, "a failed creature lookup was repeated at once")
	runTimers(31)
	Names.Npc(9999)
	check(CALLS.tip == t0 + 2, "a failed creature lookup was never retried")
	check(Names.Npc(8888) == nil and save().npc[8888] == nil, "an empty tooltip answer produced a name")
	TIP_MODE = "secret"
	check(Names.Npc(7777) == nil and save().npc[7777] == nil, "a secret value was stored as a creature name")
	TIP_MODE = "error"
	check(pcall(Names.Npc, 7778), "an error from C_TooltipInfo escaped")
	TIP_MODE = "normal"
	runTimers(2)
	local t1 = CALLS.tip
	for id = 20000, 20039 do Names.Npc(id) end
	check(CALLS.tip - t1 <= 20, "a page of creatures made " .. (CALLS.tip - t1) .. " lookups in one second")
	runTimers(2)
	-- a name the client reports for free (the target's own name) is kept
	unit.name = "Moroes-DE"
	try("/loot (creature, localized name)", SlashCmdList.WHATITDROPS, "")
	unit.name = "Moroes"
	check(save().npc[1234] == "Moroes-DE", "the target's own name was not remembered")
	SlashCmdList.WHATITDROPS("browse moroes-de"); runTimers(1.5)
	check(browserHas("Moroes-DE"), "a creature known by its client name could not be found by it")
	SlashCmdList.WHATITDROPS("names")
	check(said("Moroes-LOC |"), "/loot names did not report what the client answered for the target")

	end
	if CLIENT ~= "forever" then creatureTests(); coldCacheTests(); return end

	-- ---- items (Classic data on a non-English client)
	local lang = LOCALNAME[LOCALE]
	local queryFor = { deDE = "ÄRZT", ruRU = "ВОЛЧЬЯ", koKR = "늑대", zhCN = "狼皮" }
	local wantId = { deDE = 1004, ruRU = 1001, koKR = 1001, zhCN = 1001 }
	local query, want = queryFor[LOCALE], wantId[LOCALE]
	local lootWin, brWin
	check(Names.Item(1001) == nil, "an item the client has not loaded already had a name")
	check(REQUESTED[1001], "an item on screen was never requested from the client")
	-- searching starts collecting the client's item names, and says how far that has got
	SlashCmdList.WHATITDROPS("browse " .. query); runTimers(0.1)
	brWin = _G.WhatItDropsBrowserFrame
	check(REQUESTED[1007], "a search did not start collecting the item names")
	check(rowCount(brWin, want) == 0, "a localized search matched before any name was known")
	check(textHas(NS.L["Item names: %d of %d"]:format(0, 8)), "the browser did not show the name-collecting progress")
	-- an objective written in English still resolves on a non-English client (an English quest log)
	QUEST_ENGLISH = true
	WhatItDrops_ShowQuest(); runTimers(0.1)
	lootWin = _G.WhatItDropsFrame
	check(rowCount(lootWin, 1001) == 1 and rowCount(lootWin, 1003) == 1, "an English objective on a non-English client no longer resolves")
	QUEST_ENGLISH = nil
	-- a localized objective cannot resolve until the client has told us the names
	WhatItDrops_ShowQuest(); runTimers(0.1)
	check(rowCount(lootWin, 1001) == 0 and rowCount(lootWin, 1003) == 0, "a localized quest item resolved before any name was known")
	-- the client delivers
	for id in pairs(REQUESTED) do LOADED[id] = true; fire("GET_ITEM_INFO_RECEIVED", id, true) end
	fire("ITEM_DATA_LOAD_RESULT", 1001, true)
	runTimers(1.5)
	check(rowCount(lootWin, 1001) == 1, "the quest view did not fill in the quest item when the names arrived (the duplicate name must pick the quest-class item)")
	check(rowCount(lootWin, 1003) == 1, "the quest view did not fill in an ordinary item when the names arrived")
	check(rowCount(brWin, want) == 1, "the localized search did not find the item once the names arrived (" .. tostring(query) .. ")")
	runTimers(20); runTimers(2)       -- the pass is called done after 15 s; the redraw follows a second later
	local have, total, done = Names.Progress()
	check(done and have == 5 and total == 8, "index progress is " .. tostring(have) .. "/" .. tostring(total) .. " done=" .. tostring(done))
	check(not textHas("|cff888888" .. NS.L["Item names: %d of %d"]:format(have, total)), "the progress note stayed after the index finished")
	check(save().items[1001] == lang[1001] and save().items[1004] == lang[1004], "the item names were not saved")
	check(save().missingLast == 3 and save().build, "a finished pass did not record how many names were still missing")
	-- the English name still finds it, once (not twice, though the localized name matches too)
	SlashCmdList.WHATITDROPS("browse wolf"); runTimers(1.5)
	check(rowCount(brWin, 1001) == 1, "an English search on a non-English client listed the item " .. rowCount(brWin, 1001) .. " times")
	-- a creature name typed in English still works
	SlashCmdList.WHATITDROPS("browse moroes"); runTimers(1.5)
	check(browserHas("Moroes"), "an English creature search stopped working on a non-English client")
	creatureTests()
	coldCacheTests()
end

if WhatItDropsDB then
	try("loot window", lootWindow)
	try("names", nameTests)
	try("profile engine", profileTests)
	try("options window", optionsWindow)
	try("profile UI", profileUI)
end

-- settings must have landed in the saved table
for _, k in ipairs({ "fxBars", "fxModel", "rowSize", "opacity", "uiScale", "accent", "theme" }) do
	if (WhatItDropsDB or {})[k] == nil then note("FAIL setting never seeded: " .. k); fails = fails + 1 end
end

print = _G.__realprint or print
local cov = {}
for k, v in pairs(PRESSES or {}) do cov[#cov + 1] = k .. "=" .. v end
table.sort(cov)
note("coverage: " .. table.concat(cov, " ") .. " | menus=" .. tostring(MENUS_BUILT or 0) .. " | clicks that hit a live setting row=" .. tostring(CLICKED_ROWS or 0))
for _, m in ipairs(chat) do note("chat: " .. tostring(m)) end
return { fails = fails, notes = notes, frames = #frames, chat = chat }
