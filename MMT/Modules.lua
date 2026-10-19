-- MMT: module system.
--
-- Modules are separate addons (folder MMT_<Name>, "## Dependencies: MMT" and
-- "## X-MMT-Module: 1" in their TOC), so they show up in the game's AddOns
-- list. The AddOns enable state is the single source of truth:
--   * switching a module off in /mmt stops it right away and disables the
--     addon for the next login,
--   * switching it on starts it right away if it is loaded, otherwise it is
--     enabled in the AddOns list and loads after a UI reload.
--
-- A module calls MMT.NewModule{ name, title, description, defaults,
-- OnEnable, OnDisable, OnProfileChanged, Page(m, frame), Report(m, add), sync } and gets:
--   sync = true            share m.db with the team: "Sync to team" button
--                          on its page and /mmt sync <name> (m.store is never sent)
--   syncExclude = { keys } settings in m.db that stay on each client (window
--                          positions, per-machine options); not sent, not overwritten
--   OnSyncReceived(m, from) optional: runs after the team's settings were applied
--                          (OnProfileChanged runs before it, as on a profile switch)
--   m:SyncToTeam()         sends the settings (what the button does)
--   m:SyncButton(frame)    the button, for pages the core doesn't build
--   m.db        its settings in the active profile (profile.modules[name])
--   m.store     account-wide storage (MMTDB.moduleData[name])
--   m:On(event, fn) / m:Listen(callback, fn)   only run while enabled
--   m:Heartbeat(key, fn)   adds key=value to the team heartbeat

local _, ns = ...

ns.modules = {}       -- [name] = module
ns.moduleList = {}    -- registration order

local AddOns = C_AddOns or {}
local GetNumAddOns = AddOns.GetNumAddOns or GetNumAddOns
local GetAddOnInfo = AddOns.GetAddOnInfo or GetAddOnInfo
local GetMetadata = AddOns.GetAddOnMetadata or GetAddOnMetadata
local IsLoaded = AddOns.IsAddOnLoaded or IsAddOnLoaded
local EnableAddOn = AddOns.EnableAddOn or EnableAddOn
local DisableAddOn = AddOns.DisableAddOn or DisableAddOn

local function EnableState(addon)
    if AddOns.GetAddOnEnableState then
        return AddOns.GetAddOnEnableState(addon, UnitGUID("player")) or 0
    end
    return GetAddOnEnableState and GetAddOnEnableState(UnitName("player"), addon) or 0
end

---------------------------------------------------------------------------
-- Heartbeat extensions ("key=value,key=value" in the XP message)
---------------------------------------------------------------------------
local heartbeat = {}   -- { key, fn, module }

