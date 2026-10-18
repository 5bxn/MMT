-- MMT: vertical, movable window with XP %, rested XP %, layer and phasing
-- of every online team member. Offline members are hidden.

local _, ns = ...

local PAD, GAP = 3, 2
local A = { 0.31, 0.70, 1.00 }

local f = CreateFrame("Frame", "MMTXPFrame", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:Hide()
f.bg = f:CreateTexture(nil, "BACKGROUND")
f.bg:SetAllPoints()
f.rows = {}

f:SetScript("OnDragStart", function(self)
    if not ns.db.xp.locked then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.xp.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end)
f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then ns.ToggleConfig("xp") end
end)

-- mouseover on a row: full name and all details of that member
local function RowTooltip(row)
    local key, s = row.key, row.status
    if not key or not s then return end
    local tip = ns.MemberTooltip(row, key, "ANCHOR_RIGHT")
    tip:AddLine(" ")
    if s.isMax or s.max <= 0 then
        tip:AddDoubleLine("Level " .. s.level, "max level", 1, 1, 1, 0.7, 0.7, 0.7)
    else
        tip:AddDoubleLine("Level " .. s.level, ("%d / %d XP (%.1f%%)"):format(s.cur, s.max, s.cur / s.max * 100), 1, 1, 1, 1, 1, 1)
        if s.rested > 0 then
            tip:AddDoubleLine("Rested", ("%d XP (%d%%)"):format(s.rested, math.floor(s.rested / s.max * 100 + 0.5)), 0.75, 0.6, 1, 0.75, 0.6, 1)
        end
    end
    if s.money then tip:AddDoubleLine("Gold", GetCoinTextureString and GetCoinTextureString(s.money) or ns.FormatMoney(s.money), 1, 1, 1, 1, 1, 1) end
    if s.free then tip:AddDoubleLine("Bags", ("%d of %d slots free"):format(s.free, s.slots or 0), 1, 1, 1, 1, 1, 1) end
    if s.durMin then
        tip:AddDoubleLine("Durability", ("lowest %d%%, average %d%%"):format(s.durMin, s.durAvg or s.durMin), 1, 1, 1, 1, 1, 1)
    end
    tip:AddDoubleLine("Layer", s.layer and ("#" .. s.layer) or "unknown", 1, 1, 1, 0.7, 0.7, 0.7)
    local phase = ns.PhaseOf(key)
    if phase then tip:AddDoubleLine("Phasing", phase, 1, 1, 1, 1, 0.25, 0.25) end
    if not ns.db.xp.locked then tip:AddLine("Drag to move, right-click for settings.", 0.5, 0.5, 0.5) end
    tip:Show()
end

