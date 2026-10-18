-- MMT: push the camera zoom-out limit past the options slider.

local _, ns = ...

local CVAR = "cameraDistanceMaxZoomFactor"
local GetCV = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCV = (C_CVar and C_CVar.SetCVar) or SetCVar
local waitingForCombat = false

local function Apply()
    if InCombatLockdown() then
        waitingForCombat = true
        return
    end
    local cam = ns.db.camera
    if cam.enabled then
        if not cam.original then cam.original = GetCV(CVAR) end
        SetCV(CVAR, tostring(cam.factor))
        ns.Debug("Camera zoom factor set to %s (game now reports %s)", tostring(cam.factor), tostring(GetCV(CVAR)))
    elseif cam.original then
        SetCV(CVAR, cam.original)
        cam.original = nil
    end
end

ns.OnRefresh(Apply)
ns.On("PLAYER_ENTERING_WORLD", Apply)
ns.On("PLAYER_REGEN_ENABLED", function()
    if waitingForCombat then
        waitingForCombat = false
        Apply()
    end
end)
