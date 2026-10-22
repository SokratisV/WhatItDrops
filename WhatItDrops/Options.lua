local ADDON = ...

-- The settings window (/wid, or the gear in either WhatItDrops window), in the visual language
-- of FlareUI by Malkkav (MIT): bronze trim over Blizzard's Collections tile, the pages in a list
-- on the left, the page's settings in the middle under headings that fold, and on the right what
-- the hovered setting does. Blizzard's own controls and textures throughout; none of FlareUI's art.
-- Adapted from the same window in Unbuffed and GaruCombatText.
--
-- Pages are plain data (definePages, below): each row says what it is, what it does, how to read
-- and write its value, and when it applies. The window is drawn from that data and drawn again
-- after every change. Sliders are the exception: redrawing mid-drag would drop the drag.

local WIDTH, HEIGHT = 780, 540
local HEADER_H = 34
local LEFT_W, RIGHT_W = 130, 210
local PAD = 12
local ROW_H, SECTION_H = 26, 28
local CONTENT_W = WIDTH - 12 - LEFT_W - RIGHT_W - 2 * PAD - 14
local ICON = "Interface\\AddOns\\WhatItDrops\\icon.tga"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local BORDER = { 0.80, 0.60, 0.34 }
local BRONZE = { 0.61, 0.48, 0.29 }

local function db()
    WhatItDropsDB = WhatItDropsDB or {}
    return WhatItDropsDB
end
local function val(x) if type(x) == "function" then return x() end return x end
local function Sound(kit)
    local id = SOUNDKIT and SOUNDKIT[kit]
    if id and PlaySound then pcall(PlaySound, id) end
end

local Panel = {}
local frame
local page, info = {}, {}
local pages, pageByKey
local current
local closed = {}             -- "page:section" -> folded, for this session
local pools, used, customShown = {}, {}, {}
local navButtons = {}
local uid = 0
local needReload = false      -- the theme was switched to or from ElvUI

-- What "Reset appearance" puts back.
local APPEARANCE_DEFAULTS = {
    theme = "blizzard", accent = "gold", opacity = 1, uiScale = 1, rowSize = "normal",
    fxBars = true, fxBorders = true, fxSparkle = true, fxFade = true, fxModel = false,
}

--------------------------------------------------------------------------
-- 1. ROW DEFINITIONS
--------------------------------------------------------------------------
-- Rows read the saved settings when asked, never when made.
local function merge(row, extra)
    if extra then for k, v in pairs(extra) do row[k] = v end end
    return row
end
local function Flag(field, label, desc, default, extra)
    return merge({ kind = "toggle", label = label, desc = desc,
        get = function()
            local v = db()[field]
            if v == nil then return default end
            return v and true or false
        end,
        set = function(v) db()[field] = v end }, extra)
end
local function Choice(label, desc, choices, get, set, extra)
    return merge({ kind = "choice", label = label, desc = desc, choices = choices, get = get, set = set }, extra)
end
local function Slider(label, desc, lo, hi, step, get, set, extra)
    return merge({ kind = "slider", label = label, desc = desc, min = lo, max = hi, step = step,
        get = get, set = set }, extra)
end
local function Button(label, desc, text, run, extra)
    return merge({ kind = "button", label = label, desc = desc, buttonText = text, run = run }, extra)
end

--------------------------------------------------------------------------
-- 2. SMALL PIECES
--------------------------------------------------------------------------
local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Line(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.6)
    t:SetHeight(1)
    return t
end

-- The looks are applied to the open windows shortly after the last change, so dragging a
-- slider doesn't rebuild the loot window on every tick.
local applyToken = 0
local function ApplyLook()
    applyToken = applyToken + 1
    local mine = applyToken
    C_Timer.After(0.2, function()
        if mine == applyToken and WhatItDrops_ApplyAppearance then WhatItDrops_ApplyAppearance() end
    end)
end
local function RefreshLoot()
    if WhatItDrops_Refresh then WhatItDrops_Refresh() end
end

-- A change was made: run the row's own follow-up.
local function Applied(row)
    if row and row.apply then row.apply() end
end

-- ...and redraw the window a frame later, since a menu's own click is still running.
local function Changed()
    C_Timer.After(0, function() if frame and frame:IsShown() then Panel.Refresh() end end)
end

--------------------------------------------------------------------------
-- 3. THE RIGHT COLUMN: what the hovered setting does
--------------------------------------------------------------------------
local function ShowInfo(title, desc, tip)
    if not info.title then return end
    info.title:SetText(title or "")
    info.desc:SetText(desc or "")
    info.tip:SetText(tip and ("|cffffd100Tip:|r " .. tip) or "")
end

local function ShowPageInfo()
    local p = pageByKey and pageByKey[current]
    if p then ShowInfo(val(p.title), val(p.desc), "Hover any setting to see what it does.") end
end

--------------------------------------------------------------------------
-- 4. ROWS
--------------------------------------------------------------------------
-- One pool per kind. A row spans the page: its name on the left, its control on the right;
-- hovering it fills the right column.
local Build, Fill = {}, {}

local function RowEnter(self)
    if self.row then ShowInfo(val(self.row.label), val(self.row.desc), self.row.tip) end
    self.hover:Show()
