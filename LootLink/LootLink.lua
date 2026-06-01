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

local function BuildItemURL(itemID)
	local branch = WOWHEAD_BRANCH ~= "" and (WOWHEAD_BRANCH .. "/") or ""
	return ("https://www.wowhead.com/%sitem=%d"):format(branch, itemID)
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

-- Persist/restore window positions (absolute, UIParent-relative — survives drags
-- against any anchor and across sessions via SavedVariables).
local function SavePos(frame, key)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	if not left then return end
	LootLinkDB = LootLinkDB or {}
	LootLinkDB.pos = LootLinkDB.pos or {}
	LootLinkDB.pos[key] = { left, bottom }
end
local function RestorePos(frame, key)
	local s = LootLinkDB and LootLinkDB.pos and LootLinkDB.pos[key]
	if not s then return false end
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s[1], s[2])
	return true
end

-- A small 16px icon button anchored to a frame's top-right (left of the close X).
local function HeaderIcon(parent, texture, tip, onClick, x)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(16, 16)
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, -9)
	b:SetNormalTexture(texture)
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show() end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function GetWindow()
	if win then return win end

	local f = CreateFrame("Frame", "LootLinkFrame", UIParent, "BackdropTemplate")
	f:SetSize(340, 200)
	if not RestorePos(f, "loot") then f:SetPoint("CENTER") end
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos(self, "loot") end)
	f:SetScript("OnHide", function(self) SavePos(self, "loot") end)
	f:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "LootLinkFrame") -- closes on Escape
	LootLink_Skin.Frame(f)

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
	LootLink_Skin.Close(close)

	-- Header icon buttons (Settings, Item browser), to the left of the close X.
	HeaderIcon(f, "Interface\\Buttons\\UI-OptionsButton", "Settings",
		function() if LootLink_OpenSettings then LootLink_OpenSettings() end end, -34)
	HeaderIcon(f, "Interface\\Common\\UI-Searchbox-Icon", "Item browser",
		function() if LootLink_OpenBrowser then LootLink_OpenBrowser() end end, -56)

	-- Scrollable item list
	local scroll = CreateFrame("ScrollFrame", "LootLinkScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -HEADER_H)
	scroll:SetPoint("TOPRIGHT", -30, -HEADER_H)
	scroll:SetHeight(MAX_VIEW)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(296, 1)
	scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content
	LootLink_Skin.Scroll(scroll)

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
	LootLink_Skin.CheckBox(check)

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
	LootLink_Skin.CheckBox(worldCheck)

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
	LootLink_Skin.Button(urlBtn)
	f.urlBtn = urlBtn

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
	LootLink_Skin.EditBox(url)

	-- Ctrl+C shortcut:
	--   1st press -> reveal & select the Wowhead URL (same as the button).
	--   2nd press -> the focused box copies it natively, then we close.
	-- The popup keeps keyboard input propagating so movement/keybinds still work;
	-- it only consumes the specific Ctrl+C that triggers the reveal.
	-- SetPropagateKeyboardInput is protected, so enabling keyboard capture is only
	-- safe out of combat. If the window is first opened during combat, defer the
	-- setup to combat-end — until then the frame stays keyboard-disabled, which lets
	-- ESC fall through to the default UI (UISpecialFrames) and still close it.
	local function EnableKeyCapture()
		if InCombatLockdown() then return false end
		f:EnableKeyboard(true)
		f:SetPropagateKeyboardInput(true)
		return true
	end
	if not EnableKeyCapture() then
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:HookScript("OnEvent", function(self, e)
			if e == "PLAYER_REGEN_ENABLED" then
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				EnableKeyCapture()
			end
		end)
	end
	f:SetScript("OnKeyDown", function(self, key)
		-- SetPropagateKeyboardInput is a protected function: calling it while in
		-- combat lockdown throws ADDON_ACTION_BLOCKED and strands keyboard input,
		-- so ESC stops reaching the default UI and the window won't close. In combat
		-- we leave propagation untouched (it defaults to true) and let keys through.
		if InCombatLockdown() then return end
		if key == "C" and IsControlKeyDown() and (not url:IsShown() or not url:HasFocus()) then
			self:SetPropagateKeyboardInput(false) -- consume this Ctrl+C
			url:Show(); url:SetFocus(); url:HighlightText()
		else
			self:SetPropagateKeyboardInput(true)  -- let every other key through
		end
	end)
	-- Whenever the URL box closes (Escape or after a copy), restore pass-through so
	-- a leftover "consume" state can never carry into combat and swallow ESC.
	url:HookScript("OnHide", function()
		if not InCombatLockdown() then f:SetPropagateKeyboardInput(true) end
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
		if not self.itemID then return end
		local link = self.link or select(2, GetItemInfo(self.itemID))
		if IsModifiedClick("DRESSUP") then
			if link then DressUpItemLink(link) end       -- Ctrl-click: dressing-room preview
		elseif IsModifiedClick("CHATLINK") then
			if link then ChatEdit_InsertLink(link) end   -- Shift-click: link in chat
		elseif LootLink_ShowItemSources then
			LootLink_ShowItemSources(self.itemID)        -- plain click: who drops this?
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

	-- The junk/world-drop toggles and the Wowhead link only make sense for an NPC
	-- loot table; hide them for player-gear and quest-item views.
	local isNpc = current.id ~= nil
	if not items then
		for _, r in ipairs(rows) do r:Hide() end
		win.scroll:Hide(); win.check:Hide(); win.worldCheck:Hide(); win.urlBtn:Hide(); win.empty:Show()
		win.content:SetHeight(1)
		win:SetHeight(HEADER_H + 30 + FOOTER_H)
		return
	end
	win.empty:Hide(); win.scroll:Show()
	win.check:SetShown(isNpc)
	win.worldCheck:SetShown(isNpc)
	win.urlBtn:SetShown(isNpc)

	local function pctStr(p) return (p >= 1 and "%.1f%%" or "%.2f%%"):format(p) end
	local shown, waiting = 0, false
	for _, entry in ipairs(items) do
		local itemID = entry.id
		-- Names/quality from baked tables, or from the entry itself (player gear).
		local name = entry.name or ItemName(itemID)
		local quality = entry.quality or ItemQuality(itemID)
		local giLink, icon
		if itemID then _, giLink, _, _, _, _, _, _, _, icon = GetItemInfo(itemID) end
		local link = entry.link or giLink
		-- Only wait on the async item cache for rows that actually have an ID to
		-- look up (quest items unresolved to an ID never resolve — don't churn).
		if itemID and not link then waiting = true end
		local hidden = isNpc and hideJunk and quality and quality < 2
		if not hidden then
			shown = shown + 1
			local r = GetRow(shown)
			r:SetPoint("TOPLEFT", 0, -(shown - 1) * ROW_H)
			r.itemID, r.link = itemID, link
			r.icon:SetTexture(icon or GetItemIcon(itemID) or FALLBACK_ICON)
			local color = quality and QUALITY_COLORS[quality]
			local lbl = name or ("item:" .. tostring(itemID))
			r.name:SetText(color and (color.hex .. lbl .. "|r") or ("|cffffffff" .. lbl .. "|r"))
			r.rate:SetText(entry.rightText or (entry.pct and pctStr(entry.pct)) or "")
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
	current.player, current.unit, current.inspectGUID = false, nil, nil
	current.items = BuildList(npcID)
	f.source:SetText("Loot: Wowhead %  (data via LootCodex)")
	f.title:SetText((npcName or "NPC") .. "  |cff888888(" .. npcID .. ")|r")
	f.empty:SetText("No bundled loot for this NPC. Use the Wowhead link below.")
	f.check:SetChecked(LootLinkDB and LootLinkDB.hideJunk or false)
	f.worldCheck:SetChecked(LootLinkDB and LootLinkDB.showWorldDrops or false)
	f.url:SetText(BuildURL(npcID))
	f.url:Hide()
	f:Show()
	LootLink_Render()
end

-- Equipped-gear slots (id, label), in a sensible visual order.
local GEAR_SLOTS = {
	{ 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
	{ 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
	{ 11, "Finger" }, { 12, "Finger" }, { 13, "Trinket" }, { 14, "Trinket" },
	{ 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}

local function CollectGear(unit)
	local list = {}
	for _, slot in ipairs(GEAR_SLOTS) do
		local link = GetInventoryItemLink(unit, slot[1])
		if link then
			local itemID = tonumber(link:match("item:(%d+)"))
			local name, _, quality = GetItemInfo(link)
			list[#list + 1] = {
				id = itemID, link = link, rightText = slot[2],
				name = name or link:match("%[(.-)%]"), quality = quality,
			}
		end
	end
	return (#list > 0) and list or nil
end

-- Open the window populated with a player's equipped gear. For other players we
-- request an inspect and refresh when the data arrives (INSPECT_READY).
local function ShowPlayer(unit)
	local f = GetWindow()
	current.id, current.name = nil, UnitName(unit)
	current.player, current.unit, current.inspectGUID = true, unit, UnitGUID(unit)
	current.items = CollectGear(unit)
	f.source:SetText("Equipped gear  |cff888888(click = source, Ctrl-click = preview)|r")
	f.title:SetText((current.name or "Player") .. "  |cff888888(gear)|r")
	f.empty:SetText("No visible gear yet — get within inspect range, then reopen.")
	f.url:Hide()
	f:Show()
	LootLink_Render()
	if not UnitIsUnit(unit, "player") and CanInspect and CanInspect(unit) and NotifyInspect then
		NotifyInspect(unit)
	end
end

----------------------------------------------------------------------
-- Quest required items
----------------------------------------------------------------------
-- The quest-log API only exposes objective *names* ("Wolf Pelt: 3/8"), not item
-- IDs, so we resolve names back to IDs through the baked item table. That lets a
-- quest item show its icon/quality and, on click, jump to "who drops this".
-- (First match wins; quest objective names are essentially always unique.)
local itemNameIndex
local function ItemIDByName(name)
	if not name or name == "" then return nil end
	if not itemNameIndex then
		itemNameIndex = {}
		if LootLinkItemName then
			for id, nm in pairs(LootLinkItemName) do
				local key = nm:lower()
				if not itemNameIndex[key] then itemNameIndex[key] = id end
			end
		end
	end
	return itemNameIndex[name:lower()]
end

-- The currently selected quest's title and header flag, via the modern API when
-- present (Classic Era exposes C_QuestLog) and the legacy call otherwise.
local function SelectedQuestInfo()
	local idx = (GetQuestLogSelection and GetQuestLogSelection()) or 0
	if not idx or idx <= 0 then return nil, nil, nil end
	if C_QuestLog and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(idx)
		if info then return idx, info.title, info.isHeader end
	end
	local title, _, _, isHeader = GetQuestLogTitle(idx)
	return idx, title, isHeader
end

-- Read the "collect N of item X" objectives off the selected quest.
local function CollectQuestItems(questIndex)
	if SelectQuestLogEntry then SelectQuestLogEntry(questIndex) end
	local n = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards()) or 0
	local list = {}
	for i = 1, n do
		local text, objType = GetQuestLogLeaderBoard(i)
		if objType == "item" and text then
			-- "Item Name: have/need" -> name, "have/need" (the colon split is locale-safe
			-- enough for enUS/anniversary; if it doesn't match we keep the whole string).
			local name, progress = text:match("^(.-):%s*(%d+%s*/%s*%d+)%s*$")
			name = name or text
			progress = progress and progress:gsub("%s+", "")
			list[#list + 1] = { id = ItemIDByName(name), name = name, rightText = progress }
		end
	end
	return (#list > 0) and list or nil
end

-- Open the loot window populated with the selected quest's required items.
function LootLink_ShowQuest()
	local f = GetWindow()
	local idx, title, isHeader = SelectedQuestInfo()
	current.id, current.name = nil, title
	current.player, current.unit, current.inspectGUID = false, nil, nil
	current.items = (idx and not isHeader) and CollectQuestItems(idx) or nil
	f.source:SetText("Items this quest needs  |cff888888(click = who drops it)|r")
	f.title:SetText((title or "Quest") .. "  |cff888888(quest)|r")
	if not idx or isHeader then
		f.empty:SetText("Select a quest in the log, then click again.")
	else
		f.empty:SetText("This quest needs no gathered items.")
	end
	f.url:Hide()
	f:Show()
	LootLink_Render()
end

-- Add a button to Blizzard's quest log that opens the required-items view for the
-- selected quest. Created once, after login, and only if the quest log exists.
local function CreateQuestLogButton()
	if not QuestLogFrame or QuestLogFrame.LootLinkButton then return end
	local b = CreateFrame("Button", "LootLinkQuestLogButton", QuestLogFrame, "UIPanelButtonTemplate")
	b:SetSize(110, 22)
	b:SetText("Loot Needed")
	-- Sit just to the right of the Abandon button when it's there; fall back to a
	-- fixed bottom-left spot so the button still appears on altered layouts.
	local anchor = _G.QuestLogFrameAbandonButton or _G.QuestFrameAbandonButton
	if anchor then
		b:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
	else
		b:SetPoint("BOTTOMLEFT", QuestLogFrame, "BOTTOMLEFT", 90, 86)
	end
	b:SetScript("OnClick", LootLink_ShowQuest)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("LootLink: show the items this quest needs\nand where they drop.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if LootLink_Skin and LootLink_Skin.Button then LootLink_Skin.Button(b) end
	QuestLogFrame.LootLinkButton = b
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
	r:SetScript("OnClick", function(self)
		if self.itemID and (IsModifiedClick("DRESSUP") or IsModifiedClick("CHATLINK")) then
			local link = select(2, GetItemInfo(self.itemID))
			if link and IsModifiedClick("DRESSUP") then DressUpItemLink(link)
			elseif link then ChatEdit_InsertLink(link) end
		elseif self.onClick then
			self.onClick()
		end
	end)
	r:SetScript("OnEnter", function(self) if self.itemID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bRows[i] = r
	return r
end

RenderBrowser = function()
	local f = bWin
	if not f or not f:IsShown() then return end
	f.back:SetShown(bState == "npcs")
	f.hint:Hide(); f.url:Hide()
	local list = {}
	if bState == "items" then
		f.title:SetText("LootLink — Browser")
		local res = bResults or {}
		f.status:SetText(#res .. " result" .. (#res == 1 and "" or "s"))
		for i = 1, math.min(#res, 300) do list[i] = res[i] end
	else
		f.title:SetText("Dropped by: " .. ItemName(bSelItem))
		local src = (reverseIndex and reverseIndex[bSelItem]) or {}
		for i = 1, #src do list[i] = src[i] end
		table.sort(list, function(a, b) return a.pct > b.pct end)
		f.status:SetText(#list .. " npc" .. (#list == 1 and "" or "s"))
		while #list > 300 do list[#list] = nil end
		-- No mob drops it in our data — point to Wowhead instead.
		if #list == 0 then
			for _, r in ipairs(bRows) do r:Hide() end
			f.hint:SetText("Not a mob drop in our data (crafted, quest, vendor, or event). Open on Wowhead — Ctrl+C to copy:")
			f.hint:Show()
			local u = BuildItemURL(bSelItem)
			f.url.expected = u; f.url:SetText(u); f.url:Show(); f.url:SetFocus(); f.url:HighlightText()
			f.content:SetHeight(1)
			return
		end
	end
	local shown = 0
	for i, e in ipairs(list) do
		shown = i
		local r = GetBRow(i)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		if bState == "items" and e.kind == "npc" then
			r.itemID = nil
			r.icon:SetTexture(FALLBACK_ICON)
			r.name:SetText("|cffffd100" .. e.name .. "|r  |cff888888(" .. e.id .. ")|r")
			r.right:SetText("|cff888888target|r")
			r.onClick = function() EnsureFull(e.id); ShowNPC(e.id, e.name) end
		elseif bState == "items" then
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
	if #q >= 2 then
		-- Targets (NPCs) first, then item drops; each sorted by name.
		local npcs, items = {}, {}
		if LootLinkNpcName then
			for id, nm in pairs(LootLinkNpcName) do
				if nm:lower():find(q, 1, true) then npcs[#npcs + 1] = { kind = "npc", id = id, name = nm } end
			end
			table.sort(npcs, function(a, b) return a.name < b.name end)
		end
		if LootLinkItemName then
			for id, nm in pairs(LootLinkItemName) do
				if nm:lower():find(q, 1, true) then items[#items + 1] = { kind = "item", id = id, name = nm } end
			end
			table.sort(items, function(a, b) return a.name < b.name end)
		end
		for i = 1, math.min(#npcs, 150) do res[#res + 1] = npcs[i] end
		for i = 1, math.min(#items, 150) do res[#res + 1] = items[i] end
	end
	bResults = res
	RenderBrowser()
end

local function GetBrowser()
	if bWin then return bWin end
	local f = CreateFrame("Frame", "LootLinkBrowserFrame", UIParent, "BackdropTemplate")
	f:SetSize(360, 440); f:SetPoint("CENTER", 90, 0); f:SetFrameStrata("DIALOG")
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos(self, "browser") end)
	f:SetScript("OnHide", function(self) SavePos(self, "browser") end)
	f:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "LootLinkBrowserFrame") -- closes on Escape
	LootLink_Skin.Frame(f)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOP", 0, -12); f.title = title
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
	LootLink_Skin.Close(close)
	HeaderIcon(f, "Interface\\Buttons\\UI-OptionsButton", "Settings",
		function() if LootLink_OpenSettings then LootLink_OpenSettings() end end, -34)

	local sb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	sb:SetSize(228, 22); sb:SetPoint("TOPLEFT", 16, -34); sb:SetAutoFocus(false); sb:SetFontObject(ChatFontNormal)
	sb:SetScript("OnEnterPressed", function(self) DoBrowserSearch(self:GetText()); self:ClearFocus() end)
	sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.search = sb
	LootLink_Skin.EditBox(sb)
	local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	go:SetSize(62, 22); go:SetPoint("LEFT", sb, "RIGHT", 6, 0); go:SetText("Search")
	go:SetScript("OnClick", function() DoBrowserSearch(sb:GetText()) end)
	LootLink_Skin.Button(go)

	local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	back:SetSize(54, 20); back:SetPoint("TOPLEFT", 14, -60); back:SetText("< Back")
	back:SetScript("OnClick", function() bState = "items"; RenderBrowser() end); back:Hide(); f.back = back
	LootLink_Skin.Button(back)
	local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); status:SetPoint("TOPRIGHT", -16, -64); f.status = status

	local scroll = CreateFrame("ScrollFrame", "LootLinkBrowserScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -84); scroll:SetPoint("BOTTOMRIGHT", -30, 14)
	local content = CreateFrame("Frame", nil, scroll); content:SetSize(318, 1); scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content
	LootLink_Skin.Scroll(scroll)

	-- Hint + copyable Wowhead link, shown when an item has no mob source in our data.
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 16, -90); hint:SetPoint("TOPRIGHT", -16, -90)
	hint:SetJustifyH("LEFT"); hint:Hide(); f.hint = hint
	local url = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	url:SetPoint("TOPLEFT", 18, -140); url:SetPoint("TOPRIGHT", -18, -140); url:SetHeight(20)
	url:SetAutoFocus(false); url:SetFontObject(ChatFontNormal)
	url:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	url:SetScript("OnTextChanged", function(self)
		if self.expected and self:GetText() ~= self.expected then self:SetText(self.expected); self:HighlightText() end
	end)
	url:Hide(); LootLink_Skin.EditBox(url); f.url = url

	bWin = f
	return f
end

function LootLink_OpenBrowser(text)
	local f = GetBrowser()
	bState, bSelItem = "items", nil
	-- Use the remembered position if the user has placed it before; otherwise
	-- dock next to the loot window (flipping left near the screen edge), or centre.
	if not RestorePos(f, "browser") then
		f:ClearAllPoints()
		if win and win:IsShown() then
			local side = (win:GetRight() or 0) + f:GetWidth() + 8 > UIParent:GetWidth() and "left" or "right"
			if side == "left" then
				f:SetPoint("TOPRIGHT", win, "TOPLEFT", -8, 0)
			else
				f:SetPoint("TOPLEFT", win, "TOPRIGHT", 8, 0)
			end
		else
			f:SetPoint("CENTER", 90, 0)
		end
	end
	f:Show()
	if text and text ~= "" then
		f.search:SetText(text); DoBrowserSearch(text)
	elseif LootLinkDB and LootLinkDB.clearSearchOnOpen then
		f.search:SetText(""); bResults = nil; RenderBrowser()   -- start fresh each open
	else
		RenderBrowser()
	end
	f.search:SetFocus()
end

-- Open the browser straight to "who drops this item" (used by clicking a row).
function LootLink_ShowItemSources(itemID)
	if not itemID then return end
	LootLink_OpenBrowser()       -- position + show the browser
	bSelItem, bState = itemID, "npcs"
	BuildReverse()
	RenderBrowser()
	if bWin then bWin.search:ClearFocus() end
end

----------------------------------------------------------------------
-- Core action
----------------------------------------------------------------------
-- The unit to look up: when the option is on, a valid mouseover creature wins
-- over the current target; otherwise just the target.
local function ResolveUnit()
	if LootLinkDB and LootLinkDB.useMouseover and UnitExists("mouseover")
		and (UnitIsPlayer("mouseover") or GetNpcID("mouseover")) then
		return "mouseover"
	end
	return "target"
end

local function LinkUnit(unit)
	unit = unit or ResolveUnit()
	if not UnitExists(unit) then return end
	if UnitIsPlayer(unit) then ShowPlayer(unit); return end  -- show their gear
	local npcID = GetNpcID(unit)
	if not npcID then return end
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
		if LootLinkDB.theme == nil then LootLinkDB.theme = "blizzard" end
		if LootLinkDB.clearSearchOnOpen == nil then LootLinkDB.clearSearchOnOpen = true end
		if LootLinkDB.useMouseover == nil then LootLinkDB.useMouseover = false end
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("PLAYER_LOGIN")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:RegisterEvent("INSPECT_READY")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		CreateQuestLogButton()
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
	elseif event == "INSPECT_READY" then
		-- Inspect data arrived: refill the gear list if it's the unit we're showing.
		if current.player and current.inspectGUID and arg1 == current.inspectGUID
			and current.unit and UnitGUID(current.unit) == current.inspectGUID
			and win and win:IsShown() then
			current.items = CollectGear(current.unit)
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
	elseif msg == "config" or msg == "options" then
		if LootLink_OpenSettings then LootLink_OpenSettings() end
	elseif msg:match("^browse") then
		LootLink_OpenBrowser(msg:match("^browse%s+(.+)$") or "")
	elseif msg == "quest" then
		LootLink_ShowQuest()
	elseif msg == "help" then
		print("|cff66ccffLootLink|r commands:")
		print("  |cffffd100/loot|r — loot table for your current target (Wowhead %, via LootCodex data)")
		print("  |cffffd100/loot browse [text]|r — search items or NPCs by name")
		print("  |cffffd100/loot quest|r — items the selected quest needs, and where they drop")
		print("  |cffffd100/loot auto|r — toggle auto-showing on target")
		print("  |cffffd100/loot config|r — open settings & keybinds")
		print("  Ctrl+C shows the Wowhead link; press again to copy & close.")
		print("  Click an item to see what drops it; Ctrl-click previews; Shift-click links it.")
	else
		LinkUnit()
	end
end

-- /fullloot kept as an alias for muscle memory (single mode now).
SLASH_LOOTLINKFULL1 = "/fullloot"
SlashCmdList.LOOTLINKFULL = function() LinkUnit() end

-- Binding entry points (invoked from Bindings.xml) + Key Bindings UI labels.
BINDING_HEADER_LOOTLINK = "LootLink"
BINDING_NAME_LOOTLINK_FULLLOOKUP = "Show loot for target"
BINDING_NAME_LOOTLINK_LOOKUP = "Open item browser"
function LootLink_DoBinding()
	-- Mouseover (if enabled) or target: a player shows gear, a creature shows
	-- loot; anything else opens the browser.
	local unit = ResolveUnit()
	if UnitExists(unit) and (UnitIsPlayer(unit) or GetNpcID(unit)) then
		LinkUnit(unit)
	else
		LootLink_OpenBrowser()
	end
end
