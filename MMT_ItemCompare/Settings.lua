-- MMT Item Compare: settings page (shown under MODULES in /mmt) and
-- the module's part of the debug report.

local _, mod = ...
local MMT = MMT
local M = mod.M
local UI = MMT.UI
local H = MMT.ConfigHelpers
local COL_W, COL2_X = H.COL_W, H.COL2_X
local StatusLine, ConfirmButton = H.StatusLine, H.ConfirmButton

local function Opt(key)
    return function() return M.db[key] end,
           function(v) M.db[key] = v end
end

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }

M.Page = function(_, page)
    local L = UI.Column(page, 0, 0, COL_W)
    local status

    L:Header("Item Compare")
    L:Note("Hover an item and press your Item Compare key: you see what every team member wears in that slot.")
    L:Check("Item Compare is on", function() return M.enabled end, function(v)
        for _, entry in ipairs(MMT.InstalledModules()) do
            if entry.module == M then MMT.SetModuleEnabled(entry, v) end
        end
    end, "Same as the switch under Manage modules. Off also disables the addon for the next login.")

    -- key capture button: click, then press the key (with modifiers)
    local keyButton
    local capturing = false
    local function KeyText()
        local keys = mod.Keys()
        if #keys == 0 then return "not set" end
        local t = {}
        for _, k in ipairs(keys) do t[#t + 1] = GetBindingText(k) end
        return table.concat(t, ", ")
    end
    local function StopCapture()
        capturing = false
        keyButton:EnableKeyboard(false)
        keyButton.label:SetText("Key: " .. KeyText())
    end
    keyButton = UI.Button(page, COL_W, "", function(self, button)
        if button == "RightButton" then
            local ok, err = mod.SetKey(nil)
            status.Show_(ok and "Item Compare key removed." or err, not ok)
            StopCapture()
            return
        end
        if InCombatLockdown() then status.Show_("Key bindings can't be changed in combat.", true) return end
        capturing = true
        keyButton.label:SetText("Press a key...  (Esc = cancel)")
        keyButton:EnableKeyboard(true)
        if keyButton.SetPropagateKeyboardInput then keyButton:SetPropagateKeyboardInput(false) end
    end)
    keyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    keyButton:SetScript("OnKeyDown", function(self, key)
        if not capturing then return end
        if key == "ESCAPE" then StopCapture() return end
        if MODIFIER_KEYS[key] then return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local ok, msg = mod.SetKey(combo)
        status.Show_(ok and (msg or ("Item Compare is now on " .. GetBindingText(combo) .. ".")) or msg, not ok)
        StopCapture()
    end)
    UI.Tooltip(keyButton, "Item Compare key", "Click, then press the key you want (Alt, Ctrl and Shift combinations work). Right-click removes it. Also in Esc > Options > Keybindings > AddOns.")
    L:Add(keyButton, UI.ROW + 2)

    local gm, sm = Opt("mode")
    L:Cycle("Key mode", {
        { value = "HOLD", text = "Show while held" },
        { value = "TOGGLE", text = "Press to switch on/off" },
    }, gm, sm)
    local gs, ss = Opt("includeSelf")
    L:Check("Include your own character", gs, ss)
    local gd, sd = Opt("showDelta")
    L:Check("Show stat changes", gd, sd, "Adds \"If <name> equips the hovered item\" with the stat and item level differences to each tooltip.")
    local go, so = Opt("showStale")
    L:Check("Include offline members", go, so, "Shows the items they wore when they were last online, with the age of that data.")
    L:Space(4)
    status = StatusLine(page)
    status:SetWidth(COL_W)
    L:Add(status, 30)

    L:Header("Look")
    local gsc, ssc = Opt("scale")
    L:Slider("Tooltip scale", 0.5, 1.5, 0.05, gsc, ssc, "%.2f")
    local gp, sp = Opt("perRow")
    L:Slider("Tooltips per row", 1, 8, 1, gp, sp)

    -- right: equipment database ------------------------------------------
    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Team items")
    R:Note("Every client keeps the team's equipped items and only sends changes. Item stats come from the game.")
    local lines, lineKeys = {}, {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(COL_W, 18)
        local fs = UI.Label(row, "")
        fs:SetPoint("LEFT")
        fs:SetPoint("RIGHT")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        MMT.HoverMember(row, function() return lineKeys[i] end, function(tip, key)
            local rec = mod.EquipmentOf(key)
            tip:AddLine(rec and (mod.ItemCount(rec) .. " items stored, updated " .. MMT.Ago(rec.time)) or "No items stored yet", 0.7, 0.7, 0.7)
        end)
        R:Add(row, 18)
        lines[i] = fs
    end
    R:Space(6)
    R:Button("Request update from team", function()
        mod.RequestAll()
        status.Show_("Asked the online team for their items.")
    end)
    local clear = ConfirmButton(page, COL_W, "Clear stored items", function()
        mod.Clear()
        status.Show_("Stored items cleared. They fill in again as members come online.")
        MMT.RefreshConfig()
    end)
    R:Add(clear, UI.ROW + 2)

    page.OnRefresh = function()
        if not capturing then keyButton.label:SetText("Key: " .. KeyText()) end
        local members = MMT.SortedMembers()
        for i, fs in ipairs(lines) do
            local key = members[i]
            lineKeys[i] = key
            if key then
                local rec = mod.EquipmentOf(key)
                local n = 0
                if rec then for _ in pairs(rec.items) do n = n + 1 end end
                local colour = MMT.IsOnline(key) and "|cffffffff" or "|cff999999"
                fs:SetText(("%s%s|r  |cff888888%s|r"):format(colour, MMT.FirstName(key),
                    rec and (n .. " items, " .. MMT.Ago(rec.time)) or "no data yet"))
            elseif i == 1 then
                fs:SetText("|cff888888No team members yet.|r")
            else
                fs:SetText("")
            end
        end
    end
    M:Listen("EQUIPMENT_CHANGED", function() if page:IsVisible() then page.OnRefresh() end end)
end

function M.Report(_, add)
    add("-- Item Compare  key=" .. table.concat(mod.Keys(), ",") .. "  mode=" .. tostring(M.db.mode)
        .. "  own hash=" .. tostring(mod.OwnHash()))
    for key, rec in pairs(M.store.equipment or {}) do
        add(("equipment %s: %d items, hash %s, %s"):format(MMT.Repr(key), mod.ItemCount(rec), tostring(rec.hash), MMT.Ago(rec.time)))
    end
end
