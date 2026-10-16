-- DragonUI_Enhanced — timed debuffs above the player health bar.
-- Permanent debuffs (no duration) are skipped. The corner debuff frame is left alone.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "playerHealthDebuffs"
local SCAN_MAX = 40
local GAP = 2
local TOP_PAD = 4
local ICON_SIZE = 18

local active = false
local watching = false
local host
local buttons = {}

local function HealthBar()
    return _G.PlayerFrameHealthBar
end

local function EnsureHost()
    if host then
        return host
    end
    local bar = HealthBar()
    if not bar then
        return nil
    end
    host = CreateFrame("Frame", "DragonUIEnhancedPlayerHealthDebuffs", PlayerFrame)
    host:SetFrameLevel((PlayerFrame:GetFrameLevel() or 0) + 12)
    host:SetSize(ICON_SIZE, ICON_SIZE)
    return host
end

local function EnsureButton(index)
    local button = buttons[index]
    if button then
        return button
    end
    button = CreateFrame("Button", nil, host)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:EnableMouse(true)
    button:Hide()

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetReverse(true)
    button.cooldown = cooldown

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    border:SetAllPoints(button)
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    button.border = border

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 0)
    button.count = count

    button:SetScript("OnEnter", function(self)
        if not self.auraIndex then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetUnitDebuff("player", self.auraIndex)
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    buttons[index] = button
    return button
end

local function HideFrom(index)
    for i = index, #buttons do
        local button = buttons[i]
        if button then
            button.auraIndex = nil
            button._expiration = nil
            button._duration = nil
            button:Hide()
        end
    end
end

local function Refresh()
    if not active then
        if host then
            host:Hide()
        end
        return
    end
    local bar = HealthBar()
    local holder = EnsureHost()
    if not bar or not holder or not bar:IsShown() then
        HideFrom(1)
        if holder then
            holder:Hide()
        end
        return
    end

    local shown = {}
    for index = 1, SCAN_MAX do
        local name, _, icon, count, debuffType, duration, expirationTime = UnitDebuff("player", index)
        if not name then
            break
        end
        if duration and duration > 0 and expirationTime and expirationTime > 0 then
            shown[#shown + 1] = {
                index = index,
                icon = icon,
                count = count,
                debuffType = debuffType,
                duration = duration,
                expirationTime = expirationTime,
            }
        end
    end

    if #shown == 0 then
        HideFrom(1)
        holder:Hide()
        return
    end

    local width = bar:GetWidth()
    if not width or width < ICON_SIZE then
        width = 127
    end
    local perRow = math.floor((width + GAP) / (ICON_SIZE + GAP))
    if perRow < 1 then
        perRow = 1
    end

    holder:Show()
    for index, aura in ipairs(shown) do
        local button = EnsureButton(index)
        local column = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)
        button:ClearAllPoints()
        if column == 0 then
            button:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, TOP_PAD + row * (ICON_SIZE + GAP))
        else
            button:SetPoint("LEFT", buttons[index - 1], "RIGHT", GAP, 0)
        end
        button.auraIndex = aura.index
        button.icon:SetTexture(aura.icon)
        if aura.count and aura.count > 1 then
            button.count:SetText(aura.count)
            button.count:Show()
        else
            button.count:SetText("")
            button.count:Hide()
        end
        local color = aura.debuffType and DebuffTypeColor and DebuffTypeColor[aura.debuffType]
        if color then
            button.border:SetVertexColor(color.r, color.g, color.b)
        else
            button.border:SetVertexColor(0.8, 0, 0)
        end
        if button._expiration ~= aura.expirationTime or button._duration ~= aura.duration then
            button._expiration = aura.expirationTime
            button._duration = aura.duration
            if type(CooldownFrame_SetTimer) == "function" then
                CooldownFrame_SetTimer(button.cooldown, aura.expirationTime - aura.duration, aura.duration, 1)
            end
        end
        button:Show()
    end
    HideFrom(#shown + 1)
end

local function OnEnable()
    active = true
    if not watching then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("UNIT_AURA")
        watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        watcher:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_AURA" and unit ~= "player" then
                return
            end
            Refresh()
        end)
        watching = true
    end
    Refresh()
end

local function OnDisable()
    active = false
    Refresh()
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function() return L["Player Debuffs on Health"] end,
    desc = function()
        return L["Show your timed debuffs above the player health bar. Debuffs with no duration are hidden."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
