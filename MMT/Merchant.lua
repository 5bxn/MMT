-- MMT: sell grey items and repair when a vendor opens.

local _, ns = ...

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local BATCH, INTERVAL = 10, 0.2

local merchantOpen = false
local ticker

local function SellPrice(info)
    local price = select(11, ns.ItemInfo(info.hyperlink or info.itemID))
    return price or 0
end

local function CollectJunk()
    local list = {}
    for bag = 0, ns.BAGS do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == POOR and not info.hasNoValue and not info.isLocked then
                local price = SellPrice(info)
                if price > 0 then
                    list[#list + 1] = {
                        bag = bag, slot = slot, itemID = info.itemID,
                        count = info.stackCount or 1,
                        value = price * (info.stackCount or 1),
                    }
                end
            end
        end
    end
    return list
end

-- tell the leader's chat (another character's client)
local function Tell(msg)
    if ns.db.merchant.tellLeader and ns.TellLeader then ns.TellLeader(msg) end
end

local function Report(count, value)
    if count == 0 then return end
    if ns.db.merchant.report then
        ns.Print("%d %s sold, %s made.", count, count == 1 and "item" or "items", ns.FormatMoney(value))
    end
    Tell(("NOTE:SELL:%d:%d"):format(count, value))
end

local function SellGrey()
    if ticker then return end
    local list = CollectJunk()
    if #list == 0 then return end

    local index, count, value = 1, 0, 0
    ticker = C_Timer.NewTicker(INTERVAL, function(self)
        for _ = 1, BATCH do
            local item = list[index]
            if not item or not merchantOpen then
                self:Cancel()
                ticker = nil
                Report(count, value)
                return
            end
            index = index + 1
            if C_Container.GetContainerItemID(item.bag, item.slot) == item.itemID then
                C_Container.UseContainerItem(item.bag, item.slot)
                count = count + item.count
                value = value + item.value
            end
        end
    end)
end

local function Repair()
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    local m = ns.db.merchant
    if m.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        if limit == -1 or limit >= cost then
            RepairAllItems(true)
            if m.report then ns.Print("Repaired for %s (guild bank).", ns.FormatMoney(cost)) end
            Tell(("NOTE:REPAIR:%d:g"):format(cost))
            return
        end
    end

    if GetMoney() < cost then
        ns.Print("Not enough money to repair (%s needed).", ns.FormatMoney(cost))
        Tell(("NOTE:REPAIR:%d:x"):format(cost))
        return
    end
    RepairAllItems()
    if m.report then ns.Print("Repaired for %s.", ns.FormatMoney(cost)) end
    Tell(("NOTE:REPAIR:%d:o"):format(cost))
end

ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    if ns.db.merchant.repair then Repair() end
    if ns.db.merchant.sellGrey then SellGrey() end
end)

ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
end)

-- the leader's client: notes from the team
ns.Listen("TEAM_MESSAGE", function(key, sender, text)
    local kind, a, b = text:match("^NOTE:(%u+):(%d+):?(%w*)")
    if not kind or not ns.IsNoticeLeaderHere() then return end
    local who = ns.ShownName(key)
    if kind == "SELL" then
        local count = tonumber(a)
        ns.Print("%s sold %d grey %s for %s.", who, count, count == 1 and "item" or "items", ns.FormatMoney(tonumber(b) or 0))
    elseif kind == "REPAIR" then
        local cost = ns.FormatMoney(tonumber(a))
        if b == "x" then ns.Print("|cffff6666%s doesn't have enough money to repair (%s needed).|r", who, cost)
        else ns.Print("%s repaired for %s%s.", who, cost, b == "g" and " (guild bank)" or "") end
    end
end)
