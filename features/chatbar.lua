-- DragonUI_Enhanced — Quick chat channel button bar (from ChatBar/ChatBar.lua).
-- Uses DragonUI RegisterEditableFrame instead of ElvUI CreateMover.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "chatBar"
local BUTTON_SIZE = 23
local BUTTON_GAP = 6
local FONT_SIZE = 15

local barFrame
local buttons = {}
local editorRegistered = false
local active = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function SelectedChatFrame()
    return SELECTED_DOCK_FRAME or SELECTED_CHAT_FRAME or ChatFrame1
end

local function OpenChat(slash)
    local chatFrame = SelectedChatFrame()
    ChatFrame_OpenChat(slash, chatFrame)
end

local function LfgChannelName()
    local cfg = Cfg()
    local name = cfg and cfg.lfgChannelName
    if type(name) == "string" and name ~= "" then
        return name
    end
    return "寻求组队"
end

local function OnLfgClick(_, button)
    local chatFrame = SelectedChatFrame()
    local channelName = LfgChannelName()
    if button == "RightButton" then
        local id = GetChannelName(channelName)
        if not id or id == 0 then
            JoinPermanentChannel(channelName, nil, 1, 1)
            if ChatFrame_AddChannel then
                ChatFrame_AddChannel(chatFrame, channelName)
            end
            print("|cff00d200已加入" .. channelName .. "|r")
        else
            LeaveChannelByName(channelName)
            print("|cffd20000已离开" .. channelName .. "|r")
        end
    else
        local id = GetChannelName(channelName)
        if id and id > 0 then
            OpenChat("/" .. id .. " ")
        else
            print("|cffffcc00尚未加入" .. channelName .. "（右键按钮可加入）|r")
        end
    end
end

local function OnEmoteClick()
    if addon.ChatEmote then
        addon.ChatEmote:Toggle()
    end
end

local function OnRollClick()
    RandomRoll(1, 100)
end

local BUTTON_DEFS = {
    { key = "say", text = "说", color = {1.00, 1.00, 1.00}, click = function() OpenChat("/s ") end },
    { key = "yell", text = "喊", color = {1.00, 0.25, 0.25}, click = function() OpenChat("/y ") end },
    { key = "party", text = "队", color = {0.66, 0.66, 1.00}, click = function() OpenChat("/p ") end },
    { key = "guild", text = "会", color = {0.25, 1.00, 0.25}, click = function() OpenChat("/g ") end },
    { key = "raid", text = "团", color = {1.00, 0.50, 0.00}, click = function() OpenChat("/raid ") end },
    { key = "bg", text = "战", color = {1.00, 0.50, 0.00}, click = function() OpenChat("/bg ") end },
    { key = "ch1", text = "综", color = {0.82, 0.70, 0.55}, click = function() OpenChat("/1 ") end },
    { key = "ch2", text = "交", color = {0.20, 0.60, 0.80}, click = function() OpenChat("/2 ") end },
    { key = "ch3", text = "防", color = {0.80, 0.30, 0.30}, click = function() OpenChat("/3 ") end },
    { key = "lfg", text = "组", color = {0.78, 1.00, 0.59}, click = OnLfgClick, anyClick = true },
    { key = "emote", text = "表", color = {1.00, 0.50, 1.00}, click = OnEmoteClick },
    { key = "roll", text = "骰", color = {1.00, 1.00, 0.00}, click = OnRollClick },
}

local function PersistPosition()
    if not barFrame then return end
    local cfg = Cfg()
    if not cfg then return end
    -- 手动拖动后脱离聊天框，改为相对屏幕记住位置
    cfg.anchorToChat = false
    local anchor, _, _, x, y = barFrame:GetPoint(1)
    cfg.anchor = anchor or "BOTTOMLEFT"
    cfg.posX = x or 0
    cfg.posY = y or 30
end

local function ApplyPosition()
    if not barFrame then return end
    local cfg = Cfg()
    local defaults = addon.defaults.profile.features.chatBar
    local scale = cfg.scale or defaults.scale or 1
    barFrame:SetScale(scale)
    barFrame:ClearAllPoints()

    if cfg.anchorToChat ~= false then
        local cf = ChatFrame1 or SELECTED_CHAT_FRAME or SELECTED_DOCK_FRAME
        if cf then
            barFrame:SetPoint(
                "BOTTOMLEFT",
                cf,
                "TOPLEFT",
                cfg.chatOffsetX or defaults.chatOffsetX or 0,
                cfg.chatOffsetY or defaults.chatOffsetY or 4
            )
            return
        end
    end

    barFrame:SetPoint(
        cfg.anchor or defaults.anchor,
        UIParent,
        cfg.anchor or defaults.anchor,
        cfg.posX or defaults.posX,
        cfg.posY or defaults.posY
    )
end

local function ResetPosition()
    local cfg = Cfg()
    local d = addon.defaults.profile.features.chatBar
    cfg.anchorToChat = true
    cfg.chatOffsetX = d.chatOffsetX
    cfg.chatOffsetY = d.chatOffsetY
    cfg.anchor = d.anchor
    cfg.posX = d.posX
    cfg.posY = d.posY
    cfg.scale = d.scale
    ApplyPosition()
