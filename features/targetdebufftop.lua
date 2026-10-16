-- DragonUI_Enhanced — target/focus debuffs above the health bar.
-- The row starts at the health bar's top-left and runs across the bar and portrait.
-- Buffs stay under the frame. The debuff anchor region is pinned first so the
-- buff row and cast bar do not follow the icons upward.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "targetDebuffTop"
local MAX_DEBUFFS = 16
local GAP = 2
local TOP_PAD = 20
local MAX_DURATION = 5 * 60

local active = false
local hooked = false

local FRAMES = { "TargetFrame", "FocusFrame" }

local function PinRegion(region, parent)
    if not region or not parent then
        return
    end
    local left, top = region:GetLeft(), region:GetTop()
    local parentLeft, parentTop = parent:GetLeft(), parent:GetTop()
    if not left or not top or not parentLeft or not parentTop then
        return
    end
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", left - parentLeft, top - parentTop)
end

local function PlaceDebuffs(frame)
    if not frame or not frame:IsShown() then
        return
    end
    local frameName = frame:GetName()
    local portrait = frameName and _G[frameName .. "Portrait"]
    local health = frameName and _G[frameName .. "HealthBar"]
    if not health and not portrait then
        return
    end

    local buttons = {}
    local unit = frame.unit
    for index = 1, MAX_DEBUFFS do
        local button = _G[frameName .. "Debuff" .. index]
        if not button or not button:IsShown() then
            break
        end
        local auraIndex = button:GetID()
        if not auraIndex or auraIndex < 1 then
            auraIndex = index
        end
        local duration = unit and select(6, UnitDebuff(unit, auraIndex))
        -- No countdown, or longer than five minutes: keep it off the health bar.
        if not duration or duration <= 0 or duration > MAX_DURATION then
            button:Hide()
        else
            buttons[#buttons + 1] = button
        end
    end
    if #buttons == 0 then
        return
    end

    -- Buffs anchor to this region. Freeze it before the debuff buttons move.
    PinRegion(frame.debuffs, frame)

    local size = buttons[1]:GetWidth()
    if not size or size < 8 then
        size = 21
    end
    -- Left edge on the health bar. Width covers the bar plus the portrait beside it.
    local anchorRegion = health or portrait
    local rowWidth = (health and health:GetWidth() or 0) + (portrait and portrait:GetWidth() or 0)
    if rowWidth < size then
        rowWidth = 180
    end
    local perRow = math.floor((rowWidth + GAP) / (size + GAP))
    if perRow < 1 then
        perRow = 1
    end

    local level = (frame:GetFrameLevel() or 0) + 12
    for index, button in ipairs(buttons) do
        local column = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)
        button:SetFrameLevel(level)
        button:ClearAllPoints()
        if column == 0 then
            button:SetPoint("BOTTOMLEFT", anchorRegion, "TOPLEFT", 0, TOP_PAD + row * (size + GAP))
        else
            button:SetPoint("LEFT", buttons[index - 1], "RIGHT", GAP, 0)
        end
    end

    local anchor = frame.spellbarAnchor
    local anchorName = anchor and anchor.GetName and anchor:GetName()
    if anchorName and anchorName:find("Debuff", 1, true) then
        frame.spellbarAnchor = frame
        if frame.spellbar and type(_G.Target_Spellbar_AdjustPosition) == "function" then
            _G.Target_Spellbar_AdjustPosition(frame.spellbar)
        end
    end
end

local function Apply(frame)
    if not active or not frame then
        return
    end
    local name = frame.GetName and frame:GetName()
    if name ~= "TargetFrame" and name ~= "FocusFrame" then
        return
    end
    PlaceDebuffs(frame)
end

local function Refresh()
    if type(_G.TargetFrame_UpdateAuras) ~= "function" then
        return
    end
    for index = 1, #FRAMES do
        local frame = _G[FRAMES[index]]
        if frame and frame.unit and UnitExists(frame.unit) then
            _G.TargetFrame_UpdateAuras(frame)
        end
    end
end

local function OnEnable()
    active = true
    if not hooked and type(_G.TargetFrame_UpdateAuras) == "function" then
        hooksecurefunc("TargetFrame_UpdateAuras", Apply)
        hooked = true
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
    label = function() return L["Debuffs Above Health"] end,
    desc = function()
        return L["Show target and focus debuffs left-aligned above the health bar, across the bar and portrait. Buffs stay under the frame."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
