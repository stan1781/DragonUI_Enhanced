-- DragonUI_Enhanced — cast bars on party member frames.
-- One thin bar under each DragonUI mana bar. Party tokens only; raid frames stay untouched.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "partyCastbar"
local MAX_PARTY = 4
local BAR_HEIGHT = 10
local BAR_GAP = 1
local FLASH_TIME = 0.4

local CAST_COLOR = { 1, 0.7, 0 }
local CHANNEL_COLOR = { 0, 1, 0 }
local INTERRUPT_COLOR = { 1, 0, 0 }
local NAME_COLOR = { 1, 1, 1 }
local LOCKED_NAME_COLOR = { 1, 0.45, 0.45 }

local BARS = {}
local active = false
local pendingCreate = false

local watcher = CreateFrame("Frame")
watcher:Hide()

local function ManaBar(parent)
    if parent.DragonUI_ManaBar then
        return parent.DragonUI_ManaBar
    end
    local name = parent:GetName()
    return name and _G[name .. "ManaBar"] or nil
end

local function LayoutBar(bar)
    local parent = bar.parent
    local mana = parent and ManaBar(parent)
    if not mana then
        return
    end
    if bar._anchor == mana then
        return
    end
    bar._anchor = mana
    bar:ClearAllPoints()
    bar:SetHeight(BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", mana, "BOTTOMLEFT", 0, -BAR_GAP)
    bar:SetPoint("TOPRIGHT", mana, "BOTTOMRIGHT", 0, -BAR_GAP)
    local level = (parent:GetFrameLevel() or 0) + 5
    if bar:GetFrameLevel() ~= level then
        bar:SetFrameLevel(level)
    end
end

local function HideBar(bar)
    bar.flashUntil = nil
    bar:Hide()
    bar.icon:Hide()
end

local function PlaceName(bar, hasIcon)
    bar.name:ClearAllPoints()
    if hasIcon then
        bar.name:SetPoint("LEFT", bar.icon, "RIGHT", 1, 0)
    else
        bar.name:SetPoint("LEFT", bar, "LEFT", 2, 0)
    end
    bar.name:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
end

local function ReadCast(unit)
    local name, _, text, texture, startMS, endMS, isTrade, _, notInterruptible = UnitCastingInfo(unit)
    if not name then
        name, _, text, texture, startMS, endMS, isTrade, notInterruptible = UnitChannelInfo(unit)
        if not name or isTrade then
            return nil
        end
        return {
            name = text or name,
            icon = texture,
            start = (startMS or 0) / 1000,
            finish = (endMS or 0) / 1000,
            channeling = true,
            notInterruptible = notInterruptible and true or false,
        }
    end
    if isTrade then
        return nil
    end
    return {
        name = text or name,
        icon = texture,
        start = (startMS or 0) / 1000,
        finish = (endMS or 0) / 1000,
        channeling = false,
        notInterruptible = notInterruptible and true or false,
    }
end

local function ApplyCast(bar, info)
    LayoutBar(bar)
    local now = GetTime()
    local duration = info.finish - info.start
    if duration <= 0 or now >= info.finish then
        HideBar(bar)
        return false
    end

    local progress
    if info.channeling then
        progress = (info.finish - now) / duration
        bar:SetStatusBarColor(CHANNEL_COLOR[1], CHANNEL_COLOR[2], CHANNEL_COLOR[3])
    else
        progress = (now - info.start) / duration
        bar:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    end
    if progress < 0 then
        progress = 0
    elseif progress > 1 then
        progress = 1
    end
    bar:SetValue(progress)

    if bar._spell ~= info.name then
        bar._spell = info.name
        bar.name:SetText(info.name or "")
    end
    if info.notInterruptible then
        bar.name:SetTextColor(LOCKED_NAME_COLOR[1], LOCKED_NAME_COLOR[2], LOCKED_NAME_COLOR[3])
    else
        bar.name:SetTextColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3])
    end

    local hasIcon = info.icon and true or false
    if hasIcon then
        if bar._icon ~= info.icon then
            bar._icon = info.icon
            bar.icon:SetTexture(info.icon)
        end
        if not bar.icon:IsShown() then
            bar.icon:Show()
        end
    else
        bar._icon = nil
        bar.icon:Hide()
    end
    if bar._hasIcon ~= hasIcon then
        bar._hasIcon = hasIcon
        PlaceName(bar, hasIcon)
    end

    bar:Show()
    return true
