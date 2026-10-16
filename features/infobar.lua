-- DragonUI_Enhanced — top info bar (tokens, fps, latency, guild, friends).

local ADDON_NAME, addon = ...
local L = addon.L

local GetItemInfo = GetItemInfo
local GetItemCount = GetItemCount
local GetFramerate = GetFramerate
local GetNetStats = GetNetStats
local GetNumFriends = GetNumFriends
local GetFriendInfo = GetFriendInfo
local ShowFriends = ShowFriends
local IsInGuild = IsInGuild
local GetNumGuildMembers = GetNumGuildMembers
local GetGuildRosterInfo = GetGuildRosterInfo
local GuildRoster = GuildRoster
local GetRealmName = GetRealmName
local UnitName = UnitName
local GetTime = GetTime
local format = format
local floor = math.floor
local max = math.max

local KEY = "infoBar"

local WATCHED_TOKENS = {
    { id = 65085, name = "虚空碎片" },
    { id = 65297, name = "觉醒泰坦精华" },
    { id = 69885, name = "灵魂灰烬" },
    { id = 60038, name = "次级好运护符" },
    { id = 60039, name = "长老的好运符" },
    { id = 70539, name = "商贩标币" },
    { id = 70877, name = "求知护符" },
}

local ICON_SIZE = 20
local GAP = 10
local PAD_X = 6
local PAD_Y = 4
local FPS_INTERVAL = 1
local ROSTER_INTERVAL = 15

local SILVER = "|cffc7c7cf%s|r"
local MOSS = "|cFF80FF00%s|r"

local frame
local buttons = {}
local editorRegistered = false
local active = false
local fpsElapsed = 0
local rosterElapsed = 0
local lastRosterRequest = 0

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function Flag(key)
    local cfg = Cfg()
    if not cfg or cfg[key] == nil then
        return true
    end
    return cfg[key] and true or false
end

local function FontSize()
    local cfg = Cfg()
    local size = cfg and cfg.fontSize or 11
    if size < 8 then size = 8 end
    if size > 24 then size = 24 end
    return size
end

local function Chrome()
    local colors = addon.theme and addon.theme:GetChromeColors()
    local panel = colors and colors.panel or { 0.1216, 0.1176, 0.1294, 0.93 }
    local gold = colors and colors.gold or { 1, 0.82, 0 }
    return panel, gold
end

local function PersistPosition()
    if not frame then return end
    local cfg = Cfg()
    if not cfg then return end
    local anchor, _, _, x, y = frame:GetPoint(1)
    cfg.anchor = anchor or "TOPLEFT"
    cfg.posX = x or 20
    cfg.posY = y or -8
end

local function ApplyPosition()
    if not frame then return end
    local cfg = Cfg()
    local anchor = (cfg and cfg.anchor) or "TOPLEFT"
    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, anchor, (cfg and cfg.posX) or 20, (cfg and cfg.posY) or -8)
end

local function ResetPosition()
    local cfg = Cfg()
    if not cfg then return end
    local defaults = addon.defaults.profile.features.infoBar
    cfg.anchor = defaults.anchor
    cfg.posX = defaults.posX
    cfg.posY = defaults.posY
    ApplyPosition()
end

local function ApplyFont(fontString)
    if addon.theme and addon.theme.ApplyFont then
        addon.theme:ApplyFont(fontString, FontSize())
    end
end

local function ApplyChrome()
    if not frame or not frame.SetBackdrop then return end
    local panel, gold = Chrome()
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(panel[1], panel[2], panel[3], panel[4] or 0.93)
    frame:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.85)
end

local function LatencyColor(ms)
    if ms >= 200 then
        return 1, 0.25, 0.25
    end
    if ms >= 100 then
        return 1, 0.82, 0
    end
    return 1, 1, 1
end

local function GetTokenData(itemID)
    local realm = GetRealmName()
    local db = _G.BagSyncTOKEN_DB and realm and _G.BagSyncTOKEN_DB[realm] and _G.BagSyncTOKEN_DB[realm][itemID]
    local name, icon
    if db then
        name = db.name
        icon = db.icon
    end
    if not name or not icon then
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
        name = name or itemName
        icon = icon or itemIcon
    end
    return db, name, icon
end

local function GetTokenCount(itemID, db)
    local count = 0
    local player = UnitName("player")
    if db and player and db[player] then
        count = db[player] or 0
    end
    local bagCount = GetItemCount(itemID, true) or 0
    if bagCount > count then
        count = bagCount
    end
    return count
end

