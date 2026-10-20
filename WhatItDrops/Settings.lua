local ADDON = ...

local panel = CreateFrame("Frame")
panel.name = "WhatItDrops"
local category -- new Settings API category, when available

local function db()
	WhatItDropsDB = WhatItDropsDB or {}
	return WhatItDropsDB
end

----------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------
local function AddCheck(label, get, set, x, y, parent)
	parent = parent or panel
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	fs:SetText(label)
	cb:SetScript("OnShow", function(self) self:SetChecked(get() and true or false) end)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	return cb
end

-- A click-then-press-a-key capture row that binds directly to a Bindings.xml action.
local function AddBindRow(bindingName, label, x, y)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", x, y)
	title:SetText(label)

	local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btn:SetSize(175, 24)
	btn:SetPoint("TOPLEFT", x, y - 16)

	local function refresh()
		if btn.listening then return end
		local k = GetBindingKey(bindingName)
		btn:SetText(k and ("|cff00ff00" .. k .. "|r") or "Click to set key")
	end

	local function clear()
		local o1, o2 = GetBindingKey(bindingName)
		if o1 then SetBinding(o1) end
		if o2 then SetBinding(o2) end
		WhatItDrops_SaveBindings()
		btn.listening = false; btn:EnableKeyboard(false)
		refresh()
	end

	btn:SetScript("OnShow", refresh)
	btn:SetScript("OnHide", function(self)
		self.listening = false; self:EnableKeyboard(false)
	end)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Left-click: set key\nRight-click: clear", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	btn:SetScript("OnClick", function(self, button)
		if button == "RightButton" then clear(); return end
		-- SetPropagateKeyboardInput is protected and blocked in combat lockdown;
		-- don't start key capture there (it would throw ADDON_ACTION_BLOCKED).
		if InCombatLockdown() then return end
		self.listening = true
		self:SetText("Press a key… (Esc cancels)")
		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
	end)
	btn:SetScript("OnKeyDown", function(self, key)
		if not self.listening then
			if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
			return
		end
		if key == "ESCAPE" then
			self.listening = false; self:EnableKeyboard(false); refresh(); return
		end
		-- Wait for a real key, ignore lone modifiers.
		if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
			or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
			return
		end
		-- WoW's canonical modifier order is ALT-CTRL-SHIFT; wrong order silently
		-- fails to register for multi-modifier combos.
		local combo = ""
		if IsAltKeyDown() then combo = combo .. "ALT-" end
		if IsControlKeyDown() then combo = combo .. "CTRL-" end
		if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
		combo = combo .. key
		-- Replace any existing keys bound to this action, then bind the new one.
		local o1, o2 = GetBindingKey(bindingName)
		if o1 then SetBinding(o1) end
		if o2 then SetBinding(o2) end
		if SetBinding(combo, bindingName) then
			WhatItDrops_SaveBindings()
		end
		self.listening = false
		self:EnableKeyboard(false)
		refresh()
	end)
	return btn
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("WhatItDrops")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
sub:SetText("Loot tables for your target.  /loot, /loot browse, /loot config.")

AddCheck("Auto-show the loot window when you target an enemy",
	function() return db().auto end,
	function(v) db().auto = v end,
	18, -58)

AddCheck("Hide common (grey/white) loot by default",
	function() return db().hideJunk end,
	function(v) db().hideJunk = v; if WhatItDrops_Refresh then WhatItDrops_Refresh() end end,
	18, -88)

AddCheck("Show generic world-drop / common loot",
	function() return db().showWorldDrops end,
	function(v) db().showWorldDrops = v; if WhatItDrops_Refresh then WhatItDrops_Refresh() end end,
	18, -118)

AddCheck("Reset the search box each time the browser opens",
	function() return db().clearSearchOnOpen end,
	function(v) db().clearSearchOnOpen = v end,
	18, -148)

AddCheck("Use mouseover unit (takes priority over your target)",
	function() return db().useMouseover end,
	function(v) db().useMouseover = v end,
	18, -178)

local lookHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
lookHint:SetPoint("TOPLEFT", 22, -214)
lookHint:SetText("Theme, colours and effects are on the |cffffd100Appearance|r page (left list, under WhatItDrops)"
	.. (WhatItDrops_Skin and WhatItDrops_Skin.HasElv() and "  |cff888888(ElvUI detected)|r" or "") .. ".")

