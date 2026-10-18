-- MMT: flat, minimalist UI widgets (the look carried over from OMT).
-- Every widget with a Refresh() is registered on its page so the page can
-- redraw it after a profile switch.

local _, ns = ...

local UI = {}
ns.UI = UI

UI.ACCENT = { 0.31, 0.70, 1.00 }
local A = UI.ACCENT
UI.ROW = 22

local function Track(parent, w)
    local page = parent
    while page and type(rawget(page, "widgets")) ~= "table" do page = page:GetParent() end
    if page then table.insert(page.widgets, w) end
end

function UI.Border(frame, r, g, b, a)
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

function UI.Fill(frame, r, g, b, a, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

function UI.Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetText(text or "")
    return fs
end

function UI.Tooltip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Highlight(frame)
    local hl = frame:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    return hl
end

-- Checkbox -------------------------------------------------------------------
function UI.Check(parent, width, text, get, set, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, UI.ROW - 4)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    UI.Fill(box, 0.12, 0.12, 0.12, 1)
    UI.Border(box, 0.35, 0.35, 0.35, 1)
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3); mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(A[1], A[2], A[3], 1)

    b.label = UI.Label(b, text)
    b.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", 0, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    local hl = Highlight(b)
    hl:SetColorTexture(1, 1, 1, 0.04)

    b.Refresh = function() mark:SetShown(get() and true or false) end
    b:SetScript("OnClick", function()
        set(not get())
        b.Refresh()
        ns.Refresh()
    end)
    if tip then UI.Tooltip(b, text, tip) end
    Track(parent, b)
    return b
end

-- Slider (label + value on one line, track below) -----------------------------
function UI.Slider(parent, width, text, min, max, step, get, set, fmt)
    fmt = fmt or "%d"
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, 32)
    local label = UI.Label(c, text)
    label:SetPoint("TOPLEFT")
    local value = UI.Label(c, "")
    value:SetPoint("TOPRIGHT")

    local s = CreateFrame("Slider", nil, c)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 10)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.18, 0.18, 0.18, 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(A[1], A[2], A[3], 1)
    thumb:SetSize(8, 12)
    s:SetThumbTexture(thumb)

    local updating = false
    c.Refresh = function()
        updating = true
        s:SetValue(get())
        value:SetFormattedText(fmt, get())
        updating = false
    end
    s:SetScript("OnValueChanged", function(_, v)
        if updating then return end
        v = math.floor(v / step + 0.5) * step
        set(v)
        value:SetFormattedText(fmt, v)
        ns.Refresh()
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.min(max, math.max(min, self:GetValue() + delta * step)))
    end)
    Track(parent, c)
    return c
end

-- Flat button ---------------------------------------------------------------------
function UI.Button(parent, width, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, UI.ROW - 2)
    UI.Fill(b, 0.12, 0.12, 0.12, 1)
    UI.Border(b, 0.25, 0.25, 0.25, 1)
    Highlight(b)
    b.label = UI.Label(b, text)
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    return b
end

