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
    fontString:SetFont(STANDARD_TEXT_FONT, size)
    fontString:SetTextColor(1, 1, 1)
end
