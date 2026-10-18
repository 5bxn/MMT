-- MMT: accept group invites from team members, friends, Battle.net friends
-- and guild members.

local _, ns = ...

local function IsTeam(name, guid)
    if ns.Resolve(name) then return true end
    if guid then
        local _, _, _, _, _, first, last = ns.Safe(GetPlayerInfoByGUID, guid)
        if first and ns.Resolve(last and last ~= "" and (first .. "-" .. last) or first) then return true end
    end
    return false
end

local function Relation(guid, name)
    local cfg = ns.db.invites
    if cfg.team and IsTeam(name, guid) then return "team member" end
    if not guid then return nil end
    if cfg.friends and C_FriendList and ns.Safe(C_FriendList.IsFriend, guid) then
        return "friend"
    end
    if cfg.bnet and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID
        and ns.Safe(C_BattleNet.GetGameAccountInfoByGUID, guid) then
        return "Battle.net friend"
    end
    if cfg.guild and IsInGuild() and ns.Safe(IsGuildMember, guid) then
        return "guild member"
    end
    return nil
end

ns.On("PARTY_INVITE_REQUEST", function(name, _, _, _, _, _, inviterGUID)
    local who = ns.NameFromGUID(inviterGUID, name)
    ns.Debug("INVITE from %s (name %s, guid %s)", who, ns.Repr(name), tostring(inviterGUID))

    local relation = Relation(inviterGUID, name)
    if not relation then return end

    -- the game closes its invite popup itself once you're in the group;
    -- closing it from addon code (StaticPopup_Hide) would taint Blizzard's popups
    AcceptGroup()
    ns.Print("Accepted group invite from %s (%s).", who, relation)
end)

---------------------------------------------------------------------------
-- Invite on whisper keyword
---------------------------------------------------------------------------
local lastInvite = {}

ns.On("CHAT_MSG_WHISPER", function(text, sender)
    local cfg = ns.db.invites
    if not cfg.whisper or not cfg.keyword or cfg.keyword == "" then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= "string" then return end
    if ns.Trim(text):lower() ~= cfg.keyword:lower() or ns.IsSelf(sender) then return end
    if lastInvite[sender] and GetTime() - lastInvite[sender] < 5 then return end
    lastInvite[sender] = GetTime()

    local who = ns.StripRealm(sender):gsub("-", " ")
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        ns.Print("%s whispered the invite keyword, but only the group leader can invite.", who)
        return
    end
    if GetNumGroupMembers() >= (IsInRaid() and 40 or 5) then
        ns.Print("%s whispered the invite keyword, but the group is full.", who)
        return
    end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local ok, err = pcall(invite, sender)
    ns.Debug("INVITE by keyword: %s -> %s %s", ns.Repr(sender), tostring(ok), tostring(err or ""))
    if ok then ns.Print("Invited %s (whispered the keyword).", who) end
end)
