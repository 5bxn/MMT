-- MMT: FTL (Focusless, Targetless, Leaderless), after the ISBoxer feature.
--
-- Macros written in MMT with {FTL} (e.g. "/follow {FTL}") become real WoW
-- macros in which {FTL} is the character you are playing right now, "the
-- leader". When the leader changes, every client rewrites its macros.
--
-- WoW lets addons change macros only outside combat: a leader change in
-- combat is applied as soon as combat ends (ISBoxer can switch in combat
-- because it sends modifier keys from outside the game).
--
-- The leader is set by
--   * a left-click on a character in the XP window,
--   * the key binding "MMT: Make this character the leader",
--   * /mmt leader (this character) or /mmt leader <name>,
--   * automatically when you move a character that isn't following (setting).
-- and sent to the team: FTL:<server time>:<team key> (the newest wins).
-- The leader is kept account-wide (MMTDB.ftl), so a /reload keeps it.

local _, ns = ...

local MAX_GLOBAL_MACROS = MAX_ACCOUNT_MACROS or 120
local DEFAULT_ICON = "INV_Misc_QuestionMark"

local pending = false   -- macros to update once combat ends

local function State()
    MMTDB.ftl = MMTDB.ftl or {}
    MMTDB.ftl.managed = MMTDB.ftl.managed or {}   -- [macro name] = true for macros MMT created
    return MMTDB.ftl
end

function ns.FTLLeader()
    return MMTDB and MMTDB.ftl and MMTDB.ftl.leader
end

function ns.IsFTLLeader(key)
    local l = ns.FTLLeader()
    return l ~= nil and key ~= nil and ns.NormKey(l) == ns.NormKey(key)
end

---------------------------------------------------------------------------
-- {FTL} -> name of the leader
---------------------------------------------------------------------------
-- the text {FTL} stands for on this client, or nil (no leader known)
function ns.FTLName()
    local key = ns.FTLLeader()
    if not key then return nil end
    local fmt = ns.db.ftl.nameFormat
    if fmt == "FIRST" then return ns.FirstName(key) end
    if fmt == "UNIT" then
        if ns.IsSelf(key) then return "player" end
        return (ns.UnitForMember and ns.UnitForMember(key)) or ns.FullDisplay(key)
    end
    return ns.FullDisplay(key)
end

