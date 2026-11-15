-- WhatItDrops theming layer.
-- Themes:
--   "flare"    — the default: a dark window with bronze trim over Blizzard's Collections
--                tile, in the style of FlareUI (Blizzard textures only, none of its art).
--   "blizzard" — the classic gold-bordered dialog look.
--   "elvui"    — a flat dark skin. If ElvUI is installed it uses ElvUI's real
--                skinning API for a perfect match; otherwise a native flat look.
--   "slate", "parchment" — flat coloured frames.
-- Every skin op is pcall-guarded: a theming failure leaves the widget as-is and
-- never breaks the addon.

local Skin = {}
WhatItDrops_Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Theme()
	return (WhatItDropsDB and WhatItDropsDB.theme) or "flare"
end
Skin.GetTheme = Theme

-- Resolve ElvUI's engine + Skins module once (nil if not present/loaded).
local elvE, elvS, elvTried
local function Elv()
	if elvTried then return elvE, elvS end
	elvTried = true
	if _G.ElvUI then
		pcall(function() elvE = unpack(_G.ElvUI) end)
		if elvE then pcall(function() elvS = elvE:GetModule("Skins") end) end
	end
	return elvE, elvS
end
Skin.HasElv = function() local e = Elv(); return e ~= nil end

local function guard(fn) local ok = pcall(fn); return ok end

-- Window opacity (Settings > Appearance), applied to the background fill only.
local function Alpha(base)
	return base * ((WhatItDropsDB and WhatItDropsDB.opacity) or 1)
end

-- Flat themes that only restyle the window frame. Unlike "elvui" they leave every
-- inner widget alone, so switching between them (and Blizzard) needs no /reload.
local FLAT = {
	slate     = { bg = { 0.11, 0.14, 0.20 }, edge = { 0.30, 0.38, 0.52 } },
	parchment = { bg = { 0.17, 0.14, 0.09 }, edge = { 0.55, 0.45, 0.25 } },
}

-- Native flat backdrop helper for widgets that aren't BackdropTemplate frames.
local function flatBackdrop(w, r, g, b, a)
	local bg = w.__llbg
	if not bg then
		-- Sibling (not child) at a lower frame level, so it sits BEHIND the
		-- widget's own text/icon instead of covering them.
		bg = CreateFrame("Frame", nil, w:GetParent() or w, "BackdropTemplate")
		bg:SetPoint("TOPLEFT", w, "TOPLEFT", -1, 1)
		bg:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 1, -1)
		bg:SetFrameLevel(math.max(0, w:GetFrameLevel() - 1))
		w.__llbg = bg
		-- Because bg is a sibling, it doesn't inherit the widget's Show/Hide. Mirror
		-- it explicitly, or a widget that's hidden by default (the Back button, the
		-- URL box before first use) leaves an empty backdrop floating in the window.
		bg:SetShown(w:IsShown())
		w:HookScript("OnShow", function() bg:Show() end)
		w:HookScript("OnHide", function() bg:Hide() end)
	end
	bg:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	bg:SetBackdropColor(r, g, b, a)
	bg:SetBackdropBorderColor(0, 0, 0, 1)
	return bg
end

