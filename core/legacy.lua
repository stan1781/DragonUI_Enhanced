-- DragonUI_Enhanced — superseded standalone addons checklist + login warning.

local ADDON_NAME, addon = ...
local L = addon.L

-- folder name → human reason (feature keys already covered by Enhanced)
local LEGACY = {
    {
        name = "MotionSpeed",
        features = "motionSpeed",
        noteKey = "legacy_MotionSpeed",
    },
    {
        name = "ChatBar",
        features = "chatEnhance / chatBar",
        noteKey = "legacy_ChatBar",
    },
    {
        name = "FriendsMenuXP",
        features = "friendsMenuXP",
        noteKey = "legacy_FriendsMenuXP",
    },
    {
        name = "ElvUI_TinyInspect",
        features = "inspectPanel",
        noteKey = "legacy_TinyInspect",
    },
    {
        name = "ElvUI_bbTools",
        features = "runeBar / equipmentHelper / friendSync",
        noteKey = "legacy_bbTools",
        -- Partial: keep if user still needs Unitscan remote / ArenaScreenshot / etc.
        soft = true,
    },
}

local function AddonPresent(name)
    local _, _, _, enabled, loadable, reason = GetAddOnInfo(name)
    if reason == "MISSING" then
        return false, false
    end
    -- enabled can be nil on some clients; treat loadable+loaded as active
    local loaded = IsAddOnLoaded(name)
    local on = loaded or (enabled ~= nil and enabled ~= 0 and enabled ~= false)
    return true, on or loaded
end

function addon:GetLegacyAddonList()
    return LEGACY
end

function addon:ScanLegacyAddons()
    local active = {}
    for i = 1, #LEGACY do
        local entry = LEGACY[i]
        local present, on = AddonPresent(entry.name)
        if present and on then
            active[#active + 1] = entry
        end
    end
    return active
end

function addon:ReportLegacyAddons(force)
    local active = self:ScanLegacyAddons()
    if #active == 0 then
        if force then
            print("|cff00ff00[DragonUI 增强]|r " .. (L["No conflicting standalone addons detected."] or "No conflicting standalone addons detected."))
        end
        return active
    end

    print("|cffff8000[DragonUI 增强]|r " .. (L["These standalone addons overlap with Enhanced — disable them in the AddOns list to avoid double hooks:"] or "Overlapping addons:"))
    for i = 1, #active do
        local e = active[i]
        local note = L[e.noteKey] or e.name
        local soft = e.soft and (" " .. (L["(optional if you still need other bbTools modules)"] or "(optional)")) or ""
        print(string.format("  - |cffffffff%s|r → %s%s", e.name, note, soft))
    end
    return active
end

function addon:BuildLegacyOptions(section, C)
    C:AddDescription(section, L["Disable these folders in Character Select → AddOns after Enhanced covers them. SavedVariables are not deleted."])

    local lines = {}
    for i = 1, #LEGACY do
        local e = LEGACY[i]
        local present, on = AddonPresent(e.name)
        local status
        if not present then
            status = L["(not installed)"]
        elseif on then
            status = "|cffff6666" .. L["(loaded — disable)"] .. "|r"
        else
            status = "|cff66ff66" .. L["(disabled OK)"] .. "|r"
        end
        lines[#lines + 1] = string.format("%s %s — %s", e.name, status, L[e.noteKey] or e.features)
    end
    C:AddDescription(section, table.concat(lines, "\n"))

    C:AddButton(section, {
        label = L["Recheck conflicting addons"],
        callback = function()
            addon:ReportLegacyAddons(true)
        end,
    })
end

-- One chat dump per login while overlaps remain (not permanently muted).
local warnedThisSession = false

function addon:MaybeWarnLegacyAddons()
    if warnedThisSession then
        return
    end
    warnedThisSession = true
    local active = self:ScanLegacyAddons()
    if #active == 0 then
        return
    end
    -- Soft-only overlaps (e.g. bbTools kept for Unitscan) still get a quieter tip.
    self:ReportLegacyAddons(false)
end
