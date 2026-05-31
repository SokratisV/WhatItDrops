-- LootLink theming layer.
-- Two themes:
--   "blizzard" — the classic gold-bordered dialog look (default, unchanged).
--   "elvui"    — a flat dark skin. If ElvUI is installed it uses ElvUI's real
--                skinning API for a perfect match; otherwise a native flat look.
-- Every skin op is pcall-guarded: a theming failure leaves the widget as-is and
-- never breaks the addon.

local Skin = {}
LootLink_Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Theme()
	return (LootLinkDB and LootLinkDB.theme) or "blizzard"
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

-- A BackdropTemplate frame (our two main windows).
function Skin.Frame(f)
	local t = Theme()
	if t == "elvui" then
		local _, S = Elv()
		if S and f.SetTemplate then
			if guard(function() if f.StripTextures then f:StripTextures() end; f:SetTemplate("Transparent") end) then return end
		end
		-- native flat fallback
		guard(function()
			f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
			f:SetBackdropColor(0.06, 0.06, 0.07, 0.94)
			f:SetBackdropBorderColor(0, 0, 0, 1)
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
	local _, S = Elv()
	local bar = scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"]
	if S and S.HandleScrollBar and bar then guard(function() S:HandleScrollBar(bar) end) end
end