end

local function UpdateBar(index)
    local bar = BARS[index]
    if not bar then
        return false
    end
    if bar.flashUntil then
        if GetTime() >= bar.flashUntil then
            HideBar(bar)
            return false
        end
        bar:Show()
        return true
    end

    local unit = "party" .. index
    if not UnitExists(unit) then
        HideBar(bar)
        return false
    end
    local info = ReadCast(unit)
    if not info then
        HideBar(bar)
        return false
    end
    return ApplyCast(bar, info)
end

local function AnyVisible()
    local any = false
    for index = 1, MAX_PARTY do
        if UpdateBar(index) then
            any = true
        end
    end
    return any
end

local function Kick()
    if not active then
        return
    end
    if AnyVisible() then
        watcher:Show()
    else
        watcher:Hide()
    end
end

local function PartyIndex(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local index = tonumber(unit:match("^party(%d)$"))
    if index and index >= 1 and index <= MAX_PARTY then
        return index
    end
    return nil
end

local function BeginInterrupt(index)
    local bar = BARS[index]
    if not bar or not bar:IsShown() or bar.flashUntil then
        return
    end
    bar.flashUntil = GetTime() + FLASH_TIME
    bar:SetStatusBarColor(INTERRUPT_COLOR[1], INTERRUPT_COLOR[2], INTERRUPT_COLOR[3])
    bar:SetValue(1)
    bar:Show()
end

local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.parent = parent
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()
    bar:EnableMouse(false)

    local texture = "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(texture)
    bar:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(texture)
    bg:SetVertexColor(0, 0, 0, 0.65)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
    icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    bar.icon = icon

    local name = bar:CreateFontString(nil, "OVERLAY")
    local font = addon.theme and addon.theme:GetPrimaryFont() or STANDARD_TEXT_FONT
    name:SetFont(font, 8, "OUTLINE")
    name:SetJustifyH("CENTER")
    name:SetJustifyV("MIDDLE")
    name:SetWordWrap(false)
    name:SetTextColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3])
    bar.name = name
    PlaceName(bar, false)

    LayoutBar(bar)
    return bar
end

local function EnsureBars()
    if BARS[1] then
        pendingCreate = false
        return true
    end
    if InCombatLockdown() then
        pendingCreate = true
        return false
    end
    for index = 1, MAX_PARTY do
        local parent = _G["PartyMemberFrame" .. index]
        if not parent then
            pendingCreate = true
            return false
        end
        BARS[index] = CreateBar(parent)
    end
    pendingCreate = false
    return true
end

local CAST_EVENTS = {
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
}

local function OnEvent(_, event, unit)
    if not active then
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingCreate then
            EnsureBars()
        end
        Kick()
        return
    end
    if event == "PARTY_MEMBERS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        EnsureBars()
        Kick()
        return
    end
    if not CAST_EVENTS[event] then
        return
    end
    local index = PartyIndex(unit)
    if not index then
        return
    end
    if not BARS[1] and not EnsureBars() then
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        BeginInterrupt(index)
    end
    Kick()
end

watcher:SetScript("OnEvent", OnEvent)
watcher:SetScript("OnUpdate", function()
    if not AnyVisible() then
        watcher:Hide()
    end
end)

local function RegisterEvents()
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
    for event in pairs(CAST_EVENTS) do
        watcher:RegisterEvent(event)
    end
end

local function OnEnable()
    active = true
    RegisterEvents()
    EnsureBars()
    Kick()
end

local function OnDisable()
    active = false
    pendingCreate = false
    watcher:Hide()
    watcher:UnregisterAllEvents()
    for index = 1, MAX_PARTY do
        local bar = BARS[index]
        if bar then
            HideBar(bar)
        end
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Party Cast Bars"]
    end,
    desc = function()
        return L["Show a cast bar under each party member frame while they are casting or channeling."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
