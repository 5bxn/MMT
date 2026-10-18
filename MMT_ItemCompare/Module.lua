-- MMT module: Item Compare.
-- Builds on the MMT core: team, comm (SendToTeam, whispers), heartbeat,
-- profiles (settings in M.db), account storage (M.store), UI widgets.

local _, mod = ...
local MMT = MMT

mod.M = MMT.NewModule({
    name = "ItemCompare",
    title = "Item Compare",
    description = "Hover an item and press a key to see what every team member wears in that slot.",
    defaults = {
        mode        = "HOLD",    -- HOLD: shown while the key is held | TOGGLE: key switches it on/off
        includeSelf = false,
        showDelta   = true,      -- "if equipped" stat changes
        showStale   = true,      -- members whose data is from an earlier session
        scale       = 0.9,
        perRow      = 4,
    },
})