end
local function RowLeave(self)
    self.hover:Hide()
    ShowPageInfo()
end
local function Forward(control, f)
    if not control or not control.HookScript then return end
    control:HookScript("OnEnter", function() RowEnter(f) end)
    control:HookScript("OnLeave", function() RowLeave(f) end)
end

local function NewRow(parent, kind)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_H)
    f:EnableMouse(true)
    f:SetScript("OnEnter", RowEnter)
    f:SetScript("OnLeave", RowLeave)
    f.hover = f:CreateTexture(nil, "BACKGROUND")
    f.hover:SetAllPoints()
    f.hover:SetColorTexture(1, 0.82, 0, 0.06)
    f.hover:Hide()
    f.label = Text(f, "GameFontHighlight")
    f.label:SetPoint("LEFT", 6, 0)
    f.kind = kind
    Build[kind](f)
    return f
end

local function Acquire(parent, kind)
    pools[kind] = pools[kind] or {}
    local f = table.remove(pools[kind]) or NewRow(parent, kind)
    f:SetParent(parent)
    f:Show()
    used[#used + 1] = f
    return f
end

local function ReleaseAll()
    for _, f in ipairs(used) do
        f:Hide()
        f:ClearAllPoints()
        f.row = nil
        pools[f.kind] = pools[f.kind] or {}
        table.insert(pools[f.kind], f)
    end
    wipe(used)
    for _, f in ipairs(customShown) do f:Hide() end
    wipe(customShown)
end

-- toggle: a checkbox at the right
Build.toggle = function(f)
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("RIGHT", -4, 0)
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        if f.row then f.row.set(on); Applied(f.row); Changed() end
    end)
    Forward(check, f)
    f.check = check
end
Fill.toggle = function(f, row)
    f.check:SetChecked(row.get() and true or false)
end

-- choice: Blizzard's stepper from its Settings (a dark box with an arrow either side; the box
-- opens the list, the arrows step through it). Where a client has no such template, a plain
-- dropdown; where it has no menus either, the old one.
local function SetupMenu(dropdown, f)
    dropdown:SetupMenu(function(_, root)
        local row = f.row
        if not row then return end
        for _, c in ipairs(row.choices) do
            root:CreateRadio(c.text,
                function() return row.get() == c.value end,
                function() row.set(c.value); Applied(row); Changed() end,
                c.value)
        end
    end)
end

Build.choice = function(f)
    local ok, stepper = pcall(CreateFrame, "Frame", nil, f, "SettingsDropdownWithButtonsTemplate")
    if ok and stepper and stepper.Dropdown and stepper.IncrementButton and stepper.DecrementButton
        and stepper.Dropdown.SetupMenu then
        if stepper.Label then stepper.Label:Hide() end
        stepper:SetPoint("RIGHT", 4, 0)
        stepper.Dropdown:SetWidth(140)
        -- the template lays its arrows out past its own right edge: placed from the row's
        -- right edge instead, so the right arrow is never clipped
        stepper.IncrementButton:ClearAllPoints()
        stepper.IncrementButton:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        stepper.Dropdown:ClearAllPoints()
        stepper.Dropdown:SetPoint("RIGHT", stepper.IncrementButton, "LEFT", -5, 0)
        stepper.DecrementButton:ClearAllPoints()
        stepper.DecrementButton:SetPoint("RIGHT", stepper.Dropdown, "LEFT", -5, 0)
        Forward(stepper.Dropdown, f); Forward(stepper.IncrementButton, f); Forward(stepper.DecrementButton, f)
        SetupMenu(stepper.Dropdown, f)
        f.dropdown = stepper.Dropdown
        f:SetHeight(ROW_H + 6)
        return
    end
    if ok and stepper then stepper:Hide() end

    if MenuUtil then
        local okd, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        if okd and dd and dd.SetupMenu then
            dd:SetWidth(160)
            dd:SetPoint("RIGHT", -6, 0)
            Forward(dd, f)
            SetupMenu(dd, f)
            f.dropdown = dd
            return
        end
    end

    uid = uid + 1
    local dd = CreateFrame("Frame", "WhatItDropsDrop" .. uid, f, "UIDropDownMenuTemplate")
    dd:SetPoint("RIGHT", 10, -2)
    UIDropDownMenu_SetWidth(dd, 130)
    UIDropDownMenu_Initialize(dd, function(_, level)
        local row = f.row
        if not row then return end
        for _, c in ipairs(row.choices) do
            local entry = UIDropDownMenu_CreateInfo()
            entry.text, entry.checked = c.text, (row.get() == c.value)
            entry.func = function() row.set(c.value); CloseDropDownMenus(); Applied(row); Changed() end
            UIDropDownMenu_AddButton(entry, level)
        end
    end)
    f.legacy = dd
    f:SetHeight(ROW_H + 6)
end
Fill.choice = function(f, row)
    if f.dropdown then
        f.dropdown:GenerateMenu()
    elseif f.legacy then
        local text = ""
        for _, c in ipairs(row.choices) do if c.value == row.get() then text = c.text end end
        UIDropDownMenu_SetText(f.legacy, text)
    end
end

