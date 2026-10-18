-- MMT: small movable window showing the distance to the current target.
--
-- Exact distance is only available for group members (UnitPosition).
-- For everything else the game exposes range checks, not coordinates, so
-- MMT estimates a bracket (e.g. "20-25 yd") from the ranges of your own
-- spells, like range-check libraries do.

local _, ns = ...

local THROTTLE = 0.1
local checks = { harm = {}, help = {} }

---------------------------------------------------------------------------
-- Range checks
---------------------------------------------------------------------------
local function AddCheck(list, range, test)
    for _, c in ipairs(list) do
        if c.range == range then return end
    end
    list[#list + 1] = { range = range, test = test }
end

local function SortChecks()
    table.sort(checks.harm, function(a, b) return a.range < b.range end)
    table.sort(checks.help, function(a, b) return a.range < b.range end)
end

local function SpellTest(spellID)
    return function(unit)
        return ns.Safe(C_Spell.IsSpellInRange, spellID, unit)
    end
end

local function InteractTest(index)
    return function(unit)
        if InCombatLockdown() then return nil end
        return ns.Safe(CheckInteractDistance, unit, index)
    end
end

local function ScanSpells()
    wipe(checks.harm)
    wipe(checks.help)

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_Spell and C_Spell.IsSpellInRange then
        local bank = Enum.SpellBookSpellBank.Player
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if lineInfo and not lineInfo.offSpecID then
                local first = lineInfo.itemIndexOffset + 1
                for i = first, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID and not item.isPassive
                        and item.itemType == Enum.SpellBookItemType.Spell then
                        local spell = C_Spell.GetSpellInfo(item.spellID)
                        local maxRange = spell and spell.maxRange or 0
                        local minRange = spell and spell.minRange or 0
                        if maxRange > 0 and minRange == 0 then
                            local range = math.floor(maxRange + 0.5)
                            if C_Spell.IsSpellHarmful(item.spellID) then
                                AddCheck(checks.harm, range, SpellTest(item.spellID))
                            end
                            if C_Spell.IsSpellHelpful(item.spellID) then
                                AddCheck(checks.help, range, SpellTest(item.spellID))
                            end
                        end
                    end
                end
            end
        end
    end

    -- interaction distances (out of combat only)
    for _, list in pairs(checks) do
        AddCheck(list, 10, InteractTest(3)) -- duel
        AddCheck(list, 28, InteractTest(4)) -- follow
    end
    SortChecks()
    ns.Debug("Distance checks: %d hostile, %d friendly", #checks.harm, #checks.help)
end

local function ExactDistance(unit)
    if not UnitPosition then return nil end
    local y1, x1, _, map1 = ns.Safe(UnitPosition, "player")
    local y2, x2, _, map2 = ns.Safe(UnitPosition, unit)
    if not (y1 and y2) or ns.IsSecret(y2) or ns.IsSecret(x2) or map1 ~= map2 then return nil end
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- returns minYards, maxYards (max may be nil = "further than min")
local function EstimateRange(unit)
    local hostile = ns.Safe(UnitCanAttack, "player", unit)
    local list = hostile and checks.harm or checks.help
    local min, max = 0, nil
    local any = false
    for _, c in ipairs(list) do
        local r = c.test(unit)
        if r == true then
            any = true
            max = c.range
            break
        elseif r == false then
            any = true
            min = c.range
        end
    end
    if not any then return nil end
    return min, max
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "MMTDistanceFrame", UIParent)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:Hide()

f.bg = f:CreateTexture(nil, "BACKGROUND")
f.bg:SetAllPoints()
f.bg:SetColorTexture(0, 0, 0, 0.25)

f.text = f:CreateFontString(nil, "OVERLAY")
f.text:SetPoint("LEFT", 6, 0)
f.text:SetPoint("RIGHT", -6, 0)
f.text:SetWordWrap(false)

f:SetScript("OnDragStart", function(self)
    if not ns.db.distance.locked then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.distance.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end)
f:SetScript("OnEnter", function(self)
    if ns.db.distance.locked then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("MMT distance")
    GameTooltip:AddLine("Drag to move. Lock it in /mmt.", 1, 1, 1)
    GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function Colour(yards)
    if not ns.db.distance.colorize or not yards then return 1, 1, 1 end
    if yards <= 5 then return 0.35, 1, 0.35 end
    if yards <= 30 then return 1, 0.9, 0.25 end
    if yards <= 40 then return 1, 0.6, 0.15 end
    return 1, 0.3, 0.3
end

local function UpdateText()
    local unit = "target"
    if not UnitExists(unit) then
        f.text:SetText(ns.db.distance.locked and "-" or "No target")
        f.text:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    if UnitIsUnit(unit, "player") then
        f.text:SetText("0 yd")
        f.text:SetTextColor(Colour(0))
        return
    end

    local exact = ExactDistance(unit)
    if exact then
        f.text:SetFormattedText("%.1f yd", exact)
        f.text:SetTextColor(Colour(exact))
        return
    end

    local min, max = EstimateRange(unit)
    if not min then
        f.text:SetText("? yd")
        f.text:SetTextColor(0.7, 0.7, 0.7)
    elseif max then
        f.text:SetFormattedText("%d-%d yd", min, max)
        f.text:SetTextColor(Colour(max))
    else
        f.text:SetFormattedText("%d+ yd", min)
        f.text:SetTextColor(Colour(min + 1))
    end
end

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < THROTTLE then return end
    elapsed = 0
    UpdateText()
end)

local function ShouldShow()
    local d = ns.db.distance
    if not d.enabled then return false end
    if ns.configOpen or not d.locked then return true end
    return not d.hideNoTarget or UnitExists("target")
end

local function UpdateVisibility()
    if ShouldShow() then
        f:Show()
        UpdateText()
    else
        f:Hide()
    end
end
ns.UpdateDistanceVisibility = UpdateVisibility

local function Layout()
    local d = ns.db.distance
    ns.ApplyFont(f.text, d.font, d.size, d.outline)
    f.text:SetJustifyH(d.align)
    f.bg:SetColorTexture(0, 0, 0, d.bgAlpha)
    f:SetSize(d.width, d.size + 10)
    f:ClearAllPoints()
    local p = d.point
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    f:EnableMouse(not d.locked)
    UpdateVisibility()
end

function ns.ResetDistancePosition()
    ns.db.distance.point = { unpack(ns.defaults.distance.point) }
    Layout()
end

ns.OnRefresh(Layout)
ns.OnLogin(ScanSpells)
ns.On("PLAYER_TARGET_CHANGED", UpdateVisibility)

local rescanPending = false
ns.On("SPELLS_CHANGED", function()
    if rescanPending or not ns.db then return end
    rescanPending = true
    C_Timer.After(1, function()
        rescanPending = false
        ScanSpells()
    end)
end)
