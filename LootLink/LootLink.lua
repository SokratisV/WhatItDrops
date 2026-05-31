local ADDON = ...

-- Pick the correct Wowhead database for whatever flavor we're running on,
-- so the same file produces the right link on Retail, TBC, Wrath, Era, etc.
-- Retail uses no branch prefix ("wowhead.com/npc="); Classic flavors use one.
local function DetectBranch()
	local p = WOW_PROJECT_ID
	if not p then return "" end -- very old client; assume mainline-style
	if p == WOW_PROJECT_MAINLINE then return "" end
	if p == WOW_PROJECT_CLASSIC then return "classic" end
	if WOW_PROJECT_BURNING_CRUSADE_CLASSIC and p == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then return "tbc" end
	if WOW_PROJECT_WRATH_CLASSIC and p == WOW_PROJECT_WRATH_CLASSIC then return "wotlk" end
	if WOW_PROJECT_CATACLYSM_CLASSIC and p == WOW_PROJECT_CATACLYSM_CLASSIC then return "cata" end
	if WOW_PROJECT_MISTS_CLASSIC and p == WOW_PROJECT_MISTS_CLASSIC then return "mop-classic" end
	return "" -- unknown/new flavor: fall back to retail database
end

local WOWHEAD_BRANCH = DetectBranch()

local function BuildURL(npcID)
	local branch = WOWHEAD_BRANCH ~= "" and (WOWHEAD_BRANCH .. "/") or ""
	return ("https://www.wowhead.com/%snpc=%d#drops"):format(branch, npcID)
end

