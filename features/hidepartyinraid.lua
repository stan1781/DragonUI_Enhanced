-- DragonUI_Enhanced — hide default party frames in a raid group or raid instance.
-- DragonUI shows PartyMemberFrame again about half a second after zoning, and a
-- direct raid entry can still report party members. Re-apply the hide every frame
-- while the player is in a raid so that later Show() calls do not stick.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "hidePartyInRaid"
local MAX_PARTY = 4

local active = false
local forced = false
local watch

local function EditorOpen()
    local DUI = _G.DragonUI
    return DUI and DUI.EditorMode and DUI.EditorMode.IsActive and DUI.EditorMode:IsActive()
end

local function InRaidContext()
    if UnitInRaid and UnitInRaid("player") then
        return true
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return true
    end
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "raid" then
            return true
        end
    end
    return false
end

local function HidePartyFrames()
    forced = true
    local locked = InCombatLockdown()
    for i = 1, MAX_PARTY do
        local frame = _G["PartyMemberFrame" .. i]
        if frame then
            if frame:GetAlpha() ~= 0 then
                frame:SetAlpha(0)
            end
            if not locked and frame:IsShown() then
                frame:Hide()
            end
        end
    end
    if PartyMemberBackground then
        if PartyMemberBackground:GetAlpha() ~= 0 then
            PartyMemberBackground:SetAlpha(0)
        end
        if not locked and PartyMemberBackground:IsShown() then
            PartyMemberBackground:Hide()
        end
    end
    -- Party aura icons are parented to UIParent, so they stay up after the unit frame hides.
    for i = 1, MAX_PARTY do
        local host = _G["DragonUI_Enhanced_PartyAura" .. i]
        if host and host:IsShown() then
            host:Hide()
        end
    end
end

local function RestorePartyFrames()
    if not forced then
        return
    end
    if InCombatLockdown() or EditorOpen() then
        return
    end
    forced = false
    for i = 1, MAX_PARTY do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and frame:GetAlpha() == 0 then
            frame:SetAlpha(1)
        end
    end
    if PartyMemberBackground and PartyMemberBackground:GetAlpha() == 0 then
        PartyMemberBackground:SetAlpha(1)
    end
    if type(PartyMemberFrame_UpdateMember) ~= "function" then
        return
    end
    for i = 1, MAX_PARTY do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and UnitExists("party" .. i) then
            -- Refreshes the unit frame and the Enhanced aura icons hooked to it.
            PartyMemberFrame_UpdateMember(frame)
        end
    end
end

local function OnUpdate()
    if not active or EditorOpen() then
        if forced then
            RestorePartyFrames()
        end
        return
    end
    if InRaidContext() then
        HidePartyFrames()
    elseif forced then
        RestorePartyFrames()
    end
end

local function OnEnable()
    active = true
    if not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnUpdate", OnUpdate)
    end
    watch:Show()
    OnUpdate()
end

local function OnDisable()
    active = false
    if watch then
        watch:Hide()
    end
    RestorePartyFrames()
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Hide Party Frames in Raid"]
    end,
    desc = function()
        return L["Hide DragonUI party frames while you are in a raid. They come back when you return to a party."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
