-- MMT Loot Distribution: settings page (under MODULES in /mmt) and debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X, PAGE_W = H.COL_W, H.COL2_X, H.PAGE_W
local StatusLine = H.StatusLine

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v end
end

M.Page = function(_, page)
    local status

    -- left: loot method ---------------------------------------------------
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Loot method")
    local ga, sa = Opt("autoMethod")
    L:Check("Set loot method automatically", ga, sa,
        "When a group forms or one of your team characters becomes leader, that character sets the method and threshold below. Only the group leader can change loot settings.")
    local gm, sm = Opt("method")
    L:Cycle("Method", {
        { value = "freeforall", text = "Free for All" },
        { value = "roundrobin", text = "Round Robin" },
        { value = "master", text = "Master Looter" },
    }, gm, sm)
    local qualities = {}
    for q = 0, 5 do qualities[#qualities + 1] = { value = q, text = MMT.QualityName(q) } end
    local gt, st = Opt("threshold")
    L:Cycle("Threshold", qualities, gt, st)
    local gl, sl = Opt("looter")
    local looter = L:Cycle("Master looter", function()
        local l = { { value = "LEADER", text = "Group leader" } }
        for _, key in ipairs(MMT.SortedMembers()) do l[#l + 1] = { value = key, text = MMT.FirstName(key) } end
        return l
    end, gl, sl)
    MMT.HoverMember(looter, function() return M.db.looter ~= "LEADER" and M.db.looter or nil end)
    L:Space(4)
    L:Button("Apply now", function()
        local ok, err = mod.ApplyLootSettings(true)
        status.Show_(ok and "Loot settings applied." or err, not ok)
    end)
    status = StatusLine(page)
    status:SetWidth(COL_W)
    L:Add(status, 20)
    local current = L:Note("")

    -- right: master loot by roles -------------------------------------------
    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Master loot by roles")
    local masterOnly = {}
    local gr, sr = Opt("byRoles")
    masterOnly[#masterOnly + 1] = R:Check("Give items by roles", gr, sr,
        "As master looter, items at or above the threshold go to the team member whose roles want them (see Roles). Several members with that role: the first one in team order who has room.")
    local gres, sres = Opt("reserve")
    masterOnly[#masterOnly + 1] = R:Slider("Keep free bag slots", 0, 20, 1, gres, sres)
    local gu, su = Opt("unassigned")
    masterOnly[#masterOnly + 1] = R:Cycle("No role wants it", {
        { value = "LEAVE", text = "Leave for manual" },
        { value = "SELF", text = "Give to master looter" },
        { value = "RR", text = "Round robin to the team" },
    }, gu, su)
    local grr, srr = Opt("rrNotice")
    masterOnly[#masterOnly + 1] = R:Check("Say so in chat (round robin)", grr, srr,
        "Prints \"[Item] is not part of any role or rule, so it was given round robin to <Name>.\" (only for you). Round robin keeps the free bag slots above; quest items are never part of it.")
    local grep, srep = Opt("report")
    masterOnly[#masterOnly + 1] = R:Check("Report in chat", grep, srep, "Prints each item given and the loot settings that were applied (only for you).")
    masterOnly[#masterOnly + 1] = R:Note("Bind on Pickup items are never given out or looted: they are posted in group chat, and the master looter assigns them by hand. Items without loaded item data are left alone, too.")
    local hint = R:Note("")

    R:Header("Quest items")
    local gq, sq = Opt("questRR")
    masterOnly[#masterOnly + 1] = R:Check("Auto-Round Robin quest items", gq, sq,
        "As master looter, quest items go to the team members in turns, in team order. Only characters the game offers for the item (on the quest and able to receive it) get a turn. Turns are kept per item, so drops spread evenly. The free bag slots setting doesn't apply: quest items are given even into the last slot.")

    page.OnRefresh = function()
        local method, partyIndex = mod.GetMethod()
        local text = IsInGroup() and ("Current: " .. (mod.METHOD_TEXT[method] or tostring(method)))
            or "Not in a group."
        if IsInGroup() and method and method ~= "freeforall" then
            local t = mod.GetThreshold()
            if t then text = text .. ", from " .. MMT.QualityName(t) end
        end
        if IsInGroup() and method == "master" then
            text = text .. (mod.IsMasterLooter() and " (you are master looter)" or "")
        end
        current:SetText(text)
        local isMaster = M.db.method == "master"
        for _, w in ipairs(masterOnly) do w:SetAlpha(isMaster and 1 or 0.4) end
        looter:SetAlpha(isMaster and 1 or 0.4)
        hint:SetText(isMaster and "" or "These options only apply with Master Looter.")
    end
    M:On("PARTY_LOOT_METHOD_CHANGED", function() if page:IsVisible() then page.OnRefresh() end end)
end

function M.Report(_, add)
    local method, partyIndex, raidIndex = mod.GetMethod()
    add(("-- Loot Distribution  current=%s partyML=%s raidML=%s threshold=%s isMaster=%s leader=%s"):format(
        tostring(method), tostring(partyIndex), tostring(raidIndex), tostring(mod.GetThreshold()),
        tostring(mod.IsMasterLooter()), tostring(IsInGroup() and UnitIsGroupLeader("player"))))
    add(("settings: auto=%s method=%s threshold=%s looter=%s byRoles=%s reserve=%s unassigned=%s rrNotice=%s"):format(
        tostring(M.db.autoMethod), tostring(M.db.method), tostring(M.db.threshold), tostring(M.db.looter),
        tostring(M.db.byRoles), tostring(M.db.reserve), tostring(M.db.unassigned), tostring(M.db.rrNotice)))
    add("quest round robin=" .. tostring(M.db.questRR))
    for itemID, key in pairs(M.store.questRR or {}) do add(("  quest item %s: last given to %s"):format(tostring(itemID), MMT.Repr(key))) end
    for _, key in ipairs(MMT.SortedMembers()) do
        local s = MMT.status[key]
        add(("  %s free=%s roles=[%s]"):format(MMT.Repr(key), tostring(s and s.free), table.concat(MMT.MemberRoleList(key), ",")))
    end
end