end

local function StartBarDrag(self)
    if InCombatLockdown and InCombatLockdown() then return end
    barFrame:StartMoving()
end

local function StopBarDrag()
    barFrame:StopMovingOrSizing()
    PersistPosition()
end

local function CreateButton(parent, def, index)
    local btn = CreateFrame("Button", "DragonUI_Enhanced_ChatBar_" .. def.key, parent)
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("LEFT", parent, "LEFT", (index - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
    if def.anyClick then
        btn:RegisterForClicks("AnyUp")
    else
        btn:RegisterForClicks("LeftButtonUp")
    end
    btn:SetScript("OnClick", def.click)
    -- 按钮铺满整条；拖动任意按钮即可移动整栏
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", StartBarDrag)
    btn:SetScript("OnDragStop", StopBarDrag)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, FONT_SIZE, "OUTLINE")
    fs:SetShadowOffset(0.8, -0.8)
    fs:SetShadowColor(0.3, 0.3, 0.3, 0.7)
    fs:SetJustifyH("CENTER")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(def.text)
    fs:SetTextColor(def.color[1], def.color[2], def.color[3])
    btn.text = fs

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local hl = btn:GetHighlightTexture()
    if hl then
        hl:SetAlpha(0.35)
    end

    return btn
end

local function EnsureBar()
    if barFrame then return barFrame end

    local n = #BUTTON_DEFS
    local width = n * BUTTON_SIZE + (n - 1) * BUTTON_GAP

    barFrame = CreateFrame("Frame", "DragonUI_Enhanced_ChatBar", UIParent)
    barFrame:SetWidth(width)
    barFrame:SetHeight(BUTTON_SIZE)
    barFrame:SetClampedToScreen(true)
    barFrame:SetMovable(true)
    barFrame:EnableMouse(true)
    barFrame:RegisterForDrag("LeftButton")
    barFrame:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:StartMoving()
    end)
    barFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        PersistPosition()
    end)

    for i = 1, n do
        buttons[i] = CreateButton(barFrame, BUTTON_DEFS[i], i)
    end

    ApplyPosition()
    return barFrame
end

local function RegisterEditor()
    if editorRegistered then return end
    local DUI = _G.DragonUI
    if not (DUI and DUI.RegisterEditableFrame) then
        return
    end
    DUI:RegisterEditableFrame({
        name = "enhancedChatBar",
        frame = barFrame,
        editorVisible = function()
            return addon:IsFeatureEnabled(KEY)
        end,
        applyPosition = ApplyPosition,
        resetPosition = ResetPosition,
        isDefaultPosition = function()
            local cfg = Cfg()
            local d = addon.defaults.profile.features.chatBar
            if cfg.anchorToChat == false then
                return false
            end
            return (cfg.chatOffsetX or 0) == (d.chatOffsetX or 0)
                and (cfg.chatOffsetY or 4) == (d.chatOffsetY or 4)
        end,
        onNudge = PersistPosition,
        onHide = function()
            PersistPosition()
            ApplyPosition()
        end,
        showTest = function()
            if barFrame then barFrame:Show() end
        end,
        hideTest = function()
            if barFrame and addon:IsFeatureEnabled(KEY) then
                -- keep visible
            elseif barFrame then
                barFrame:Hide()
            end
        end,
        module = addon,
    })
    editorRegistered = true
end

local function OnEnable()
    active = true
    EnsureBar()
    RegisterEditor()
    ApplyPosition()
    barFrame:Show()
    if addon.ChatEmote then
        addon.ChatEmote:InstallFilters()
    end
end

local function OnDisable()
    active = false
    if barFrame then
        barFrame:Hide()
    end
    if addon.ChatEmote then
        addon.ChatEmote:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "chat",
    default = true,
    label = function() return L["Quick Chat Bar"] end,
    desc = function()
        return L["Colored channel buttons: Say/Yell/Party/Guild/Raid/BG/1-3/LFG/Emote/Roll. Drag to move; use DragonUI editor for precise placement."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Left-click opens that channel. Right-click「组」joins/leaves the LFG channel."])
        C:AddDescription(section, L["Default position: above ChatFrame1. Drag to move; reset in DragonUI editor restores chat-top anchor."])
        C:AddButton(section, {
            label = L["Reset to Above Chat"],
            callback = function()
                ResetPosition()
            end,
        })
        C:AddEditBox(section, {
            label = L["LFG Channel Name"],
            desc = L["Channel toggled by the「组」button (right-click). Default: 寻求组队."],
            getFunc = function()
                return Cfg().lfgChannelName or "寻求组队"
            end,
            setFunc = function(val)
                val = tostring(val or ""):match("^%s*(.-)%s*$") or ""
                Cfg().lfgChannelName = (val ~= "") and val or nil
            end,
        })
        C:AddSlider(section, {
            label = L["Scale"],
            min = 0.5,
            max = 2,
            step = 0.05,
            getFunc = function()
                return (Cfg().scale) or 1
            end,
            setFunc = function(val)
                Cfg().scale = val
                ApplyPosition()
            end,
        })
    end,
    Refresh = function()
        if active then
            ApplyPosition()
        end
    end,
})
