-- DragonUI_Enhanced — target/focus debuffs limited to player and pet casts.
-- Wraps UnitDebuff the same way buffkeyword wraps UnitBuff, and remaps
-- GameTooltip:SetUnitDebuff because that C API ignores the Lua wrap.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "ownDebuffs"

local rawUnitDebuff = UnitDebuff
local rawSetUnitDebuff
local wrapInstalled = false
local active = false

local function ShouldFilterUnit(unit)
    return unit == "target" or unit == "focus"
end

local function IsOwnCaster(caster)
    if not caster or caster == "" then
        return false
    end
    if caster == "player" or caster == "pet" then
        return true
    end
    if UnitExists(caster) then
        if UnitIsUnit(caster, "player") then
            return true
        end
        if UnitExists("pet") and UnitIsUnit(caster, "pet") then
            return true
        end
    end
    local playerName = UnitName("player")
    if playerName and caster == playerName then
        return true
    end
    if UnitExists("pet") then
        local petName = UnitName("pet")
        if petName and caster == petName then
            return true
        end
    end
    return false
end

-- Map a filtered (display) debuff index to the real UnitDebuff index.
-- Returns realIndex, resultsTable; or nil when the display index is past the end.
local function MapVirtualDebuffIndex(unit, index, filter)
    local shown = 0
    local real = 0
    while true do
        real = real + 1
        local results = { rawUnitDebuff(unit, real, filter) }
        local name = results[1]
        if not name then
            return nil
        end
        if IsOwnCaster(results[8]) then
            shown = shown + 1
            if shown == index then
                return real, results
            end
        end
        if real > 80 then
            return nil
        end
    end
end

local function FilteredUnitDebuff(unit, index, filter)
    if not active or type(index) ~= "number" or not ShouldFilterUnit(unit) then
        return rawUnitDebuff(unit, index, filter)
    end
    local _, results = MapVirtualDebuffIndex(unit, index, filter)
    if not results then
        return nil
    end
    return unpack(results)
end

local function FilteredSetUnitDebuff(self, unit, index, filter)
    if active and type(index) == "number" and ShouldFilterUnit(unit) then
        local real = MapVirtualDebuffIndex(unit, index, filter)
        if not real then
            return
        end
        index = real
    end
    return rawSetUnitDebuff(self, unit, index, filter)
end

local function InstallWrap()
    if wrapInstalled then return end
    rawUnitDebuff = UnitDebuff
    _G.UnitDebuff = FilteredUnitDebuff
    wrapInstalled = true
end

local function InstallTooltipHook()
    if rawSetUnitDebuff then
        return
    end
    if not GameTooltip or type(GameTooltip.SetUnitDebuff) ~= "function" then
        return
    end
    rawSetUnitDebuff = GameTooltip.SetUnitDebuff
    GameTooltip.SetUnitDebuff = FilteredSetUnitDebuff
end

local function RefreshFrames()
    local DUI = _G.DragonUI
    if DUI and DUI.RefreshTargetFocusAuraLayout then
        DUI.RefreshTargetFocusAuraLayout()
    elseif type(_G.TargetFrame_UpdateAuras) == "function" then
        if TargetFrame and UnitExists("target") then
            TargetFrame_UpdateAuras(TargetFrame)
        end
        if FocusFrame and UnitExists("focus") then
            TargetFrame_UpdateAuras(FocusFrame)
        end
    end
end

local function OnEnable()
    InstallWrap()
    InstallTooltipHook()
    active = true
    RefreshFrames()
end

local function OnDisable()
    active = false
    RefreshFrames()
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = false,
    label = function() return L["Own Debuffs Only"] end,
    desc = function()
        return L["On target and focus, show only debuffs cast by you or your pet. Debuffs with an unknown caster are hidden."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
