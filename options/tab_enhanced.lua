-- DragonUI_Enhanced — Options tab registered into DragonUI_Options (LoD-safe).

local ADDON_NAME, addon = ...
local L = addon.L

local CATEGORIES = {
    { key = "general", labelKey = "General" },
    { key = "chat", labelKey = "Chat" },
    { key = "tools", labelKey = "Tools" },
    { key = "combat", labelKey = "Combat" },
}

local activeSubTab = "general"

local function Resolve(value, fallback)
    if type(value) == "function" then
        value = value()
    end
    if value == nil then
        return fallback
    end
    return value
end

local function BuildFeatureSection(scroll, C, def)
    local label = Resolve(def.label, def.key)
    local desc = Resolve(def.desc, nil)
    local section = C:AddSection(scroll, label)

    if desc then
        C:AddDescription(section, desc)
    end

    C:AddToggle(section, {
        label = string.format(L["Enable %s"], label),
        desc = def.requiresReload and L["Requires UI reload to fully disable."] or nil,
        getFunc = function()
            return addon:IsFeatureEnabled(def.key)
        end,
        setFunc = function(val)
            addon:SetFeatureEnabled(def.key, val)
            local Panel = _G.DragonUI and _G.DragonUI.OptionsPanel
            if Panel and Panel.SelectTab then
                Panel:SelectTab("enhanced")
            end
        end,
        requiresReload = def.requiresReload and true or false,
    })

    if type(def.BuildOptions) == "function" and addon:IsFeatureEnabled(def.key) then
        local ok, err = pcall(def.BuildOptions, section, C)
        if not ok and _G.DragonUI and _G.DragonUI.Debug then
            _G.DragonUI:Debug("Enhanced BuildOptions failed for " .. tostring(def.key) .. ": " .. tostring(err))
        end
    end
end

local function BuildCategory(scroll, categoryKey)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then
        return
    end
    local C = _G.DragonUI.PanelControls

    if categoryKey == "general" and addon.BuildLegacyOptions then
        local legacySection = C:AddSection(scroll, L["Legacy AddOns"])
        local okLegacy, errLegacy = pcall(addon.BuildLegacyOptions, addon, legacySection, C)
        if not okLegacy and _G.DragonUI and _G.DragonUI.Debug then
            _G.DragonUI:Debug("Enhanced legacy section failed: " .. tostring(errLegacy))
        end
    end

    local list = addon:GetFeaturesByCategory(categoryKey)

    if #list == 0 then
        local section = C:AddSection(scroll, L["Placeholder"])
        C:AddDescription(section, L["Features in this category will appear here as they are ported."])
        return
    end

    for i = 1, #list do
        local ok, err = pcall(BuildFeatureSection, scroll, C, list[i])
        if not ok and _G.DragonUI and _G.DragonUI.Debug then
            _G.DragonUI:Debug("Enhanced feature section failed: " .. tostring(err))
        end
    end
end

local function BuildEnhancedTab(scroll)
    if not _G.DragonUI or not _G.DragonUI.PanelControls then
        return
    end
    local C = _G.DragonUI.PanelControls
    local Panel = _G.DragonUI.OptionsPanel

    local builders = {}
    local subtabs = {}
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
        builders[cat.key] = function(s)
            BuildCategory(s, cat.key)
        end
        subtabs[#subtabs + 1] = {
            key = cat.key,
            label = L[cat.labelKey] or cat.labelKey,
        }
    end

    if not builders[activeSubTab] then
        activeSubTab = "general"
    end

    C:AddSubTabs(scroll, subtabs, activeSubTab, function(key)
        activeSubTab = key
        if Panel and Panel.SelectTab then
            Panel:SelectTab("enhanced")
        end
    end, builders)

    if not Panel.indexing then
        local b = builders[activeSubTab]
        if b then
            b(scroll)
        end
    end
end

local function TryRegister()
    if _G.DragonUI and _G.DragonUI.OptionsPanel then
        _G.DragonUI.OptionsPanel:RegisterTab(
            "enhanced",
            "增强 [by 斑比]",
            BuildEnhancedTab,
            1.6
        )
        return true
    end
    return false
end

if not TryRegister() then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, name)
        if name == "DragonUI_Options" and TryRegister() then
            f:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
