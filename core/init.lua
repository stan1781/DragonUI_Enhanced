-- DragonUI_Enhanced — bootstrap, feature registry, slash command.

local ADDON_NAME, addon = ...

addon._dir = "Interface\\AddOns\\DragonUI_Enhanced\\"
_G.DragonUI_Enhanced = addon

local _acl = LibStub("AceLocale-3.0-DragonUIEnhanced")
local _localeMeta = { __index = _acl:GetLocale("DragonUI_Enhanced", "enUS") }
addon.L = setmetatable({}, _localeMeta)

function addon.RefreshLocale()
    local DUI = _G.DragonUI
    local activeLocale = (DUI and DUI.GetActiveLocale and DUI.GetActiveLocale()) or GetLocale()
    if activeLocale == "enGB" then
        activeLocale = "enUS"
    end
    _localeMeta.__index = _acl:GetLocale("DragonUI_Enhanced", activeLocale)
end

-- ---------------------------------------------------------------------------
-- Feature registry
-- ---------------------------------------------------------------------------

local features = {}
local featureOrder = {}

function addon:RegisterFeature(key, def)
    if not key or type(def) ~= "table" then
        return
    end
    if not features[key] then
        featureOrder[#featureOrder + 1] = key
    end
    def.key = key
    def.category = def.category or "general"
    if def.default == nil then
        def.default = true
    end
    features[key] = def

    -- Seed AceDB defaults so late-registered features still get a profile slot.
    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.features
    if defaults and not defaults[key] then
        defaults[key] = { enabled = def.default and true or false }
    end
end

function addon:GetFeature(key)
    return features[key]
end

function addon:GetRegisteredFeatures()
    local list = {}
    for i = 1, #featureOrder do
        local key = featureOrder[i]
        list[#list + 1] = features[key]
    end
    return list
end

function addon:GetFeaturesByCategory(category)
    local list = {}
    for i = 1, #featureOrder do
        local def = features[featureOrder[i]]
        if def and def.category == category then
            list[#list + 1] = def
        end
    end
    return list
end

function addon:GetFeatureConfig(key)
    if not addon.db or not addon.db.profile then
        return nil
    end
    local feats = addon.db.profile.features
    if not feats then
        feats = {}
        addon.db.profile.features = feats
    end
    local cfg = feats[key]
    if type(cfg) ~= "table" then
        local def = features[key]
        cfg = { enabled = def and def.default ~= false }
        feats[key] = cfg
    end
    return cfg
end

function addon:IsFeatureEnabled(key)
    local cfg = self:GetFeatureConfig(key)
    return cfg and cfg.enabled and true or false
end

-- Runtime start/stop only — does not mutate the enabled flag in SavedVariables.
function addon:StartFeature(key)
    local def = features[key]
    if not def then
        return false
    end
    if def._active then
        return true
    end
    if type(def.OnEnable) == "function" then
        local ok, err = pcall(def.OnEnable, def)
        if not ok then
            geterrorhandler()("DragonUI_Enhanced StartFeature(" .. tostring(key) .. "): " .. tostring(err))
            return false
        end
    end
    def._active = true
    return true
end

function addon:StopFeature(key)
    local def = features[key]
    if not def then
        return false
    end
    if not def._active then
        return true
    end
    if type(def.OnDisable) == "function" then
        local ok, err = pcall(def.OnDisable, def)
        if not ok then
            geterrorhandler()("DragonUI_Enhanced StopFeature(" .. tostring(key) .. "): " .. tostring(err))
        end
    end
    def._active = false
    return true
end

function addon:EnableFeature(key)
    local cfg = self:GetFeatureConfig(key)
    if cfg then
        cfg.enabled = true
    end
    return self:StartFeature(key)
end

function addon:DisableFeature(key)
    local cfg = self:GetFeatureConfig(key)
    if cfg then
        cfg.enabled = false
    end
    return self:StopFeature(key)
end

function addon:SetFeatureEnabled(key, enabled)
    if enabled then
        return self:EnableFeature(key)
    end
    local def = features[key]
    local ok = self:DisableFeature(key)
    if ok and def and def.requiresReload and _G.StaticPopup_Show then
        StaticPopup_Show("DRAGONUI_RELOAD_UI")
    end
    return ok
end

function addon:ApplyAllFeatures()
    for i = 1, #featureOrder do
        local key = featureOrder[i]
        if self:IsFeatureEnabled(key) then
            self:StartFeature(key)
        else
            self:StopFeature(key)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Open options → Enhanced tab
-- ---------------------------------------------------------------------------

function addon:OpenOptions()
    local DUI = _G.DragonUI
    if not DUI then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if DUI.Error then
            DUI:Error(addon.L["Cannot open options during combat."] or "Cannot open options during combat.")
        end
        return
    end
    if not IsAddOnLoaded("DragonUI_Options") then
        local reason = select(6, GetAddOnInfo("DragonUI_Options"))
        if reason ~= "MISSING" and reason ~= "DISABLED" then
            LoadAddOn("DragonUI_Options")
        end
    end
    if DUI.ToggleOptionsUI then
        DUI:ToggleOptionsUI("enhanced")
    elseif DUI.OptionsPanel and DUI.OptionsPanel.Open then
        DUI.OptionsPanel:Open("enhanced")
    end
end

-- ---------------------------------------------------------------------------
-- AceAddon lifecycle
-- ---------------------------------------------------------------------------

addon.core = LibStub("AceAddon-3.0"):NewAddon(
    "DragonUI_Enhanced",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0"
)

function addon.core:OnInitialize()
    addon.db = LibStub("AceDB-3.0"):New("DragonUI_EnhancedDB", addon.defaults, true)
    addon.RefreshLocale()

    self:RegisterChatCommand("duie", function()
        addon:OpenOptions()
    end)
    self:RegisterChatCommand("dragonuie", function()
        addon:OpenOptions()
    end)

    addon.db.RegisterCallback(addon.core, "OnProfileChanged", "OnProfileRefresh")
    addon.db.RegisterCallback(addon.core, "OnProfileCopied", "OnProfileRefresh")
    addon.db.RegisterCallback(addon.core, "OnProfileReset", "OnProfileRefresh")
end

function addon.core:OnProfileRefresh()
    -- Stop runtime state, then re-apply from the new profile's enabled flags.
    for i = 1, #featureOrder do
        addon:StopFeature(featureOrder[i])
    end
    addon:ApplyAllFeatures()
end

function addon.core:OnEnable()
    addon.RefreshLocale()
    addon:ApplyAllFeatures()
end
