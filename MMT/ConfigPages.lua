-- MMT: the pages of the configuration window.
-- Order of registration = order of the tabs.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local PAGE_W = 518
local COL_W = 248
local COL2_X = 270

local function Opt(section, key)
    return function() return ns.db[section][key] end,
           function(v) ns.db[section][key] = v end
end

-- Status line for feedback (errors in red, success in grey).
local function StatusLine(parent)
    local fs = UI.Label(parent, "")
    fs:SetJustifyH("LEFT")
    fs.Show_ = function(text, isError)
        fs:SetText(text or "")
        if isError then fs:SetTextColor(1, 0.4, 0.4) else fs:SetTextColor(0.6, 0.6, 0.6) end
    end
    return fs
end

-- Buttons that need a second click within 3 seconds to run.
local function ConfirmButton(parent, width, text, action)
    local b
    local armed = false
    b = UI.Button(parent, width, text, function()
        if armed then
            armed = false
            b.label:SetText(text)
            action()
        else
            armed = true
            b.label:SetText("Click again")
            C_Timer.After(3, function()
                if armed then armed = false; b.label:SetText(text) end
            end)
        end
    end)
    return b
end

-- A fixed pool of list rows with mouse-wheel scrolling.
local function List(parent, width, rows, rowHeight, makeRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, rows * rowHeight)
    list.offset = 0
    list.rows = {}
    for i = 1, rows do
        local row = makeRow(list, i)
        row:SetSize(width, rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        list.rows[i] = row
    end
    function list:Render(data)
        self.data = data
        self.offset = math.max(0, math.min(self.offset, #data - rows))
        for i, row in ipairs(self.rows) do
            local index = i + self.offset
            if data[index] then
                fillRow(row, data[index], index)
                row:Show()
            else
                row:Hide()
            end
        end
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta
        self:Render(self.data or {})
    end)
    return list
end

local function RowBackground(row, index)
    local bg = UI.Fill(row, 1, 1, 1, (index % 2 == 0) and 0.025 or 0)
    return bg
end

-- shared with modules for their own settings pages
ns.ConfigHelpers = {
    PAGE_W = PAGE_W, COL_W = COL_W, COL2_X = COL2_X,
    StatusLine = StatusLine, ConfirmButton = ConfirmButton, List = List, RowBackground = RowBackground,
}

---------------------------------------------------------------------------
-- Team
---------------------------------------------------------------------------
ns.RegisterPage("team", "Team", function(page)
    local col = UI.Column(page, 0, 0, PAGE_W)
    col:Header("Team members")
    col:Note("The characters of your team, in the order the XP window shows them. Green dot = online with MMT.")

    local list = List(page, PAGE_W, 11, 22, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        RowBackground(row, i)
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(6, 6)
        row.dot:SetPoint("LEFT", 8, 0)
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", 22, 0)
        row.roles = UI.Label(row, "")
        row.roles:SetPoint("LEFT", 220, 0)
        row.roles:SetWidth(190)
        row.roles:SetJustifyH("LEFT")
        row.roles:SetWordWrap(false)
        row.roles:SetTextColor(0.55, 0.55, 0.55)
        row.remove = UI.TextButton(row, "x", function() ns.RemoveMember(row.key); ns.Refresh() end)
        row.remove:SetPoint("RIGHT", -2, 0)
        row.down = UI.TextButton(row, "Dn", function() ns.MoveMember(row.key, 1); ns.Refresh() end, 26)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
        row.up = UI.TextButton(row, "Up", function() ns.MoveMember(row.key, -1); ns.Refresh() end, 26)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        ns.HoverMember(row, function() return row.key end, function(tip, key)
            tip:AddLine("Team key: " .. key, 0.5, 0.5, 0.5)
        end)
        return row
    end, function(row, key)
        row.key = key
        local m = ns.db.team[key]
        row.name:SetText(ns.FirstName(key))
        local c = m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
        if c then row.name:SetTextColor(c.r, c.g, c.b) else row.name:SetTextColor(1, 1, 1) end
        if ns.IsOnline(key) then row.dot:SetColorTexture(0.3, 1, 0.3, 1) else row.dot:SetColorTexture(0.3, 0.3, 0.3, 1) end
        local roles = table.concat(ns.MemberRoleList(key), ", ")
        row.roles:SetText(roles ~= "" and roles or "no roles")
    end)
    col:Add(list, 11 * 22)
    local empty = UI.Label(page, "No team members yet. Group up and press \"Add group\", or type a name below.")
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -4)
    empty:SetTextColor(0.5, 0.5, 0.5)

    col:Space(8)
    local status
    local group = UI.Button(page, 120, "Add group", function()
        local n = ns.AddGroupMembers()
        status.Show_(n > 0 and ("Added " .. n .. " character(s) from your group.") or "Nobody new in your group.")
        ns.Refresh()
    end)
    col:Add(group, 0)
    UI.Tooltip(group, "Add group", "Adds you and everybody in your party or raid.")
    local me = UI.Button(page, 90, "Add me", function() ns.AddUnit("player"); ns.Refresh() end)
    me:SetPoint("LEFT", group, "RIGHT", 8, 0)
    local target = UI.Button(page, 100, "Add target", function()
        if UnitExists("target") and UnitIsPlayer("target") then
            ns.AddUnit("target")
            status.Show_("")
        else
            status.Show_("Target a player first.", true)
        end
        ns.Refresh()
    end)
    target:SetPoint("LEFT", me, "RIGHT", 8, 0)
    local clear = ConfirmButton(page, 120, "Remove all", function() ns.ClearTeam(); ns.Refresh() end)
    clear:SetPoint("LEFT", target, "RIGHT", 8, 0)
    col:Space(UI.ROW + 6)

    local input = UI.EditBox(page, 300, "First Last", function(text, box)
        local ok, err = ns.AddManual(text)
        if ok then box:SetText(""); box:ClearFocus(); status.Show_("Added " .. ns.Trim(text) .. ".") else status.Show_(err, true) end
        ns.Refresh()
    end)
    col:Add(input, 0)
    local add = UI.Button(page, 90, "Add", function() input:GetScript("OnEnterPressed")(input) end)
    add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    col:Space(UI.ROW + 6)

    status = StatusLine(page)
    col:Add(status, UI.ROW)
    local youHover = CreateFrame("Frame", nil, page)
    youHover:SetSize(PAGE_W, UI.ROW)
    local you = UI.Label(youHover, "")
    you:SetPoint("LEFT")
    you:SetTextColor(0.5, 0.5, 0.5)
    ns.HoverMember(youHover, function() return ns.PlayerFull() end)
    col:Add(youHover, UI.ROW)
    col:Note("Every account keeps its own team. Add the team on each client, or send it with Profiles > Sync to team.")

    page.OnRefresh = function()
        local members = ns.SortedMembers()
        list:Render(members)
        empty:SetShown(#members == 0)
        you:SetText("You are playing " .. ns.FirstName(ns.PlayerFull()) .. ".")
    end
    ns.Listen("STATUS_CHANGED", function() if page:IsVisible() then list:Render(ns.SortedMembers()) end end)
end)

---------------------------------------------------------------------------
-- Roles
---------------------------------------------------------------------------
local LEFT_W, RIGHT_X, RIGHT_W = 180, 200, 318

ns.RegisterPage("roles", "Roles", function(page)
    local selected
    local quality, itemGroup = 0, "cloth"

    local top = UI.Column(page, 0, 0, PAGE_W)
    local gt, st = Opt("trade", "enabled")
    top:Check("Fill the trade window from role rules", gt, st,
        "When you open a trade with a team member, the items their roles ask for go into the trade window. You still accept the trade yourself. /mmt trade fills it again.")

    -- left: roles --------------------------------------------------------
    local L = UI.Column(page, 0, top.y, LEFT_W)
    L:Header("Roles")
    local roleList = List(page, LEFT_W, 12, 22, function(parent, i)
        local row = CreateFrame("Button", nil, parent)
        RowBackground(row, i)
        row.sel = UI.Fill(row, A[1], A[2], A[3], 0.18, "BORDER")
        row.name = UI.Label(row, "")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetPoint("RIGHT", -44, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.count = UI.Label(row, "")
        row.count:SetPoint("RIGHT", -26, 0)
        row.count:SetTextColor(0.5, 0.5, 0.5)
        row.remove = UI.TextButton(row, "x", function() ns.RemoveRole(row.role); ns.Refresh() end)
        row.remove:SetPoint("RIGHT", -2, 0)
        row:SetScript("OnClick", function() selected = row.role; ns.RefreshConfig() end)
        return row
    end, function(row, role)
        row.role = role
        row.name:SetText(role)
        row.count:SetText(ns.MembersWithRole(role))
        row.sel:SetShown(role == selected)
    end)
    L:Add(roleList, 12 * 22 + 6)

    local roleStatus
    local roleInput = UI.EditBox(page, LEFT_W - 50, "New role", function(text, box)
        local name, err = ns.AddRole(text)
        if name then selected = name; box:SetText(""); box:ClearFocus(); roleStatus.Show_("") else roleStatus.Show_(err, true) end
        ns.Refresh()
    end)
    L:Add(roleInput, 0)
    local roleAdd = UI.Button(page, 44, "Add", function() roleInput:GetScript("OnEnterPressed")(roleInput) end)
    roleAdd:SetPoint("LEFT", roleInput, "RIGHT", 6, 0)
    L:Space(UI.ROW + 4)
    roleStatus = StatusLine(page)
    roleStatus:SetWidth(LEFT_W)
    L:Add(roleStatus, 16)
    L:Note("Soulbound and quest items are never traded. A trade holds 6 stacks.")

    -- right: members & rules ----------------------------------------------
    local R = UI.Column(page, RIGHT_X, top.y, RIGHT_W)
    local membersHeader = R:Header("Members")
    local memberChecks, memberKeys = {}, {}
    local half = RIGHT_W / 2
    for i = 1, 10 do
        local cb = UI.Check(page, half - 8, "",
            function() return selected and memberKeys[i] and ns.HasRole(memberKeys[i], selected) end,
            function(v) if selected and memberKeys[i] then ns.SetMemberRole(memberKeys[i], selected, v) end end)
        cb:SetPoint("TOPLEFT", page, "TOPLEFT", RIGHT_X + ((i - 1) % 2) * half, R.y - math.floor((i - 1) / 2) * 22)
        ns.HoverMember(cb, function() return memberKeys[i] end)
        memberChecks[i] = cb
    end
    local noTeam = UI.Label(page, "Add team members on the Team tab first.")
    noTeam:SetPoint("TOPLEFT", page, "TOPLEFT", RIGHT_X, R.y - 2)
    noTeam:SetTextColor(0.5, 0.5, 0.5)
    R:Space(5 * 22)

    local rulesHeader = R:Header("Items")
    local ruleList = List(page, RIGHT_W, 7, 20, function(parent, i)
        local row = CreateFrame("Frame", nil, parent)
        RowBackground(row, i)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 6, 0)
        row.text = UI.Label(row, "")
        row.text:SetPoint("LEFT", 26, 0)
        row.text:SetPoint("RIGHT", -26, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.remove = UI.TextButton(row, "x", function() ns.RemoveRule(selected, row.i); ns.Refresh() end)
        row.remove:SetPoint("RIGHT", -2, 0)
        return row
    end, function(row, rule, index)
        row.i = index
        local text, icon, r, g, b = ns.DescribeRule(rule)
        row.text:SetText(text)
        row.text:SetTextColor(r, g, b)
        row.icon:SetTexture(icon or "Interface\\Buttons\\WHITE8x8")
        if icon then row.icon:SetVertexColor(1, 1, 1) else row.icon:SetVertexColor(0.3, 0.3, 0.3) end
    end)
    R:Add(ruleList, 7 * 20 + 6)
    local noRules = UI.Label(page, "No items or rules on this role yet.")
    noRules:SetPoint("TOPLEFT", ruleList, "TOPLEFT", 6, -4)
    noRules:SetTextColor(0.5, 0.5, 0.5)

    local ruleStatus
    local function AddRule(rule)
        if not selected then ruleStatus.Show_("Select or create a role first.", true) return false end
        local ok, err = ns.AddRule(selected, rule)
        ruleStatus.Show_(ok and "" or err, not ok)
        ns.Refresh()
        return ok
    end

    local drop = UI.Button(page, RIGHT_W, "Drop an item from your bags here", function()
        local kind, id = GetCursorInfo()
        if kind == "item" then
            AddRule({ type = "item", itemID = id, name = (ns.ItemInfo(id)) })
            ClearCursor()
        end
    end)
    drop:SetScript("OnReceiveDrag", drop:GetScript("OnClick"))
    R:Add(drop, UI.ROW + 2)

    local itemInput = UI.EditBox(page, RIGHT_W - 52, "Click, then shift-click an item", function(text, box)
        local rule = ns.RuleFromText(text)
        if rule and AddRule(rule) then box:SetText(""); box:ClearFocus() end
    end)
    UI.AcceptItemLinks(itemInput, function(link)
        ruleStatus.Show_(link .. "  - press Enter or Add.")
    end)
    UI.Tooltip(itemInput, "Add an item", "Click into the field, then shift-click an item in your bags, the loot window, a chat link or any other window. Item IDs and exact item names work too.")
    R:Add(itemInput, 0)
    local itemAdd = UI.Button(page, 44, "Add", function() itemInput:GetScript("OnEnterPressed")(itemInput) end)
    itemAdd:SetPoint("LEFT", itemInput, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)

    local grey = UI.Button(page, half - 4, "All grey items", function() AddRule({ type = "quality", quality = 0 }) end)
    R:Add(grey, 0)
    local boe = UI.Button(page, half - 4, "All Bind on Equip", function() AddRule({ type = "boe" }) end)
    boe:SetPoint("LEFT", grey, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)

    local qualities = {}
    for q = 0, 5 do qualities[#qualities + 1] = { value = q, text = ns.QualityName(q) } end
    local qCycle = UI.Cycle(page, RIGHT_W - 52, "Quality", qualities,
        function() return quality end, function(v) quality = v end)
    R:Add(qCycle, 0)
    local qAdd = UI.Button(page, 44, "Add", function() AddRule({ type = "quality", quality = quality }) end)
    qAdd:SetPoint("LEFT", qCycle, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)

    local groups = {}
    for _, g in ipairs(ns.ITEM_GROUPS) do
        groups[#groups + 1] = g.header and { header = true, text = g.header } or { value = g.id, text = g.name }
    end
    local cCycle = UI.Dropdown(page, RIGHT_W - 52, "Item group", groups,
        function() return itemGroup end, function(v) itemGroup = v end)
    R:Add(cCycle, 0)
    UI.Tooltip(cCycle, "Item group", "Ready-made groups by item category, e.g. Cloth (Linen, Wool, Silk, Mageweave, Runecloth and their bolts), Herbs, Potions, Food & drink or Reagents.")
    local cAdd = UI.Button(page, 44, "Add", function() AddRule({ type = "group", group = itemGroup }) end)
    cAdd:SetPoint("LEFT", cCycle, "RIGHT", 8, 0)
    R:Space(UI.ROW + 2)

    ruleStatus = StatusLine(page)
    R:Add(ruleStatus, 16)

    local noRole = UI.Label(page, "Create a role on the left (e.g. Cloth), then tick its members and add items.")
    noRole:SetPoint("TOPLEFT", page, "TOPLEFT", RIGHT_X, top.y - 30)
    noRole:SetWidth(RIGHT_W)
    noRole:SetJustifyH("LEFT")
    noRole:SetTextColor(0.5, 0.5, 0.5)
    local rightSide = { membersHeader, rulesHeader, ruleList, drop, itemInput, itemAdd, grey, boe, qCycle, qAdd, cCycle, cAdd, ruleStatus }

    page.OnRefresh = function()
        local roles = ns.SortedRoleNames()
        if selected and not ns.db.roles[selected] then selected = nil end
        if not selected then selected = roles[1] end
        roleList:Render(roles)

        for _, region in ipairs(rightSide) do region:SetShown(selected ~= nil) end
        noRole:SetShown(selected == nil)
        membersHeader:SetText(selected and ("Members of " .. selected) or "Members")
        rulesHeader:SetText(selected and ("Items for " .. selected) or "Items")

        local rules = selected and ns.db.roles[selected].rules or {}
        ruleList:Render(rules)
        noRules:SetShown(selected ~= nil and #rules == 0)

        local members = ns.SortedMembers()
        for i, cb in ipairs(memberChecks) do
            memberKeys[i] = members[i]
            cb.label:SetText(members[i] and ns.FirstName(members[i]) or "")
            cb:SetShown(selected ~= nil and members[i] ~= nil)
            cb.Refresh()
        end
        noTeam:SetShown(selected ~= nil and #members == 0)
    end
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if page:IsVisible() then ruleList:Render(ruleList.data or {}) end
    end)
end)

---------------------------------------------------------------------------
-- XP window
---------------------------------------------------------------------------
ns.RegisterPage("xp", "XP Window", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("XP window")
    L:Check("Show window", Opt("xp", "enabled"))
    L:Check("Lock position", Opt("xp", "locked"))
    local gct, sct = Opt("xp", "clickThrough")
    L:Check("Click-through", gct, sct, "Clicks go through the window to the game world. No mouseover details then.")
    L:Check("Show your own character", Opt("xp", "showSelf"))
    L:Check("Show level", Opt("xp", "showLevel"))
    local gr, sr = Opt("xp", "showRested")
    L:Check("Show rested XP (%)", gr, sr, "Rested XP in percent of the current level, e.g. R 35%. Also shaded on the bar.")
    L:Check("Show XP bars", Opt("xp", "showBars"))
    L:Check("Class colours", Opt("xp", "classColors"))

    L:Header("Gold, bags & durability")
    L:Check("Show gold", Opt("xp", "showGold"))
    L:Check("Show free bag slots", Opt("xp", "showBags"))
    L:Check("Show durability", Opt("xp", "showDurability"))
    local gdm, sdm = Opt("xp", "durability")
    L:Cycle("Durability", {
        { value = "LOWEST", text = "Lowest item" },
        { value = "AVERAGE", text = "Average of all items" },
    }, gdm, sdm)
    local ggf, sgf = Opt("xp", "goldFormat")
    L:Cycle("Gold", {
        { value = "GOLD", text = "Gold only" },
        { value = "FULL", text = "Gold, silver, copper" },
    }, ggf, sgf)

    L:Header("Layer hop")
    local gn, sn = Opt("xp", "layerHopNotify")
    L:Check("Notify when layer/phase switch is pending", gn, sn,
        "Shows a pulsing red \"Layer Hop\" left of the name when the game offers to move that character to another layer. Click it to accept in 3 seconds (for a teammate, their client accepts).")
    local gau, sau = Opt("xp", "layerHopAuto")
    L:Check("Accept the layer hop automatically", gau, sau, "Counts down in chat, then accepts.")
    local gd, sd = Opt("xp", "layerHopDelay")
    L:Slider("Accept after (seconds)", 1, 30, 1, gd, sd)
    L:Note("Tip: with many values per row, widen the window (Width) or use a smaller font.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Look")
    local gf, sf = Opt("xp", "font")
    R:Cycle("Font", function()
        local l = {}
        for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
        local cur = ns.db.xp.font
        local known = false
        for _, c in ipairs(l) do if c.value == cur then known = true end end
        if not known then l[#l + 1] = { value = cur, text = "Custom" } end
        return l
    end, gf, sf)
    local go, so = Opt("xp", "outline")
    R:Cycle("Outline", {
        { value = "NONE", text = "None" },
        { value = "OUTLINE", text = "Thin" },
        { value = "THICKOUTLINE", text = "Thick" },
        { value = "MONOCHROME,OUTLINE", text = "Mono" },
    }, go, so)
    local ga, sa = Opt("xp", "align")
    R:Cycle("Layout", {
        { value = "SPLIT", text = "Name left, values right" },
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Center" },
        { value = "RIGHT", text = "Right" },
    }, ga, sa)
    local gz, sz = Opt("xp", "size")
    R:Slider("Font size", 8, 24, 1, gz, sz)
    local gw, sw = Opt("xp", "width")
    R:Slider("Width", 100, 400, 5, gw, sw)
    local gh, sh = Opt("xp", "barHeight")
    R:Slider("Bar height", 10, 36, 1, gh, sh)
    local gs, ss = Opt("xp", "scale")
    R:Slider("Scale", 0.5, 2, 0.05, gs, ss, "%.2f")
    local gal, sal = Opt("xp", "alpha")
    R:Slider("Window opacity", 0.2, 1, 0.05, gal, sal, "%.2f")
    local gb, sb = Opt("xp", "bgAlpha")
    R:Slider("Background opacity", 0, 1, 0.05, gb, sb, "%.2f")
    R:Button("Reset window position", function() ns.ResetXPPosition() end)

end)

---------------------------------------------------------------------------
-- Automations (formerly OMT)
---------------------------------------------------------------------------
ns.RegisterPage("automations", "Automations", function(page)
    local L = UI.Column(page, 0, 0, COL_W)

    L:Header("Gossip")
    local gv, sv = Opt("gossip", "vendor")
    L:Check("Go straight to the vendor", gv, sv,
        "Opens the vendor pane even when the NPC has other options, e.g. an innkeeper.")
    local gdl, sdl = Opt("gossip", "dialog")
    L:Check("Click through NPC dialogs", gdl, sdl,
        "When an NPC has no quests and only plain dialog lines, MMT picks them one after another to advance the conversation. Lines that could cost gold, teleport, train, bind your hearthstone or start a fight are left to you, and NPCs with any other option (vendor, trainer, flights, ...) stay manual.")
    L:Check("Hold Shift to skip automation",
        function() return ns.db.shiftBypass end,
        function(v) ns.db.shiftBypass = v end,
        "Hold Shift while an NPC window opens to keep that page manual. Pick an option without Shift and the next page is automated again.")
    L:Note("Quest automation (accept, turn in, share) is in the Quest Tracker module.")

    L:Header("Vendor")
    L:Check("Sell grey items", Opt("merchant", "sellGrey"))
    L:Check("Repair automatically", Opt("merchant", "repair"))
    local gg, sg = Opt("merchant", "guildRepair")
    L:Check("Use guild funds if allowed", gg, sg, "Falls back to your own gold.")
    L:Check("Print results to chat", Opt("merchant", "report"))
    local gtr, str = Opt("trade", "enabled")
    L:Check("Fill trades from role rules", gtr, str,
        "When you open a trade with a team member, the items their roles ask for go into the trade window. Same switch as on the Roles tab.")
    local gm, sm = Opt("merchant", "moneyFormat")
    L:Cycle("Money format", {
        { value = "text",  text = "1 gold 2 silver" },
        { value = "short", text = "1g 2s 3c" },
        { value = "coins", text = "Coin icons" },
    }, gm, sm)

    L:Header("Group invites")
    L:Check("Accept from team members", Opt("invites", "team"))
    L:Check("Accept from friends", Opt("invites", "friends"))
    L:Check("Accept from Battle.net friends", Opt("invites", "bnet"))
    L:Check("Accept from guild members", Opt("invites", "guild"))
    local gw, sw = Opt("invites", "whisper")
    L:Check("Invite people who whisper the keyword", gw, sw,
        "Anyone who whispers you exactly this word (not case-sensitive) gets a group invite.")
    -- keyword: saved on Enter or when the box loses focus
    local keyword = UI.EditBox(page, COL_W - 24, "keyword", function(text, box)
        local word = ns.Trim(text)
        if word ~= "" then ns.db.invites.keyword = word end
        box:SetText(ns.db.invites.keyword)
        box:ClearFocus()
    end)
    keyword:HookScript("OnEditFocusLost", function(box)
        local word = ns.Trim(box:GetText())
        if word ~= "" then ns.db.invites.keyword = word end
        box:SetText(ns.db.invites.keyword)
        box:UpdatePlaceholder()
    end)
    keyword.Refresh = function()
        if not keyword:HasFocus() then keyword:SetText(ns.db.invites.keyword or "") keyword:UpdatePlaceholder() end
    end
    table.insert(page.widgets, keyword)
    L:Add(keyword, UI.ROW + 2, 24)

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Camera")
    R:Check("Maximum camera distance", Opt("camera", "enabled"))
    local gf, sf = Opt("camera", "factor")
    R:Slider("Zoom factor", 1, 2.6, 0.1, gf, sf, "%.1f")

    R:Header("Distance window")
    R:Check("Show window", Opt("distance", "enabled"))
    R:Check("Lock (click-through)", Opt("distance", "locked"))
    local gh, sh = Opt("distance", "hideNoTarget")
    R:Check("Hide without target", gh, sh, "Only applies while the window is locked.")
    local gc, sc = Opt("distance", "colorize")
    R:Check("Colour by distance", gc, sc, "Green melee, yellow up to 30, orange up to 40, red beyond.")
    local gfo, sfo = Opt("distance", "font")
    R:Cycle("Font", function()
        local l = {}
        for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
        return l
    end, gfo, sfo)
    local go, so = Opt("distance", "outline")
    R:Cycle("Outline", {
        { value = "NONE", text = "None" },
        { value = "OUTLINE", text = "Thin" },
        { value = "THICKOUTLINE", text = "Thick" },
    }, go, so)
    local ga, sa = Opt("distance", "align")
    R:Cycle("Alignment", {
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Center" },
        { value = "RIGHT", text = "Right" },
    }, ga, sa)
    local gz, sz = Opt("distance", "size")
    R:Slider("Font size", 8, 32, 1, gz, sz)
    local gw, sw = Opt("distance", "width")
    R:Slider("Width", 40, 250, 5, gw, sw)
    local gb, sb = Opt("distance", "bgAlpha")
    R:Slider("Background opacity", 0, 1, 0.05, gb, sb, "%.2f")
    R:Button("Reset window position", function() ns.ResetDistancePosition() end)
end)

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
ns.RegisterPage("profiles", "Profiles", function(page)
    local col = UI.Column(page, 0, 0, PAGE_W)
    local copySource

    col:Header("Profile")
    col:Note("Profiles are shared by all characters on this account. Each character uses one profile; new characters start with \"Default\".")

    local function ProfileChoices()
        local l = {}
        for _, name in ipairs(ns.ProfileNames()) do l[#l + 1] = { value = name, text = name } end
        return l
    end
    local active = UI.Cycle(page, 360, "Active profile", ProfileChoices,
        function() return ns.CurrentProfileName() end,
        function(v) ns.SetProfile(v) end)
    col:Add(active, UI.ROW + 6)

    local status
    local newName = UI.EditBox(page, 230, "New profile name", nil)
    col:Add(newName, 0)
    local function Create(copy)
        local name = ns.Trim(newName:GetText())
        if ns.CreateProfile(name, copy and ns.db or nil) then
            ns.SetProfile(name)
            newName:SetText(""); newName:ClearFocus()
            status.Show_(("Created \"%s\"%s."):format(name, copy and " as a copy of the current settings" or ""))
        else
            status.Show_("Enter a name that isn't used yet.", true)
        end
        ns.Refresh()
    end
    newName:SetScript("OnEnterPressed", function() Create(true) end)
    local copyCurrent = UI.Button(page, 130, "Copy current", function() Create(true) end)
    copyCurrent:SetPoint("LEFT", newName, "RIGHT", 8, 0)
    local empty = UI.Button(page, 130, "New (empty)", function() Create(false) end)
    empty:SetPoint("LEFT", copyCurrent, "RIGHT", 8, 0)
    col:Space(UI.ROW + 6)

    local source = UI.Cycle(page, 230, "Copy from", function()
        local l = {}
        for _, name in ipairs(ns.ProfileNames()) do
            if name ~= ns.CurrentProfileName() then l[#l + 1] = { value = name, text = name } end
        end
        if #l == 0 then l[1] = { value = nil, text = "-" } end
        return l
    end, function() return copySource end, function(v) copySource = v end)
    col:Add(source, 0)
    local copy = ConfirmButton(page, 130, "Copy into active", function()
        if copySource and ns.CopyProfileInto(copySource) then
            status.Show_(("Copied \"%s\" into \"%s\"."):format(copySource, ns.CurrentProfileName()))
        end
    end)
    copy:SetPoint("LEFT", source, "RIGHT", 8, 0)
    col:Space(UI.ROW + 6)

    local reset = ConfirmButton(page, 120, "Reset profile", function()
        ns.ResetProfile()
        status.Show_("Profile reset to defaults.")
    end)
    col:Add(reset, 0)
    local delete = ConfirmButton(page, 120, "Delete profile", function()
        local name = ns.CurrentProfileName()
        if ns.DeleteProfile(name) then status.Show_(("Deleted \"%s\"."):format(name)) ns.Refresh() end
    end)
    delete:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    UI.Tooltip(delete, "Delete profile", "Deletes the active profile. Default can't be deleted. Characters using it go back to Default.")
    local sync = UI.Button(page, 160, "Sync to team (/mmt sync)", function() ns.SendProfileToTeam() end)
    sync:SetPoint("LEFT", delete, "RIGHT", 8, 0)
    UI.Tooltip(sync, "Sync to team", "Same as /mmt sync: sends the active profile to your group and online team members. Each of them gets a dialog to accept it.")
    col:Space(UI.ROW + 6)

    col:Header("Export / import")
    col:Note("Export, copy the text (Ctrl+A, Ctrl+C) and import it on the other account. Import uses the name box if filled, overwrites a profile of that name and activates it.")
    local area = UI.TextArea(page, PAGE_W, 110)
    col:Add(area, 118)

    local export = UI.Button(page, 120, "Export", function()
        area.edit:SetText(ns.ExportProfile())
        area.edit:SetFocus()
        area.edit:HighlightText()
        status.Show_(("Exported \"%s\"."):format(ns.CurrentProfileName()))
    end)
    col:Add(export, 0)
    local import = UI.Button(page, 120, "Import", function()
        local name, data = ns.ParseExport(area.edit:GetText())
        if not name then
            status.Show_("That text is not a valid MMT profile export.", true)
            return
        end
        local custom = ns.Trim(newName:GetText())
        if custom ~= "" then name = custom end
        ns.ImportProfile(name, data, true)
        area.edit:SetText("")
        newName:SetText("")
        status.Show_(("Profile \"%s\" imported and activated."):format(name))
        ns.Refresh()
    end)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    col:Space(UI.ROW + 8)

    status = StatusLine(page)
    status:SetWidth(PAGE_W)
    col:Add(status, UI.ROW)

    page.OnRefresh = function()
        if not copySource or copySource == ns.CurrentProfileName() or not MMTDB.profiles[copySource] then
            copySource = nil
            for _, name in ipairs(ns.ProfileNames()) do
                if name ~= ns.CurrentProfileName() then copySource = name break end
            end
        end
        source.Refresh()
        local canDelete = ns.CurrentProfileName() ~= "Default"
        delete:SetEnabled(canDelete)
        delete:SetAlpha(canDelete and 1 or 0.4)
    end
end)

---------------------------------------------------------------------------
-- Manage modules
---------------------------------------------------------------------------
ns.RegisterPage("modules", "Modules", function(page)
    local col = UI.Column(page, 0, 0, PAGE_W)
    col:Header("Installed modules")
    col:Note("Modules add features on top of the core. Each one is its own addon (folder MMT_<Name>), so it can also be switched on and off in the game's AddOns list.")

    local status
    local rows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, page)
        row:SetSize(PAGE_W, 46)
        RowBackground(row, i)
        row.check = UI.Check(row, 24, "", function() return row.entry and row.on end, function(v)
            if not row.entry then return end
            local result = ns.SetModuleEnabled(row.entry, v)
            if result == "reload" then
                status.Show_(row.entry.title .. " is enabled and loads after a UI reload.")
            elseif result == "active" then
                status.Show_(row.entry.title .. " is on.")
            else
                status.Show_(row.entry.title .. " is off and won't load at the next login.")
            end
            ns.RefreshConfig()
        end)
        row.check:SetPoint("TOPLEFT", 8, -6)
        row.title = UI.Label(row, "", "GameFontNormal")
        row.title:SetPoint("TOPLEFT", 34, -8)
        row.state = UI.Label(row, "")
        row.state:SetPoint("TOPRIGHT", -8, -8)
        row.notes = UI.Label(row, "")
        row.notes:SetPoint("TOPLEFT", 34, -26)
        row.notes:SetPoint("RIGHT", -8, 0)
        row.notes:SetJustifyH("LEFT")
        row.notes:SetWordWrap(false)
        row.notes:SetTextColor(0.6, 0.6, 0.6)
        col:Add(row, 48)
        rows[i] = row
    end
    local none = UI.Label(page, "No modules installed. Put module folders (e.g. MMT_ItemCompare) next to the MMT folder in Interface/AddOns.")
    none:SetPoint("TOPLEFT", rows[1], "TOPLEFT", 8, -8)
    none:SetWidth(PAGE_W - 16)
    none:SetJustifyH("LEFT")
    none:SetTextColor(0.5, 0.5, 0.5)

    col:Space(6)
    local reload = UI.Button(page, 160, "Reload UI", function() ReloadUI() end)
    col:Add(reload, UI.ROW + 6)
    status = StatusLine(page)
    status:SetWidth(PAGE_W)
    col:Add(status, UI.ROW)

    page.OnRefresh = function()
        local list = ns.InstalledModules()
        for i, row in ipairs(rows) do
            local e = list[i]
            row.entry = e
            if e then
                local active = e.module and e.module.enabled
                row.on = active or (not e.loaded and e.enabled)
                row.title:SetText(e.title)
                row.notes:SetText(e.notes)
                if active then
                    row.state:SetText("on"); row.state:SetTextColor(0.4, 1, 0.4)
                elseif e.loaded then
                    row.state:SetText("off"); row.state:SetTextColor(0.6, 0.6, 0.6)
                elseif e.enabled then
                    row.state:SetText("loads after reload"); row.state:SetTextColor(1, 0.85, 0.2)
                else
                    row.state:SetText("off (not loaded)"); row.state:SetTextColor(0.6, 0.6, 0.6)
                end
                row.check.Refresh()
                row:Show()
            else
                row:Hide()
            end
        end
        none:SetShown(#list == 0)
        reload:SetShown(ns.reloadNeeded == true)
    end
end)
