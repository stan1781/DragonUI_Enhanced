-- DragonUI_Enhanced — unit tooltip: who in the group is targeting this unit.
-- Only party and raid members are visible to the client. The player is omitted.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "targetTip"

local active = false
local hooked = false
local names = {}

local function Hex(r, g, b)
    return string.format(
        "%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5)
    )
end

local function ColoredName(unit)
    local name = UnitName(unit)
    if not name or name == "" then
        return nil
    end
    local r, g, b = 1, 1, 1
    if UnitIsPlayer(unit) and not (UnitHasVehicleUI and UnitHasVehicleUI(unit)) then
        local _, class = UnitClass(unit)
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then
            r, g, b = color.r, color.g, color.b
        end
    else
        local reaction = UnitReaction(unit, "player")
        local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if color then
            r, g, b = color.r, color.g, color.b
        end
    end
    return string.format("|cff%s%s|r", Hex(r, g, b), name)
end

local function ResolveUnit(tt)
    if tt.GetUnit then
        local _, unit = tt:GetUnit()
        if unit and UnitExists(unit) then
            return unit
        end
    end
    if GetMouseFocus then
        local focus = GetMouseFocus()
        if focus and focus.GetAttribute then
            local attr = focus:GetAttribute("unit")
            if attr and UnitExists(attr) then
                return attr
            end
        end
    end
    if UnitExists("mouseover") then
        return "mouseover"
    end
end

local function AddTargetLine(tt, unit)
    if unit == "player" then
        return
    end
    local unitTarget = unit .. "target"
    if not UnitExists(unitTarget) then
        return
    end
    local colored = ColoredName(unitTarget)
    if not colored then
        return
    end
    tt:AddDoubleLine((TARGET or "Target") .. ":", colored, 1, 1, 1)
end

local function AddTargetedBy(tt, unit)
    local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
    local total = inRaid and GetNumRaidMembers() or (GetNumPartyMembers and GetNumPartyMembers() or 0)
    if not total or total < 1 then
        return
    end
    local prefix = inRaid and "raid" or "party"
    local count = 0
    for i = 1, total do
        local groupUnit = prefix .. i
        if UnitExists(groupUnit)
            and not UnitIsUnit(groupUnit, "player")
            and UnitIsUnit(groupUnit .. "target", unit)
        then
            local colored = ColoredName(groupUnit)
            if colored then
                count = count + 1
                names[count] = colored
            end
        end
    end
    for i = count + 1, #names do
        names[i] = nil
    end
    if count > 0 then
        tt:AddLine(
            string.format("%s (|cffffffff%d|r): %s", L["Targeted By:"], count, table.concat(names, ", ")),
            1, 1, 1,
            true
        )
    end
end

local function OnTooltipSetUnit(tt)
    if not active or not tt then
        return
    end
    local unit = ResolveUnit(tt)
    if not unit then
        return
    end
    AddTargetLine(tt, unit)
    AddTargetedBy(tt, unit)
end

local function OnEnable()
    active = true
    if hooked or not GameTooltip or not GameTooltip.HookScript then
        return
    end
    GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
    hooked = true
end

local function OnDisable()
    active = false
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Targeted By"]
    end,
    desc = function()
        return L["On unit tooltips, list party and raid members who are targeting that unit. Also shows that unit's target."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
