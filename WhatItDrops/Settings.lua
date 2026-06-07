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
local function AddCheck(label, get, set, x, y)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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
		SaveBindings(GetCurrentBindingSet())
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
			SaveBindings(GetCurrentBindingSet())
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

AddCheck("Flat / ElvUI skin" .. (WhatItDrops_Skin and WhatItDrops_Skin.HasElv() and "  (ElvUI detected)" or "") .. "  — requires /reload",
	function() return db().theme == "elvui" end,
	function(v) db().theme = v and "elvui" or "blizzard" end,
	18, -208)

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
-- Register + open helper (supports both the new and legacy options APIs)
----------------------------------------------------------------------
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, "WhatItDrops")
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end

function WhatItDrops_OpenSettings()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel) -- called twice to work around
		InterfaceOptionsFrame_OpenToCategory(panel) -- a long-standing classic bug
	end
end