-- template -> macro text for this client; second value: true if cut at 255 characters
function ns.FTLResolve(body)
    local key = ns.FTLLeader()
    local name = ns.FTLName()
    local skip = key and ns.IsSelf(key) and ns.db.ftl.skipSelf
    local lines = {}
    for line in ((body or "") .. "\n"):gmatch("(.-)\n") do
        if line:find("{FTL}", 1, true) then
            -- no leader yet, or the leader's own client: leave the line out
            if name and not skip then lines[#lines + 1] = (line:gsub("{FTL}", (name:gsub("%%", "%%%%")))) end
        else
            lines[#lines + 1] = line
        end
    end
    local text = table.concat(lines, "\n")
    if #text > 255 then return text:sub(1, 255), true end
    return text, false
end

---------------------------------------------------------------------------
-- Writing the WoW macros (account macros of this client)
---------------------------------------------------------------------------
local function GlobalMacroCount()
    local n = GetNumMacros and GetNumMacros() or 0
    return n
end

-- returns a short status for the settings page
function ns.FTLUpdateMacros(reason)
    if not ns.db or not ns.db.ftl then return end
    if InCombatLockdown() then
        pending = true
        return "combat"
    end
    pending = false
    if not (CreateMacro and EditMacro and GetMacroIndexByName) then return "no macro API" end
    local st = State()
    local cfg = ns.db.ftl
    local wanted = {}
    if cfg.enabled then
        for _, m in ipairs(cfg.macros or {}) do
            local name = ns.Trim(m.name or "")
            if name ~= "" then
                wanted[name] = true
                local text = ns.FTLResolve(m.body)
                local icon = (m.icon and m.icon ~= "") and m.icon or DEFAULT_ICON
                local index = GetMacroIndexByName(name)
                if not index or index == 0 then
                    if GlobalMacroCount() < MAX_GLOBAL_MACROS then
                        local ok, err = pcall(CreateMacro, name, icon, text, nil)
                        ns.Debug("FTL: create macro %s -> %s %s", ns.Repr(name), tostring(ok), tostring(err or ""))
                        if ok then st.managed[name] = true end
                    else
                        ns.Print("FTL: no room for the macro \"%s\" (the account macros are full).", name)
                    end
                else
                    st.managed[name] = true
                    local current = GetMacroBody and GetMacroBody(index)
                    if current ~= text then
                        local ok, err = pcall(EditMacro, index, name, icon, text)
                        ns.Debug("FTL: edit macro %s -> %s %s", ns.Repr(name), tostring(ok), tostring(err or ""))
                    end
                end
            end
        end
    end
    -- macros MMT created that are no longer wanted (deleted, renamed, FTL off)
    for name in pairs(st.managed) do
        if not wanted[name] then
            local index = GetMacroIndexByName(name)
            if index and index > 0 and DeleteMacro then pcall(DeleteMacro, index) end
            st.managed[name] = nil
            ns.Debug("FTL: removed macro %s", ns.Repr(name))
        end
    end
    ns.Fire("FTL_MACROS_CHANGED", reason)
    return "ok"
end

-- put a macro on the cursor (to drag it to an action bar)
function ns.FTLPickup(name)
    if InCombatLockdown() then ns.Print("Not in combat.") return end
    local index = GetMacroIndexByName and GetMacroIndexByName(name)
    if index and index > 0 and PickupMacro then PickupMacro(index) end
end

---------------------------------------------------------------------------
-- Leader
---------------------------------------------------------------------------
local function Now() return (GetServerTime and GetServerTime()) or time() end

local function Send(msg, target)
    if target then ns.SendAddon(msg, "WHISPER", target, "ALERT")
    elseif ns.SendToTeam then ns.SendToTeam(msg, true, "ALERT") end
end

-- key: team key of the new leader. fromTeam: the change came from another client.
function ns.SetFTLLeader(key, fromTeam, when)
    if not key or not ns.db then return end
    local st = State()
    when = when or Now()
    if st.leader and ns.NormKey(st.leader) == ns.NormKey(key) then
        st.time = math.max(st.time or 0, when)
        return
    end
    if fromTeam and st.time and when < st.time then return end   -- an older change
    st.leader, st.time = key, when
    ns.Debug("FTL: leader %s (%s)", ns.Repr(key), fromTeam and "from team" or "here")
    local status = ns.FTLUpdateMacros("leader")
    if ns.db.ftl.announce then
        if status == "combat" then
            ns.Print("FTL: %s is the leader now. The macros change when combat ends.", ns.FullDisplay(key))
        else
            ns.Print("FTL: %s is the leader now.", ns.FullDisplay(key))
        end
    elseif status == "combat" then
        ns.Print("FTL: the macros change to %s when combat ends.", ns.FullDisplay(key))
    end
    if not fromTeam then Send(("FTL:%d:%s"):format(when, key)) end
    ns.Fire("FTL_LEADER", key)
    ns.Fire("STATUS_CHANGED")
end

function ns.ClaimFTLLeader()
    local me = ns.PlayerFull()
    if me then ns.SetFTLLeader(me) end
end

-- key binding (Bindings.xml)
function MMT_FTL_SetLeader()
    if ns.ready and ns.db and ns.db.ftl.enabled then ns.ClaimFTLLeader() end
end
BINDING_HEADER_MMT = BINDING_HEADER_MMT or "MMT - Manage My Team"
BINDING_NAME_MMT_FTL_LEADER = "Make this character the leader (FTL)"

ns.Listen("TEAM_MESSAGE", function(key, sender, text)
    local when, who = text:match("^FTL:(%d+):(.+)$")
    if not when then return end
    local leader = ns.IsSelf(who) and ns.PlayerFull() or ns.Resolve(who)
    if leader then ns.SetFTLLeader(leader, true, tonumber(when)) end
end)

-- a member comes online: tell them who leads
ns.Listen("MEMBER_ONLINE", function(key, sender)
    local st = MMTDB.ftl
    if ns.db.ftl.enabled and st and st.leader then Send(("FTL:%d:%s"):format(st.time or Now(), st.leader), sender) end
end)

---------------------------------------------------------------------------
-- Automatic: moving a character that isn't following makes it the leader
---------------------------------------------------------------------------
local function Moving()
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    return speed and speed > 0
end

ns.On("PLAYER_STARTED_MOVING", function()
    local cfg = ns.db.ftl
    if not (cfg.enabled and cfg.detect == "MOVE") then return end
    if ns.IsFTLLeader(ns.PlayerFull()) then return end
    -- wait a moment: a short bump or the start of a follow doesn't count
    C_Timer.After(0.5, function()
        if ns.IsFollowing and ns.IsFollowing() then return end
        if UnitOnTaxi and UnitOnTaxi("player") then return end
        if not Moving() then return end
        if not ns.IsFTLLeader(ns.PlayerFull()) then ns.ClaimFTLLeader() end
    end)
end)

---------------------------------------------------------------------------
-- When the macros are (re)written
---------------------------------------------------------------------------
ns.On("PLAYER_REGEN_ENABLED", function()
    if pending then
        ns.FTLUpdateMacros("after combat")
        if ns.db.ftl.announce then ns.Print("FTL: macros updated after combat.") end
    end
end)
ns.On("GROUP_ROSTER_UPDATE", function()
    if ns.db.ftl.enabled and ns.db.ftl.nameFormat == "UNIT" then ns.FTLUpdateMacros("group") end
end)
ns.OnLogin(function() C_Timer.After(2, function() ns.FTLUpdateMacros("login") end) end)
ns.Listen("PROFILE_CHANGED", function() if ns.ready then ns.FTLUpdateMacros("profile") end end)
