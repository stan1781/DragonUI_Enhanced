-- DragonUI_Enhanced — drag the server challenge / battleground world-state list.
-- Those rows are Blizzard AlwaysUpFrame1..N. ElvUI moves them with PvPMover;
-- DragonUI never registers them, so this feature adds an editor overlay here.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "worldState"
local MOVER_WIDTH = 280
local ROW_HEIGHT = 18
local PREVIEW_LINES = {
    "挑战模式状态：进行中",
    "挑战等级：23",
    "剩余时间：1:28:14",
    "死亡次数：0 (+0秒)",
    "敌方部队击杀完成度：0%",
}

local mover
local preview
local editorRegistered = false
local hooked = false
local active = false
local editing = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function OwnsAnchor()
    if not active or not mover then
        return false
    end
    if editing then
        return true
    end
    local cfg = Cfg()
    return cfg and cfg.custom_position and true or false
end

local function ShownRows()
    local rows = {}
    local limit = NUM_ALWAYS_UP_UI_FRAMES or 0
    if limit < 40 then
        limit = 40
    end
    for i = 1, limit do
        local frame = _G["AlwaysUpFrame" .. i]
        if frame and frame:IsShown() then
            rows[#rows + 1] = frame
        end
    end
    return rows
end

local function UpdatePreview()
    if not preview then
        return
    end
    local show = editing and #ShownRows() == 0
    if show then
        preview:Show()
    else
        preview:Hide()
    end
end

local function FitMover()
    if not mover then
        return
    end
    local rows = ShownRows()
    local height
    if #rows == 0 then
        height = #PREVIEW_LINES * ROW_HEIGHT
    else
        height = 0
        for i = 1, #rows do
            local h = rows[i]:GetHeight()
            if not h or h < 1 then
                h = ROW_HEIGHT
            end
            height = height + h
        end
    end
    if height < ROW_HEIGHT then
        height = ROW_HEIGHT
    end
    mover:SetSize(MOVER_WIDTH, height)
end

-- Re-chain every visible row from the mover. Stock layout anchors row 2+ to the
-- previous row, but a server update may pin each row to WorldStateAlwaysUpFrame.
local function AnchorRows()
    if not OwnsAnchor() then
        return
    end
    local prev
    local rows = ShownRows()
    for i = 1, #rows do
        local frame = rows[i]
        frame:ClearAllPoints()
        if prev then
            frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
        else
            frame:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
        end
        prev = frame
    end
    FitMover()
    UpdatePreview()
end

local function ApplySavedPosition()
    if not mover then
        return
    end
    local cfg = Cfg()
    if not (cfg and cfg.custom_position) then
        return false
    end
    mover:ClearAllPoints()
    mover:SetPoint(cfg.anchor or "TOPLEFT", UIParent, cfg.relPoint or cfg.anchor or "TOPLEFT", cfg.posX or 0, cfg.posY or -40)
    return true
end

local function SnapMoverToRows()
    if not mover then
        return
    end
    local rows = ShownRows()
    local first = rows[1]
    if not first then
        mover:ClearAllPoints()
        mover:SetPoint("TOP", UIParent, "TOP", 0, -40)
        return
    end
    local left, top = first:GetLeft(), first:GetTop()
    local parentLeft, parentTop = UIParent:GetLeft(), UIParent:GetTop()
    if not (left and top and parentLeft and parentTop) then
        mover:ClearAllPoints()
        mover:SetPoint("TOP", UIParent, "TOP", 0, -40)
        return
    end
    mover:ClearAllPoints()
    mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - parentLeft, top - parentTop)
end

local function PlaceMover()
    if not ApplySavedPosition() then
        SnapMoverToRows()
    end
    AnchorRows()
end

local function PersistPosition()
    if not mover then
        return
    end
    local cfg = Cfg()
    if not cfg then
        return
    end
    local point, _, relPoint, x, y = mover:GetPoint(1)
    cfg.anchor = point or "TOPLEFT"
    cfg.relPoint = relPoint or cfg.anchor
    cfg.posX = x or 0
    cfg.posY = y or 0
    cfg.custom_position = true
    AnchorRows()
end

local function ReleaseToBlizzard()
    if WorldStateAlwaysUpFrame_Update then
        WorldStateAlwaysUpFrame_Update()
    end
end

