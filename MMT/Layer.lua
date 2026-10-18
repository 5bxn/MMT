-- MMT: layer and phasing of team members.
--
-- Layer: NPC GUIDs look like
--   Creature-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]
-- All NPCs of one layer share the zoneUID, so the zoneUID of a nearby NPC
-- (target, mouseover, nameplates) tells which layer this client is on.
-- It is shared with the team via the XP message. After a zone change it is
-- unknown until an NPC comes into range.
--
-- Phasing: two characters can be on the same layer but still not see each
-- other (player shards inside a layer, phases, War Mode, ...). For group
-- members UnitPhaseReason(unit) says why. Values found in game on Forever:
-- 0 Phasing, 1 Sharding, 2 War Mode, 3 Chromie Time, 4 Timerunning, 5 Ruleset.

local _, ns = ...

ns.layer = nil      -- shown value (zoneUID)
ns.layerKey = nil   -- serverID-zoneUID, used for comparisons

---------------------------------------------------------------------------
-- Layer
---------------------------------------------------------------------------
local function FromGUID(guid)
    if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
    local unitType, _, serverID, _, zoneUID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    if not zoneUID or zoneUID == "0" or zoneUID == "" then return nil end
    return zoneUID, (serverID or "?") .. "-" .. zoneUID
end

local function Set(layer, key)
    if key == ns.layerKey then return end
    ns.layer, ns.layerKey = layer, key
    ns.Debug("Layer: %s (key %s)", tostring(layer), tostring(key))
    ns.Fire("LAYER_CHANGED")
    ns.Fire("STATUS_CHANGED")
end

local function Check(unit)
    local layer, key = FromGUID(ns.Safe(UnitGUID, unit))
    if layer then Set(layer, key) end
end

ns.On("PLAYER_TARGET_CHANGED", function() Check("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() Check("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) Check(unit) end)

local function Reset()
    Set(nil, nil)
    C_Timer.After(2, function() Check("target") end)
end
ns.On("PLAYER_ENTERING_WORLD", Reset)
ns.On("ZONE_CHANGED_NEW_AREA", Reset)

---------------------------------------------------------------------------
-- Phasing
---------------------------------------------------------------------------
local PRETTY = {
    Phasing = "Phased", Sharding = "Sharded", WarMode = "War Mode",
    ChromieTime = "Chromie Time", TimerunningHwt = "Timerunning", Timerunning = "Timerunning",
    Ruleset = "Ruleset",
}
local LABELS = { [0] = "Phased", [1] = "Sharded", [2] = "War Mode", [3] = "Chromie Time", [4] = "Timerunning", [5] = "Ruleset" }
if Enum and Enum.PhaseReason then
    for name, value in pairs(Enum.PhaseReason) do
        if type(value) == "number" then LABELS[value] = PRETTY[name] or name end
    end
end
ns.PHASE_LABELS = LABELS

function ns.GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- group unit of a team member, or nil when not grouped with you
function ns.UnitForMember(key)
    for _, unit in ipairs(ns.GroupUnits()) do
        if not UnitIsUnit(unit, "player") then
            local _, _, unitKey = ns.SplitUnit(unit)
            if unitKey and ns.Resolve(unitKey) == key then return unit end
        end
    end
    return nil
end

-- returns label, reason (nil when together or not grouped)
function ns.PhaseOf(key)
    if not UnitPhaseReason or ns.IsSelf(key) then return nil end
    local unit = ns.UnitForMember(key)
    if not unit then return nil end
    local reason = ns.Safe(UnitPhaseReason, unit)
    if type(reason) ~= "number" then return nil end
    return LABELS[reason] or ("Phase " .. reason), reason
end

ns.On("UNIT_PHASE", function() ns.Fire("STATUS_CHANGED") end)
ns.On("GROUP_ROSTER_UPDATE", function() ns.Fire("STATUS_CHANGED") end)
