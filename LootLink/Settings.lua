local ADDON = ...

local panel = CreateFrame("Frame")
panel.name = "LootLink"
local category -- new Settings API category, when available

local function db()
	LootLinkDB = LootLinkDB or {}
	return LootLinkDB
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

	btn:SetScript("OnShow", refresh)
	btn:SetScript("OnHide", function(self)
		self.listening = false; self:EnableKeyboard(false)
	end)
	btn:SetScript("OnClick", function(self)
		self.listening = true
		self:SetText("Press a key… (Esc cancels)")
		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
	end)
	btn:SetScript("OnKeyDown", function(self, key)
		if not self.listening then self:SetPropagateKeyboardInput(true); return end
		if key == "ESCAPE" then
			self.listening = false; self:EnableKeyboard(false); refresh(); return
		end
		-- Wait for a real key, ignore lone modifiers.
		if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
			or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
			return
		end
		local combo = ""
		if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
		if IsControlKeyDown() then combo = combo .. "CTRL-" end
		if IsAltKeyDown() then combo = combo .. "ALT-" end
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
title:SetText("LootLink")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
sub:SetText("Loot tables for your target.  /loot = notable drops,  /fullloot = complete table.")

AddCheck("Auto-show the loot window when you target an enemy",
	function() return db().auto end,
	function(v) db().auto = v end,
	18, -58)

AddCheck("Hide common (grey/white) loot by default",
	function() return db().hideJunk end,
	function(v) db().hideJunk = v; if LootLink_Render then LootLink_Render() end end,
	18, -88)

AddCheck("Show generic world-drop pool in /fullloot",
	function() return db().showWorldDrops end,
	function(v) db().showWorldDrops = v; if LootLink_Render then LootLink_Render() end end,
	18, -118)

local kb = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
kb:SetPoint("TOPLEFT", 16, -156)
kb:SetText("Keybinds")

AddBindRow("LOOTLINK_LOOKUP", "Notable loot for target", 18, -180)
AddBindRow("LOOTLINK_FULLLOOKUP", "Full loot for target", 215, -180)

local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
note:SetPoint("TOPLEFT", 18, -234)
note:SetText("These also appear under Esc \226\134\146 Key Bindings \226\134\146 LootLink.")

----------------------------------------------------------------------
-- Register + open helper (supports both the new and legacy options APIs)
----------------------------------------------------------------------
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, "LootLink")
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end

function LootLink_OpenSettings()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel) -- called twice to work around
		InterfaceOptionsFrame_OpenToCategory(panel) -- a long-standing classic bug
	end
end
