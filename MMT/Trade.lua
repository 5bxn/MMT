-- MMT: when a trade opens with a team member, put every item that matches
-- that member's role rules into the trade window. Trades are never
-- accepted automatically. /mmt trade fills an open trade again.
--
-- Share among team (any number of roles): the items of each shared role are
-- split evenly between the members that have that role. Every member's client reports its
-- counts of those items; in a trade between two members, the one above the
-- even share gives the other what is missing (no more than it has above
-- its share). Per item: share = floor(total of the role members / number
-- of role members). Members not heard from count as 0.
--   SHC:<id>,<count>;<id>,<count>...:<role>   this character's counts (one
--                                            message per shared role it has)
--   SHQ                                      please send your counts
-- An item in several shared roles is shared by the first of them (by name).

local _, ns = ...

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local Pickup = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

local tradeOpen = false
local token = 0

local function GetItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return end
        return info.itemID, info.hyperlink, info.quality, info.isLocked, info.isBound
    end
    local tex, _, locked, quality, _, _, link, _, _, itemID, isBound = GetContainerItemInfo(bag, slot)
    if not tex then return end
    return itemID, link, quality, locked, isBound
end

-- soulbound / quest items can't be traded; the tooltip is the reliable check
local scanTip
local function IsUntradeable(bag, slot)
    local ok, result = pcall(function()
        if not scanTip then
            scanTip = CreateFrame("GameTooltip", "MMTScanTooltip", nil, "GameTooltipTemplate")
        end
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetBagItem(bag, slot)
        for i = 2, 7 do
            local fs = _G["MMTScanTooltipTextLeft" .. i]
            local text = fs and fs:GetText()
            if text and (text == ITEM_SOULBOUND or text == ITEM_BIND_QUEST) then return true end
        end
        return false
    end)
    return ok and result
end

local RuleMatches = function(...) return ns.RuleMatches(...) end