-- Pull the NPC ID out of a unit GUID.
-- Creature/Vehicle/Pet GUIDs look like: "Creature-0-1234-5-6789-NPCID-SPAWN"
local function GetNpcID(unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	local kind, _, _, _, _, npcID = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then
		return tonumber(npcID), kind
	end
	return nil, kind
end

local QUALITY_COLORS = _G.ITEM_QUALITY_COLORS
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Names/quality are baked (LootLinkItems.lua); fall back to GetItemInfo when an
-- item/npc isn't in our tables (e.g. items not present in the CMaNGOS DB).
local function ItemName(id)
	return (LootLinkItemName and LootLinkItemName[id]) or GetItemInfo(id) or ("item:" .. id)
end
local function ItemQuality(id)
	local q = LootLinkItemQuality and LootLinkItemQuality[id]
	if q ~= nil then return q end
	return select(3, GetItemInfo(id))
end
local function NpcName(id)
	return (LootLinkNpcName and LootLinkNpcName[id]) or ("NPC " .. id)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local ROW_H, MAX_VIEW = 18, 216
local HEADER_H, FOOTER_H = 40, 78
local win, rows
local current = { id = nil, name = nil, items = nil }

local function GetWindow()
	if win then return win end

	local f = CreateFrame("Frame", "LootLinkFrame", UIParent, "BackdropTemplate")
	f:SetSize(340, 200)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 },
	})

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetPoint("TOPRIGHT", -76, -12)
	title:SetJustifyH("LEFT")
	f.title = title

	local source = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	source:SetPoint("TOPLEFT", 14, -26)
	source:SetText("Drop data: Wowhead via Questie")
	f.source = source

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	-- Header icon buttons: open Settings / open Item Browser.
	local function HeaderButton(texture, tip, onClick, anchorTo, dx)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(16, 16)
		b:SetPoint("RIGHT", anchorTo, "LEFT", dx, 0)
		b:SetNormalTexture(texture)
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show() end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end
	local cfgBtn = HeaderButton("Interface\\Buttons\\UI-OptionsButton", "Settings",
		function() if LootLink_OpenSettings then LootLink_OpenSettings() end end, close, -1)
	HeaderButton("Interface\\Common\\UI-Searchbox-Icon", "Item browser",
		function() if LootLink_OpenBrowser then LootLink_OpenBrowser() end end, cfgBtn, -4)

	-- Scrollable item list
	local scroll = CreateFrame("ScrollFrame", "LootLinkScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -HEADER_H)
	scroll:SetPoint("TOPRIGHT", -30, -HEADER_H)
	scroll:SetHeight(MAX_VIEW)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(296, 1)
	scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content

	-- "No data" message (shown when the NPC isn't in our DB)
	local empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	empty:SetPoint("TOPLEFT", 16, -HEADER_H - 6)
	empty:SetPoint("TOPRIGHT", -16, -HEADER_H - 6)
	empty:SetJustifyH("LEFT")
	empty:SetText("No bundled loot for this NPC. Use the Wowhead link below.")
	empty:Hide()
	f.empty = empty

	-- Footer: two toggles (hide-junk, world-drops) + copyable Wowhead URL
	local check = CreateFrame("CheckButton", "LootLinkHideJunk", f, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:SetPoint("BOTTOMLEFT", 10, 8)
	local checkLabel = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
	checkLabel:SetText("Hide common loot")
	check:SetScript("OnClick", function(self)
		LootLinkDB.hideJunk = self:GetChecked() and true or false
		LootLink_Refresh()
	end)
	f.check = check

	local worldCheck = CreateFrame("CheckButton", "LootLinkWorldDrops", f, "UICheckButtonTemplate")
	worldCheck:SetSize(22, 22)
	worldCheck:SetPoint("BOTTOMLEFT", 10, 30)
	local worldLabel = worldCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	worldLabel:SetPoint("LEFT", worldCheck, "RIGHT", 2, 0)
	worldLabel:SetText("Show world drops")
	worldCheck:SetScript("OnClick", function(self)
		LootLinkDB.showWorldDrops = self:GetChecked() and true or false
		LootLink_Refresh()
	end)
	f.worldCheck = worldCheck

	local urlBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	urlBtn:SetSize(80, 20)
	urlBtn:SetPoint("BOTTOMRIGHT", -10, 8)
	urlBtn:SetText("Wowhead")
	urlBtn:SetScript("OnClick", function()
		if f.url:IsShown() then
			f.url:Hide()
		else
			f.url:Show(); f.url:SetFocus(); f.url:HighlightText()
		end
	end)

	local url = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	url:SetPoint("BOTTOMLEFT", 12, 54)
	url:SetPoint("BOTTOMRIGHT", -12, 54)
	url:SetHeight(20)
	url:SetAutoFocus(false)
	url:SetFontObject(ChatFontNormal)
	url:SetScript("OnEscapePressed", function(self) self:Hide() end)
	url:SetScript("OnTextChanged", function(self)
		if current.id and self:GetText() ~= BuildURL(current.id) then
			self:SetText(BuildURL(current.id)); self:HighlightText()
		end
	end)
	url:Hide()
	f.url = url

	-- Ctrl+C shortcut:
	--   1st press -> reveal & select the Wowhead URL (same as the button).
	--   2nd press -> the focused box copies it natively, then we close.
	-- The popup keeps keyboard input propagating so movement/keybinds still work;
	-- it only consumes the specific Ctrl+C that triggers the reveal.
	f:EnableKeyboard(true)
	f:SetPropagateKeyboardInput(true)
	f:SetScript("OnKeyDown", function(self, key)
		if key == "C" and IsControlKeyDown() and (not url:IsShown() or not url:HasFocus()) then
			self:SetPropagateKeyboardInput(false) -- consume this Ctrl+C
			url:Show(); url:SetFocus(); url:HighlightText()
		else
			self:SetPropagateKeyboardInput(true)  -- let every other key through
		end
	end)
	url:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			-- WoW performs the clipboard copy as part of this keypress; defer the
			-- close by one frame so the copy completes before the box disappears.
			C_Timer.After(0, function() f:Hide() end)
		end
	end)

	win, rows = f, {}
	return f
end

local function GetRow(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, win.content)
	r:SetSize(296, ROW_H)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetPoint("LEFT", 0, 0)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
	r.name:SetJustifyH("LEFT")

	r.rate = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.rate:SetPoint("RIGHT", 0, 0)
	r.rate:SetJustifyH("RIGHT")
	r.name:SetPoint("RIGHT", r.rate, "LEFT", -6, 0)

	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)

	r:SetScript("OnEnter", function(self)
		if not self.itemID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.itemID)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick("CHATLINK") then
			ChatEdit_InsertLink(self.link)
		end
	end)

	rows[i] = r
	return r
