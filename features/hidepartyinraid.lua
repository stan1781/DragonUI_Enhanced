-- DragonUI_Enhanced — hide default party frames while in a raid.
-- DragonUI only hides them when the hidePartyInRaid CVar is on, and this client
-- can still report a party after a raid convert. This feature hides the frames
-- after Blizzard and DragonUI show them again.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "hidePartyInRaid"
local MAX_PARTY = 4

local active = false
local hooked = false

local function InRaid()
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

local function EditorOpen()
    local DUI = _G.DragonUI
    return DUI and DUI.EditorMode and DUI.EditorMode:IsActive()
end

local function ShouldHide()
    return active and InRaid() and not EditorOpen() and not InCombatLockdown()
end

local function HidePartyFrames()
    if not ShouldHide() then
        return
    end
    for i = 1, MAX_PARTY do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and frame:IsShown() then
            frame:Hide()
        end
    end
    if PartyMemberBackground and PartyMemberBackground:IsShown() then
        PartyMemberBackground:Hide()
    end
end

local function RestorePartyFrames()
    if InCombatLockdown() or EditorOpen() then
        return
    end
    if type(PartyMemberFrame_UpdateMember) ~= "function" then
        return
    end
    for i = 1, MAX_PARTY do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and UnitExists("party" .. i) then
            PartyMemberFrame_UpdateMember(frame)
        end
    end
end

local function InstallHooks()
    if hooked then
        return
    end
    hooked = true

    for i = 1, MAX_PARTY do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and not frame.DragonUIEnhanced_HideInRaid then
            hooksecurefunc(frame, "Show", function(self)
                if ShouldHide() then
                    self:Hide()
                end
            end)
            frame.DragonUIEnhanced_HideInRaid = true
        end
    end

    if type(PartyMemberFrame_UpdateMember) == "function" then
        hooksecurefunc("PartyMemberFrame_UpdateMember", function()
            HidePartyFrames()
        end)
    end
end

local eventFrame

local function OnEvent(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if active and InRaid() then
            HidePartyFrames()
        elseif not active then
            RestorePartyFrames()
        end
        return
    end
    if active and InRaid() then
        HidePartyFrames()
    end
end

local function EnsureEvents()
    if eventFrame then
        return
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
end

local function OnEnable()
    active = true
    EnsureEvents()
    eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    InstallHooks()
    HidePartyFrames()
end

local function OnDisable()
    active = false
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if InRaid() then
        RestorePartyFrames()
    end
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
