-- DragonUI_Enhanced — thin theme wrappers around DragonUI chrome.
-- Prefer host NineSlice / PanelControls so Enhanced UI matches DragonUI.

local ADDON_NAME, addon = ...

addon.theme = addon.theme or {}

local function Host()
    return _G.DragonUI
end

function addon.theme:GetPanelControls()
    local DUI = Host()
    return DUI and DUI.PanelControls or nil
end

function addon.theme:AddNineslice(frame)
    local DUI = Host()
    if DUI and DUI.AddNineslice then
        DUI.AddNineslice(frame)
        return true
    end
    return false
end

function addon.theme:SetNinesliceState(frame, selected)
    local DUI = Host()
    if DUI and DUI.SetNinesliceState then
        DUI.SetNinesliceState(frame, selected)
        return true
    end
    return false
end

function addon.theme:ShowNineslice(frame)
    local DUI = Host()
    if DUI and DUI.ShowNineslice then
        DUI.ShowNineslice(frame)
        return true
    end
    return false
end

function addon.theme:HideNineslice(frame)
    local DUI = Host()
    if DUI and DUI.HideNineslice then
        DUI.HideNineslice(frame)
        return true
    end
    return false
end

-- Apply a GameFont that follows client UI scale; keep color neutral (white/highlight).
function addon.theme:ApplyFont(fontString, size)
    if not fontString then return end
    size = size or 11
    local path = self:GetPrimaryFont()
    fontString:SetFont(path, size)
    fontString:SetTextColor(1, 1, 1)
end

function addon.theme:GetForeverUI()
    local DUI = Host()
    return DUI and DUI.ForeverUI or nil
end

function addon.theme:GetPrimaryFont()
    local DUI = Host()
    if DUI and DUI.Fonts and DUI.Fonts.PRIMARY then
        return DUI.Fonts.PRIMARY
    end
    return STANDARD_TEXT_FONT
end

function addon.theme:GetChromeColors()
    local FUI = self:GetForeverUI()
    return (FUI and FUI.Colors) or nil
end

-- Skin an existing frame with ForeverUI diamond-metal dialog chrome (DragonUI look).
function addon.theme:SkinDialog(frame, opts)
    local FUI = self:GetForeverUI()
    if FUI and FUI.SkinDialog then
        return FUI.SkinDialog(frame, opts or {})
    end
    return nil
end