end

-- Re-render the current NPC's list (called on open, on toggle, and when
-- async item info arrives via GET_ITEM_INFO_RECEIVED).
function LootLink_Render()
	if not win or not win:IsShown() then return end
	local items = current.items
	local hideJunk = LootLinkDB and LootLinkDB.hideJunk

	if not items then
		for _, r in ipairs(rows) do r:Hide() end
		win.scroll:Hide(); win.check:Hide(); win.worldCheck:Hide(); win.empty:Show()
		win.content:SetHeight(1)
		win:SetHeight(HEADER_H + 30 + FOOTER_H)
		return
	end
	win.empty:Hide(); win.scroll:Show(); win.check:Show(); win.worldCheck:Show()

	local function pctStr(p) return (p >= 1 and "%.1f%%" or "%.2f%%"):format(p) end
	local shown, waiting = 0, false
	for _, entry in ipairs(items) do
		local itemID, rate = entry.id, entry.pct
		-- Names/quality come from our baked tables (instant, offline). GetItemInfo
		-- is only needed for the chat link + icon, which may arrive asynchronously.
		local name = ItemName(itemID)
		local quality = ItemQuality(itemID)
		local _, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
		if not link then waiting = true end
		local hidden = hideJunk and quality and quality < 2
		if not hidden then
			shown = shown + 1
			local r = GetRow(shown)
			r:SetPoint("TOPLEFT", 0, -(shown - 1) * ROW_H)
			r.itemID, r.link = itemID, link
			r.icon:SetTexture(icon or GetItemIcon(itemID) or FALLBACK_ICON)
			local color = quality and QUALITY_COLORS[quality]
			r.name:SetText(color and (color.hex .. name .. "|r") or ("|cffffffff" .. name .. "|r"))
			r.rate:SetText(pctStr(rate))
			r:Show()
		end
	end
	for i = shown + 1, #rows do rows[i]:Hide() end

	win.content:SetHeight(math.max(shown * ROW_H, 1))
	local viewH = math.min(shown * ROW_H, MAX_VIEW)
	win.scroll:SetHeight(math.max(viewH, ROW_H))
	win:SetHeight(HEADER_H + math.max(viewH, ROW_H) + FOOTER_H)

	-- If any item wasn't cached yet, the GET_ITEM_INFO_RECEIVED handler will
	-- re-render as the data streams in.
	current.waiting = waiting
end

-- Continent / instance data is split into per-region LoadOnDemand addons that
-- all populate the global LootLinkFull. We load only the region you're in, the
-- first time you /fullloot there — so memory tracks where you actually play.
local PARTITIONS = { "EasternKingdoms", "Kalimdor", "Outland", "Instances", "Misc" }
local CONTINENT  = { [0] = "EasternKingdoms", [1] = "Kalimdor", [530] = "Outland" }
local loadedPart = {}

local function LoadPartition(name)
	if loadedPart[name] then return end
	loadedPart[name] = true
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if load then load("LootLink_" .. name) end
end

local function CurrentPartition()
	local mapID = select(8, GetInstanceInfo())
	return CONTINENT[mapID] or "Instances"
end