AddCheck("Show the minimap button  (left-click: reload UI, right-click: loot lookup)",
	function() return not (db().minimap and db().minimap.hide) end,
	function(v)
		local m = db(); m.minimap = m.minimap or {}; m.minimap.hide = not v
		if WhatItDrops_UpdateMinimapButton then WhatItDrops_UpdateMinimapButton() end
	end,
	18, -238)

local kb = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
kb:SetPoint("TOPLEFT", 16, -278)
kb:SetText("Keybinds")

AddBindRow("WHATITDROPS_FULLLOOKUP", "Loot for target", 18, -302)
AddBindRow("WHATITDROPS_LOOKUP", "Item browser", 215, -302)

local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
note:SetPoint("TOPLEFT", 18, -356)
note:SetText("Bind: left-click a slot then press a key. Right-click a slot to clear.")
local note2 = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
note2:SetPoint("TOPLEFT", 18, -370)
note2:SetText("These also appear under Esc > Key Bindings > WhatItDrops.")

----------------------------------------------------------------------
-- Appearance page: theme, accent, opacity, scale, row height, effects
----------------------------------------------------------------------
local ap = CreateFrame("Frame")
ap.name = "Appearance"
ap.parent = "WhatItDrops"          -- nests it under the main page on the legacy options API

local FLATTEX = "Interface\\Buttons\\WHITE8X8"
local function applyLook()
	if WhatItDrops_ApplyAppearance then WhatItDrops_ApplyAppearance() end
end
local function apHeader(text, x, y)
	local fs = ap:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local apTitle = ap:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
apTitle:SetPoint("TOPLEFT", 16, -16)
apTitle:SetText("WhatItDrops: Appearance")
local apSub = ap:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
apSub:SetPoint("TOPLEFT", apTitle, "BOTTOMLEFT", 0, -4)
apSub:SetText("Changes apply to any open WhatItDrops window straight away.")

-- A small flat colour button; `selected` decides its border.
local function Swatch(w, h, r, g, b)
	local s = CreateFrame("Button", nil, ap, "BackdropTemplate")
	s:SetSize(w, h)
	s:SetBackdrop({ bgFile = FLATTEX, edgeFile = FLATTEX, edgeSize = 2 })
	s:SetBackdropColor(r, g, b, 1)
	s:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
	return s
end

-- Theme
apHeader("Theme", 16, -62)
local THEMES = {
	{ "blizzard",  "Blizzard",  0.10, 0.09, 0.07 },
	{ "elvui",     "ElvUI",     0.11, 0.11, 0.11 },
	{ "slate",     "Slate",     0.11, 0.14, 0.20 },
	{ "parchment", "Parchment", 0.17, 0.14, 0.09 },
}
local themeBtns = {}
local reloadNote = ap:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
reloadNote:SetPoint("TOPLEFT", 18, -142)
reloadNote:SetText("Switching to or from ElvUI needs a /reload; the other themes change instantly.")
reloadNote:Hide()

local function refreshThemes()
	local cur = db().theme or "blizzard"
	for _, b in ipairs(themeBtns) do
		if b.key == cur then b:SetBackdropBorderColor(1, 0.82, 0, 1) else b:SetBackdropBorderColor(0.25, 0.25, 0.28, 1) end
	end
end
for i, t in ipairs(THEMES) do
	local b = Swatch(96, 54, t[3], t[4], t[5])
	b:SetPoint("TOPLEFT", 18 + (i - 1) * 104, -82)
	local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lbl:SetPoint("BOTTOMLEFT", 6, 5)
	lbl:SetText(t[2])
	b.key = t[1]
	b:SetScript("OnClick", function(self)
		local old = db().theme or "blizzard"
		db().theme = self.key
		refreshThemes()
		applyLook()
		reloadNote:SetShown((old == "elvui") ~= (self.key == "elvui"))
	end)
	themeBtns[i] = b
end

-- Accent
apHeader("Accent colour", 16, -166)
local ACCENT_ORDER = { "gold", "blue", "green", "red", "violet" }
local accentBtns = {}
local function refreshAccents()
	local cur = db().accent or "gold"
	for _, b in ipairs(accentBtns) do
		if b.key == cur then b:SetBackdropBorderColor(1, 1, 1, 1) else b:SetBackdropBorderColor(0.25, 0.25, 0.28, 1) end
	end
end
for i, key in ipairs(ACCENT_ORDER) do
	local c = (WhatItDrops_Accents and WhatItDrops_Accents[key]) or { 1, 0.82, 0 }
	local b = Swatch(26, 26, c[1], c[2], c[3])
	b:SetPoint("TOPLEFT", 18 + (i - 1) * 34, -186)
	b.key = key
	b:SetScript("OnClick", function(self)
		db().accent = self.key
		refreshAccents()
		applyLook()
	end)
	accentBtns[i] = b
