-- MMT: addon messages between the team's game clients (from MMT 0.1.x,
-- tested on WoW: Forever), extended with rested XP and layer.
--
-- Every client runs its own copy of MMT. Characters that play at the same
-- time are on different accounts, so every client has its own saved team.
-- A client only accepts XP messages from characters in ITS team.
-- Messages go to the party/raid, and by whisper to team members who are
-- not in the group.

local _, ns = ...

ns.status = {}   -- [teamKey] = { level, cur, max, rested, class, layer, layerKey, isMax, last, online, sender }
ns.recent = {}   -- last received addon messages (debug report)

local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage

local ONLINE_TIMEOUT = 90
local HEARTBEAT = 30

local RESULT = {
    [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage", [3] = "AddonMessageThrottle",
    [4] = "InvalidChatType", [5] = "NotInGroup", [6] = "TargetRequiredForChatType",
    [7] = "ChannelThrottle", [8] = "GeneralError",
}

local function Send(msg, channel, target)
    local ok, res = pcall(SendAddon, ns.prefix, msg, channel, target)
    if not ok then res = "error: " .. tostring(res) end
    ns.Debug("SEND %s %s %s -> %s %s", channel or "?", target and ns.Repr(target) or "",
        msg:sub(1, 40), tostring(res), RESULT[res] or "")
    return res
end

ns.SendAddon = Send

local function Note(line)
    local r = ns.recent
    r[#r + 1] = date("%H:%M:%S") .. " " .. line
    if #r > 15 then table.remove(r, 1) end
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
function ns.IsOnline(key)
    if ns.IsSelf(key) then return true end
    local s = ns.status[key]
    return s ~= nil and s.online and (GetTime() - s.last) < ONLINE_TIMEOUT
end

-- free slots in normal bags (profession bags don't count) and total slots
local function BagSpace()
    local free, total = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        local f, bagType = C_Container.GetContainerNumFreeSlots(bag)
        if slots > 0 and (bagType == nil or bagType == 0) then
            free, total = free + (f or 0), total + slots
        end
    end
    return free, total
end

-- average (all items) and lowest durability in percent, nil without items
local function Durability()
    local cur, max, lowest = 0, 0, nil
    for slot = 1, 18 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m and m > 0 then
            cur, max = cur + c, max + m
            local pct = c / m * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    if max == 0 then return nil, nil end
    return math.floor(cur / max * 100 + 0.5), math.floor(lowest + 0.5)
end

function ns.UpdateOwnStatus()
    local level = UnitLevel("player") or 0
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local _, class = UnitClass("player")
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    local isMax = level >= maxLevel or (IsXPUserDisabled and IsXPUserDisabled()) or false
    local s = {
        level = level, cur = cur, max = max, rested = GetXPExhaustion() or 0,
        class = class, layer = ns.layer, layerKey = ns.layerKey, isMax = isMax,
        last = GetTime(), online = true,
    }
    s.money = GetMoney()
    s.free, s.slots = BagSpace()
    s.durAvg, s.durMin = Durability()
    local key = ns.PlayerFull()
    if key then ns.status[key] = s end
    return s
end

-- The name to whisper: exactly as the game reported the sender last time
-- (that spelling is known to work), otherwise "First Last".
function ns.WhisperTarget(key)
    local s = ns.status[key]
    if s and s.sender then return s.sender end
    local m = ns.db.team[key]
    if m and m.name and m.last then return m.name .. " " .. m.last end
    return key
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function UnitInGroupByKey(key)
    local name = ns.FullDisplay(key)
    return UnitInParty(name) or UnitInRaid(name)
        or UnitInParty(ns.FirstName(key)) or UnitInRaid(ns.FirstName(key))
end

-- onlyOnline: whisper only members currently believed to be online
function ns.SendToTeam(msg, onlyOnline)
    if not ns.db then return end
    local channel
    if IsInRaid() then channel = "RAID" elseif IsInGroup() then channel = "PARTY" end
    if channel then Send(msg, channel) end
    for key in pairs(ns.db.team) do
        if not ns.IsSelf(key) and (not onlyOnline or ns.IsOnline(key)) then
            if not (channel and UnitInGroupByKey(key)) then
                Send(msg, "WHISPER", ns.WhisperTarget(key))
            end
        end
    end
end

-- XP2:level:cur:max:class:rested:isMax:layerKey:layer:moduleData:money:freeSlots:slots:durAvg:durMin
-- moduleData is "key=value,..." from modules (e.g. eq=<equipment hash>)
function ns.BuildXPMessage()
    local s = ns.UpdateOwnStatus()
    return ("XP2:%d:%d:%d:%s:%d:%d:%s:%s:%s:%d:%d:%d:%s:%s"):format(s.level, s.cur, s.max, s.class or "",
        s.rested, s.isMax and 1 or 0, s.layerKey or "", s.layer or "", ns.HeartbeatExtra(),
        s.money or 0, s.free or 0, s.slots or 0, s.durAvg or "", s.durMin or "")
end

function ns.BroadcastXP(onlyOnline)
    if not ns.db then return end
    ns.SendToTeam(ns.BuildXPMessage(), onlyOnline)
    ns.Fire("STATUS_CHANGED")
end

---------------------------------------------------------------------------
-- System messages: hide "No player named X is currently playing" for team
-- whispers (shown and logged while debugging or pinging).
---------------------------------------------------------------------------
local notFound
if ERR_CHAT_PLAYER_NOT_FOUND_S then
    notFound = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if not ns.db or type(msg) ~= "string" or ns.IsSecret(msg) then return end
        local window = ns.noFilterUntil and GetTime() < ns.noFilterUntil
        if window then ns.Debug("SYSTEM %s", msg:sub(1, 160)) end
        local who = notFound and msg:match(notFound)
        if not who then return end
        if window or MMTDB.debug then
            ns.Debug("  'player not found' for %s -> team key %s", ns.Repr(who), ns.Repr(ns.Resolve(who)))
            return
        end
        if ns.Resolve(who) then return true end
    end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local hinted = {}

local function HandleXP(key, sender, s)
    local old = ns.status[key]
    local wasOnline = old and old.online and (GetTime() - old.last) < ONLINE_TIMEOUT
    s.last, s.online, s.sender = GetTime(), true, sender
    if s.class and s.class ~= "" then ns.db.team[key].class = s.class end
    ns.status[key] = s
    ns.Fire("XP_RECEIVED", key, sender, s)
    if not wasOnline then
        -- they just came online: answer so they see us right away
        Send(ns.BuildXPMessage(), "WHISPER", sender)
    end
    ns.Fire("STATUS_CHANGED")
end

local function ParseXP(text)
    local level, cur, max, class = text:match("^XP:(%d+):(%d+):(%d+):(%a*)$") -- MMT 0.1.x
    if level then
        level, cur, max = tonumber(level), tonumber(cur), tonumber(max)
        return { level = level, cur = cur, max = max, rested = 0, class = class, isMax = max == 0 }
    end
    local f = { strsplit(":", text) }
    if f[1] ~= "XP2" then return nil end
    return {
        level = tonumber(f[2]) or 0, cur = tonumber(f[3]) or 0, max = tonumber(f[4]) or 0,
        class = f[5], rested = tonumber(f[6]) or 0, isMax = f[7] == "1",
        layerKey = (f[8] ~= "" and f[8]) or nil, layer = (f[9] ~= "" and f[9]) or nil,
        ext = ns.ParseHeartbeatExtra(f[10]),
        money = tonumber(f[11]), free = tonumber(f[12]), slots = tonumber(f[13]),
        durAvg = tonumber(f[14]), durMin = tonumber(f[15]),
    }
end

local function HintUnknown(sender)
    if hinted[sender] then return end
    hinted[sender] = true
    ns.Print("%s (in your group) runs MMT but is not in the team stored on THIS account.", sender)
    ns.Print("Open /mmt > Team > \"Add group\" here too, or accept a profile sent with /mmt sync from the other client.")
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= ns.prefix or not ns.db or type(text) ~= "string" or ns.IsSecret(text) then return end
    if ns.IsSelf(sender) then return end
    local fromGroup = channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT"
    local key = ns.Resolve(sender)
    Note(("%s %s %s %s"):format(tostring(channel), ns.Repr(sender), key and "(team)" or "(NOT in team)", text:sub(1, 30)))
    ns.Debug("RECV %s from %s %s %s", channel or "?", ns.Repr(sender),
        key and ("-> team key " .. ns.Repr(key)) or "-> not in team", text:sub(1, 40))

    -- connectivity test, answered for everybody
    local pv = text:match("^PING:(%d+)$")
    if pv then Send("PONG:" .. pv, "WHISPER", sender) return end
    local ov = text:match("^PONG:(%d+)$")
    if ov then ns.OnPong(key, sender, tonumber(ov)) return end

    local isSync = text:match("^SYNC") ~= nil   -- SYNC, SYNCHI, SYNCACK (Sync.lua)
    if not key then
        if fromGroup then HintUnknown(sender) end
        if not (isSync and fromGroup) then return end -- settings sync from group members is allowed
    end
    if isSync then ns.OnSyncMessage(key, sender, text, channel) return end

    local s = ParseXP(text)
    if s then
        if key then HandleXP(key, sender, s) end
        return
    end
    if text == "BYE" then
        local st = ns.status[key or sender]
        if st then st.online = false end
        ns.Fire("STATUS_CHANGED")
        return
    end
    if key then ns.Fire("TEAM_MESSAGE", key, sender, text) end -- item compare data etc.
end)

---------------------------------------------------------------------------
-- Ping: whispers every team member under three spellings of the name
-- and reports which one got an answer.
---------------------------------------------------------------------------
local VARIANT_LABEL = { "team key", "First Last (space)", "first name only" }
local pending

local function Variants(key)
    local m = ns.db.team[key]
    local first = (m and m.name) or key:match("^([^-]+)") or key
    local last = m and m.last
    return { key, last and (first .. " " .. last) or false, first }
end

function ns.OnPong(key, sender, variant)
    ns.Debug("PONG from %s variant %s %s", ns.Repr(sender), tostring(variant),
        key and ("-> team key " .. ns.Repr(key)) or "-> not in team")
    if key and pending and pending[key] and variant and pending[key][variant] ~= nil then
        pending[key][variant] = true
    end
    ns.Print("PONG from %s%s", tostring(sender), key and "" or " (not in this team)")
end

function ns.Ping()
    if not ns.db then return end
    pending = {}
    ns.noFilterUntil = GetTime() + 8
    local n = 0
    if IsInGroup() then Send("PING:0", IsInRaid() and "RAID" or "PARTY") end
    for key in pairs(ns.db.team) do
        if not ns.IsSelf(key) then
            n = n + 1
            pending[key] = {}
            for i, name in ipairs(Variants(key)) do
                if name then
                    pending[key][i] = false
                    Send("PING:" .. i, "WHISPER", name)
                end
            end
        end
    end
    if n == 0 and not IsInGroup() then
        ns.Print("No other team members to ping.")
        return
    end
    ns.Print("Ping sent to %d team member(s)%s, waiting for answers...", n, IsInGroup() and " and your group" or "")
    C_Timer.After(5, function()
        for key, vars in pairs(pending or {}) do
            local ok = {}
            for i = 1, 3 do if vars[i] then ok[#ok + 1] = VARIANT_LABEL[i] end end
            ns.Print("%s: %s", ns.FullDisplay(key), #ok > 0 and ("answered via " .. table.concat(ok, ", ")) or "NO answer")
        end
        ns.Print("No answer = other client offline, no MMT there, or the name was not accepted. Run /mmt debug dump on both clients.")
    end)
end

---------------------------------------------------------------------------
-- Events / heartbeat
---------------------------------------------------------------------------
ns.OnLogin(function()
    if RegisterPrefix then
        local ok = RegisterPrefix(ns.prefix)
        ns.Debug("RegisterAddonMessagePrefix returned %s", tostring(ok))
    end
    C_Timer.NewTicker(HEARTBEAT, function() ns.BroadcastXP(true) end)
end)

local lastBroadcast = 0
local function SoonBroadcast()
    if GetTime() - lastBroadcast < 1 then return end
    lastBroadcast = GetTime()
    ns.BroadcastXP(true)
end

-- gold, bags and durability change often: update the window now, tell the team a bit later
local soon = false
local function StatusChanged()
    ns.Fire("STATUS_CHANGED")
    if soon then return end
    soon = true
    C_Timer.After(5, function()
        soon = false
        ns.BroadcastXP(true)
    end)
end
ns.On("PLAYER_MONEY", StatusChanged)
ns.On("BAG_UPDATE_DELAYED", StatusChanged)
ns.On("UPDATE_INVENTORY_DURABILITY", StatusChanged)

ns.On("PLAYER_ENTERING_WORLD", function() ns.BroadcastXP(false) end)
ns.On("PLAYER_XP_UPDATE", SoonBroadcast)
ns.On("UPDATE_EXHAUSTION", SoonBroadcast)
ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(1, function() ns.BroadcastXP(true) end) end)
ns.On("PLAYER_LOGOUT", function() if ns.db then ns.SendToTeam("BYE", true) end end)
ns.Listen("TEAM_CHANGED", function() if ns.ready then ns.BroadcastXP(false) end end)
ns.Listen("LAYER_CHANGED", function() if ns.ready then ns.BroadcastXP(true) end end)