-- exclude(link or itemID): true = leave this item out
local function CollectItems(rules, exclude)
    local result = {}
    for bag = 0, ns.BAGS do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local itemID, link, quality, locked, bound = GetItem(bag, slot)
            if itemID and not locked and not (exclude and exclude(link or itemID)) then
                if not bound then bound = IsUntradeable(bag, slot) end
                if not bound then
                    local name, _, q, _, _, _, _, _, _, _, _, classID, subClassID, bindType = ns.ItemInfo(link or itemID)
                    if not classID then _, classID, subClassID = ns.ItemCategory(link or itemID) end
                    quality = quality or q
                    for _, rule in ipairs(rules) do
                        if RuleMatches(rule, itemID, name, quality, classID, bindType, subClassID) then
                            result[#result + 1] = { bag = bag, slot = slot, itemID = itemID }
                            break
                        end
                    end
                end
            end
        end
    end
    return result
end

-- Finds the trade partner in the team, trying every way the game exposes the name.
local function ResolvePartner()
    local n, r = ns.Safe(UnitFullName, "NPC")
    local frameName = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
    ns.Debug("TRADE partner: UnitFullName(npc)=%s / %s UnitName(npc)=%s frameText=%s",
        ns.Repr(n), ns.Repr(r), ns.Repr((ns.Safe(UnitName, "NPC"))), ns.Repr(frameName))
    local candidates = {}
    if n then
        candidates[#candidates + 1] = r and (n .. "-" .. r) or n
        candidates[#candidates + 1] = n
    end
    if frameName and frameName ~= "" and not ns.IsSecret(frameName) then candidates[#candidates + 1] = frameName end
    for _, c in ipairs(candidates) do
        local key = ns.Resolve(c)
        if key then
            ns.Debug("TRADE partner resolved via %s -> team key %s", ns.Repr(c), ns.Repr(key))
            return key
        end
    end
end

---------------------------------------------------------------------------
-- Share among team
---------------------------------------------------------------------------
-- the shared roles, sorted (deleted roles left out). Converts the single
-- role of MMT 0.9.19.
function ns.ShareRoles()
    if not ns.db then return {} end
    local t = ns.db.trade
    t.shareRoles = t.shareRoles or {}
    if type(t.shareRole) == "string" then
        if t.shareRole ~= "" then t.shareRoles[t.shareRole] = true end
        t.shareRole = nil
    end
    local l = {}
    for r, on in pairs(t.shareRoles) do if on and ns.db.roles[r] then l[#l + 1] = r end end
    table.sort(l)
    return l
end

local function HasRole(key, role)
    for _, r in ipairs(ns.MemberRoleList(key)) do if r == role then return true end end
    return false
end

function ns.ShareMembers(role)
    local l = {}
    for _, key in ipairs(ns.SortedMembers()) do if HasRole(key, role) then l[#l + 1] = key end end
    return l
end

-- this character's tradeable items of the role: counts [id] = n, stacks [id] = { {bag, slot, count} }
local function OwnShare(role)
    local counts, stacks = {}, {}
    for bag = 0, ns.BAGS do
        for slot = 1, (GetNumSlots(bag) or 0) do
            local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and ns.RoleWantsItem(role, info.hyperlink or info.itemID) then
                local id, n = info.itemID, info.stackCount or 1
                counts[id] = (counts[id] or 0) + n
                stacks[id] = stacks[id] or {}
                table.insert(stacks[id], { bag = bag, slot = slot, count = n, locked = info.isLocked })
            end
        end
    end
    return counts, stacks
end

-- last known counts of the team: MMTDB.shareCounts[key][role] = { items = { [id] = n }, at }
local function Known(key)
    MMTDB.shareCounts = MMTDB.shareCounts or {}
    local k = MMTDB.shareCounts[key]
    if not k or k.items then k = {} MMTDB.shareCounts[key] = k end   -- 0.9.19 kept one role
    return k
end

local function CountsOf(key, role, own)
    if ns.IsSelf(key) then return own or OwnShare(role) end
    local k = Known(key)[role]
    return k and k.items or {}
end

local function Encode(counts)
    local ids = {}
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = id .. "," .. counts[id] end
    return table.concat(parts, ";")
end

local lastSent = {}   -- [role] = message
local function SendShareCounts(force)
    local me = ns.PlayerFull()
    if not me then return end
    for _, role in ipairs(ns.ShareRoles()) do
        if HasRole(me, role) then
            local counts = OwnShare(role)
            Known(me)[role] = { items = counts, at = time() }
            local msg = ("SHC:%s:%s"):format(Encode(counts), role)
            if force or msg ~= lastSent[role] then
                lastSent[role] = msg
                if #msg > 240 and ns.SendLong then ns.SendLong(msg, nil, "NORMAL") else ns.SendToTeam(msg, true, "NORMAL") end
            end
        end
    end
end

local sendPending = false
local function SendSoon(force)
    if sendPending then return end
    sendPending = true
    C_Timer.After(2, function() sendPending = false SendShareCounts(force) end)
end

ns.Listen("TEAM_MESSAGE", function(key, sender, text)
    if text == "SHQ" then SendShareCounts(true) return end
    local list, role = text:match("^SHC:([%d,;]*):(.+)$")
    if not list then return end
    local items = {}
    for id, n in list:gmatch("(%d+),(%d+)") do items[tonumber(id)] = tonumber(n) end
    Known(key)[role] = { items = items, at = time() }
end)

ns.On("BAG_UPDATE_DELAYED", function() if ns.ready and #ns.ShareRoles() > 0 then SendSoon(false) end end)
ns.Listen("LOGIN", function() C_Timer.After(5, function()
    if #ns.ShareRoles() > 0 then SendShareCounts(true) ns.SendToTeam("SHQ", true, "NORMAL") end
end) end)
-- other roles chosen: everybody reports again
local reported = ""
ns.OnRefresh(function()
    if not ns.ready then return end
    local now = table.concat(ns.ShareRoles(), "\n")
    if now ~= reported then
        reported = now
        if now ~= "" then SendSoon(true) ns.SendToTeam("SHQ", true, "NORMAL") end
    end
end)

-- per item: { id, give, share, stacks } for this character -> partner;
-- done[id] = true: already shared by another role (skipped, then marked)
function ns.SharePlan(role, partner, done)
    done = done or {}
    local members = ns.ShareMembers(role)
    local own, stacks = OwnShare(role)
    local ids = {}
    for _, key in ipairs(members) do for id in pairs(CountsOf(key, role, own)) do ids[id] = true end end
    local plan = {}
    for id in pairs(ids) do
        if not done[id] then
            done[id] = true
            local total = 0
            for _, key in ipairs(members) do total = total + (CountsOf(key, role, own)[id] or 0) end
            local share = math.floor(total / #members)
            local partnerHas = CountsOf(partner, role, own)[id] or 0
            local give = math.min((own[id] or 0) - share, share - partnerHas)
            ns.Debug("SHARE %s item %d: total %d, %d members, share %d, mine %d, partner %d -> give %d",
                role, id, total, #members, share, own[id] or 0, partnerHas, math.max(0, give))
            if give > 0 then plan[#plan + 1] = { id = id, give = give, share = share, stacks = stacks[id] } end
        end
    end
    table.sort(plan, function(a, b) return a.id < b.id end)
    return plan
end

-- for the settings page: per shared role its members, per item total and share
function ns.ShareSummary(maxLines)
    maxLines = maxLines or 6
    local lines, done = {}, {}
    local roles = ns.ShareRoles()
    for _, role in ipairs(roles) do
        local members = ns.ShareMembers(role)
        if #members == 0 then
            lines[#lines + 1] = ("%s: nobody has the role (Roles page)"):format(role)
        else
            local totals = {}
            for _, key in ipairs(members) do
                for id, n in pairs(CountsOf(key, role)) do totals[id] = (totals[id] or 0) + n end
            end
            local ids = {}
            for id in pairs(totals) do if not done[id] then ids[#ids + 1] = id end end
            table.sort(ids)
            local parts = {}
            for _, id in ipairs(ids) do
                done[id] = true
                parts[#parts + 1] = ("%s %d each"):format(ns.ItemInfo(id) or ("item " .. id), math.floor(totals[id] / #members))
            end
            lines[#lines + 1] = ("%s (%d): %s"):format(role, #members, #parts > 0 and table.concat(parts, ", ") or "none carried")
        end
    end
    if #lines > maxLines then
        local more = #lines - maxLines + 1
        for _ = 1, more do table.remove(lines) end
        lines[#lines + 1] = ("+%d more roles"):format(more)
    end
    return table.concat(lines, "\n")
end

-- whole stacks (biggest first) while they fit, then a split of one more stack
local function StackActions(stacks, amount)
    local list = {}
    for _, st in ipairs(stacks or {}) do if not st.locked then list[#list + 1] = st end end
    table.sort(list, function(a, b) return a.count > b.count end)
    local actions, left, skipped = {}, amount, nil
    for _, st in ipairs(list) do
        if left <= 0 then break end
        if st.count <= left then
            actions[#actions + 1] = { bag = st.bag, slot = st.slot }
            left = left - st.count
        else
            skipped = st   -- the smallest stack bigger than what is left
        end
    end
    if left > 0 and skipped then actions[#actions + 1] = { bag = skipped.bag, slot = skipped.slot, split = left } end
    return actions
end

---------------------------------------------------------------------------
-- Filling the trade window
---------------------------------------------------------------------------
local function Run(actions)
    local limit = MAX_TRADABLE_ITEMS or 6
    local free = {}
    for s = 1, limit do
        if not GetTradePlayerItemLink(s) then free[#free + 1] = s end
    end
    local count = math.min(#actions, #free)
    token = token + 1
    local mine = token
    for i = 1, count do
        C_Timer.After(0.3 * (i - 1) + 0.1, function()
            if mine ~= token or not tradeOpen then return end
            local a = actions[i]
            ClearCursor()
            if a.split and C_Container and C_Container.SplitContainerItem then
                C_Container.SplitContainerItem(a.bag, a.slot, a.split)
            else
                Pickup(a.bag, a.slot)
            end
            if CursorHasItem() then ClickTradeButton(free[i]) end
            if CursorHasItem() then ClearCursor() end
        end)
    end
    return count, #actions - count
end

local function Fill(force)
    local partner = ResolvePartner()
    local member = partner and ns.db.team[partner]
    if not member then
        ns.Debug("TRADE partner is not a team member -> nothing to do")
        return
    end
    local who = ns.FullDisplay(partner)

    -- shared roles: only between two of their members
    local me = ns.PlayerFull()
    local sharing, done = {}, {}
    local actions, notes = {}, {}
    for _, role in ipairs(ns.ShareRoles()) do
        if me and HasRole(me, role) and HasRole(partner, role) then
            sharing[#sharing + 1] = role
            local parts = {}
            for _, p in ipairs(ns.SharePlan(role, partner, done)) do
                for _, a in ipairs(StackActions(p.stacks, p.give)) do actions[#actions + 1] = a end
                parts[#parts + 1] = ("%d x %s (%d each)"):format(p.give, ns.ItemInfo(p.id) or ("item " .. p.id), p.share)
            end
            if #parts > 0 then notes[#notes + 1] = role .. ": " .. table.concat(parts, ", ") end
        end
    end

    local shareCount = #actions
    local roleNames = {}
    if ns.db.trade.enabled or force then
        local rules = {}
        for _, r in ipairs(ns.MemberRoleList(partner)) do
            roleNames[#roleNames + 1] = r
            for _, rule in ipairs(ns.db.roles[r].rules) do rules[#rules + 1] = rule end
        end
        ns.Debug("TRADE roles: %s rules: %d", table.concat(roleNames, ","), #rules)
        if #rules > 0 then
            -- shared items are only given out by sharing
            local exclude = #sharing > 0 and function(item)
                for _, role in ipairs(sharing) do if ns.RoleWantsItem(role, item) then return true end end
            end or nil
            local items = CollectItems(rules, exclude)
            ns.Debug("TRADE matching stacks in bags: %d", #items)
            for _, it in ipairs(items) do actions[#actions + 1] = { bag = it.bag, slot = it.slot } end
        end
    end
    if #actions == 0 then return end

    local count, rest = Run(actions)
    if count == 0 then return end
    if #notes > 0 then ns.Print("Share with %s: %s.", who, table.concat(notes, "; ")) end
    if count > shareCount then
        ns.Print("%d stack(s) put into the trade with %s (%s).", count - shareCount, who, table.concat(roleNames, ", "))
    end
    if rest > 0 then
        ns.Print("%d more stack(s) did not fit. Trade again to hand over the rest.", rest)
    end
end

function ns.FillTrade(force)
    if not ns.db or not tradeOpen then
        if force then ns.Print("Open a trade with a team member first.") end
        return
    end
    local shared = #ns.ShareRoles() > 0
    if not ns.db.trade.enabled and not shared and not force then return end
    -- sharing: fresh counts first (the partner answers within a moment)
    if shared then
        ns.SendToTeam("SHQ", true, "ALERT")
        token = token + 1
        local mine = token
        C_Timer.After(1, function() if mine == token and tradeOpen then Fill(force) end end)
        return
    end
    Fill(force)
end

ns.On("TRADE_SHOW", function()
    tradeOpen = true
    ns.FillTrade(false)
end)

ns.On("TRADE_CLOSED", function()
    tradeOpen = false
    token = token + 1
end)
