local ADDON = ...

-- The entry in the game's own AddOns settings: a button that opens the WhatItDrops window
-- (Options.lua). The window is where every setting lives.
local stub = CreateFrame("Frame")
stub.name = "WhatItDrops"

local stubText = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
stubText:SetPoint("TOPLEFT", 16, -16)
stubText:SetText("WhatItDrops has its own settings window.  /wid opens it too.")

local stubButton = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
stubButton:SetSize(200, 24)
stubButton:SetPoint("TOPLEFT", 16, -46)
stubButton:SetText("Open WhatItDrops settings")
stubButton:SetScript("OnClick", function()
	-- Close the game's settings first, or our window opens behind it.
	if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then
		pcall(HideUIPanel, SettingsPanel)
	end
	if WhatItDrops_ShowOptionsPage then WhatItDrops_ShowOptionsPage() end
end)
stub.OnRefresh = function() end
stub.OnCommit  = function() end
stub.OnDefault = function() end

if Settings and Settings.RegisterCanvasLayoutCategory then
	-- Deliberately NOT overwriting category.ID with the addon name: on 12.x
	-- Settings.OpenToCategory wants a numeric id and throws on a string.
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(stub, stub.name))
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(stub)
end

-- Used by /loot config, /wid and the gear icons. With a page key ("general", "appearance",
-- "keybinds") it opens the window on that page; with none it toggles the window.
function WhatItDrops_OpenSettings(which)
	if which then
		if WhatItDrops_ShowOptionsPage then WhatItDrops_ShowOptionsPage(which) end
	elseif WhatItDrops_ToggleOptions then
		WhatItDrops_ToggleOptions()
	end
end