-- slider: Blizzard's minimal slider with its stepper arrows, and the value in a box you can
-- type into
local function Snap(v, step)
    if step >= 1 then return math.floor(v / step + 0.5) * step end
    local m = 1 / step
    return math.floor(v * m + 0.5) / m
end
local function ValueText(row, v)
    if row.fmt then return row.fmt(v) end
    if row.step < 1 then return string.format("%.1f", v) end
    return tostring(v)
end

local function SliderChanged(f, value)
    local row = f.row
    if f.filling or not row then return end
    value = Snap(value, row.step)
    if value ~= row.get() then row.set(value); Applied(row) end
    f.edit:SetText(ValueText(row, value))
end

Build.slider = function(f)
    local ok, s = pcall(CreateFrame, "Frame", nil, f, "MinimalSliderWithSteppersTemplate")
    if ok and s and s.Init and s.RegisterCallback and MinimalSliderWithSteppersMixin
        and MinimalSliderWithSteppersMixin.Event then
        s:SetWidth(160)
        s:SetPoint("RIGHT", -54, 0)
        if s.MinText then s.MinText:Hide() end
        if s.MaxText then s.MaxText:Hide() end
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value) SliderChanged(f, value) end, f)
        Forward(s, f); Forward(s.Slider, f)
        f.slider = s
    else
        if ok and s then s:Hide() end
        -- no template: a bare slider in the same place
        local bare = CreateFrame("Slider", nil, f)
        bare:SetOrientation("HORIZONTAL")
        bare:SetSize(150, 14)
        bare:SetPoint("RIGHT", -60, 0)
        bare:SetHitRectInsets(0, 0, -6, -6)
        pcall(bare.SetObeyStepOnDrag, bare, true)
        local track = bare:CreateTexture(nil, "ARTWORK")
        track:SetColorTexture(0.30, 0.30, 0.34, 0.9); track:SetHeight(4)
        track:SetPoint("LEFT"); track:SetPoint("RIGHT")
        local thumb = bare:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1); thumb:SetSize(10, 16)
        bare:SetThumbTexture(thumb)
        bare:SetScript("OnValueChanged", function(_, value) SliderChanged(f, value) end)
        Forward(bare, f)
        f.slider = bare
    end

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(52, 18)
    edit:SetPoint("RIGHT", -6, 0)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(8)
    local function restore(self)
        if f.row then self:SetText(ValueText(f.row, f.row.get())) end
        self:ClearFocus()
    end
    edit:SetScript("OnEditFocusGained", function(self)
        if f.row then self:SetText(tostring(f.row.get())) end
        self:HighlightText()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local row, v = f.row, tonumber(self:GetText())
        if row and v then
            v = Snap(math.min(row.max, math.max(row.min, v)), row.step)
            f.slider:SetValue(v)
            if v ~= row.get() then row.set(v); Applied(row) end
        end
        restore(self)
    end)
    edit:SetScript("OnEscapePressed", restore)
    edit:SetScript("OnEditFocusLost", restore)
    Forward(edit, f)
    f.edit = edit
    f:SetHeight(ROW_H + 4)
end
Fill.slider = function(f, row)
    f.filling = true
    local v = row.get()
    if f.slider.Init then
        local steps = math.max(1, math.floor((row.max - row.min) / row.step + 0.5))
        f.slider:Init(v, row.min, row.max, steps, {})
    else
        f.slider:SetMinMaxValues(row.min, row.max)
        f.slider:SetValueStep(row.step)
        f.slider:SetValue(v)
    end
    f.edit:SetText(ValueText(row, v))
    f.edit:SetCursorPosition(0)
    f.filling = false
end

-- button: an action, at the right
Build.button = function(f)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetHeight(22)
    b:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if f.row and f.row.run then f.row.run(); Changed() end
    end)
    Forward(b, f)
    f.button = b
end
Fill.button = function(f, row)
    f.button:SetText(val(row.buttonText) or "")
    f.button:SetWidth(math.max(90, (f.button:GetFontString() and f.button:GetFontString():GetStringWidth() or 60) + 28))
end

-- keybind: click, then press the key; right-click clears. Binds straight to a Bindings.xml action.
local function KeyText(binding)
    local k = binding and GetBindingKey(binding)
    return k and ("|cff00ff00" .. k .. "|r") or "Click to set key"
end
Build.keybind = function(f)
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(176, 22)
    btn:SetPoint("RIGHT", -4, 0)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function stop()
        btn.listening = false
        btn:EnableKeyboard(false)
        btn:SetText(KeyText(f.row and f.row.binding))
    end
    btn.stop = stop
    btn:SetScript("OnClick", function(self, button)
        local binding = f.row and f.row.binding
        if not binding then return end
        if button == "RightButton" then
            local o1, o2 = GetBindingKey(binding)
            if o1 then SetBinding(o1) end
            if o2 then SetBinding(o2) end
            WhatItDrops_SaveBindings()
            stop()
            return
        end
        -- SetPropagateKeyboardInput is protected; don't start key capture in combat.
        if InCombatLockdown() then return end
        self.listening = true
        self:SetText("Press a key... (Esc cancels)")
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
    end)
    btn:SetScript("OnKeyDown", function(self, key)
        if not self.listening then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            return
        end
        if key == "ESCAPE" then stop() return end
        -- Wait for a real key, ignore lone modifiers.
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
            or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
            return
        end
        -- WoW's canonical modifier order is ALT-CTRL-SHIFT; the wrong order silently
        -- fails to register for multi-modifier combos.
        local combo = ""
        if IsAltKeyDown() then combo = combo .. "ALT-" end
        if IsControlKeyDown() then combo = combo .. "CTRL-" end
        if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
        combo = combo .. key
        local binding = f.row and f.row.binding
        if binding then
            local o1, o2 = GetBindingKey(binding)
            if o1 then SetBinding(o1) end
            if o2 then SetBinding(o2) end
            if SetBinding(combo, binding) then WhatItDrops_SaveBindings() end
        end
        stop()
        Changed()          -- the key may have been taken from the other action
    end)
    Forward(btn, f)
    f.keyBtn = btn
