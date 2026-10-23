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

local function GetNumSlots(bag) return ((C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots)(bag) end
local function Pickup(bag, slot) return ((C_Container and C_Container.PickupContainerItem) or PickupContainerItem)(bag, slot) end

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

---------------------------------------------------------------------------
-- Stacks for sharing
---------------------------------------------------------------------------
-- empty bag slots: plain bags first, then special bags (quiver, herb bag, ...)
local function EmptySlots()
    local plain, special = {}, {}
    for bag = 0, ns.BAGS do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, (GetNumSlots(bag) or 0) do
            if not C_Container.GetContainerItemID(bag, slot) then
                local t = (not family or family == 0) and plain or special
                t[#t + 1] = { bag = bag, slot = slot }
            end
        end
    end
    for _, e in ipairs(special) do plain[#plain + 1] = e end
    return plain
end

-- Plans how to hand over `amount` of one item in as few stacks as possible.
-- The trade window takes whole bag slots only (a split dropped on it brings
-- the whole stack), so the bags are re-stacked first:
--   1. full stacks go as they are; too few of them: partial stacks are
--      merged into full ones first,
--   2. the rest: a stack with exactly that many; else the biggest smaller
--      stack, topped up from the others (smallest first); else a part split
--      off into an empty bag slot.
-- Returns moves { from, to, n, whole } and trade entries { bag, slot, expect }
-- (plus a note when only part of it fits), or nil and a reason.
local function ShareStacks(id, stacks, amount, empties)
    local max = select(8, ns.ItemInfo(id))
    local list = {}
    for _, st in ipairs(stacks or {}) do
        if not st.locked then list[#list + 1] = { bag = st.bag, slot = st.slot, count = st.count } end
    end
    if not max or max < 1 then max = 1 end
    for _, st in ipairs(list) do if st.count > max then max = st.count end end
    local moves, trade = {}, {}
    local function Move(from, to, n)
        moves[#moves + 1] = { from = from, to = to, n = n, whole = n == from.count }
        from.count, to.count = from.count - n, to.count + n
    end
    local function Full()
        local l = {}
        for _, st in ipairs(list) do if st.count >= max and not st.used then l[#l + 1] = st end end
        return l
    end

    -- 1. full stacks (merge partial ones first when there are too few)
    local fulls, rest = math.floor(amount / max), amount % max
    if #Full() < fulls then
        table.sort(list, function(a, b) return a.count > b.count end)
        local i, j = 1, #list
        while i < j do
            local to, from = list[i], list[j]
            if to.count >= max then i = i + 1
            elseif from.count == 0 then j = j - 1
            else Move(from, to, math.min(from.count, max - to.count)) end
        end
    end
    local full = Full()
    if #full < fulls then return nil, "not enough in the bags" end
    for k = 1, fulls do
        full[k].used = true
        trade[#trade + 1] = { bag = full[k].bag, slot = full[k].slot, expect = max }
    end
    if rest == 0 then return moves, trade end

    -- 2. the rest
    local left = {}
    for _, st in ipairs(list) do if not st.used and st.count > 0 then left[#left + 1] = st end end
    table.sort(left, function(a, b) return a.count < b.count end)
    for _, st in ipairs(left) do
        if st.count == rest then
            trade[#trade + 1] = { bag = st.bag, slot = st.slot, expect = rest }
            return moves, trade
        end
    end
    local base
    for _, st in ipairs(left) do if st.count < rest then base = st end end   -- biggest smaller one
    if base then
        for _, src in ipairs(left) do
            if base.count >= rest then break end
            if src ~= base then Move(src, base, math.min(src.count, rest - base.count)) end
        end
        if base.count ~= rest then return nil, "not enough in the bags" end
        trade[#trade + 1] = { bag = base.bag, slot = base.slot, expect = rest }
        return moves, trade
    end
    local src = left[1]   -- the smallest stack, bigger than the rest
    if not src then return nil, "not enough in the bags" end
    local e = table.remove(empties, 1)
    if not e then
        -- the full stacks still go; the rest needs a free bag slot
        local note = ("no empty bag slot to split %d into"):format(rest)
        if #trade > 0 then return moves, trade, note end
        return nil, note
    end
    local to = { bag = e.bag, slot = e.slot, count = 0 }
    Move(src, to, rest)
    trade[#trade + 1] = { bag = e.bag, slot = e.slot, expect = rest }
    return moves, trade
end

---------------------------------------------------------------------------
-- Filling the trade window
---------------------------------------------------------------------------
-- puts one bag slot into a trade slot; with expect, only once the slot holds
-- that many (bag moves before it take a moment)
local function Place(a, tslot, mine, tries)
    if mine ~= token or not tradeOpen then return end
    if a.expect then
        local info = C_Container.GetContainerItemInfo(a.bag, a.slot)
        if not info or info.isLocked or info.stackCount ~= a.expect then
            if tries < 5 then
                C_Timer.After(0.4, function() Place(a, tslot, mine, tries + 1) end)
            else
                ns.Print("Share: re-stacking didn't work out (bag %d slot %d should hold %d); put them in by hand.", a.bag, a.slot, a.expect)
            end
            return
        end
    end
    ClearCursor()
    Pickup(a.bag, a.slot)
    if CursorHasItem() then ClickTradeButton(tslot) end
    if CursorHasItem() then ClearCursor() end
    -- the right amount in the slot? Otherwise take it back out.
    if a.expect then
        C_Timer.After(0.25, function()
            if mine ~= token or not tradeOpen or not GetTradePlayerItemInfo then return end
            local _, _, n = GetTradePlayerItemInfo(tslot)
            ns.Debug("TRADE slot %d: %s (wanted %d)", tslot, tostring(n), a.expect)
            if n and n ~= a.expect then
                ClearCursor()
                ClickTradeButton(tslot)        -- back onto the cursor
                if CursorHasItem() then ClearCursor() end   -- and into the bags
                ns.Print("Share: %d instead of %d landed in the trade, taken out again. Put %d in by hand.", n, a.expect, a.expect)
            end
        end)
    end
end

local function FreeTradeSlots()
    local free = {}
    for s = 1, (MAX_TRADABLE_ITEMS or 6) do
        if not GetTradePlayerItemLink(s) then free[#free + 1] = s end
    end
    return free
end

local function Locked(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.isLocked
end

-- bag moves first (one after the other, each once its slots are free again),
-- then the stacks into the trade window
local function Run(moves, actions)
    local free = FreeTradeSlots()
    local count = math.min(#actions, #free)
    token = token + 1
    local mine = token
    local Split = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem

    local function PlaceAll()
        local t = 0
        for i = 1, count do
            local a, tslot = actions[i], free[i]
            C_Timer.After(t, function() Place(a, tslot, mine, 0) end)
            t = t + 0.3
        end
    end

    local function Move(k, tries)
        if mine ~= token or not tradeOpen then return end
        local m = moves[k]
        if not m then C_Timer.After(#moves > 0 and 0.4 or 0.1, PlaceAll) return end
        if (Locked(m.from.bag, m.from.slot) or Locked(m.to.bag, m.to.slot)) and tries < 8 then
            C_Timer.After(0.25, function() Move(k, tries + 1) end)
            return
        end
        ClearCursor()
        ns.Debug("TRADE move %d from bag %d slot %d to bag %d slot %d%s", m.n, m.from.bag, m.from.slot,
            m.to.bag, m.to.slot, m.whole and " (whole stack)" or "")
        if m.whole then Pickup(m.from.bag, m.from.slot)
        elseif Split then Split(m.from.bag, m.from.slot, m.n) end
        if CursorHasItem() then Pickup(m.to.bag, m.to.slot) end
        if CursorHasItem() then ClearCursor() end
        C_Timer.After(0.2, function() Move(k + 1, 0) end)
    end
    Move(1, 0)
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
    local moves, actions, notes = {}, {}, {}
    local slotsLeft = #FreeTradeSlots()
    local empties = EmptySlots()
    local Split = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
    for _, role in ipairs(ns.ShareRoles()) do
        if me and HasRole(me, role) and HasRole(partner, role) then
            sharing[#sharing + 1] = role
            local parts = {}
            for _, p in ipairs(ns.SharePlan(role, partner, done)) do
                local name = ns.ItemInfo(p.id) or ("item " .. p.id)
                local m, list, note = ShareStacks(p.id, p.stacks, p.give, empties)
                if m and not Split then
                    for _, mv in ipairs(m) do if not mv.whole then m, list = nil, "this client can't split stacks" break end end
                end
                if not m then
                    ns.Print("Share: %d x %s for %s: %s; put them in by hand.", p.give, name, who, list)
                elseif #list > slotsLeft then
                    ns.Print("Share: %d x %s needs %d trade slots, %d are free. Trade again for it.", p.give, name, #list, slotsLeft)
                else
                    slotsLeft = slotsLeft - #list
                    local n = 0
                    for _, mv in ipairs(m) do moves[#moves + 1] = mv end
                    for _, a in ipairs(list) do actions[#actions + 1] = a n = n + a.expect end
                    parts[#parts + 1] = ("%d x %s (%d each)"):format(n, name, p.share)
                    if note then ns.Print("Share: %d more %s for %s: %s; put them in by hand.", p.give - n, name, who, note) end
                end
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

    local count, rest = Run(moves, actions)
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