local function Row(i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f)
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints()
    row.track:SetColorTexture(1, 1, 1, 0.04)
    row.fill = row:CreateTexture(nil, "BORDER")
    row.fill:SetPoint("TOPLEFT"); row.fill:SetPoint("BOTTOMLEFT")
    row.rest = row:CreateTexture(nil, "BORDER")
    row.rest:SetPoint("TOPLEFT", row.fill, "TOPRIGHT"); row.rest:SetPoint("BOTTOMLEFT", row.fill, "BOTTOMRIGHT")
    row.rest:SetColorTexture(0.65, 0.45, 1.0, 0.30)
    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", -4, 0)
    row.value:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.line = row:CreateFontString(nil, "OVERLAY")
    row.line:SetPoint("LEFT", 4, 0)
    row.line:SetPoint("RIGHT", -4, 0)
    row.line:SetWordWrap(false)
    -- pulsing red "Layer Hop" left of the name; clickable even when the window is click-through
    row.hop = CreateFrame("Button", nil, row)
    row.hop:SetPoint("LEFT", 2, 0)
    row.hop:SetFrameLevel(row:GetFrameLevel() + 5)
    row.hop.text = row.hop:CreateFontString(nil, "OVERLAY")
    row.hop.text:SetPoint("LEFT")
    row.hop.text:SetTextColor(1, 0.2, 0.2)
    local pulse = row.hop.text:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0.25); fade:SetDuration(0.6)
    row.hop.pulse = pulse
    row.hop:SetScript("OnClick", function() ns.HopClicked(row.key) end)
    row.hop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Layer Hop", 1, 0.2, 0.2)
        if ns.IsSelf(row.key) then
            GameTooltip:AddLine("The game offers to move you to another layer. Click to accept in 3 seconds.", 1, 1, 1, true)
        else
            GameTooltip:AddLine(("%s has a layer hop pending. Click to make %s accept it in 3 seconds."):format(
                ns.FullDisplay(row.key), ns.FirstName(row.key)), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row.hop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.hop:Hide()
    -- rows show details on mouseover and pass dragging / right-click to the window
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
    row:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
    row:SetScript("OnMouseUp", function(_, button) f:GetScript("OnMouseUp")(f, button) end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
    return row
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return nil
end

-- names to show, in team order (your own character first if not in the team)
local function Members()
    local list = {}
    local me = ns.PlayerFull()
    local inTeam = false
    for _, key in ipairs(ns.SortedMembers()) do
        if ns.IsSelf(key) then
            inTeam = true
            if ns.db.xp.showSelf then list[#list + 1] = key end
        elseif ns.IsOnline(key) and ns.status[key] then
            list[#list + 1] = key
        end
    end
    if not inTeam and ns.db.xp.showSelf and me then table.insert(list, 1, me) end
    return list
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t"
local BAG_ICON = "|TInterface\\Icons\\INV_Misc_Bag_08:0:0:0:0:64:64:6:58:6:58|t"
local DUR_ICON = "|TInterface\\Icons\\Trade_BlackSmithing:0:0:0:0:64:64:6:58:6:58|t"

local function Thousands(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function DurabilityColour(pct)
    if pct >= 60 then return Hex(0.4, 1, 0.4) elseif pct >= 25 then return Hex(1, 0.85, 0.2) end
    return Hex(1, 0.3, 0.3)
end

-- gold, free bag slots and durability
local function InventoryText(s)
    local x = ns.db.xp
    local parts = {}
    if x.showGold and s.money then
        if x.goldFormat == "FULL" and GetCoinTextureString then
            parts[#parts + 1] = GetCoinTextureString(s.money)
        else
            parts[#parts + 1] = Thousands(math.floor(s.money / 10000)) .. GOLD_ICON
        end
    end
    if x.showBags and s.free then
        local colour = (s.free == 0 and Hex(1, 0.3, 0.3)) or (s.free <= 4 and Hex(1, 0.85, 0.2)) or ""
        parts[#parts + 1] = BAG_ICON .. " " .. colour .. s.free .. (colour ~= "" and "|r" or "")
    end
    if x.showDurability then
        local pct = (x.durability == "AVERAGE") and s.durAvg or s.durMin
        if pct then parts[#parts + 1] = DUR_ICON .. " " .. DurabilityColour(pct) .. pct .. "%|r" end
    end
    return parts
end

local function ValueText(key, s)
    local x = ns.db.xp
    local parts = {}
    if x.showLevel then parts[#parts + 1] = Hex(0.75, 0.75, 0.75) .. "L" .. s.level .. "|r" end
    if s.isMax or s.max <= 0 then
        parts[#parts + 1] = "max"
    else
        parts[#parts + 1] = ("%.1f%%"):format(s.cur / s.max * 100)
        if x.showRested and s.rested > 0 then
            parts[#parts + 1] = Hex(0.75, 0.6, 1) .. ("R %d%%"):format(math.floor(s.rested / s.max * 100 + 0.5)) .. "|r"
        end
    end
    for _, part in ipairs(InventoryText(s)) do parts[#parts + 1] = part end
    return table.concat(parts, "  ")
end

local function Update()
    local x = ns.db.xp
    if not x.enabled or not ns.ready then f:Hide() return end
    ns.UpdateOwnStatus()
    local list = Members()
    if #list == 0 then f:Hide() return end

    local h = math.max(x.barHeight, x.size + 4)
    for i, key in ipairs(list) do
        local s = ns.status[key] or ns.UpdateOwnStatus()
        local row = Row(i)
        row.key, row.status = key, s
        row:EnableMouse(not x.clickThrough)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, -(PAD + (i - 1) * (h + GAP)))
        row:SetSize(x.width, h)

        local cr, cg, cb = ClassColor(s.class)
        local useClass = x.classColors and cr
        local r, g, b = useClass and cr or A[1], useClass and cg or A[2], useClass and cb or A[3]

        local pct = (s.isMax or s.max <= 0) and 0 or math.min(1, s.cur / s.max)
        local restPct = (s.isMax or s.max <= 0) and 0 or math.min(1 - pct, s.rested / s.max)
        row.fill:SetColorTexture(r * 0.6, g * 0.6, b * 0.6, 0.85)
        row.fill:SetShown(x.showBars and pct > 0)
        row.fill:SetWidth(math.max(1, x.width * pct))
        row.rest:SetShown(x.showBars and x.showRested and restPct > 0)
        row.rest:SetWidth(math.max(1, x.width * restPct))
        row.track:SetShown(x.showBars)

        local name = ns.Display(key)
        local values = ValueText(key, s)

        -- Layer Hop tag
        local hop = x.layerHopNotify and ns.HopPendingFor(key)
        local left = 4
        if hop then
            ns.ApplyFont(row.hop.text, x.font, x.size, x.outline)
            row.hop.text:SetText(ns.HopCountdownRunning() and ns.IsSelf(key) and "Layer Hop..." or "Layer Hop")
            row.hop:SetSize(row.hop.text:GetStringWidth() + 4, h)
            row.hop:Show()
            if not row.hop.pulse:IsPlaying() then row.hop.pulse:Play() end
            left = row.hop:GetWidth() + 8
        else
            row.hop.pulse:Stop()
            row.hop:Hide()
        end
        row.name:SetPoint("LEFT", left, 0)
        row.line:SetPoint("LEFT", left, 0)
        local nr, ng, nb = useClass and cr or 1, useClass and cg or 1, useClass and cb or 1
        if x.align == "SPLIT" then
            ns.ApplyFont(row.name, x.font, x.size, x.outline)
            ns.ApplyFont(row.value, x.font, x.size, x.outline)
            row.name:SetText(name)
            row.name:SetTextColor(nr, ng, nb)
            row.value:SetText(values)
            row.value:SetTextColor(1, 1, 1)
            row.name:Show(); row.value:Show(); row.line:Hide()
        else
            ns.ApplyFont(row.line, x.font, x.size, x.outline)
            row.line:SetJustifyH(x.align)
            row.line:SetText(Hex(nr, ng, nb) .. name .. "|r  " .. values)
            row.line:SetTextColor(1, 1, 1)
            row.line:Show(); row.name:Hide(); row.value:Hide()
        end
        row:Show()
    end
    for i = #list + 1, #f.rows do f.rows[i]:Hide() end

    f:SetScale(x.scale)
    f:SetAlpha(x.alpha)
    f:SetSize(x.width + PAD * 2, #list * (h + GAP) - GAP + PAD * 2)
    f.bg:SetColorTexture(0, 0, 0, x.bgAlpha)
    f:Show()
end
ns.UpdateXPWindow = Update

local function Layout()
    local x = ns.db.xp
    f:ClearAllPoints()
    local p = x.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:EnableMouse(not x.clickThrough)
    Update()
end

function ns.ResetXPPosition()
    ns.db.xp.point = { unpack(ns.defaults.xp.point) }
    Layout()
end

function ns.ToggleXPWindow()
    ns.db.xp.enabled = not ns.db.xp.enabled
    ns.Refresh()
end

ns.OnRefresh(Layout)
ns.Listen("STATUS_CHANGED", Update)
ns.Listen("TEAM_CHANGED", Update)
ns.Listen("PROFILE_CHANGED", function() if ns.ready then Layout() end end)
ns.OnLogin(function()
    C_Timer.NewTicker(5, Update) -- drops members whose heartbeat stopped, updates phase tags
end)