end
Fill.keybind = function(f, row)
    f.keyBtn.listening = false
    f.keyBtn:EnableKeyboard(false)
    f.keyBtn:SetText(KeyText(row.binding))
end

local function FillRow(f, row)
    f.row = row
    f.label:SetText(val(row.label) or "")
    Fill[f.kind](f, row)
end

--------------------------------------------------------------------------
-- 5. THEME AND ACCENT SWATCHES (custom rows)
--------------------------------------------------------------------------
local THEMES = {
    { key = "blizzard",  text = "Blizzard",  r = 0.10, g = 0.09, b = 0.07,
      desc = "The classic gold-bordered dialog look." },
    { key = "elvui",     text = "ElvUI",     r = 0.11, g = 0.11, b = 0.11,
      desc = "A flat dark skin. It uses ElvUI's own skinning when ElvUI is installed.",
      tip = "Switching to or from this one needs a reload." },
    { key = "slate",     text = "Slate",     r = 0.11, g = 0.14, b = 0.20,
      desc = "A flat blue-grey window frame." },
    { key = "parchment", text = "Parchment", r = 0.17, g = 0.14, b = 0.09,
      desc = "A flat warm-brown window frame." },
}
local ACCENT_ORDER = { "gold", "blue", "green", "red", "violet" }
local ACCENT_NAMES = { gold = "Gold", blue = "Blue", green = "Green", red = "Red", violet = "Violet" }

local function Swatch(parent, w, h, r, g, b)
    local s = CreateFrame("Button", nil, parent, "BackdropTemplate")
    s:SetSize(w, h)
    s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    s:SetBackdropColor(r, g, b, 1)
    s:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    return s
end