end

-- A horizontal slider built from plain textures (no dependence on a template the
-- client may have renamed). `live` applies while dragging; otherwise on release.
local function AddSlider(label, lo, hi, get, set, y, live)
	local t = ap:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	t:SetPoint("TOPLEFT", 18, y)
	t:SetText(label)
	local s = CreateFrame("Slider", nil, ap)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(220, 18)
	s:SetPoint("TOPLEFT", 150, y + 3)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0.25, 0.25, 0.28, 1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local val = ap:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	val:SetPoint("LEFT", s, "RIGHT", 10, 0)
	s.ready = false
	s:SetScript("OnShow", function(self)
		self.ready = false
		self:SetValue(get())
		val:SetText(math.floor(get() + 0.5) .. "%")
		self.ready = true
	end)
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v + 0.5)
		val:SetText(v .. "%")
		if not self.ready then return end
		set(v)
		if live then applyLook() end
	end)
	if not live then s:SetScript("OnMouseUp", applyLook) end
	return s
end

AddSlider("Window opacity", 40, 100,
	function() return (db().opacity or 1) * 100 end,
	function(v) db().opacity = v / 100 end,
	-228, true)
AddSlider("Window scale", 70, 140,
	function() return (db().uiScale or 1) * 100 end,
	function(v) db().uiScale = v / 100 end,
	-258, false)

-- Row height
local rowLabel = ap:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
rowLabel:SetPoint("TOPLEFT", 18, -294)
rowLabel:SetText("Row height")
local ROWSIZES = { { "compact", "Compact" }, { "normal", "Normal" }, { "roomy", "Roomy" } }
local rowBtns = {}
local function refreshRows()
	local cur = db().rowSize or "normal"
	for _, b in ipairs(rowBtns) do
		if b.key == cur then b:LockHighlight() else b:UnlockHighlight() end
	end
end
for i, rs in ipairs(ROWSIZES) do
	local b = CreateFrame("Button", nil, ap, "UIPanelButtonTemplate")
	b:SetSize(76, 22)
	b:SetPoint("TOPLEFT", 150 + (i - 1) * 82, -290)
	b:SetText(rs[2])
	b.key = rs[1]
	b:SetScript("OnClick", function(self)
		db().rowSize = self.key
		refreshRows()
		applyLook()
	end)
	rowBtns[i] = b
end

-- Effects
apHeader("Loot window effects", 16, -330)
AddCheck("Drop-rate bars behind each row",
	function() return db().fxBars ~= false end,
	function(v) db().fxBars = v; applyLook() end, 18, -352, ap)
AddCheck("Quality-coloured icon borders",
	function() return db().fxBorders ~= false end,
	function(v) db().fxBorders = v; applyLook() end, 18, -380, ap)
AddCheck("Sparkle on rare or better drops under 2%",
	function() return db().fxSparkle ~= false end,
	function(v) db().fxSparkle = v; applyLook() end, 18, -408, ap)
AddCheck("Rows fade in when a list opens",
	function() return db().fxFade ~= false end,
	function(v) db().fxFade = v end, 18, -436, ap)
AddCheck("3D model of the target beside the window",
	function() return db().fxModel == true end,
	function(v) db().fxModel = v; applyLook() end, 18, -464, ap)

ap:SetScript("OnShow", function()
	refreshThemes(); refreshAccents(); refreshRows()
	reloadNote:Hide()
end)

----------------------------------------------------------------------
-- Register + open helper (supports both the new and legacy options APIs)
----------------------------------------------------------------------
local subCategory
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, "WhatItDrops")
	Settings.RegisterAddOnCategory(category)
	if Settings.RegisterCanvasLayoutSubcategory then
		subCategory = Settings.RegisterCanvasLayoutSubcategory(category, ap, "Appearance")
	end
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
	InterfaceOptions_AddCategory(ap)
end

-- `which` = "appearance" opens the Appearance page; anything else opens the main one.
function WhatItDrops_OpenSettings(which)
	local target = (which == "appearance" and subCategory) or category
	if target and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(target:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		local p = (which == "appearance") and ap or panel
		InterfaceOptionsFrame_OpenToCategory(p) -- called twice to work around
		InterfaceOptionsFrame_OpenToCategory(p) -- a long-standing classic bug
	end
end