-- Small text button for list rows (e.g. "x", "Up") -------------------------------
function UI.TextButton(parent, text, onClick, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 22, UI.ROW - 4)
    b.label = UI.Label(b, text)
    b.label:SetPoint("CENTER")
    b.label:SetTextColor(0.6, 0.6, 0.6)
    b:SetScript("OnEnter", function() b.label:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function() b.label:SetTextColor(0.6, 0.6, 0.6) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Dropdown: a button showing the current value; click opens a list.
-- choices: { { value, text }, ... } or a function returning that list.
-- Entries with header = true are section titles (not selectable).
local POPUP_ROWS, POPUP_ROW_H = 14, 20
local popup

local function Popup()
    if popup then return popup end
    -- invisible full-screen catcher: a click outside the list closes it
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()

    local p = CreateFrame("Frame", "MMTDropdownList", UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(catcher:GetFrameLevel() + 10)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:EnableMouseWheel(true)
    UI.Fill(p, 0.07, 0.07, 0.08, 0.98)
    UI.Border(p, A[1], A[2], A[3], 0.5)
    p.rows = {}
    for i = 1, POPUP_ROWS do
        local r = CreateFrame("Button", nil, p)
        r:SetHeight(POPUP_ROW_H)
        r:SetPoint("TOPLEFT", 1, -2 - (i - 1) * POPUP_ROW_H)
        r:SetPoint("TOPRIGHT", -1, -2 - (i - 1) * POPUP_ROW_H)
        r.sel = UI.Fill(r, A[1], A[2], A[3], 0.18, "BORDER")
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)
        r.text = UI.Label(r, "")
        r.text:SetPoint("LEFT", 10, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            local item = self.item
            if not item or item.header then return end
            p:Hide()
            if p.onPick then p.onPick(item.value) end
        end)
        p.rows[i] = r
    end
    p.more = UI.Label(p, "")
    p.more:SetPoint("BOTTOMRIGHT", -8, 3)
    p.more:SetTextColor(0.5, 0.5, 0.5)

    function p:Render()
        local items, current = self.items, self.current
        self.offset = math.max(0, math.min(self.offset, #items - POPUP_ROWS))
        for i, r in ipairs(self.rows) do
            local item = items[i + self.offset]
            r.item = item
            if item then
                r.text:SetText(item.text or tostring(item.value))
                if item.header then
                    r.text:SetTextColor(A[1], A[2], A[3], 0.8)
                    r.text:SetPoint("LEFT", 6, 0)
                    r.sel:Hide()
                    r.hl:SetShown(false)
                else
                    r.text:SetPoint("LEFT", 14, 0)
                    r.text:SetTextColor(1, 1, 1)
                    r.sel:SetShown(item.value == current)
                    r.hl:SetShown(true)
                end
                r:Show()
            else
                r:Hide()
            end
        end
        self.more:SetText(#items > POPUP_ROWS and (self.offset + POPUP_ROWS < #items and "more ..." or "") or "")
    end
    p:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta
        self:Render()
    end)
    p:SetScript("OnHide", function() catcher:Hide() end)
    catcher:SetScript("OnClick", function() p:Hide() end)
    UI.CloseOnEscape(p)
    p:Hide()
    p.catcher = catcher
    popup = p
    return p
end

function UI.OpenList(owner, items, current, onPick)
    local p = Popup()
    if p:IsShown() and p.owner == owner then p:Hide() return end
    p.owner, p.items, p.current, p.onPick = owner, items, current, onPick
    -- start scrolled to the selected entry
    p.offset = 0
    for i, item in ipairs(items) do
        if item.value == current and not item.header then p.offset = math.max(0, i - POPUP_ROWS) end
    end
    local rows = math.min(#items, POPUP_ROWS)
    p:SetSize(math.max(owner:GetWidth(), 140), rows * POPUP_ROW_H + 4 + (#items > POPUP_ROWS and 12 or 0))
    p:ClearAllPoints()
    local bottom = owner:GetBottom() or 0
    if bottom * owner:GetEffectiveScale() < p:GetHeight() * p:GetEffectiveScale() + 20 then
        p:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    else
        p:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
    p:Render()
    p.catcher:Show()
    p:Show()
end

function UI.Dropdown(parent, width, text, choices, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, UI.ROW - 2)
    UI.Fill(b, 0.12, 0.12, 0.12, 1)
    UI.Border(b, 0.25, 0.25, 0.25, 1)
    Highlight(b)
    local fs = UI.Label(b, text)
    fs:SetPoint("LEFT", 8, 0)
    local arrow = UI.Label(b, "v")
    arrow:SetPoint("RIGHT", -7, 1)
    arrow:SetTextColor(0.6, 0.6, 0.6)
    local value = UI.Label(b, "")
    value:SetPoint("RIGHT", arrow, "LEFT", -6, -1)
    value:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)
    value:SetTextColor(A[1], A[2], A[3])

    local function list() return type(choices) == "function" and choices() or choices end
    b.Refresh = function()
        local v = get()
        local shown
        for _, c in ipairs(list()) do
            if not c.header and c.value == v then shown = c.text end
        end
        value:SetText(shown or (v ~= nil and tostring(v)) or "-")
    end
    b:SetScript("OnClick", function(self)
        local l = list()
        if #l == 0 then return end
        UI.OpenList(self, l, get(), function(v)
            set(v)
            b.Refresh()
            ns.Refresh()
        end)
    end)
    Track(parent, b)
    return b
end

-- older name, used all over the settings pages
UI.Cycle = UI.Dropdown

-- Single-line edit box with placeholder -------------------------------------------
function UI.EditBox(parent, width, placeholder, onEnter)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, UI.ROW - 2)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(6, 6, 0, 0)
    UI.Fill(e, 0.09, 0.09, 0.10, 1)
    UI.Border(e, 0.25, 0.25, 0.25, 1)
    local ph = UI.Label(e, placeholder)
    ph:SetPoint("LEFT", 6, 0)
    ph:SetTextColor(0.45, 0.45, 0.45)
    local function UpdatePlaceholder()
        ph:SetShown(e:GetText() == "" and not e:HasFocus())
    end
    e:SetScript("OnEditFocusGained", UpdatePlaceholder)
    e:SetScript("OnEditFocusLost", UpdatePlaceholder)
    e:SetScript("OnTextChanged", UpdatePlaceholder)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        if onEnter then onEnter(self:GetText(), self) end
    end)
    e.UpdatePlaceholder = UpdatePlaceholder
    return e
end

-- Multi-line, scrollable edit box (profile export/import) -------------------------
function UI.TextArea(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)
    UI.Fill(holder, 0.09, 0.09, 0.10, 1)
    UI.Border(holder, 0.25, 0.25, 0.25, 1)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local e = CreateFrame("EditBox", nil, scroll)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetWidth(width - 12)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(e)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 20)))
    end)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() e:SetFocus() end)
    holder.edit = e
    return holder