-- Ensure the target's data is loaded: try the current region (+ Misc) first,
-- and only fall back to loading every partition if the NPC isn't found there.
local function EnsureFull(npcID)
	LoadPartition(CurrentPartition())
	LoadPartition("Misc")
	if LootLinkFull and LootLinkFull[npcID] then return true end
	for _, p in ipairs(PARTITIONS) do LoadPartition(p) end
	if not LootLinkFull then
		print("|cff66ccffLootLink|r: full data not loaded — enable the |cffffd100LootLink_*|r data addons in your AddOns list.")
	end
	return LootLinkFull and LootLinkFull[npcID] ~= nil
end

-- Build the item list from the flat data: { {id=, pct=}, ... }, rate-sorted.
-- Flat layout: arr = { specificCount, id,pct, id,pct, ... } with mob-specific
-- drops first and the generic world-drop pool after; world drops are included
-- only when the toggle is on.
local function BuildList(npcID)
	local arr = LootLinkFull and LootLinkFull[npcID]
	if not arr then return nil end
	local total = (#arr - 1) / 2
	local maxPairs = (LootLinkDB and LootLinkDB.showWorldDrops) and total or arr[1]
	local list = {}
	for k = 0, maxPairs - 1 do
		list[#list + 1] = { id = arr[2 + 2 * k], pct = arr[3 + 2 * k] }
	end
	table.sort(list, function(a, b) return a.pct > b.pct end)
	return (#list > 0) and list or nil
end

-- Rebuild the current NPC's list (needed when a toggle changes *which* items are
-- included, e.g. world drops) and redraw. Global so the toggles/Settings can call it.
function LootLink_Refresh()
	if current.id then current.items = BuildList(current.id) end
	LootLink_Render()
end

local function ShowNPC(npcID, npcName)
	local f = GetWindow()
	current.id, current.name = npcID, npcName
	current.items = BuildList(npcID)
	f.source:SetText("Loot: Wowhead %  (data via LootCodex)")
	f.title:SetText((npcName or "NPC") .. "  |cff888888(" .. npcID .. ")|r")
	f.check:SetChecked(LootLinkDB and LootLinkDB.hideJunk or false)
	f.worldCheck:SetChecked(LootLinkDB and LootLinkDB.showWorldDrops or false)
	f.url:SetText(BuildURL(npcID))
	f.url:Hide()
	f:Show()
	LootLink_Render()
end

----------------------------------------------------------------------
-- Item browser: search items by name, see which NPCs drop them
----------------------------------------------------------------------
local bWin, bRows = nil, {}
local bState, bSelItem, bResults = "items", nil, nil
local reverseIndex                  -- itemID -> { {npc=, pct=}, ... }, built lazily
local RenderBrowser, DoBrowserSearch

-- Reverse index needs every region's data, so building it loads all partitions.
-- Only triggered when you click an item in the browser, then cached.
local function BuildReverse()
	if reverseIndex then return end
	for _, p in ipairs(PARTITIONS) do LoadPartition(p) end
	reverseIndex = {}
	for npc, arr in pairs(LootLinkFull or {}) do
		local total = (#arr - 1) / 2
		for k = 0, total - 1 do
			local id = arr[2 + 2 * k]
			local t = reverseIndex[id]; if not t then t = {}; reverseIndex[id] = t end
			t[#t + 1] = { npc = npc, pct = arr[3 + 2 * k] }
		end
	end
end

local function GetBRow(i)
	if bRows[i] then return bRows[i] end
	local r = CreateFrame("Button", nil, bWin.content)
	r:SetSize(318, ROW_H)
	r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 0, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetJustifyH("LEFT")
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.right:SetPoint("RIGHT", 0, 0)
	r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
	local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
	r:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	r:SetScript("OnEnter", function(self) if self.itemID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bRows[i] = r
	return r
end

RenderBrowser = function()
	local f = bWin
	if not f or not f:IsShown() then return end
	f.back:SetShown(bState == "npcs")
	local list = {}
	if bState == "items" then
		f.title:SetText("LootLink — Item Browser")
		local res = bResults or {}
		f.status:SetText(#res .. " match" .. (#res == 1 and "" or "es"))
		for i = 1, math.min(#res, 300) do list[i] = res[i] end
	else
		f.title:SetText("Dropped by: " .. ItemName(bSelItem))
		local src = (reverseIndex and reverseIndex[bSelItem]) or {}
		for i = 1, #src do list[i] = src[i] end
		table.sort(list, function(a, b) return a.pct > b.pct end)
		f.status:SetText(#list .. " npc" .. (#list == 1 and "" or "s"))
		while #list > 300 do list[#list] = nil end
	end
	local shown = 0
	for i, e in ipairs(list) do
		shown = i
		local r = GetBRow(i)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		if bState == "items" then
			r.itemID = e.id
			local q = ItemQuality(e.id); local c = q and QUALITY_COLORS[q]
			r.icon:SetTexture(GetItemIcon(e.id) or FALLBACK_ICON)
			r.name:SetText((c and c.hex or "|cffffffff") .. e.name .. "|r")
			r.right:SetText("")
			r.onClick = function() bSelItem = e.id; bState = "npcs"; BuildReverse(); RenderBrowser() end
		else
			r.itemID = nil
			r.icon:SetTexture(FALLBACK_ICON)
			r.name:SetText(NpcName(e.npc) .. "  |cff888888(" .. e.npc .. ")|r")
			r.right:SetText((e.pct >= 1 and "%.1f%%" or "%.2f%%"):format(e.pct))
			r.onClick = function() ShowNPC(e.npc, NpcName(e.npc)) end
		end
		r:Show()
	end
	for i = shown + 1, #bRows do bRows[i]:Hide() end
	f.content:SetHeight(math.max(shown * ROW_H, 1))
end

DoBrowserSearch = function(query)
	bState, bSelItem = "items", nil
	local q = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local res = {}
	if #q >= 2 and LootLinkItemName then
		for id, nm in pairs(LootLinkItemName) do
			if nm:lower():find(q, 1, true) then res[#res + 1] = { id = id, name = nm } end
		end
		table.sort(res, function(a, b) return a.name < b.name end)
	end
	bResults = res
	RenderBrowser()
end

local function GetBrowser()
	if bWin then return bWin end
	local f = CreateFrame("Frame", "LootLinkBrowserFrame", UIParent, "BackdropTemplate")
	f:SetSize(360, 440); f:SetPoint("CENTER", 90, 0); f:SetFrameStrata("DIALOG")
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing); f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 },
	})
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOP", 0, -12); f.title = title
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)

	local sb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	sb:SetSize(228, 22); sb:SetPoint("TOPLEFT", 16, -34); sb:SetAutoFocus(false); sb:SetFontObject(ChatFontNormal)
	sb:SetScript("OnEnterPressed", function(self) DoBrowserSearch(self:GetText()); self:ClearFocus() end)
	sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.search = sb
	local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	go:SetSize(62, 22); go:SetPoint("LEFT", sb, "RIGHT", 6, 0); go:SetText("Search")
	go:SetScript("OnClick", function() DoBrowserSearch(sb:GetText()) end)

	local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	back:SetSize(54, 20); back:SetPoint("TOPLEFT", 14, -60); back:SetText("< Back")
	back:SetScript("OnClick", function() bState = "items"; RenderBrowser() end); back:Hide(); f.back = back
	local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); status:SetPoint("TOPRIGHT", -16, -64); f.status = status

	local scroll = CreateFrame("ScrollFrame", "LootLinkBrowserScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -84); scroll:SetPoint("BOTTOMRIGHT", -30, 14)
	local content = CreateFrame("Frame", nil, scroll); content:SetSize(318, 1); scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content

	bWin = f
	return f
end

function LootLink_OpenBrowser(text)
	local f = GetBrowser()
	bState, bSelItem = "items", nil
	f:Show()
	if text and text ~= "" then f.search:SetText(text); DoBrowserSearch(text) else RenderBrowser() end
	f.search:SetFocus()
end

----------------------------------------------------------------------
-- Core action
----------------------------------------------------------------------
local function LinkUnit(unit)
	unit = unit or "target"
	if not UnitExists(unit) then
		print("|cff66ccffLootLink|r: No target. Target a mob and try again.")
		return
	end
	local npcID, kind = GetNpcID(unit)
	if not npcID then
		if kind == "Player" then
			print("|cff66ccffLootLink|r: That's a player — no loot table to look up.")
		else
			print("|cff66ccffLootLink|r: Couldn't read an NPC ID from that unit.")
		end
		return
	end
	EnsureFull(npcID)
	ShowNPC(npcID, UnitName(unit))
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		LootLinkDB = LootLinkDB or {}
		if LootLinkDB.auto == nil then LootLinkDB.auto = false end
		if LootLinkDB.hideJunk == nil then LootLinkDB.hideJunk = false end
		if LootLinkDB.showWorldDrops == nil then LootLinkDB.showWorldDrops = true end
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("PLAYER_LOGIN")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		-- Apply the default keybind (CTRL-L) once, and only if the action is
		-- unbound and CTRL-L isn't already taken — never clobber the user.
		if not LootLinkDB.defaultBindApplied then
			LootLinkDB.defaultBindApplied = true
			if not GetBindingKey("LOOTLINK_FULLLOOKUP") then
				local taken = GetBindingAction("CTRL-L")
				if not taken or taken == "" then
					SetBinding("CTRL-L", "LOOTLINK_FULLLOOKUP")
					SaveBindings(GetCurrentBindingSet())
				end
			end
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		if LootLinkDB.auto and UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsPlayer("target") then
			local npcID = GetNpcID("target")
			if npcID then EnsureFull(npcID); ShowNPC(npcID, UnitName("target")) end
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if win and win:IsShown() and current.waiting then
			LootLink_Render()
		end
	end
end)

----------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------
SLASH_LOOTLINK1 = "/loot"
SLASH_LOOTLINK2 = "/lootlink"
SlashCmdList.LOOTLINK = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "auto" then
		LootLinkDB.auto = not LootLinkDB.auto
		print("|cff66ccffLootLink|r: auto-show on target is now " ..
			(LootLinkDB.auto and "|cff00ff00ON|r" or "|cffff0000OFF|r") .. ".")
	elseif msg == "config" or msg == "options" then
		if LootLink_OpenSettings then LootLink_OpenSettings() end
	elseif msg:match("^browse") then
		LootLink_OpenBrowser(msg:match("^browse%s+(.+)$") or "")
	elseif msg == "help" then
		print("|cff66ccffLootLink|r commands:")
		print("  |cffffd100/loot|r — loot table for your current target (Wowhead %, via LootCodex data)")
		print("  |cffffd100/loot browse [text]|r — search items by name and see who drops them")
		print("  |cffffd100/loot auto|r — toggle auto-showing on target")
		print("  |cffffd100/loot config|r — open settings & keybinds")
		print("  Ctrl+C shows the Wowhead link; press again to copy & close.")
		print("  Shift-click an item to link it in chat; hover for its tooltip.")
	else
		LinkUnit("target")
	end
end

-- /fullloot kept as an alias for muscle memory (single mode now).
SLASH_LOOTLINKFULL1 = "/fullloot"
SlashCmdList.LOOTLINKFULL = function() LinkUnit("target") end

-- Binding entry points (invoked from Bindings.xml) + Key Bindings UI labels.
BINDING_HEADER_LOOTLINK = "LootLink"
BINDING_NAME_LOOTLINK_FULLLOOKUP = "Show loot for target"
BINDING_NAME_LOOTLINK_LOOKUP = "Open item browser"
function LootLink_DoBinding()
	LinkUnit("target")
end