local function BuildCharTooltip(db)
    if not db then return nil end
    local tmp = {}
    for k, v in pairs(db) do
        if k ~= "name" and k ~= "icon" and k ~= "header" and type(v) == "number" then
            tmp[#tmp + 1] = { name = k, count = v }
        end
    end
    table.sort(tmp, function(a, b) return a.name < b.name end)
    return tmp
end

local function CountFriends()
    local total = GetNumFriends() or 0
    local online = 0
    for i = 1, total do
        local _, _, _, _, connected = GetFriendInfo(i)
        if connected then
            online = online + 1
        end
    end
    return online, total
end

local function CountGuild()
    if not IsInGuild() then
        return nil, nil
    end
    local total = GetNumGuildMembers() or 0
    local online = 0
    for i = 1, total do
        local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if isOnline then
            online = online + 1
        end
    end
    return online, total
end

local function RequestRoster()
    if not IsInGuild() or not GuildRoster then return end
    local now = GetTime()
    if now - lastRosterRequest < ROSTER_INTERVAL then return end
    lastRosterRequest = now
    GuildRoster()
end

local function OnTokenEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.tokenName or "Token")
    if self.charTooltip and #self.charTooltip > 0 then
        GameTooltip:AddLine(" ")
        for i = 1, #self.charTooltip do
            GameTooltip:AddDoubleLine(
                format(MOSS, self.charTooltip[i].name),
                format(SILVER, self.charTooltip[i].count)
            )
        end
    else
        GameTooltip:AddLine(format(SILVER, self.countText:GetText() or "0"), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function OnTokenLeave()
    GameTooltip:Hide()
end

local function StartDrag()
    if frame then
        frame:StartMoving()
    end
end

local function StopDrag()
    if frame then
        frame:StopMovingOrSizing()
        PersistPosition()
    end
end

local function CreateButton(parent)
    local btn = CreateFrame("Frame", nil, parent)
    btn:SetHeight(ICON_SIZE)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnEnter", OnTokenEnter)
    btn:SetScript("OnLeave", OnTokenLeave)
    btn:SetScript("OnDragStart", StartDrag)
    btn:SetScript("OnDragStop", StopDrag)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(ICON_SIZE)
    icon:SetHeight(ICON_SIZE)
    icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local countText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    countText:SetJustifyH("LEFT")
    countText:SetText("0")
    btn.countText = countText
    return btn
end

local function PlaceText(fontString, text, x)
    fontString:SetText(text)
    fontString:Show()
    fontString:ClearAllPoints()
    fontString:SetPoint("LEFT", frame, "LEFT", x, 0)
    local width = fontString:GetStringWidth() or 20
    if width < 8 then width = 8 end
    return x + width + GAP
end

local function Layout(sample)
    if not frame then return end
    local x = PAD_X
    local any = false

    ApplyFont(frame.fpsText)
    ApplyFont(frame.latencyText)
    ApplyFont(frame.friendsText)
    ApplyFont(frame.guildText)

    if Flag("showFps") then
        local fps = sample and 60 or floor((GetFramerate() or 0) + 0.5)
        x = PlaceText(frame.fpsText, format("%d FPS", fps), x)
        any = true
    else
        frame.fpsText:Hide()
    end

    if Flag("showLatency") then
        local _, _, home = GetNetStats()
        local ms = sample and 32 or floor((home or 0) + 0.5)
        x = PlaceText(frame.latencyText, format("%d ms", ms), x)
        local r, g, b = LatencyColor(ms)
        frame.latencyText:SetTextColor(r, g, b)
        any = true
    else
        frame.latencyText:Hide()
    end

    if Flag("showSocial") then
        local friendsOnline, friendsTotal
        if sample then
            friendsOnline, friendsTotal = 3, 12
        else
            friendsOnline, friendsTotal = CountFriends()
        end
        x = PlaceText(frame.friendsText, format("%s %d/%d", L["Info Friends"], friendsOnline, friendsTotal), x)

        local guildText
        if sample then
            guildText = format("%s %d/%d", L["Info Guild"], 40, 180)
        else
            local guildOnline, guildTotal = CountGuild()
            if not guildOnline then
                guildText = format("%s —", L["Info Guild"])
            else
                guildText = format("%s %d/%d", L["Info Guild"], guildOnline, guildTotal)
            end
        end
        x = PlaceText(frame.guildText, guildText, x)
        any = true
    else
        frame.friendsText:Hide()
        frame.guildText:Hide()
    end

    if Flag("showTokens") then
        for i, info in ipairs(WATCHED_TOKENS) do
            local btn = buttons[i]
            if not btn then
                btn = CreateButton(frame)
                buttons[i] = btn
            end
            ApplyFont(btn.countText)
            local db, name, icon = GetTokenData(info.id)
            local count = sample and 0 or GetTokenCount(info.id, db)
            btn.tokenName = name or info.name
            btn.charTooltip = sample and nil or BuildCharTooltip(db)
            btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            btn.countText:SetText(tostring(count or 0))
            local textWidth = btn.countText:GetStringWidth() or 20
            btn:SetWidth(ICON_SIZE + 3 + textWidth)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", frame, "LEFT", x, 0)
            btn:Show()
            x = x + btn:GetWidth() + GAP
            any = true
        end
    end

    if not Flag("showTokens") then
        for i = 1, #buttons do
            buttons[i]:Hide()
        end
    end

    if not any then
        frame:SetWidth(40)
        frame:Hide()
        return
    end

    frame:SetWidth(max(x - GAP + PAD_X, 40))
    if active then
        frame:Show()
    end
end

local function Refresh()
    if not active then return end
    Layout(false)
end

local function OnUpdate(_, elapsed)
    fpsElapsed = fpsElapsed + elapsed
    rosterElapsed = rosterElapsed + elapsed
    if rosterElapsed >= ROSTER_INTERVAL then
        rosterElapsed = 0
        RequestRoster()
    end
    if fpsElapsed < FPS_INTERVAL then
        return
    end
    fpsElapsed = 0
    Refresh()
end

local function OnEvent(_, event)
    if event == "PLAYER_LOGIN" then
        if ShowFriends then
            ShowFriends()
        end
        RequestRoster()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RequestRoster()
    end
    Refresh()
end

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "DragonUI_Enhanced_InfoBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetHeight(ICON_SIZE + PAD_Y * 2)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)

    frame.fpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.latencyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.friendsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.guildText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    frame:SetScript("OnEvent", OnEvent)
    ApplyChrome()
    ApplyPosition()
    return frame
end

local function RegisterEvents()
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("BAG_UPDATE")
    frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    frame:RegisterEvent("FRIENDLIST_UPDATE")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
end

local function RegisterEditor()
    if editorRegistered then return end
    local DUI = _G.DragonUI
    if not (DUI and DUI.RegisterEditableFrame) then
        return
    end
    DUI:RegisterEditableFrame({
        name = "enhancedInfoBar",
        frame = frame,
        editorVisible = function()
            return addon:IsFeatureEnabled(KEY)
        end,
        applyPosition = ApplyPosition,
        resetPosition = ResetPosition,
        isDefaultPosition = function()
            local cfg = Cfg()
            local d = addon.defaults.profile.features.infoBar
            return (cfg.anchor or "TOPLEFT") == d.anchor
                and (cfg.posX or 20) == d.posX
                and (cfg.posY or -8) == d.posY
        end,
        onNudge = PersistPosition,
        onHide = function()
            PersistPosition()
            ApplyPosition()
        end,
        showTest = function()
            if not frame then return end
            Layout(true)
            frame:Show()
        end,
        hideTest = function()
            if active then
                Refresh()
            elseif frame then
                frame:Hide()
            end
        end,
        module = addon,
    })
    editorRegistered = true
end

local function OnEnable()
    active = true
    EnsureFrame()
    RegisterEditor()
    ApplyPosition()
    ApplyChrome()
    RegisterEvents()
    fpsElapsed = FPS_INTERVAL
    rosterElapsed = 0
    if ShowFriends then
        ShowFriends()
    end
    RequestRoster()
    frame:SetScript("OnUpdate", OnUpdate)
    Refresh()
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(function()
            if active then
                Refresh()
            end
        end, 1)
    end
end

local function OnDisable()
    active = false
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:UnregisterAllEvents()
        frame:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function() return L["Info Bar"] end,
    desc = function()
        return L["Top bar for watched tokens, FPS, latency, guild and friends."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        local function Toggle(key, label)
            C:AddToggle(section, {
                label = label,
                getFunc = function()
                    return Flag(key)
                end,
                setFunc = function(val)
                    Cfg()[key] = val and true or false
                    if addon:IsFeatureEnabled(KEY) then
                        Refresh()
                    end
                end,
            })
        end
        Toggle("showTokens", L["Show Tokens"])
        Toggle("showFps", L["Show FPS"])
        Toggle("showLatency", L["Show Latency"])
        Toggle("showSocial", L["Show Guild and Friends"])
        C:AddSlider(section, {
            label = L["Font Size"],
            min = 8,
            max = 24,
            step = 1,
            getFunc = function()
                return FontSize()
            end,
            setFunc = function(val)
                Cfg().fontSize = val
                if addon:IsFeatureEnabled(KEY) then
                    Refresh()
                end
            end,
        })
    end,
    Refresh = function()
        if addon:IsFeatureEnabled(KEY) then
            ApplyPosition()
            ApplyChrome()
            Refresh()
        end
    end,
})