end

-- Simple vertical layout helper ------------------------------------------------------
local Column = {}
Column.__index = Column

function UI.Column(parent, x, y, width)
    return setmetatable({ parent = parent, x = x, y = y, width = width }, Column)
end

function Column:Add(frame, height, indent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (indent or 0), self.y)
    self.y = self.y - (height or UI.ROW)
    return frame
end

function Column:Space(h) self.y = self.y - (h or 8) end

function Column:Header(text)
    self.y = self.y - 6
    local fs = UI.Label(self.parent, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
    local line = self.parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y - 16)
    line:SetWidth(self.width)
    self.y = self.y - 22
    return fs
end

function Column:Note(text)
    local fs = UI.Label(self.parent, text)
    fs:SetTextColor(0.6, 0.6, 0.6)
    fs:SetWidth(self.width)
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
    self.y = self.y - math.max(UI.ROW, (fs:GetStringHeight() or 12) + 8)
    return fs
end

function Column:Check(...) return self:Add(UI.Check(self.parent, self.width, ...)) end
function Column:Slider(...) return self:Add(UI.Slider(self.parent, self.width, ...), 36) end
function Column:Cycle(...) return self:Add(UI.Dropdown(self.parent, self.width, ...), UI.ROW + 2) end
Column.Dropdown = Column.Cycle
function Column:Button(...) return self:Add(UI.Button(self.parent, self.width, ...), UI.ROW + 2) end
function Column:Color(...) return self:Add(UI.Color(self.parent, self.width, ...), UI.ROW + 2) end

