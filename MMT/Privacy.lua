-- MMT: privacy. Replaces the names of your team's characters in text with the
-- name chosen in Team > Privacy ("Catsi", "Purrita", "Druid 1", "Slot 2").
--
--   * ns.ReplaceNames(text, forDebug): used for debug logs and reports when
--     "Keep full names in debug logs" is off.
--   * "Hide names outside MMT too": chat (every chat window), unit frames
--     (player, target, focus, target of target, party, raid), nameplates and
--     unit tooltips, as far as the game allows: values the game hands out as
--     secrets can't be read and stay as they are. Other addons' windows are
--     only covered where they print to chat.
--
-- Only what is shown changes: player links in chat keep the real name, so
-- clicking a name still whispers the right character. Addon messages,
-- macros, invites and whispers always use the real names.

local _, ns = ...

local function Settings() return ns.db and ns.db.privacy end

local function Active()
    local p = Settings()
    return p and p.hideOutside and p.nameMode ~= "FULL"
end

---------------------------------------------------------------------------
-- Text replacement
---------------------------------------------------------------------------
local LETTER = "%w\128-\255"
local function Esc(s) return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) end

-- { pattern, replacement } for every spelling of every team name, longest first
local function Rules(forDebug)
    local rules = {}
    local team = ns.db and ns.db.team
    if not team then return rules end
    local mode = Settings() and Settings().nameMode or "FIRST"
    for key, m in pairs(team) do
        local first, last = ns.RealFirst(key), ns.RealLast(key)
        local alias
        if forDebug and mode == "FULL" then alias = ns.NameFor(key, "SLOT")
        else alias = ns.ShownName(key) end
        local function Add(text)
            if text and text ~= "" and text ~= alias then
                rules[#rules + 1] = { text = text, alias = alias }
            end
        end
        if first and last then
            Add(first .. " " .. last)
            Add(first .. "-" .. last)
            if forDebug then
                Add(first .. "<20>" .. last)   -- ns.Repr spellings
                Add(first .. "<2d>" .. last)
            end
        end
        Add(first)
        Add(last)
    end
    table.sort(rules, function(a, b) return #a.text > #b.text end)
    for _, r in ipairs(rules) do
        r.pattern = "%f[" .. LETTER .. "]" .. Esc(r.text) .. "%f[^" .. LETTER .. "]"
        r.repl = r.alias:gsub("%%", "%%%%")
    end
    return rules
end

local cache = {}
local function CachedRules(forDebug)
    local k = forDebug and "debug" or "show"
    if not cache[k] then cache[k] = Rules(forDebug) end
    return cache[k]
end
function ns.PrivacyChanged()
    cache = {}
    if ns.RefreshNameFrames then ns.RefreshNameFrames() end
end
ns.Listen("TEAM_CHANGED", function() cache = {} end)
ns.Listen("PROFILE_CHANGED", function() cache = {} end)
ns.Listen("XP_RECEIVED", function() cache = {} end)   -- a class learned later changes "Druid 1" names

local function ReplacePlain(text, rules)
    for _, r in ipairs(rules) do text = text:gsub(r.pattern, r.repl) end
    return text
end

-- replaces the names in shown text; link data (|H...|h) and textures stay as they are
function ns.ReplaceNames(text, forDebug)
    if type(text) ~= "string" or ns.IsSecret(text) or text == "" then return text end
    local rules = CachedRules(forDebug)
    if #rules == 0 then return text end
    if forDebug then return ReplacePlain(text, rules) end
    local out, pos = {}, 1
    while true do
        local a, b = text:find("|[HT].-|[ht]", pos)
        if not a then break end
        out[#out + 1] = ReplacePlain(text:sub(pos, a - 1), rules)
        out[#out + 1] = text:sub(a, b)   -- link data or texture: unchanged
        pos = b + 1
    end
    out[#out + 1] = ReplacePlain(text:sub(pos), rules)
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Chat: every chat window shows the replaced text
---------------------------------------------------------------------------
local wrapped = {}
local function WrapChatFrame(frame)
    if not frame or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
    wrapped[frame] = true
    local original = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if Active() and type(text) == "string" and not ns.IsSecret(text) then
            local ok, replaced = pcall(ns.ReplaceNames, text)
            if ok then text = replaced end
        end
        return original(self, text, ...)
    end
end

local function WrapAllChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do WrapChatFrame(_G["ChatFrame" .. i]) end
    for _, name in ipairs(CHAT_FRAMES or {}) do WrapChatFrame(_G[name]) end
end

---------------------------------------------------------------------------
-- Unit frames, nameplates
---------------------------------------------------------------------------
local function NameText(frame)
    if not frame then return nil end
    local content = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
    local fs = frame.name or frame.Name or (content and content.Name)
    if not fs and frame.GetName and frame:GetName() then
        fs = _G[frame:GetName() .. "Name"] or _G[frame:GetName() .. "TextureFrameName"]
    end
    if fs and fs.GetText and fs.SetText then return fs end
end

local function FixFrame(frame)
    if not Active() then return end
    local fs = NameText(frame)
    if not fs then return end
    local text = fs:GetText()
    if type(text) ~= "string" or ns.IsSecret(text) then return end
    local new = ns.ReplaceNames(text)
    if new ~= text then fs:SetText(new) end
end

local FRAMES = { "PlayerFrame", "TargetFrame", "FocusFrame", "TargetFrameToT", "FocusFrameToT",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }

function ns.RefreshNameFrames()
    if not Active() then return end
    for _, name in ipairs(FRAMES) do FixFrame(_G[name]) end
    if PlayerName then FixFrame({ name = PlayerName }) end
    local party = _G.PartyFrame
    if party then
        for i = 1, 4 do FixFrame(party["MemberFrame" .. i]) end
    end
end

local function RefreshSoon() C_Timer.After(0, ns.RefreshNameFrames) end

if hooksecurefunc then
    if UnitFrame_Update then hooksecurefunc("UnitFrame_Update", function(self) FixFrame(self) end) end
    if CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(self) FixFrame(self) end)   -- raid frames, nameplates
    end
    if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, WrapAllChatFrames) end) end
end

for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_NAME_UPDATE",
    "PLAYER_ENTERING_WORLD" }) do
    ns.On(e, RefreshSoon)
end

---------------------------------------------------------------------------
-- Unit tooltips
---------------------------------------------------------------------------
local function FixTooltip(tt)
    if not Active() or not tt or not tt.NumLines or not tt.GetName or not tt:GetName() then return end
    for i = 1, math.min(3, tt:NumLines() or 0) do
        local fs = _G[tt:GetName() .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if type(text) == "string" and not ns.IsSecret(text) then
            local new = ns.ReplaceNames(text)
            if new ~= text then fs:SetText(new) end
        end
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, FixTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", FixTooltip)
end

ns.OnLogin(function()
    WrapAllChatFrames()
    RefreshSoon()
end)
ns.On("UPDATE_CHAT_WINDOWS", function() WrapAllChatFrames() end)
