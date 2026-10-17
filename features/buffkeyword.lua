-- DragonUI_Enhanced — buff keyword blocklist for target/focus/party.
-- Ported from ElvUI UnitFrames/Elements/Auras.lua (keyword filter only).
-- Wraps UnitBuff so Blizzard TargetFrame/PartyMemberFrame skip blocked auras without gaps.
-- Also remaps GameTooltip:SetUnitBuff indices (C API ignores the Lua UnitBuff wrap).

local ADDON_NAME, addon = ...
local L = addon.L

local find = string.find
local gsub = string.gsub
local KEY = "buffKeyword"

local DEFAULT_KEYWORDS = {
    "艾泽拉斯的",
    "部落士兵",
    "联盟士兵",
    "霜之哀伤",
    "使者的",
    "天命",
    "挑战者的",
}

local rawUnitBuff = UnitBuff
local rawSetUnitBuff
local wrapInstalled = false
local active = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function GetKeywords()
    local cfg = Cfg()
    local list = cfg and cfg.keywords
    if type(list) ~= "table" or #list == 0 then
        return DEFAULT_KEYWORDS
    end
    return list
end

local function ShouldFilterUnit(unit)
    if not unit then return false end
    if unit == "target" or unit == "focus" then
        return true
    end
    if find(unit, "^party%d+$") then
        return true
    end
    return false
end

local function IsBuffBlockedByKeyword(name, skipKeyword)
    if not name then return false end
    local list = GetKeywords()
    for i = 1, #list do
        local keyword = list[i]
        if keyword and keyword ~= "" and keyword ~= skipKeyword and find(name, keyword, 1, true) then
            return true
        end
    end
    return false
end

-- Map a filtered (display) buff index to the real UnitBuff index.
-- Returns realIndex, resultsTable; or nil when the display index is past the end.
local function MapVirtualBuffIndex(unit, index, filter)
    -- Match ElvUI: on target, allow auras whose only hit is the "天命" keyword.
    local skipKeyword = (unit == "target") and "天命" or nil
    local shown = 0
    local real = 0
    while true do
        real = real + 1
        local results = { rawUnitBuff(unit, real, filter) }
        local name = results[1]
        if not name then
            return nil
        end
        if not IsBuffBlockedByKeyword(name, skipKeyword) then
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

local function FilteredUnitBuff(unit, index, filter)
    if not active or type(index) ~= "number" or not ShouldFilterUnit(unit) then
        return rawUnitBuff(unit, index, filter)
    end
    local _, results = MapVirtualBuffIndex(unit, index, filter)
    if not results then
        return nil
    end
    return unpack(results)
end

local function FilteredSetUnitBuff(self, unit, index, filter)
    if active and type(index) == "number" and ShouldFilterUnit(unit) then
        local real = MapVirtualBuffIndex(unit, index, filter)
        if not real then
            return
        end
        index = real
    end
    return rawSetUnitBuff(self, unit, index, filter)
end

local function InstallWrap()
    if wrapInstalled then return end
    rawUnitBuff = UnitBuff
    _G.UnitBuff = FilteredUnitBuff
    wrapInstalled = true
end

local function InstallTooltipHook()
    if rawSetUnitBuff then
        return
    end
    if not GameTooltip or type(GameTooltip.SetUnitBuff) ~= "function" then
        return
    end
    rawSetUnitBuff = GameTooltip.SetUnitBuff
    GameTooltip.SetUnitBuff = FilteredSetUnitBuff
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
    for i = 1, 4 do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and UnitExists("party" .. i) and PartyMemberFrame_UpdateMember then
            PartyMemberFrame_UpdateMember(frame)
        end
    end
end

local function KeywordsToText(list)
    if type(list) ~= "table" then return "" end
    return table.concat(list, ", ")
end

local function TextToKeywords(text)
    local list = {}
    if type(text) ~= "string" then return list end
    -- AceGUI EditBox is single-line; accept comma / Chinese comma / semicolon / newline.
    text = gsub(text, "[,;，；\r\n]+", "\n")
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        line = strtrim and strtrim(line) or line:match("^%s*(.-)%s*$")
        if line and line ~= "" then
            list[#list + 1] = line
        end
    end
    return list
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
    default = true,
    label = function() return L["Buff Keyword Block"] end,
    desc = function()
        return L["Hide target/focus/party buffs whose names contain blocked keywords (private-server junk auras)."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["One keyword per line. On target, auras matching only「天命」are kept."])
        C:AddEditBox(section, {
            label = L["Blocked Keywords"],
            desc = L["Press Enter to save. Separate keywords with commas. Leave empty to restore defaults."],
            getFunc = function()
                local cfg = Cfg()
                local list = cfg.keywords
                if type(list) ~= "table" or #list == 0 then
                    list = DEFAULT_KEYWORDS
                end
                return KeywordsToText(list)
            end,
            setFunc = function(val)
                local cfg = Cfg()
                local list = TextToKeywords(val)
                if #list == 0 then
                    cfg.keywords = nil
                else
                    cfg.keywords = list
                end
                if active then
                    RefreshFrames()
                end
            end,
        })
        C:AddButton(section, {
            label = L["Reset Keywords"],
            desc = L["Restore the default junk-buff keyword list."],
            callback = function()
                Cfg().keywords = nil
                local Panel = _G.DragonUI and _G.DragonUI.OptionsPanel
                if Panel and Panel.SelectTab then
                    Panel:SelectTab("enhanced")
                end
                if active then
                    RefreshFrames()
                end
            end,
        })
    end,
})

-- Expose for diagnostics / other features.
addon.BuffKeyword = {
    IsBlocked = IsBuffBlockedByKeyword,
    MapIndex = MapVirtualBuffIndex,
    Defaults = DEFAULT_KEYWORDS,
}