local function ResetPosition()
    local cfg = Cfg()
    if cfg then
        cfg.custom_position = false
        cfg.anchor, cfg.relPoint = "TOPLEFT", "TOPLEFT"
        cfg.posX, cfg.posY = 0, -40
    end
    ReleaseToBlizzard()
    SnapMoverToRows()
    if editing then
        AnchorRows()
    end
end

local function EnsureHook()
    if hooked or not WorldStateAlwaysUpFrame_Update then
        return
    end
    hooked = true
    hooksecurefunc("WorldStateAlwaysUpFrame_Update", function()
        AnchorRows()
    end)
end

local function EnsurePreview()
    if preview or not mover then
        return
    end
    preview = CreateFrame("Frame", nil, mover)
    preview:SetAllPoints(mover)
    preview:Hide()
    local previous
    for i = 1, #PREVIEW_LINES do
        local text = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetJustifyH("LEFT")
        text:SetText(PREVIEW_LINES[i])
        text:SetTextColor(1, 0.82, 0)
        if previous then
            text:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 0)
        else
            text:SetPoint("TOPLEFT", preview, "TOPLEFT", 20, 0)
        end
        previous = text
    end
end

local function EnsureMover()
    if mover then
        return mover
    end
    local DUI = _G.DragonUI
    if DUI and DUI.CreateUIFrame then
        mover = DUI.CreateUIFrame(MOVER_WIDTH, #PREVIEW_LINES * ROW_HEIGHT, "WorldState")
    else
        mover = CreateFrame("Frame", "DragonUI_Enhanced_WorldState", UIParent)
        mover:SetSize(MOVER_WIDTH, #PREVIEW_LINES * ROW_HEIGHT)
        mover:SetMovable(true)
        mover:EnableMouse(false)
        mover:RegisterForDrag("LeftButton")
        mover:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        mover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            PersistPosition()
        end)
    end
    mover:SetClampedToScreen(true)
    if mover.editorText then
        mover.editorText:SetText(L["World State"])
        mover.editorText:ClearAllPoints()
        mover.editorText:SetPoint("BOTTOM", mover, "TOP", 0, 2)
    end
    mover:HookScript("OnDragStop", function()
        PersistPosition()
    end)
    EnsurePreview()
    return mover
end

local function RegisterEditor()
    if editorRegistered then
        return
    end
    local DUI = _G.DragonUI
    if not (DUI and DUI.RegisterEditableFrame and mover) then
        return
    end
    DUI:RegisterEditableFrame({
        name = "enhancedWorldState",
        frame = mover,
        editorVisible = function()
            return addon:IsFeatureEnabled(KEY)
        end,
        applyPosition = PlaceMover,
        resetPosition = ResetPosition,
        isDefaultPosition = function()
            local cfg = Cfg()
            return not (cfg and cfg.custom_position)
        end,
        onNudge = PersistPosition,
        onShow = function()
            editing = true
            PlaceMover()
        end,
        onHide = function()
            editing = false
            if mover and (mover.DragonUI_WasDragged or mover.DragonUI_WasAdjustedByEditor) then
                PersistPosition()
                mover.DragonUI_WasDragged = nil
                mover.DragonUI_WasAdjustedByEditor = nil
            end
            if Cfg() and Cfg().custom_position then
                AnchorRows()
            else
                ReleaseToBlizzard()
            end
            UpdatePreview()
        end,
        showTest = function()
            editing = true
            if mover then
                mover:Show()
            end
            PlaceMover()
            UpdatePreview()
        end,
        hideTest = function()
            editing = false
            UpdatePreview()
            if mover and addon:IsFeatureEnabled(KEY) then
                mover:Show()
            elseif mover then
                mover:Hide()
            end
        end,
        module = addon,
    })
    editorRegistered = true
end

local function OnEnable()
    active = true
    EnsureHook()
    EnsureMover()
    RegisterEditor()
    PlaceMover()
    mover:Show()
end

local function OnDisable()
    active = false
    editing = false
    UpdatePreview()
    ReleaseToBlizzard()
    if mover then
        mover:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function() return L["World State"] end,
    desc = function()
        return L["Drag the challenge and battleground world-state list from DragonUI editor mode. The whole column moves together."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Open DragonUI editor mode and drag the World State box. Outside a challenge or battleground, the box shows a sample list."])
        C:AddButton(section, {
            label = L["Reset World State Position"],
            callback = function()
                ResetPosition()
            end,
        })
    end,
})