-- Colour picker: a button with a swatch; click opens a small palette with a
-- hex field. Own popup instead of Blizzard's ColorPickerFrame (opening that
-- from addon code goes through the UI panel manager and can taint it).
-- get() returns { r, g, b } (0..1), set(c) receives a new table.
local PALETTE = {
    { 1, 1, 1 }, { 0.85, 0.85, 0.85 }, { 0.65, 0.65, 0.65 }, { 0.45, 0.45, 0.45 }, { 0.25, 0.25, 0.25 }, { 0, 0, 0 },
    { 1, 0.82, 0 }, { 1, 0.95, 0.4 }, { 1, 0.6, 0.15 }, { 1, 0.3, 0.3 }, { 0.8, 0.1, 0.1 }, { 1, 0.5, 0.75 },
    { 0.31, 0.70, 1 }, { 0.55, 0.85, 1 }, { 0.2, 0.9, 0.9 }, { 0.2, 0.6, 0.6 }, { 0.6, 0.45, 1 }, { 0.75, 0.3, 0.9 },
    { 0.3, 1, 0.3 }, { 0.6, 1, 0.6 }, { 0.2, 0.65, 0.2 }, { 0.6, 0.6, 0.2 }, { 0.65, 0.45, 0.25 }, { 0.4, 0.25, 0.1 },
}
local SW, SW_GAP, SW_COLS = 18, 4, 6
local colorPopup

local function ToHex(c)
    return ("%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end
UI.ColorHex = ToHex

local function ColorPopup()
    if colorPopup then return colorPopup end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()

    local p = CreateFrame("Frame", "MMTColorPopup", UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(catcher:GetFrameLevel() + 10)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    local rows = math.ceil(#PALETTE / SW_COLS)
    p:SetSize(SW_COLS * (SW + SW_GAP) - SW_GAP + 16, rows * (SW + SW_GAP) - SW_GAP + 16 + 26)
    UI.Fill(p, 0.07, 0.07, 0.08, 0.98)
    UI.Border(p, A[1], A[2], A[3], 0.5)
    for i, c in ipairs(PALETTE) do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(SW, SW)
        local col, row = (i - 1) % SW_COLS, math.floor((i - 1) / SW_COLS)
        b:SetPoint("TOPLEFT", 8 + col * (SW + SW_GAP), -8 - row * (SW + SW_GAP))
        UI.Fill(b, c[1], c[2], c[3], 1, "ARTWORK")
        UI.Border(b, 0.35, 0.35, 0.35, 1)
        Highlight(b)
        b:SetScript("OnClick", function()
            p:Hide()
            if p.onPick then p.onPick({ r = c[1], g = c[2], b = c[3] }) end
        end)
    end
    local hex = UI.EditBox(p, p:GetWidth() - 16, "hex, e.g. ffd100", function(text, box)
        local r, g, b = ns.Trim(text):match("^#?(%x%x)(%x%x)(%x%x)$")
        if not r then box:SetText("") return end
        p:Hide()
        if p.onPick then p.onPick({ r = tonumber(r, 16) / 255, g = tonumber(g, 16) / 255, b = tonumber(b, 16) / 255 }) end
    end)
    hex:SetPoint("BOTTOMLEFT", 8, 8)
    p.hex = hex
    p:SetScript("OnHide", function() catcher:Hide() end)
    catcher:SetScript("OnClick", function() p:Hide() end)
    UI.CloseOnEscape(p)
    p:Hide()
    p.catcher = catcher
    colorPopup = p
    return p
end

function UI.OpenColorPicker(owner, current, onPick)
    local p = ColorPopup()
    if p:IsShown() and p.owner == owner then p:Hide() return end
    p.owner, p.onPick = owner, onPick
    p.hex:SetText(current and ToHex(current) or "")
    p.hex:UpdatePlaceholder()
    p:ClearAllPoints()
    local bottom = owner:GetBottom() or 0
    if bottom * owner:GetEffectiveScale() < p:GetHeight() * p:GetEffectiveScale() + 20 then
        p:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 2)
    else
        p:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    end
    p.catcher:Show()
    p:Show()
end

function UI.Color(parent, width, text, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, UI.ROW - 2)
    UI.Fill(b, 0.12, 0.12, 0.12, 1)
    UI.Border(b, 0.25, 0.25, 0.25, 1)
    Highlight(b)
    local fs = UI.Label(b, text)
    fs:SetPoint("LEFT", 8, 0)
    local swatch = CreateFrame("Frame", nil, b)
    swatch:SetSize(28, 12)
    swatch:SetPoint("RIGHT", -6, 0)
    local fill = UI.Fill(swatch, 1, 1, 1, 1, "ARTWORK")
    UI.Border(swatch, 0.45, 0.45, 0.45, 1)
    local value = UI.Label(b, "")
    value:SetPoint("RIGHT", swatch, "LEFT", -6, 0)
    value:SetTextColor(0.6, 0.6, 0.6)
    b.Refresh = function()
        local c = get() or { r = 1, g = 1, b = 1 }
        fill:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1)
        value:SetText("#" .. ToHex(c))
    end
    b:SetScript("OnClick", function(self)
        UI.OpenColorPicker(self, get(), function(c)
            set(c)
            b.Refresh()
            ns.Refresh()
        end)
    end)
    Track(parent, b)
    return b
end

-- Escape closes the frame without registering it in Blizzard's UISpecialFrames
-- (that table is read by the protected game menu code and taints it).
-- The frame only swallows the Escape key; all other keys pass through.
function UI.CloseOnEscape(frame)
    frame:EnableKeyboard(true)
    local function Propagate(on)
        if not InCombatLockdown() and frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(on) end
    end
    Propagate(true) -- pass keys through by default (only Escape is ever kept)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            Propagate(false)
            self:Hide()
            C_Timer.After(0, function() Propagate(true) end)
        else
            Propagate(true)
        end
    end)
