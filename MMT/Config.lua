-- MMT: configuration window (/mmt).
-- Navigation: CORE pages (always on), then MODULES: one entry per installed
-- module (greyed out when switched off) and "Manage modules".

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

local WIDTH, HEIGHT, NAV = 700, 620, 150
local window
local pages, coreOrder = {}, {}
local current

-- Core pages register themselves from ConfigPages.lua.
function ns.RegisterPage(key, title, build)
    pages[key] = { key = key, title = title, build = build }
    if key ~= "modules" then coreOrder[#coreOrder + 1] = key end
end

-- settings pages of loaded modules (m.Page(m, frame)), added when the window is built
local function RegisterModulePages()
    for _, m in ipairs(ns.moduleList) do
        if m.Page and not pages["mod:" .. m.name] then
            pages["mod:" .. m.name] = { key = "mod:" .. m.name, title = m.title, module = m,
                build = function(frame) m.Page(m, frame) end }
        end
    end
end

local function RefreshPage(page)
    if not page or not page.frame then return end
    for _, w in ipairs(page.frame.widgets) do w.Refresh() end
    if page.frame.OnRefresh then pcall(page.frame.OnRefresh) end
    if page.overlay then page.overlay:SetShown(not page.module.enabled) end
end

local function RefreshNav()
    if not window then return end
    for _, tab in ipairs(window.tabs) do tab.Update() end
    for _, wd in ipairs(window.navWidgets) do wd.Refresh() end
end

function ns.RefreshConfig()
    if window and window:IsShown() then
        RefreshPage(pages[current])
        RefreshNav()
    end
end
ns.OnRefresh(ns.RefreshConfig)
ns.Listen("TEAM_CHANGED", function() ns.RefreshConfig() end)
ns.Listen("ROLES_CHANGED", function() ns.RefreshConfig() end)

-- grey cover over the page of a switched-off module
local function Overlay(page, frame)
    local o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints()
    o:SetFrameLevel(frame:GetFrameLevel() + 30)
    o:EnableMouse(true)
    UI.Fill(o, 0.05, 0.05, 0.06, 0.85)
    local text = UI.Label(o, page.title .. " is switched off.", "GameFontNormal")
    text:SetPoint("TOP", 0, -120)
    local sub = UI.Label(o, "Its settings are kept. Switch it on to use and change them.")
    sub:SetPoint("TOP", text, "BOTTOM", 0, -8)
    sub:SetTextColor(0.6, 0.6, 0.6)
    local on = UI.Button(o, 160, "Switch on", function()
        for _, entry in ipairs(ns.InstalledModules()) do
            if entry.module == page.module then ns.SetModuleEnabled(entry, true) end
        end
        ns.RefreshConfig()
    end)
    on:SetPoint("TOP", sub, "BOTTOM", 0, -14)
    page.overlay = o
end

local function Select(key)
    if not pages[key] then key = "team" end
    current = key
    for k, page in pairs(pages) do
        local selected = (k == key)
        if selected and not page.frame then
            local frame = CreateFrame("Frame", nil, window)
            frame:SetPoint("TOPLEFT", NAV + 16, -44)
            frame:SetSize(WIDTH - NAV - 32, HEIGHT - 56)
            frame.widgets = {}
            page.build(frame)
            if page.module then Overlay(page, frame) end
            page.frame = frame
        end
        if page.frame then page.frame:SetShown(selected) end
    end
    window.pageTitle:SetText(pages[key].title)
    RefreshPage(pages[key])
    RefreshNav()
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
-- isOn(): nil = no on/off state, true/false = module state
local function Tab(parent, title, target, isOn)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV, 26)
    local bg = UI.Fill(b, 1, 1, 1, 0)
    local bar = b:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(A[1], A[2], A[3], 1)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(2)
    local label = UI.Label(b, title, "GameFontNormal")
    label:SetPoint("LEFT", 16, 0)
    local state = UI.Label(b, "")
    state:SetPoint("RIGHT", -10, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
    b.Update = function()
        local selected = (current == target)
        local on = isOn and isOn()
        bar:SetShown(selected)
        bg:SetColorTexture(1, 1, 1, selected and 0.06 or 0)
        if isOn and not on then
            label:SetTextColor(0.4, 0.4, 0.4)
            state:SetText("off")
            state:SetTextColor(0.4, 0.4, 0.4)
        else
            if selected then label:SetTextColor(1, 1, 1) else label:SetTextColor(0.65, 0.65, 0.65) end
            state:SetText("")
        end
    end
    b:SetScript("OnClick", function() Select(target) end)
    return b
end

local function SectionLabel(parent, text, y)
    local fs = UI.Label(parent, text)
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetTextColor(A[1], A[2], A[3], 0.8)
    return fs
end

local function Build()
    RegisterModulePages()
    local w = CreateFrame("Frame", "MMTConfigFrame", UIParent)
    w:SetSize(WIDTH, HEIGHT)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    UI.CloseOnEscape(w)
    w.tabs = {}

    UI.Fill(w, 0.05, 0.05, 0.06, 0.94)
    UI.Border(w, 0.22, 0.22, 0.24, 1)

    local nav = CreateFrame("Frame", nil, w)
    nav:SetPoint("TOPLEFT", 1, -1)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(NAV)
    UI.Fill(nav, 1, 1, 1, 0.025)
    local divider = w:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetPoint("TOPLEFT", nav, "TOPRIGHT")
    divider:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT")
    divider:SetWidth(1)

    local title = UI.Label(nav, "MMT", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetTextColor(A[1], A[2], A[3])
    local sub = UI.Label(nav, "Manage My Team")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetTextColor(0.6, 0.6, 0.6)

    local y = -58
    SectionLabel(nav, "CORE", y)
    y = y - 16
    for _, key in ipairs(coreOrder) do
        local tab = Tab(nav, pages[key].title, key)
        tab:SetPoint("TOPLEFT", 0, y)
        w.tabs[#w.tabs + 1] = tab
        y = y - 26
    end

    y = y - 12
    SectionLabel(nav, "MODULES", y)
    y = y - 16
    for _, entry in ipairs(ns.InstalledModules()) do
        local m = entry.module
        local target = (m and pages["mod:" .. m.name]) and ("mod:" .. m.name) or "modules"
        local tab = Tab(nav, entry.title, target, function()
            if m then return m.enabled end
            return false
        end)
        tab:SetPoint("TOPLEFT", 0, y)
        w.tabs[#w.tabs + 1] = tab
        y = y - 26
    end
    local manage = Tab(nav, "Manage modules", "modules")
    manage:SetPoint("TOPLEFT", 0, y)
    w.tabs[#w.tabs + 1] = manage

    -- footer: version (debug tools are on the Help page)
    nav.widgets = {}
    local version = UI.Label(nav, "v" .. ns.version)
    version:SetPoint("BOTTOMLEFT", 16, 12)
    version:SetTextColor(0.4, 0.4, 0.4)
    w.navWidgets = nav.widgets

    w.pageTitle = UI.Label(w, "", "GameFontNormalLarge")
    w.pageTitle:SetPoint("TOPLEFT", NAV + 16, -14)
    local close = UI.TextButton(w, "x", function() w:Hide() end, 20)
    close:SetPoint("TOPRIGHT", -8, -8)

    w:SetScript("OnShow", function()
        ns.configOpen = true
        Select(current or "team")
        if ns.UpdateDistanceVisibility then ns.UpdateDistanceVisibility() end
    end)
    w:SetScript("OnHide", function()
        w:SetFrameStrata("DIALOG")
        ns.configOpen = false
        if ns.UpdateDistanceVisibility then ns.UpdateDistanceVisibility() end
    end)
    return w
end

-- key: page key ("team", "xp", "modules", ...) or a module name
function ns.ToggleConfig(key)
    window = window or Build()
    RegisterModulePages()
    if key then
        if not pages[key] and pages["mod:" .. key] then key = "mod:" .. key end
        if pages[key] then
            current = key
            if window:IsShown() then Select(key) return end
        end
    end
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Game options entry (Esc > Options > AddOns > MMT)
---------------------------------------------------------------------------
ns.OnLogin(function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local t = UI.Label(panel, "MMT - Manage My Team", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    -- opens MMT on top of the game options (closing Blizzard's panel from addon code would taint it)
    local open = UI.Button(panel, 160, "Open settings", function()
        window = window or Build()
        window:SetFrameStrata("FULLSCREEN_DIALOG")
        window:Show()
    end)
    open:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "MMT")
    Settings.RegisterAddOnCategory(category)
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_MMT1 = "/mmt"
SlashCmdList.MMT = function(msg)
    local raw = ns.Trim(msg)
    local cmd, arg = raw:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if not ns.ready then return end
    if cmd == "" or cmd == "config" then
        ns.ToggleConfig()
    elseif cmd == "xp" then
        ns.ToggleXPWindow()
    elseif cmd == "trade" then
        ns.FillTrade(true)
    elseif cmd == "sync" then
        ns.SendProfileToTeam()
    elseif cmd == "ping" then
        ns.Ping()
    elseif cmd == "debug" then
        ns.HandleDebugCommand(arg)
    elseif cmd == "modules" then
        ns.ToggleConfig("modules")
    elseif cmd == "help" then
        ns.ToggleConfig("help")
    elseif cmd == "reset" then
        ns.ResetProfile()
        ns.Print("Profile \"%s\" reset to defaults.", ns.CurrentProfileName())
    else
        ns.Print("/mmt - open settings")
        ns.Print("/mmt xp - show/hide the XP window")
        ns.Print("/mmt trade - (re)fill the open trade window for the partner's roles")
        ns.Print("/mmt sync - send the active profile to your online team")
        ns.Print("/mmt ping - test whispering every team member by name")
        ns.Print("/mmt modules - show installed modules")
        ns.Print("/mmt help - debug tools and guides for writing modules")
        ns.Print("/mmt debug - debug tools (on, off, dump, log, clear, chat, name <text>)")
        ns.Print("/mmt reset - reset the active profile")
    end
end