function ns.HeartbeatExtra()
    local parts = {}
    for _, h in ipairs(heartbeat) do
        if not h.module or h.module.enabled then
            local ok, v = pcall(h.fn)
            if ok and v ~= nil and v ~= "" then parts[#parts + 1] = h.key .. "=" .. tostring(v) end
        end
    end
    return table.concat(parts, ",")
end

function ns.ParseHeartbeatExtra(s)
    local t = {}
    if not s or s == "" then return t end
    if s:match("^%d+$") then t.eq = s return t end -- MMT 0.3.0 sent the equipment hash here
    for k, v in s:gmatch("(%w+)=([^,]*)") do t[k] = v end
    return t
end

---------------------------------------------------------------------------
-- Module objects
---------------------------------------------------------------------------
local Module = {}
Module.__index = Module

function Module:On(event, fn)
    ns.On(event, function(...) if self.enabled then fn(...) end end)
end

function Module:Listen(name, fn)
    ns.Listen(name, function(...) if self.enabled then fn(...) end end)
end

function Module:Heartbeat(key, fn)
    heartbeat[#heartbeat + 1] = { key = key, fn = fn, module = self }
end

function Module:Debug(fmt, ...) ns.Debug("[" .. self.name .. "] " .. fmt, ...) end

-- Settings sync (sync = true). The core adds the button to pages it builds
-- (m.Page); call m:SyncButton(frame) yourself only for a frame of your own.
function Module:SyncToTeam()
    if not self.sync then
        ns.Print("%s doesn't share its settings (sync = true is missing in MMT.NewModule).", self.title)
        return false
    end
    return ns.SendModuleSettings(self)
end

function Module:SyncButton(frame)
    if not self.sync or frame.mmtSyncButton then return frame.mmtSyncButton end
    frame.mmtSyncButton = ns.UI.SyncButton(frame, "Sync to team", function() self:SyncToTeam() end,
        "Sync " .. self.title .. " settings",
        ("Same as /mmt sync %s: sends only the %s settings of your active profile to your group and online team members. Each of them gets a dialog to accept them. Core settings and other modules are not touched."):format(self.name:lower(), self.title))
    return frame.mmtSyncButton
end

-- the settings that travel: m.db without syncExclude keys
function Module:SyncData()
    local data = ns.CopyTable(self.db)
    for _, k in ipairs(self.syncExclude or {}) do data[k] = nil end
    return data
end

local function Bind(m)
    -- settings live in the active profile, storage is account-wide
    ns.db.modules = ns.db.modules or {}
    ns.db.modules[m.name] = ns.db.modules[m.name] or {}
    ns.MergeDefaults(ns.db.modules[m.name], m.defaults or {})
    m.db = ns.db.modules[m.name]
    MMTDB.moduleData = MMTDB.moduleData or {}
    MMTDB.moduleData[m.name] = MMTDB.moduleData[m.name] or {}
    m.store = MMTDB.moduleData[m.name]
end

local function Start(m)
    if m.enabled then return end
    m.enabled = true
    if m.OnEnable then
        local ok, err = pcall(m.OnEnable, m)
        if not ok then ns.Debug("module %s OnEnable error: %s", m.name, tostring(err)) end
    end
end

local function Stop(m)
    if not m.enabled then return end
    m.enabled = false
    if m.OnDisable then
        local ok, err = pcall(m.OnDisable, m)
        if not ok then ns.Debug("module %s OnDisable error: %s", m.name, tostring(err)) end
    end
end

function ns.NewModule(def)
    assert(type(def) == "table" and def.name, "MMT.NewModule needs a name")
    local m = setmetatable(def, Module)
    m.addon = m.addon or ("MMT_" .. m.name)
    m.title = m.title or m.name
    m.enabled = false
    ns.modules[m.name] = m
    ns.moduleList[#ns.moduleList + 1] = m
    if ns.ready then Bind(m) Start(m) end -- loaded after login (e.g. LoadAddOn)
    return m
end

-- called by the core at login and on every profile change
ns.OnLogin(function()
    for _, m in ipairs(ns.moduleList) do
        Bind(m)
        Start(m)
    end
end)

ns.Listen("PROFILE_CHANGED", function()
    if not ns.ready then return end
    for _, m in ipairs(ns.moduleList) do
        Bind(m)
        if m.enabled and m.OnProfileChanged then pcall(m.OnProfileChanged, m) end
    end
end)

---------------------------------------------------------------------------
-- Installed modules (also those that aren't loaded)
---------------------------------------------------------------------------
-- returns a list of { addon, title, notes, loaded, enabled (AddOns list), module, reason }
function ns.InstalledModules()
    local list, seen = {}, {}
    for i = 1, (GetNumAddOns and GetNumAddOns() or 0) do
        local name, title, notes, _, reason = GetAddOnInfo(i)
        if name and GetMetadata(name, "X-MMT-Module") then
            local m
            for _, mod in ipairs(ns.moduleList) do if mod.addon == name then m = mod end end
            list[#list + 1] = {
                addon = name,
                title = (m and m.title) or GetMetadata(name, "X-MMT-Title") or title or name,
                notes = (m and m.description) or notes or "",
                loaded = IsLoaded(name) and true or false,
                enabled = EnableState(name) > 0,
                module = m,
                reason = reason,
            }
            seen[name] = true
        end
    end
    -- modules that registered without being found in the list (shouldn't happen)
    for _, m in ipairs(ns.moduleList) do
        if not seen[m.addon] then
            list[#list + 1] = { addon = m.addon, title = m.title, notes = m.description or "",
                loaded = true, enabled = true, module = m }
        end
    end
    table.sort(list, function(a, b) return a.title < b.title end)
    return list
end

-- on = true/false. Returns "active", "stopped" or "reload".
function ns.SetModuleEnabled(entry, on)
    if on then
        EnableAddOn(entry.addon)
        if entry.module then
            Start(entry.module)
            ns.Refresh()
            return "active"
        end
        ns.reloadNeeded = true
        return "reload"
    end
    DisableAddOn(entry.addon)
    if entry.module then Stop(entry.module) end
    ns.Refresh()
    return "stopped"
end

---------------------------------------------------------------------------
-- Settings sync of modules (modules opt in with sync = true in NewModule)
---------------------------------------------------------------------------
-- loaded modules that can share their settings
function ns.SyncableModules()
    local l = {}
    for _, m in ipairs(ns.moduleList) do
        if m.sync and m.db then l[#l + 1] = m end
    end
    return l
end

-- finds a syncable module by name or title, case and spaces ignored,
-- also by the start of it ("quest" -> Quest Tracker)
function ns.FindSyncModule(text)
    local want = ns.NormKey(text)
    if want == "" then return nil end
    local found
    for _, m in ipairs(ns.SyncableModules()) do
        local n, t = ns.NormKey(m.name), ns.NormKey(m.title)
        if n == want or t == want then return m end
        if n:sub(1, #want) == want or t:sub(1, #want) == want then
            if found and found ~= m then return nil, true end -- ambiguous
            found = m
        end
    end
    return found
end

-- replaces the module's settings in the active profile; syncExclude keys
-- keep this client's values. from = full name of the sender (or nil).
function ns.ImportModuleSettings(name, data, from)
    local m = ns.modules[name]
    if not m or type(data) ~= "table" then return false end
    ns.db.modules = ns.db.modules or {}
    local old = ns.db.modules[name] or {}
    for _, k in ipairs(m.syncExclude or {}) do data[k] = old[k] end
    ns.db.modules[name] = data
    Bind(m)
    if m.enabled and m.OnProfileChanged then
        local ok, err = pcall(m.OnProfileChanged, m)
        if not ok then ns.Debug("module %s OnProfileChanged error: %s", m.name, tostring(err)) end
    end
    if m.OnSyncReceived then
        local ok, err = pcall(m.OnSyncReceived, m, from)
        if not ok then ns.Debug("module %s OnSyncReceived error: %s", m.name, tostring(err)) end
    end
    ns.Refresh()
    return true
end

function ns.ModuleActive(name)
    local m = ns.modules[name]
    return m and m.enabled or false
end