end

-- Small flat yes/no dialog (instead of Blizzard's StaticPopup, which taints).
local confirm
function UI.Confirm(text, acceptText, onAccept, cancelText)
    if not confirm then
        local f = CreateFrame("Frame", "MMTConfirmFrame", UIParent)
        f:SetSize(380, 130)
        f:SetPoint("TOP", 0, -160)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, 0.31, 0.70, 1.00, 0.6)
        f.text = UI.Label(f, "")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetPoint("TOPRIGHT", -16, -16)
        f.text:SetJustifyH("LEFT")
        f.accept = UI.Button(f, 150, "", function() f:Hide(); if f.onAccept then f.onAccept() end end)
        f.accept:SetPoint("BOTTOMLEFT", 16, 14)
        f.cancel = UI.Button(f, 150, "Cancel", function() f:Hide() end)
        f.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
        UI.CloseOnEscape(f)
        f:Hide()
        confirm = f
    end
    confirm.text:SetText(text)
    confirm.accept.label:SetText(acceptText or "Accept")
    confirm.cancel.label:SetText(cancelText or "Cancel")
    confirm.onAccept = onAccept
    confirm:Show()
end

-- Shift-click item links into an edit box: while the box has focus,
-- shift-clicking an item anywhere (bags, loot, character, chat links, ...)
-- puts its link into the box. Hooks only observe the game's link insert
-- (hooksecurefunc), so Blizzard's code is never replaced.
local linkTargets = {}
local hooked = false
local lastLink, lastTime

local function OnInsertLink(link)
    if type(link) ~= "string" or ns.IsSecret(link) or not link:find("|Hitem:", 1, true) then return end
    if link == lastLink and lastTime and GetTime() - lastTime < 0.2 then return end -- both hooks fired
    for box in pairs(linkTargets) do
        if box:IsVisible() and box:HasFocus() then
            lastLink, lastTime = link, GetTime()
            box:SetText(link)
            if box.UpdatePlaceholder then box:UpdatePlaceholder() end
            if box.onLink then box.onLink(link, box) end
            return
        end
    end
end

function UI.AcceptItemLinks(box, onLink)
    linkTargets[box] = true
    box.onLink = onLink
    if hooked then return end
    hooked = true
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink) end
end
