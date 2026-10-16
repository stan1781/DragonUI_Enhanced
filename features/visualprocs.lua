-- DragonUI_Enhanced — VisualProcs (ported from ElvUI_VisualProcs for DragonUI action bars).

local ADDON_NAME, addon = ...
local L = addon.L

local LBP = LibStub("LibBlizzardProcs-1.0", true)

local KEY = "visualprocs"
local MEDIA_PATH = "Interface\\AddOns\\DragonUI_Enhanced\\Libs\\LibBlizzardProcs\\textures\\"

local find = string.find
local pairs = pairs
local tonumber = tonumber
local wipe = wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
local strtrim = strtrim or function(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local overlayFrame
local scanFrame
local glowEnabled = false
local overlayEnabled = false
local actionButtonHooked = false
local trackedButtons = {}
local extraScanElapsed = 0

local BUTTON_SPECS = {
    { prefix = "ActionButton", count = 12 },
    { prefix = "MultiBarBottomLeftButton", count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton", count = 12 },
    { prefix = "MultiBarLeftButton", count = 12 },
    { prefix = "BonusActionButton", count = 12 },
    { prefix = "DragonUI_ExtraBarButton", count = 12 },
}

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function ClassSupported()
    return LBP and LBP.isClassSupported
end

local function GetSpellIdByName(spellName)
    if not spellName then
        return nil
    end
    local spellLink = GetSpellLink(spellName)
    if spellLink then
        return tonumber(spellLink:match("spell:(%d+)"))
    end
    return nil
end

local function ResolveActionSpellID(action)
    if not action or type(action) ~= "number" then
        return nil
    end
    local actionType, id, _, globalID = GetActionInfo(action)
    if actionType == "spell" then
        return globalID or id
    elseif actionType == "macro" then
        return GetSpellIdByName(GetMacroSpell(id))
    end
    return nil
end

local function ResolveExtraBarSpellID(button)
    if button.GetSlotData then
        local data = button:GetSlotData()
        if data then
            if data.spellID then
                return data.spellID
            end
            if data.type == "spell" and data.spell then
                return GetSpellIdByName(data.spell)
            end
            if data.type == "macro" and data.macro then
                return GetSpellIdByName(GetMacroSpell(data.macro))
            end
        end
    end
    local slotType = button.GetAttribute and button:GetAttribute("type")
    if slotType == "spell" then
        return GetSpellIdByName(button:GetAttribute("spell"))
    elseif slotType == "macro" then
        local macrotext = button:GetAttribute("macrotext")
        if macrotext then
            local showArg = macrotext:match("#showtooltip([^\n]*)")
            if showArg then
                showArg = strtrim(showArg)
                if showArg ~= "" then
                    return GetSpellIdByName(showArg)
                end
            end
        end
    end
    return nil
end

local function GetButtonActionKey(button)
    if not button then
        return nil
    end
    local name = button.GetName and button:GetName()
    if name and find(name, "^DragonUI_ExtraBarButton") then
        return "DUE_" .. name
    end
    if button.action then
        return button.action
    end
    if type(ActionButton_GetPagedID) == "function" then
        local ok, action = pcall(ActionButton_GetPagedID, button)
        if ok and action and action > 0 then
            return action
        end
    end
    if button.GetAttribute then
        local action = button:GetAttribute("action")
        if action then
            return action
        end
    end
    return name and ("DUE_" .. name) or nil
end

local function GetButtonSpellID(button, actionKey)
    local name = button.GetName and button:GetName()
    if name and find(name, "^DragonUI_ExtraBarButton") then
        return ResolveExtraBarSpellID(button)
    end
    if type(actionKey) == "number" then
        return ResolveActionSpellID(actionKey)
    end
    return nil
end

local function OverlayGlowShow(button, spellID)
    if button.__DUE_spellID == spellID then
        LBP:ShowOverlayGlow(button)
    end
end

local function OverlayGlowHide(button, spellID)
    if button.__DUE_spellID == spellID then
        LBP:HideOverlayGlow(button)
    end
end

local function ClearButtonGlowTracking(button)
    if not button then
        return
    end
    if button.__DUE_glowEvents then
        LBP:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", button)
        LBP:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", button)
        button.__DUE_glowEvents = nil
    end
    if button.__DUE_action ~= nil then
        LBP:ChangeAction(button.__DUE_action, nil)
        button.__DUE_action = nil
    end
    button.__DUE_spellID = nil
    LBP:HideOverlayGlow(button)
end

local function UpdateButtonGlow(button)
    if not (glowEnabled and ClassSupported()) then
        return
    end
    if not button or not button.GetName then
        return
    end

    local actionKey = GetButtonActionKey(button)
    local spellID = GetButtonSpellID(button, actionKey)
    local hasContent = spellID ~= nil

    if hasContent then
        if not button.__DUE_glowEvents then
            LBP:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", button, OverlayGlowShow)
            LBP:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", button, OverlayGlowHide)
            button.__DUE_glowEvents = true
        end
        if button.__DUE_action and button.__DUE_action ~= actionKey then
            LBP:ChangeAction(button.__DUE_action, nil)
        end
        button.__DUE_action = actionKey
        button.__DUE_spellID = spellID
        if actionKey then
            LBP:ChangeAction(actionKey, spellID)
        end
        trackedButtons[button] = true
    else
        ClearButtonGlowTracking(button)
        trackedButtons[button] = nil
    end

    if spellID and LBP:IsSpellOverlayed(spellID) then
        LBP:ShowOverlayGlow(button)
    else
        LBP:HideOverlayGlow(button)
    end
end

local function ScanButtonsByPrefix(prefix, count)
    for index = 1, count do
        local button = _G[prefix .. index]
        if button then
            UpdateButtonGlow(button)
        end
    end
end

local function ScanAllButtons()
    if not (glowEnabled and ClassSupported()) then
        return
    end
    for i = 1, #BUTTON_SPECS do
        local spec = BUTTON_SPECS[i]
        ScanButtonsByPrefix(spec.prefix, spec.count)
    end
end

local function ScanExtraBarButtons()
    if not (glowEnabled and ClassSupported()) then
        return
    end
    ScanButtonsByPrefix("DragonUI_ExtraBarButton", 12)
end

local function ClearAllButtonTracking()
    for button in pairs(trackedButtons) do
        ClearButtonGlowTracking(button)
    end
    wipe(trackedButtons)
end

local function OverlayShow(frame, spellID, texture, positions, scale, r, g, b)
    LBP:ShowAllOverlays(frame, spellID, texture, positions, scale, r, g, b)
end

local function OverlayHide(frame, spellID)
    if spellID then
        LBP:HideOverlays(frame, spellID)
    else
        LBP:HideAllOverlays(frame)
    end
end

local function UpdateOverlayScale()
    if not (overlayFrame and ClassSupported()) then
        return
    end
    local scale = (Cfg().overlayScale) or 0.8
    if scale < 0.1 then
        scale = 0.1
    end
    if scale > 2 then
        scale = 2
    end

    LBP.overlay.sizeScale = scale
    LBP.overlay.longSide = 256 * scale
    LBP.overlay.shortSide = 128 * scale
    overlayFrame:SetSize(256 * scale, 256 * scale)

    for _, overlayList in pairs(LBP.overlay.inUse) do
        if overlayList then
            for i = 1, #overlayList do
                LBP:OverlayPointSize(overlayFrame, overlayList[i], 1)
            end
        end
    end
end

local function UpdateSoundSetting()
    if not ClassSupported() then
        return
    end
    LBP.disableSound = Cfg().disableSound and true or false
end

local function UpdateLBPState()
    if not ClassSupported() then
        return
    end
    if LBP.disableOverlay and LBP.disableButtonGlow then
        if LBP:isEnabled() then
            LBP:Disable()
        end
    else
        if not LBP:isEnabled() then
            LBP:Enable()
        end
    end
end

local function EnsureOverlayFrame()
    if overlayFrame then
        return overlayFrame
    end

    -- Same as ElvUI_VisualProcs: fixed center anchor, no mouse (clicks must pass through).
    overlayFrame = CreateFrame("Frame", "DragonUI_Enhanced_VisualProcsOverlay", UIParent)
    overlayFrame:SetSize(256, 256)
    overlayFrame:EnableMouse(false)
    overlayFrame:SetPoint("CENTER", UIParent, "CENTER")
    overlayFrame:Hide()
    return overlayFrame
end

local function StopOverlayTest()
    if not overlayFrame then
        return
    end
    overlayFrame.test = false
    if scanFrame then
        scanFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    LBP:HideAllOverlays(overlayFrame)
end

local function ToggleOverlayTest()
    if not (overlayFrame and ClassSupported() and overlayEnabled) then
        return
    end

    overlayFrame.test = not overlayFrame.test
    if overlayFrame.test then
        local path = LBP.mediaPath .. "overlay\\"
        LBP:HideAllOverlays(overlayFrame)

        local textures = LBP_Data and LBP_Data.OverlayTextures and LBP_Data.OverlayTextures[LBP.playerClass]
        if textures then
            local foundTop, foundLeft
            for _, data in pairs(textures) do
                if not foundTop and find(data[3], "Top") then
                    foundTop = true
                    LBP:ShowAllOverlays(overlayFrame, 100000, path .. data[2], data[3], data[4], data[5], data[6], data[7])
                elseif not foundLeft and find(data[3], "Left") then
                    foundLeft = true
                    LBP:ShowAllOverlays(overlayFrame, 100001, path .. data[2], data[3], data[4], data[5], data[6], data[7])
                end
                if foundTop and foundLeft then
                    break
                end
            end
        end

        if scanFrame then
            scanFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        end
    else
        StopOverlayTest()
    end
end

local function ToggleOverlay(force)
    if not ClassSupported() then
        return
    end
    EnsureOverlayFrame()

    local want = force
    if want == nil then
        want = Cfg().overlay ~= false
    end
    overlayEnabled = want and true or false
    LBP.disableOverlay = not overlayEnabled

    if overlayEnabled then
        LBP:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW", overlayFrame, OverlayShow)
        LBP:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE", overlayFrame, OverlayHide)
        overlayFrame:Show()
        UpdateOverlayScale()
    else
        LBP:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW", overlayFrame)
        LBP:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE", overlayFrame)
        StopOverlayTest()
        LBP:DisableOverlays()
        overlayFrame:Hide()
    end

    UpdateLBPState()
end

local function EnsureScanFrame()
    if scanFrame then
        return scanFrame
    end
    scanFrame = CreateFrame("Frame", "DragonUI_Enhanced_VisualProcsScan", UIParent)
    scanFrame:Hide()
    scanFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if overlayFrame and overlayFrame.test then
                ToggleOverlayTest()
            end
            return
        end
        if glowEnabled then
            ScanAllButtons()
        end
    end)
    -- ExtraBar does not use Blizzard action slots; light poll keeps glow in sync after drag-drop.
    scanFrame:SetScript("OnUpdate", function(self, elapsed)
        if not glowEnabled then
            return
        end
        extraScanElapsed = extraScanElapsed + elapsed
        if extraScanElapsed < 0.5 then
            return
        end
        extraScanElapsed = 0
        ScanExtraBarButtons()
    end)
    return scanFrame
end

local function SetScanEvents(enabled)
    EnsureScanFrame()
    local events = {
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "ACTIONBAR_SLOT_CHANGED",
        "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_SHAPESHIFT_FORM",
        "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_MACROS",
        "SPELLS_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED",
    }
    for i = 1, #events do
        if enabled then
            scanFrame:RegisterEvent(events[i])
        else
            scanFrame:UnregisterEvent(events[i])
        end
    end
    if enabled then
        scanFrame:Show()
        extraScanElapsed = 0
    else
        scanFrame:Hide()
    end
end

local function HookActionButtonUpdate()
    if actionButtonHooked or type(hooksecurefunc) ~= "function" then
        return
    end
    if type(ActionButton_Update) ~= "function" then
        return
    end
    hooksecurefunc("ActionButton_Update", function(button)
        if glowEnabled and button then
            UpdateButtonGlow(button)
        end
    end)
    actionButtonHooked = true
end

local function ToggleButtonGlow(force)
    if not ClassSupported() then
        return
    end

    local want = force
    if want == nil then
        want = Cfg().buttonGlow ~= false
    end
    glowEnabled = want and true or false
    LBP.disableButtonGlow = not glowEnabled

    if glowEnabled then
        HookActionButtonUpdate()
        SetScanEvents(true)
        ScanAllButtons()
    else
        SetScanEvents(false)
        ClearAllButtonTracking()
        LBP:DisableButtonGlows()
    end

    UpdateLBPState()
end

local function OnEnable()
    if not LBP then
        return
    end

    LBP.mediaPath = MEDIA_PATH
    EnsureOverlayFrame()
    EnsureScanFrame()
    UpdateSoundSetting()
    ToggleButtonGlow()
    UpdateOverlayScale()
    ToggleOverlay()
end

local function OnDisable()
    if not LBP then
        return
    end

    glowEnabled = false
    overlayEnabled = false
    LBP.disableButtonGlow = true
    LBP.disableOverlay = true
    SetScanEvents(false)
    ClearAllButtonTracking()
    LBP:DisableButtonGlows()
    if overlayFrame then
        LBP:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW", overlayFrame)
        LBP:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE", overlayFrame)
        StopOverlayTest()
        LBP:DisableOverlays()
        overlayFrame:Hide()
    end
    if LBP:isEnabled() then
        LBP:Disable()
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Visual Procs"]
    end,
    desc = function()
        return L["Show Cataclysm-style spell proc overlays and action-button glows on DragonUI bars."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        local unsupported = not ClassSupported()
        if unsupported then
            C:AddDescription(section, L["Your class has no supported proc overlays in the bundled data."])
        end

        C:AddToggle(section, {
            label = L["Overlay Frame"],
            desc = L["Show large spell-activation overlays near the center of the screen."],
            getFunc = function()
                return Cfg().overlay ~= false
            end,
            setFunc = function(val)
                Cfg().overlay = val and true or false
                if addon:IsFeatureEnabled(KEY) then
                    ToggleOverlay()
                end
            end,
            disabled = unsupported,
        })
        C:AddToggle(section, {
            label = L["Button Glow"],
            desc = L["Glow action buttons that become usable from a proc."],
            getFunc = function()
                return Cfg().buttonGlow ~= false
            end,
            setFunc = function(val)
                Cfg().buttonGlow = val and true or false
                if addon:IsFeatureEnabled(KEY) then
                    ToggleButtonGlow()
                end
            end,
            disabled = unsupported,
        })
        C:AddSlider(section, {
            label = L["Overlay Frame Scale"],
            min = 0.1,
            max = 2,
            step = 0.01,
            getFunc = function()
                return Cfg().overlayScale or 0.8
            end,
            setFunc = function(val)
                Cfg().overlayScale = val
                if addon:IsFeatureEnabled(KEY) then
                    UpdateOverlayScale()
                end
            end,
            disabled = function()
                return unsupported or Cfg().overlay == false
            end,
        })
        C:AddToggle(section, {
            label = L["Disable Sound"],
            desc = L["Disable playing sound on overlay proc."],
            getFunc = function()
                return Cfg().disableSound and true or false
            end,
            setFunc = function(val)
                Cfg().disableSound = val and true or false
                if addon:IsFeatureEnabled(KEY) then
                    UpdateSoundSetting()
                end
            end,
            disabled = function()
                return unsupported or Cfg().overlay == false
            end,
        })
        C:AddButton(section, {
            label = L["Preview Overlay"],
            desc = L["Show or hide a sample overlay (clears when entering combat)."],
            callback = function()
                if addon:IsFeatureEnabled(KEY) then
                    ToggleOverlayTest()
                end
            end,
            disabled = function()
                return unsupported or Cfg().overlay == false or not addon:IsFeatureEnabled(KEY)
            end,
        })
    end,
    Refresh = function()
        if not addon:IsFeatureEnabled(KEY) then
            return
        end
        UpdateSoundSetting()
        UpdateOverlayScale()
        ToggleOverlay()
        ToggleButtonGlow()
    end,
})
