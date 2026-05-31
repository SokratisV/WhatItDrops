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
	title:SetPoint("TOPRIGHT", -30, -12)
	title:SetJustifyH("LEFT")
	f.title = title

	local source = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	source:SetPoint("TOPLEFT", 14, -26)
	source:SetText("Drop data: Wowhead via Questie")
	f.source = source

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

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
		LootLink_Render()
	end)
	f.check = check

	local worldCheck = CreateFrame("CheckButton", "LootLinkWorldDrops", f, "UICheckButtonTemplate")
	worldCheck:SetSize(22, 22)
	worldCheck:SetPoint("BOTTOMLEFT", 10, 30)
	local worldLabel = worldCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	worldLabel:SetPoint("LEFT", worldCheck, "RIGHT", 2, 0)
	worldLabel:SetText("Show world drops |cff888888(full)|r")
	worldCheck:SetScript("OnClick", function(self)
		LootLinkDB.showWorldDrops = self:GetChecked() and true or false
		LootLink_Render()
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
	win.empty:Hide(); win.scroll:Show(); win.check:Show()
	win.worldCheck:SetShown(current.full and true or false)

	local function pctStr(p) return (p >= 1 and "%.1f%%" or "%.2f%%"):format(p) end
	local shown, waiting = 0, false
	for _, entry in ipairs(items) do
		local itemID, rate = entry.id, entry.pct
		local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
		if not name then waiting = true end
		-- Only filter once we actually know the quality.
		local hidden = hideJunk and quality and quality < 2
		if not hidden then
			shown = shown + 1
			local r = GetRow(shown)
			r:SetPoint("TOPLEFT", 0, -(shown - 1) * ROW_H)
			r.itemID, r.link = itemID, link
			r.icon:SetTexture(icon or GetItemIcon(itemID) or FALLBACK_ICON)
			local color = quality and QUALITY_COLORS[quality]
			local label = name or ("item:" .. itemID .. " (loading)")
			r.name:SetText(color and (color.hex .. label .. "|r") or ("|cffffffff" .. label .. "|r"))
			local txt = pctStr(rate)
			if current.full and entry.wh then
				txt = txt .. "  |cff66ccff(WH " .. pctStr(entry.wh) .. ")|r"
			end
			r.rate:SetText(txt)
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

-- Build a normalized item list: { {id=, pct=, wh=}, ... }.
--  * notable mode -> Wowhead data only (pct == Wowhead %).
--  * full mode    -> flat CMaNGOS data { specificCount, id,pct, ... }; world-drop
--    pool items (after the first specificCount pairs) are shown only when toggled.
local function BuildList(npcID, full)
	local W = LootLinkWowhead and LootLinkWowhead[npcID]
	local list = {}
	if full then
		local arr = LootLinkFull and LootLinkFull[npcID]
		if arr then
			local total = (#arr - 1) / 2
			local maxPairs = (LootLinkDB and LootLinkDB.showWorldDrops) and total or arr[1]
			for k = 0, maxPairs - 1 do
				local id = arr[2 + 2 * k]
				list[#list + 1] = { id = id, pct = arr[3 + 2 * k], wh = W and W[id] }
			end
		end
	elseif W then
		for id, pct in pairs(W) do
			list[#list + 1] = { id = id, pct = pct }
		end
		table.sort(list, function(a, b) return a.pct > b.pct end)
	end
	return (#list > 0) and list or nil
end

local function ShowNPC(npcID, npcName, full)
	local f = GetWindow()
	current.id, current.name, current.full = npcID, npcName, full
	current.items = BuildList(npcID, full)
	if full then
		f.source:SetText("Full loot: CMaNGOS-TBC %   |cff66ccff(WH)|r = Wowhead %")
	else
		f.source:SetText("Notable drops: Wowhead % (via Questie)")
	end
	f.title:SetText((npcName or "NPC") .. "  |cff888888(" .. npcID .. ")|r")
	f.check:SetChecked(LootLinkDB and LootLinkDB.hideJunk or false)
	f.worldCheck:SetChecked(LootLinkDB and LootLinkDB.showWorldDrops or false)
	f.url:SetText(BuildURL(npcID))
	f.url:Hide()
	f:Show()
	LootLink_Render()
end

----------------------------------------------------------------------
-- Core action
----------------------------------------------------------------------
local function LinkUnit(unit, full)
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
	if full then EnsureFull(npcID) end
	ShowNPC(npcID, UnitName(unit), full)
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
		if LootLinkDB.showWorldDrops == nil then LootLinkDB.showWorldDrops = false end
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
			if npcID then ShowNPC(npcID, UnitName("target")) end
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
	elseif msg == "help" then
		print("|cff66ccffLootLink|r commands:")
		print("  |cffffd100/loot|r — notable/quest-relevant drops for your target (Questie data)")
		print("  |cffffd100/fullloot|r — complete loot table for your target (CMaNGOS data)")
		print("  |cffffd100/loot auto|r — toggle auto-showing on target")
		print("  |cffffd100/loot config|r — open settings & keybinds")
		print("  Ctrl+C shows the Wowhead link; press again to copy & close.")
		print("  Shift-click an item to link it in chat; hover for its tooltip.")
	else
		LinkUnit("target")
	end
end

-- Complete loot table (loads the heavy CMaNGOS dataset on demand).
SLASH_LOOTLINKFULL1 = "/fullloot"
SlashCmdList.LOOTLINKFULL = function()
	LinkUnit("target", true)
end

-- Binding entry point (invoked from Bindings.xml) + Key Bindings UI labels.
BINDING_HEADER_LOOTLINK = "LootLink"
BINDING_NAME_LOOTLINK_LOOKUP = "Notable loot for target"
BINDING_NAME_LOOTLINK_FULLLOOKUP = "Full loot for target"
function LootLink_DoBinding(mode)
	LinkUnit("target", mode == "full")
end