local function BuildThemeRow(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(ROW_H + 14)
    f.label = Text(f, "GameFontHighlight")
    f.label:SetPoint("LEFT", 6, 0)
    f.label:SetText("Window theme")
    f.btns = {}
    for i, t in ipairs(THEMES) do
        local b = Swatch(f, 56, 30, t.r, t.g, t.b)
        b:SetPoint("RIGHT", -6 - (#THEMES - i) * 62, 0)
        b.key = t.key
        local lbl = Text(b, "GameFontHighlightSmall", "CENTER")
        lbl:SetPoint("BOTTOM", 0, 3)
        lbl:SetText(t.text)
        b:SetScript("OnEnter", function() ShowInfo(t.text .. " theme", t.desc, t.tip) end)
        b:SetScript("OnLeave", ShowPageInfo)
        b:SetScript("OnClick", function(self)
            Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            local old = db().theme or "blizzard"
            db().theme = self.key
            if (old == "elvui") ~= (self.key == "elvui") then needReload = true end
            ApplyLook()
            Changed()
        end)
        f.btns[i] = b
    end
    return f, function()
        local cur = db().theme or "blizzard"
        for _, b in ipairs(f.btns) do
            if b.key == cur then b:SetBackdropBorderColor(1, 0.82, 0, 1)
            else b:SetBackdropBorderColor(0.25, 0.25, 0.28, 1) end
        end
        return f:GetHeight()
    end
end

local function BuildAccentRow(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(ROW_H + 6)
    f.label = Text(f, "GameFontHighlight")
    f.label:SetPoint("LEFT", 6, 0)
    f.label:SetText("Accent colour")
    f.btns = {}
    for i, key in ipairs(ACCENT_ORDER) do
        local c = (WhatItDrops_Accents and WhatItDrops_Accents[key]) or { 1, 0.82, 0 }
        local b = Swatch(f, 24, 24, c[1], c[2], c[3])
        b:SetPoint("RIGHT", -6 - (#ACCENT_ORDER - i) * 30, 0)
        b.key = key
        b:SetScript("OnEnter", function()
            ShowInfo(ACCENT_NAMES[key] .. " accent",
                "Tints window titles, the rare-drop sparkle and the portrait card's border.",
                "The window itself stays bronze.")
        end)
        b:SetScript("OnLeave", ShowPageInfo)
        b:SetScript("OnClick", function(self)
            Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            db().accent = self.key
            ApplyLook()
            Changed()
        end)
        f.btns[i] = b
    end
    return f, function()
        local cur = db().accent or "gold"
        for _, b in ipairs(f.btns) do
            if b.key == cur then b:SetBackdropBorderColor(1, 1, 1, 1)
            else b:SetBackdropBorderColor(0.25, 0.25, 0.28, 1) end
        end
        return f:GetHeight()
    end
end

--------------------------------------------------------------------------
-- 5b. THE PROFILE BOX (custom row): a multi-line text box and a status line
--------------------------------------------------------------------------
local function BuildProfileBox(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(176)
    local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 40)
    bg:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bg:SetBackdropColor(0, 0, 0, 0.45)
    bg:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 0.8)
    local scroll = CreateFrame("ScrollFrame", nil, bg)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(CONTENT_W - 28)
    edit:SetHeight(126)
    edit:SetMaxLetters(20000)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 30)))
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnter", function()
        ShowInfo("Profile text",
            "Export fills this box. To import, paste a profile here first, then use Import.",
            "It holds every setting, the window and minimap positions, and your two keybinds.")
    end)
    edit:SetScript("OnLeave", ShowPageInfo)

    local status = Text(f, "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 2, -6)
    status:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    status:SetWordWrap(true)
    status:SetJustifyV("TOP")
    status:SetHeight(28)

    f.edit = edit
    f.status = status
    f.setStatus = function(text, ok)
        status:SetText((ok and "|cff66dd66" or "|cffff6666") .. (text or "") .. "|r")
    end
    return f, function() return f:GetHeight() end
end

--------------------------------------------------------------------------
-- 6. THE PAGES
--------------------------------------------------------------------------
local function ResetAppearance()
    local d = db()
    local wasElv = d.theme == "elvui"
    for k, v in pairs(APPEARANCE_DEFAULTS) do d[k] = v end
    if wasElv then needReload = true end
    if WhatItDrops_ApplyAppearance then WhatItDrops_ApplyAppearance() end
end

local function definePages()
    local themeFrame, renderTheme = BuildThemeRow(page.content)
    local accentFrame, renderAccent = BuildAccentRow(page.content)

    -- Two clicks rather than a popup: a StaticPopup shown from addon code taints the game
    -- menu's Escape and can hang the client in Gamepad mode. The first click arms the button
    -- and says so; it disarms itself if the second never comes.
    local confirming, armed = false, 0
    local function resetClick()
        if confirming then
            confirming = false
            ResetAppearance()
            return
        end
        confirming = true
        armed = armed + 1
        local mine = armed
        C_Timer.After(4, function()
            if armed == mine and confirming then
                confirming = false
                if frame and frame:IsShown() then Panel.Refresh() end
            end
        end)
    end

    local function pct(v) return v .. "%" end

    -- Profile: export fills the box; import checks it first, then asks for a second click
    local box, renderBox = BuildProfileBox(page.content)
    local importArmed, importToken = false, 0
    local function doExport()
        local s = WhatItDrops_ExportProfile()
        box.edit:SetText(s)
        box.edit:SetFocus()
        box.edit:HighlightText()
        importArmed = false
        box.setStatus("Exported " .. #s .. " characters. Press Ctrl+C to copy, then paste it into the other install's Profile page.", true)
    end
    local function importClick()
        local text = box.edit:GetText()
        if importArmed then
            importArmed = false
            local before = db().theme or "blizzard"
            local ok, msg = WhatItDrops_ImportProfile(text)
            if ok and (before == "elvui") ~= ((db().theme or "blizzard") == "elvui") then needReload = true end
            box.setStatus(msg, ok)
            return
        end
        local ok, msg = WhatItDrops_CheckProfile(text)
        if not ok then box.setStatus(msg, false) return end
        importArmed = true
        importToken = importToken + 1
        local mine = importToken
        box.setStatus(msg .. " Click Import again to replace your current settings.", true)
        C_Timer.After(8, function()
            if importToken == mine and importArmed then
                importArmed = false
                if frame and frame:IsShown() then Panel.Refresh() end
            end
        end)
    end
    Panel.profile = {
        export = doExport,
        focus = function() box.edit:SetFocus() end,
    }

    pages = {
        {
            key = "general", title = "General",
            desc = "How the loot window and the browser behave.",
            sections = {
                { title = "Loot lookup", key = "lookup", rows = {
                    Flag("auto", "Auto-show on target",
                        "Open the loot window by itself whenever you target an enemy.", false,
                        { tip = "Other players always need the keybind." }),
                    Flag("useMouseover", "Use mouseover first",
                        "When a creature is under your mouse, look that one up instead of your target.", false),
                    Flag("hideJunk", "Hide common loot",
                        "Leave grey and white items out of loot lists.", false, { apply = RefreshLoot }),
                    Flag("showWorldDrops", "Show world drops",
                        "Include the generic world-drop pool along with a creature's own drops.", true,
                        { apply = RefreshLoot, tip = "Retail data has no world-drop pool, so this changes nothing there." }),
                    Flag("clearSearchOnOpen", "Clear the browser search",
                        "Start the item browser with an empty search box each time it opens.", true),
                } },
                { title = "Minimap", key = "minimap", rows = {
                    { kind = "toggle", label = "Show the minimap button",
                      desc = "Left-click reloads the UI, right-click does a loot lookup, and you can drag it around the minimap.",
                      get = function() return not (db().minimap and db().minimap.hide) end,
                      set = function(v)
                          local m = db(); m.minimap = m.minimap or {}; m.minimap.hide = not v
                      end,
                      apply = function() if WhatItDrops_UpdateMinimapButton then WhatItDrops_UpdateMinimapButton() end end },
                } },
            },
        },
        {
            key = "appearance", title = "Appearance",
            desc = "Theme, colours and effects for the loot window and the browser.",
            sections = {
                { title = "Theme", key = "theme", rows = {
                    { kind = "custom", frame = themeFrame, render = renderTheme },
                    { kind = "custom", frame = accentFrame, render = renderAccent },
                    Button("Finish switching theme",
                        "ElvUI skins widgets as they are created, so switching to or from it takes a reload.",
                        "Reload UI", function() ReloadUI() end, { vis = function() return needReload end }),
                } },
                { title = "Window", key = "window", rows = {
                    Slider("Opacity", "How solid the window background is. The text and icons stay fully visible.",
                        40, 100, 1,
                        function() return math.floor((db().opacity or 1) * 100 + 0.5) end,
                        function(v) db().opacity = v / 100 end,
                        { fmt = pct, apply = ApplyLook }),
                    Slider("Scale", "The size of the loot window and the browser.",
                        70, 140, 1,
                        function() return math.floor((db().uiScale or 1) * 100 + 0.5) end,
                        function(v) db().uiScale = v / 100 end,
                        { fmt = pct, apply = ApplyLook, tip = "Each window keeps its place on screen." }),
                    Choice("Row height", "How tall each line of a loot list is.",
                        { { value = "compact", text = "Compact" }, { value = "normal", text = "Normal" },
                          { value = "roomy", text = "Roomy" } },
                        function() return db().rowSize or "normal" end,
                        function(v) db().rowSize = v end,
                        { apply = ApplyLook }),
                } },
                { title = "Loot list effects", key = "fx", rows = {
                    Flag("fxBars", "Drop-rate bars",
                        "A bar behind each row, as wide as that item's drop chance and tinted by its quality.", true,
                        { apply = ApplyLook, tip = "A 1.8% drop gets a very thin bar. That is the real chance." }),
                    Flag("fxBorders", "Quality-coloured icon borders",
                        "A thin border around each icon in the item's quality colour.", true, { apply = ApplyLook }),
                    Flag("fxSparkle", "Sparkle on rare drops",
                        "A sparkle beside rare-or-better items that drop less than 2% of the time.", true,
                        { apply = ApplyLook }),
                    Flag("fxFade", "Rows fade in",
                        "Rows ease in when a list opens, instead of appearing all at once.", true),
                    Flag("fxModel", "3D model of the target",
                        "Show a model of the creature or player in a small card beside the loot window.", false,
                        { apply = ApplyLook, tip = "Boss entries from the Encounter Journal have no model." }),
                } },
                { title = "Defaults", key = "reset", rows = {
                    Button("Reset appearance",
                        "Put the theme, accent, opacity, scale, row height and effects back to how they started.",
                        function() return confirming and "Click again to confirm" or "Reset appearance" end,
                        resetClick),
                } },
            },
        },
        {
            key = "keybinds", title = "Keybinds",
            desc = "Click a key button, then press the key you want. Right-click a button to clear it.",
            sections = {
                { title = "Keys", key = "keys", rows = {
                    { kind = "keybind", label = "Loot for target", binding = "WHATITDROPS_FULLLOOKUP",
                      desc = "Look up your target: loot for a creature, equipped gear for a player. With no target inside a dungeon or raid it lists that instance's bosses.",
                      tip = "These also appear under Esc > Key Bindings > WhatItDrops." },
                    { kind = "keybind", label = "Item browser", binding = "WHATITDROPS_LOOKUP",
                      desc = "Open the item and creature browser: search by name, see who drops an item." },
                } },
            },
        },
        {
            key = "profile", title = "Profile",
            desc = "Copy your whole setup as one line of text and paste it back on another character or install. Settings are already shared by every character on this account.",
            sections = {
                { title = "Share your setup", key = "share", rows = {
                    { kind = "custom", frame = box, render = renderBox },
                    Button("Export",
                        "Build a profile from your current settings and put it in the box, selected, ready to copy with Ctrl+C.",
                        "Export current settings", doExport,
                        { tip = "Covers every setting, window and minimap positions, and your two keybinds." }),
                    Button("Import",
                        "Replace your settings with the profile in the box. It is checked first, and nothing changes unless it is valid.",
                        function() return importArmed and "Click again to replace" or "Import from the box" end,
                        importClick,
                        { tip = "Anything the profile leaves out goes back to its default." }),
                } },
            },
        },
    }
    pageByKey = {}
    for _, p in ipairs(pages) do pageByKey[p.key] = p end
end

--------------------------------------------------------------------------
-- 7. THE MIDDLE COLUMN: the page
--------------------------------------------------------------------------
local function SectionClick(h)
    if not h.sectionKey then return end
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    closed[h.sectionKey] = not closed[h.sectionKey] or nil
    Panel.Refresh()
end

local function SectionHeader(parent, text, y, sectionKey)
    pools.section = pools.section or {}
    local h = table.remove(pools.section)
    if not h then
        h = CreateFrame("Frame", nil, parent)
        h:SetHeight(SECTION_H)
        h.kind = "section"
        h.text = Text(h, "GameFontNormal")
        h.text:SetPoint("BOTTOMLEFT", 6, 6)
        h.sign = Text(h, "GameFontNormal")
        h.sign:SetPoint("BOTTOMRIGHT", -10, 6)
        h.line = Line(h)
        h.line:SetPoint("BOTTOMLEFT", 0, 2)
        h.line:SetPoint("BOTTOMRIGHT", 0, 2)
        h.hover = h:CreateTexture(nil, "BACKGROUND")
        h.hover:SetAllPoints()
        h.hover:SetColorTexture(1, 0.82, 0, 0.06)
        h.hover:Hide()
        h:EnableMouse(true)
        h:SetScript("OnEnter", function(self) self.hover:Show() end)
        h:SetScript("OnLeave", function(self) self.hover:Hide() end)
        h:SetScript("OnMouseUp", SectionClick)
    end
    h:SetParent(parent)
    h.sectionKey = sectionKey
    h.sign:SetText(sectionKey and (closed[sectionKey] and "+" or "-") or "")
    h.text:SetText(text)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 0, y)
    h:SetWidth(CONTENT_W)
    h:Show()
    used[#used + 1] = h
    return SECTION_H
end

-- Lays rows out from y down and returns the new y.
local function PlaceRows(parent, rows, y)
    for _, row in ipairs(rows) do
        if row.kind == "custom" then
            local f = row.frame
            f:SetParent(parent)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, y)
            f:SetWidth(CONTENT_W)
            local h = row.render()
            f:SetHeight(h)
            f:Show()
            customShown[#customShown + 1] = f
            y = y - h
        else
            local f = Acquire(parent, row.kind)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, y)
            f:SetWidth(CONTENT_W)
            FillRow(f, row)
            y = y - f:GetHeight()
        end
    end
    return y
end

local function visibleRows(section)
    local out = {}
    for _, row in ipairs(section.rows) do
        if not row.vis or row.vis() then out[#out + 1] = row end
    end
    return out
end

local function UpdateNav()
    for key, b in pairs(navButtons) do
        b.selected:SetShown(key == current)
        b.text:SetText(val(pageByKey[key].title))
    end
end

function Panel.Refresh()
    if not frame then return end
    ReleaseAll()
    local p = pageByKey[current]
    page.title:SetText(val(p.title))

    local y = 0
    for _, section in ipairs(p.sections) do
        local rows = visibleRows(section)
        if #rows > 0 then
            local key = p.key .. ":" .. section.key
            y = y - SectionHeader(page.content, val(section.title), y, key)
            if not closed[key] then y = PlaceRows(page.content, rows, y) - 4 end
        end
    end
    page.content:SetHeight(math.max(1, -y + 8))
    if page.scrollLine then page.scrollLine.Update() end
    UpdateNav()
end

function Panel.Select(key)
    if not pageByKey[key] then return end
    current = key
    db().optionsPage = key
    page.scroll:SetVerticalScroll(0)
    Panel.Refresh()
    ShowPageInfo()
end

--------------------------------------------------------------------------
-- 8. THE WINDOW
--------------------------------------------------------------------------
-- A thin scroll line beside the page, like FlareUI's: a faint track and a bronze thumb, shown
-- only when there is something to scroll; the wheel scrolls the page.
local function AttachScrollLine(scroll, parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetWidth(8)
    line:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    line:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    line.track = line:CreateTexture(nil, "ARTWORK")
    line.track:SetWidth(2); line.track:SetPoint("TOP"); line.track:SetPoint("BOTTOM")
    line.track:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.25)
    line.thumb = line:CreateTexture(nil, "OVERLAY")
    line.thumb:SetWidth(2)
    line.thumb:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    function line.Update()
        local range = scroll:GetVerticalScrollRange() or 0
        local h = line:GetHeight() or 0
        if not scroll:IsShown() or range <= 0.5 or h <= 0 then line:Hide() return end
        line:Show()
        local visible = scroll:GetHeight() / (scroll:GetHeight() + range)
        local th = math.max(16, h * visible)
        line.thumb:SetHeight(th)
        line.thumb:ClearAllPoints()
        line.thumb:SetPoint("TOP", line, "TOP", 0, -(h - th) * ((scroll:GetVerticalScroll() or 0) / range))
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    scroll:HookScript("OnVerticalScroll", line.Update)
    scroll:HookScript("OnScrollRangeChanged", line.Update)
    scroll:HookScript("OnSizeChanged", line.Update)
    return line
end

-- The window remembers where you left it, like the loot window and the browser do.
local function SaveWindowPos(f)
    local left, bottom = f:GetLeft(), f:GetBottom()
    if not left or not bottom then return end
    local d = db()
    d.pos = d.pos or {}
    d.pos.options = { left, bottom }
end
local function RestoreWindowPos(f)
    local s = db().pos and db().pos.options
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s[1], s[2])
        return true
    end
    return false
end

local function BuildWindow()
    frame = CreateFrame("Frame", "WhatItDropsOptions", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    if not RestoreWindowPos(frame) then frame:SetPoint("CENTER") end
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveWindowPos(self) end)
    frame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
    frame:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    -- a dark base, Blizzard's Collections tile over it, and a black wash (FlareUI's)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    base:SetPoint("TOPLEFT", 5, -5); base:SetPoint("BOTTOMRIGHT", -5, 5)
    base:SetColorTexture(0.06, 0.055, 0.045, 0.97)
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAllPoints(base)
    art:SetTexture("Interface\\Collections\\CollectionsBackgroundTile", "REPEAT", "REPEAT")
    art:SetHorizTile(true); art:SetVertTile(true)
    local wash = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    wash:SetAllPoints(base)
    wash:SetColorTexture(0, 0, 0, 0.5)
    frame:Hide()
    tinsert(UISpecialFrames, "WhatItDropsOptions")
    frame:SetScript("OnShow", function()
        Sound("IG_CHARACTER_INFO_OPEN")
        Panel.Refresh()
        ShowPageInfo()
    end)
    frame:SetScript("OnHide", function()
        Sound("IG_CHARACTER_INFO_CLOSE")
        -- never leave a key capture armed behind a closed window
        for _, f in ipairs(used) do
            if f.kind == "keybind" and f.keyBtn and f.keyBtn.listening then f.keyBtn.stop() end
        end
    end)

    -- header: name, version, close
    local title = Text(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD + 4, -12)
    title:SetText("WhatItDrops")
    local version = Text(frame, "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    version:SetText(meta and meta(ADDON, "Version") or "")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local headerLine = Line(frame)
    headerLine:SetPoint("TOPLEFT", 6, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", -6, -HEADER_H)

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 6, -HEADER_H - 1)
    body:SetPoint("BOTTOMRIGHT", -6, 6)

    -- left column: the pages
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LEFT_W)
    local leftLine = Line(body)
    leftLine:SetWidth(1)
    leftLine:SetPoint("TOPLEFT", left, "TOPRIGHT"); leftLine:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")

    -- right column: what the hovered setting does
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(RIGHT_W)
    local rightBg = right:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints()
    rightBg:SetColorTexture(0, 0, 0, 0.25)
    local rightLine = Line(body)
    rightLine:SetWidth(1)
    rightLine:SetPoint("TOPRIGHT", right, "TOPLEFT"); rightLine:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    local icon = right:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", PAD, -PAD)
    icon:SetTexture(ICON)
    info.title = Text(right, "GameFontNormalLarge")
    info.title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    info.title:SetPoint("RIGHT", -PAD, 0)
    info.title:SetWordWrap(true)
    info.desc = Text(right, "GameFontHighlight")
    info.desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
    info.desc:SetPoint("RIGHT", -PAD, 0)
    info.desc:SetSpacing(3)
    info.desc:SetTextColor(0.85, 0.85, 0.85)
    info.tip = Text(right, "GameFontNormalSmall")
    info.tip:SetPoint("TOPLEFT", info.desc, "BOTTOMLEFT", 0, -10)
    info.tip:SetPoint("RIGHT", -PAD, 0)
    info.tip:SetSpacing(2)

    -- middle column: the page
    local middle = CreateFrame("Frame", nil, body)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", PAD, -PAD)
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -PAD - 10, PAD)

    local header = CreateFrame("Frame", nil, middle)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    header:SetHeight(34)
    page.header = header
    page.title = Text(header, "GameFontNormalHuge")
    page.title:SetPoint("LEFT", 4, 0)

    local scroll = CreateFrame("ScrollFrame", nil, middle)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content
    page.scrollLine = AttachScrollLine(scroll, middle)

    definePages()

    -- the page list, from the data
    local y = -PAD + 4
    for _, p in ipairs(pages) do
        local b = CreateFrame("Button", nil, left)
        b:SetSize(LEFT_W - 2 * PAD, 24)
        b:SetPoint("TOPLEFT", PAD, y)
        b.selected = b:CreateTexture(nil, "BACKGROUND")
        b.selected:SetAllPoints()
        b.selected:SetColorTexture(1, 0.82, 0, 0.12)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        b:GetHighlightTexture():SetAlpha(0.25)
        b.text = Text(b, "GameFontHighlight")
        b.text:SetPoint("LEFT", 8, 0)
        local key = p.key
        b:SetScript("OnClick", function()
            Sound("IG_CHARACTER_INFO_TAB")
            Panel.Select(key)
        end)
        navButtons[key] = b
        y = y - 24
    end

    current = db().optionsPage
    if not (current and pageByKey[current]) then current = "general" end
end

--------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------
function WhatItDrops_ToggleOptions()
    if not frame then BuildWindow() end
    frame:SetShown(not frame:IsShown())
end

-- Open the window on a given page, from outside it (/wid appearance).
function WhatItDrops_ShowOptionsPage(key)
    if not frame then BuildWindow() end
    frame:Show()
    if key then Panel.Select(key) end
end

-- /wid export and /wid import: open the Profile page; "export" also fills the box, "import" focuses it.
function WhatItDrops_OpenProfile(mode)
    WhatItDrops_ShowOptionsPage("profile")
    local p = Panel.profile
    if not p then return end
    if mode == "export" then p.export() elseif mode == "import" then p.focus() end
end

-- Something outside the window changed a setting: redraw it.
function WhatItDrops_RefreshOptions()
    if frame and frame:IsShown() then Panel.Refresh() end
end