local function stripTextures(w)
	for _, region in ipairs({ w:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" then
			region:SetTexture(nil)
		end
	end
end

----------------------------------------------------------------------
-- Public skinning entry points
----------------------------------------------------------------------

-- FlareUI's frame: a bronze tooltip-style border over a dark base, Blizzard's Collections
-- tile and a black wash. The three layers are made once per frame and hidden under any
-- other theme.
local FLARE_BORDER = { 0.80, 0.60, 0.34 }
local function flareLayers(f)
	local l = f.__flare
	if not l then
		l = {}
		l.base = f:CreateTexture(nil, "BACKGROUND", nil, 0)
		l.base:SetPoint("TOPLEFT", 5, -5); l.base:SetPoint("BOTTOMRIGHT", -5, 5)
		l.art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
		l.art:SetAllPoints(l.base)
		l.art:SetTexture("Interface\\Collections\\CollectionsBackgroundTile", "REPEAT", "REPEAT")
		l.art:SetHorizTile(true); l.art:SetVertTile(true)
		l.wash = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		l.wash:SetAllPoints(l.base)
		f.__flare = l
	end
	return l
end

function Skin.Frame(f)
	local t = Theme()
	if f.__flare and t ~= "flare" then
		f.__flare.base:Hide(); f.__flare.art:Hide(); f.__flare.wash:Hide()
	end
	if t == "flare" then
		guard(function()
			local l = flareLayers(f)
			f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
			f:SetBackdropBorderColor(FLARE_BORDER[1], FLARE_BORDER[2], FLARE_BORDER[3], 1)
			l.base:SetColorTexture(0.06, 0.055, 0.045, Alpha(0.97))
			l.art:SetAlpha(Alpha(1))
			l.wash:SetColorTexture(0, 0, 0, Alpha(0.5))
			l.base:Show(); l.art:Show(); l.wash:Show()
		end)
		return
	end
	if t == "elvui" then
		local _, S = Elv()
		if S and f.SetTemplate then
			if guard(function() if f.StripTextures then f:StripTextures() end; f:SetTemplate("Transparent") end) then return end
		end
		-- native flat fallback
		guard(function()
			f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
			f:SetBackdropColor(0.06, 0.06, 0.07, Alpha(0.94))
			f:SetBackdropBorderColor(0, 0, 0, 1)
		end)
		return
	end
	local flat = FLAT[t]
	if flat then
		guard(function()
			f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
			f:SetBackdropColor(flat.bg[1], flat.bg[2], flat.bg[3], Alpha(0.96))
			f:SetBackdropBorderColor(flat.edge[1], flat.edge[2], flat.edge[3], 1)
		end)
		return
	end
	-- blizzard
	guard(function()
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
		f:SetBackdropColor(1, 1, 1, Alpha(1))
		f:SetBackdropBorderColor(1, 1, 1, 1)
	end)
end

function Skin.Button(b)
	if Theme() ~= "elvui" then return end
	local _, S = Elv()
	if S and S.HandleButton then
		if guard(function() S:HandleButton(b) end) then return end
	end
	guard(function()
		stripTextures(b)
		flatBackdrop(b, 0.18, 0.18, 0.2, 1)
		local hl = b:GetHighlightTexture()
		if hl then hl:SetTexture(WHITE); hl:SetVertexColor(1, 1, 1, 0.15) end
	end)
end

function Skin.EditBox(e)
	if Theme() ~= "elvui" then return end
	local _, S = Elv()
	if S and S.HandleEditBox then
		if guard(function() S:HandleEditBox(e) end) then return end
	end
	guard(function()
		stripTextures(e)
		flatBackdrop(e, 0.04, 0.04, 0.05, 1)
	end)
end

function Skin.CheckBox(c)
	if Theme() ~= "elvui" then return end
	local _, S = Elv()
	if S and S.HandleCheckBox then guard(function() S:HandleCheckBox(c) end) end
	-- native: leave the default check art (small + harmless on dark backgrounds)
end

function Skin.Close(btn)
	if Theme() ~= "elvui" then return end
	local _, S = Elv()
	if S and S.HandleCloseButton then guard(function() S:HandleCloseButton(btn) end) end
	-- native: the red X reads fine on a dark frame, leave it
end

-- scroll is a UIPanelScrollFrameTemplate; its bar is $parentScrollBar.
function Skin.Scroll(scroll)
	if Theme() ~= "elvui" then return end
	local name = scroll:GetName()
	local bar = name and _G[name .. "ScrollBar"]
	if not bar then return end
	local _, S = Elv()
	if S and S.HandleScrollBar then
		if guard(function() S:HandleScrollBar(bar) end) then return end
	end
	-- Native flat fallback: the default scrollbar is stone-textured Blizzard art that
	-- reads as "leftover" widgets against our flat skin. Strip the arrow buttons + the
	-- bar's own textures and give the thumb a plain flat fill. Drag and mouse-wheel
	-- still work; the arrows just become invisible (and clickable) hit areas.
	guard(function()
		local function hideTex(t) if t then t:SetTexture(nil) end end
		for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
			local b = _G[name .. "ScrollBar" .. suffix]
			if b then
				hideTex(b:GetNormalTexture()); hideTex(b:GetPushedTexture())
				hideTex(b:GetDisabledTexture()); hideTex(b:GetHighlightTexture())
			end
		end
		stripTextures(bar)
		local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
		if thumb then thumb:SetTexture(WHITE); thumb:SetVertexColor(0.28, 0.28, 0.32, 1) end
	end)
end
