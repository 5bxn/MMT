-- MMT: gossip goes straight to the vendor pane.
--
-- Quest automation (accept, turn in, announce, share) lives in the Quest
-- Tracker module (MMT_QuestTracker). It adds a gossip handler that runs
-- first: when a handler picks a quest, the vendor step is skipped.

local _, ns = ...

local gossipHandlers = {}

-- fn() returns true when it handled the gossip window (e.g. picked a quest)
function ns.AddGossipHandler(fn)
    gossipHandlers[#gossipHandlers + 1] = fn
end

local VENDOR_ICON = 132060 -- Interface\GossipFrame\VendorGossipIcon

local function IsVendorOption(opt)
    if opt.icon == VENDOR_ICON then return true end
    local name = opt.name
    if type(name) == "string" and not ns.IsSecret(name) then
        name = name:lower()
        return name:find("browse your goods", 1, true) ~= nil
    end
    return false
end

ns.On("GOSSIP_SHOW", function()
    if ns.IsBypassed() then ns.Debug("Shift held: gossip left manual") return end
    for _, fn in ipairs(gossipHandlers) do
        local ok, handled = pcall(fn)
        if not ok then ns.Debug("gossip handler error: %s", tostring(handled)) end
        if ok and handled then return end
    end
    if not ns.db.gossip.vendor then return end

    local options = C_GossipInfo.GetOptions() or {}
    for _, opt in ipairs(options) do
        ns.Debug("Gossip option: %s (icon %s, id %s)", tostring(opt.name), tostring(opt.icon), tostring(opt.gossipOptionID))
    end
    for _, opt in ipairs(options) do
        if IsVendorOption(opt) then
            C_GossipInfo.SelectOption(opt.gossipOptionID)
            return
        end
    end
end)
