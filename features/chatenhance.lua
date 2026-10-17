-- DragonUI_Enhanced — ChatBar P1: channel shorten, timestamp, Tab cycle, dice,
-- plus persistent chat editbox history (ElvUI-style).
-- Uses chained wrappers (no blind global overwrite). No chat-copy / link-hover.

local ADDON_NAME, addon = ...
local L = addon.L

local format = string.format
local gsub = string.gsub
local find = string.find
local strsub = string.sub
local tostring = tostring
local ipairs = ipairs
local tinsert = table.insert
local tremove = table.remove

local KEY = "chatEnhance"

local active = false
local originals = {} -- ChatFrame AddMessage backups
local prevTabHandler
local tabHandler
local tabClaimFrame
local tagsApplied = false
local savedTags = {}
local slashRegistered = false
local historyInstalled = false
local restoringHistory = false

-- Combat/secure macros: keep out of SavedVariables (session ↑/↓ still works).
-- Utility cmds like /rl /reload /logout are persisted on purpose.
local SECURE_SLASH = {
    "^/assist",
    "^/cancelaura",
    "^/cancelform",
    "^/cast",
    "^/castsequence",
    "^/equip",
    "^/startattack",
    "^/stopattack",
    -- "^/tar",
    -- "^/target",
    "^/use",
}

local TAG_KEYS = {
    "CHAT_GUILD_GET", "CHAT_OFFICER_GET",
    "CHAT_RAID_GET", "CHAT_RAID_WARNING_GET", "CHAT_RAID_LEADER_GET",
    "CHAT_PARTY_GET", "CHAT_PARTY_LEADER_GET", "CHAT_PARTY_GUIDE_GET",
    "CHAT_BATTLEGROUND_GET", "CHAT_BATTLEGROUND_LEADER_GET",
    "CHAT_SAY_GET", "CHAT_YELL_GET",
    "CHAT_WHISPER_INFORM_GET", "CHAT_WHISPER_GET",
    "CHAT_FLAG_AFK", "CHAT_FLAG_DND", "CHAT_FLAG_GM",
}

local ZHCN_TAGS = {
    CHAT_GUILD_GET = "|Hchannel:GUILD|h[公会]|h %s: ",
    CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[官员]|h %s: ",
    CHAT_RAID_GET = "|Hchannel:RAID|h[团队]|h %s: ",
    CHAT_RAID_WARNING_GET = "[通知] %s: ",
    CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[团长]|h %s: ",
    CHAT_PARTY_GET = "|Hchannel:PARTY|h[队伍]|h %s: ",
    CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[队长]|h %s: ",
    CHAT_PARTY_GUIDE_GET = "|Hchannel:PARTY|h[向导]|h %s: ",
    CHAT_BATTLEGROUND_GET = "|Hchannel:BATTLEGROUND|h[战场]|h %s: ",
    CHAT_BATTLEGROUND_LEADER_GET = "|Hchannel:BATTLEGROUND|h[领袖]|h %s: ",
    CHAT_WHISPER_INFORM_GET = "发送给%s: ",
    CHAT_WHISPER_GET = "%s悄悄的说: ",
    CHAT_SAY_GET = "%s: ",
    CHAT_YELL_GET = "%s: ",
    CHAT_FLAG_AFK = "[暂离] ",
    CHAT_FLAG_DND = "[勿扰] ",
    CHAT_FLAG_GM = "[GM] ",
}

-- 私服常报 enCN/enTW，按中文频道名处理。
local function IsZhCN()
    local locale = GetLocale()
    return locale == "zhCN" or locale == "enCN"
end

local function IsZhTW()
    local locale = GetLocale()
    return locale == "zhTW" or locale == "enTW"
end

local chn = {
    "%[(%d+)%. General.-%]",
    "%[(%d+)%. Trade.-%]",
    "%[(%d+)%. LocalDefense.-%]",
    "%[(%d+)%. LookingForGroup%]",
    "%[(%d+)%. WorldDefense%]",
    "%[(%d+)%. GuildRecruitment.-%]",
    "%[(%d+)%. BigFootChannel.-%]",
    "%[(%d+)%. CustomChannel.-%]",
}
local rplc = { "[GEN]", "[TR]", "[LD]", "[LFG]", "[WD]", "[GR]", "[BFC]", "[CL]" }

if IsZhCN() then
    chn = {
        "%[(%d+)%. 综合.-%]",
        "%[(%d+)%. 交易.-%]",
        "%[(%d+)%. 本地防务.-%]",
        "%[(%d+)%. 寻求组队%]",
        "%[(%d+)%. 世界防务%]",
        "%[(%d+)%. 公会招募.-%]",
        "%[(%d+)%. 大脚世界频道.-%]",
        "%[(%d+)%. 自定义频道.-%]",
    }
    rplc = {
        "[%1综合]", "[%1交易]", "[%1本地防务]", "[%1组队]",
        "[%1世界防务]", "[%1招募]", "[%1世界]", "[%1自定义]",
    }
elseif IsZhTW() then
    chn = {
        "%[(%d+)%. 綜合.-%]",
        "%[(%d+)%. 貿易.-%]",
        "%[(%d+)%. 本地防務.-%]",
        "%[(%d+)%. 尋求組隊%]",
        "%[(%d+)%. 世界防務%]",
        "%[(%d+)%. 公會招募.-%]",
        "%[(%d+)%. 大脚世界频道.-%]",
        "%[(%d+)%. 自定义频道.-%]",
    }
    rplc = {
        "[%1綜合]", "[%1貿易]", "[%1防務]", "[%1組隊]",
        "[%1世界]", "[%1招募]", "[%1世]", "[%1自定义]",
    }
end

local TS = "|cff68ccef|h%s|h|r %s"

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function InParty()
    return (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
end

local function InRaid()
    return (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
end

local function WorldChannelKeywords()
    local cfg = Cfg()
    local list = cfg.worldChannelKeywords
    if type(list) == "table" and #list > 0 then
        return list
    end
    return { "大脚世界频道", "世界频道", "寻求组队" }
end

local function ChannelNameMatchesWorld(channelName)
    if not channelName then return false end
    local keys = WorldChannelKeywords()
    for i = 1, #keys do
        if find(channelName, keys[i], 1, true) then
            return true
        end
    end
    return false
end

local function ShortenChannels(text)
    for i = 1, #chn do
        text = gsub(text, chn[i], rplc[i])
    end
    text = gsub(text, "%[(%d0?)%. .-%]", "%1.")
    return text
end

-- QQ-group bridge posts into 寻求组队 as: [4组队] ： <QQ群> [name(id)]： msg
-- Only rewrite when the body carries the <QQ群> marker; normal LFG chat is untouched.
local function FormatQQGroupBridge(text)
    if not find(text, "<QQ群>", 1, true) then
        return text
    end
    -- After ShortenChannels: [4组队] / hyperlink variants → [QQ群]
    text = gsub(text, "%|Hchannel:.-%|h%[%d+组队%]%|h", "[QQ群]")
    text = gsub(text, "%[%d+组队%]", "[QQ群]")
    text = gsub(text, "%|Hchannel:.-%|h%[%d+%. 寻求组队%]%|h", "[QQ群]")
    text = gsub(text, "%[%d+%. 寻求组队%]", "[QQ群]")
    text = gsub(text, "<QQ群>%s*", "")
    return text
end

local function ProcessMessage(text)
    local cfg = Cfg()
    if type(text) ~= "string" then
        text = tostring(text)
    end
    text = ShortenChannels(text)
    text = FormatQQGroupBridge(text)
    if cfg and cfg.timestamp then
        text = format(TS, date("%H:%M:%S"), text)
    end
    return text
end

local function WrapFrame(frame)
    if not frame or not frame.GetName then return end
    local name = frame:GetName()
    if not name or originals[name] then return end
    originals[name] = frame.AddMessage
    frame.AddMessage = function(self, text, ...)
        if active then
            text = ProcessMessage(text)
        end
        return originals[name](self, text, ...)
    end
end

local function WrapAllChatFrames()
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        if i ~= 2 then
            WrapFrame(_G["ChatFrame" .. i])
        end
    end
end

local function ApplyChatTags()
    if tagsApplied then return end
    if not (IsZhCN() or IsZhTW()) then return end
    for i = 1, #TAG_KEYS do
        local key = TAG_KEYS[i]
        if ZHCN_TAGS[key] and _G[key] ~= nil then
            savedTags[key] = _G[key]
            _G[key] = ZHCN_TAGS[key]
        end
    end
    tagsApplied = true
end

local function RestoreChatTags()
    if not tagsApplied then return end
    for key, value in pairs(savedTags) do
        _G[key] = value
    end
    wipe(savedTags)
    tagsApplied = false
end

-- Tab channel cycle (WotLK-safe; world channel name configurable)
local chatTypeBeforeSwitch, tellTargetBeforeSwitch

local cycles = {
    {
        chatType = "SAY",
        use = function() return true end,
    },
    {
        chatType = "YELL",
        use = function() return true end,
    },
    {
        chatType = "PARTY",
        use = function() return InParty() end,
    },
    {
        chatType = "RAID",
        use = function() return InRaid() end,
    },
    {
        chatType = "BATTLEGROUND",
        use = function()
            local _, itype = IsInInstance()
            return itype == "pvp"
        end,
    },
    {
        chatType = "GUILD",
        use = function() return IsInGuild() end,
    },
    {
        chatType = "CHANNEL",
        use = function(_, editbox, currChatType)
            local currNum = tonumber(editbox:GetAttribute("channelTarget")) or 0
            if currChatType ~= "CHANNEL" then
                currNum = IsShiftKeyDown() and 21 or 0
            end
            local h, r, step = currNum + 1, 20, 1
            if IsShiftKeyDown() then
                h, r, step = currNum - 1, 1, -1
            end
            for i = h, r, step do
                local channelNum, channelName = GetChannelName(i)
                if channelNum and channelNum > 0 and channelName and ChannelNameMatchesWorld(channelName) then
                    editbox:SetAttribute("channelTarget", channelNum)
                    return true
                end
            end
            -- Index scan can miss custom channels; resolve keywords by name (e.g. 寻求组队).
            local keys = WorldChannelKeywords()
            local kStart, kEnd, kStep = 1, #keys, 1
            if IsShiftKeyDown() then
                kStart, kEnd, kStep = #keys, 1, -1
            end
            for ki = kStart, kEnd, kStep do
                local id = GetChannelName(keys[ki])
                if id and id > 0 and id ~= currNum then
                    local _, name = GetChannelName(id)
                    if name and ChannelNameMatchesWorld(name) then
                        editbox:SetAttribute("channelTarget", id)
                        return true
                    end
                end
            end
        end,
    },
    {
        chatType = "SAY",
        use = function() return true end,
    },
}

-- Bare "/s" / "/g " left by chat-bar buttons still allow Tab; "/s hello" does not.
local function ShouldDeferTabForSlash(text)
    if strsub(text, 1, 1) ~= "/" then
        return false
    end
    local body = text:match("^/%S+%s*(.*)$")
    return body ~= nil and body ~= ""
end

-- Returns true if Tab was handled (caller should not run Blizzard default).
local function TabPressedInner(self)
    if not self or not self.GetText then
        return false
    end
    local text = tostring(self:GetText() or "")
    if ShouldDeferTabForSlash(text) then
        return false
    end
    local currChatType = self:GetAttribute("chatType") or "SAY"
    if IsControlKeyDown() then
        if currChatType == "WHISPER" or currChatType == "BN_WHISPER" then
            self:SetAttribute("chatType", chatTypeBeforeSwitch or "SAY")
            ChatEdit_UpdateHeader(self)
            chatTypeBeforeSwitch = currChatType
            tellTargetBeforeSwitch = self:GetAttribute("tellTarget")
            return true
        else
            local newTarget, newTargetType
            if ChatEdit_GetNextTellTarget then
                newTarget, newTargetType = ChatEdit_GetNextTellTarget()
            end
            if tellTargetBeforeSwitch or (newTarget and newTarget ~= "") then
                self:SetAttribute("chatType", tellTargetBeforeSwitch and chatTypeBeforeSwitch or newTargetType)
                self:SetAttribute("tellTarget", tellTargetBeforeSwitch or newTarget)
                ChatEdit_UpdateHeader(self)
                chatTypeBeforeSwitch = currChatType
                tellTargetBeforeSwitch = nil
                return true
            end
        end
    end

    for i, curr in ipairs(cycles) do
        if curr.chatType == currChatType then
            local h, r, step = i + 1, #cycles, 1
            if IsShiftKeyDown() then
                h, r, step = i - 1, 1, -1
            end
            if currChatType == "CHANNEL" then
                h = i
            end
            for j = h, r, step do
                if cycles[j].use(cycles[j], self, currChatType) then
                    self:SetAttribute("chatType", cycles[j].chatType)
                    ChatEdit_UpdateHeader(self)
                    return true
                end
            end
            return true
        end
    end
    return false
end

local function ResolveEditBox(editbox)
    if editbox and editbox.GetAttribute then
        return editbox
    end
    if ChatEdit_GetActiveWindow then
        local activeEdit = ChatEdit_GetActiveWindow()
        if activeEdit and activeEdit.GetAttribute then
            return activeEdit
        end
    end
    return _G.ChatFrameEditBox or _G.ChatFrame1EditBox
end

local function HookEditBoxTab(editbox)
    if not editbox or editbox._duieTabHooked then
        return
    end
    editbox._duieTabHooked = true
    local orig = editbox:GetScript("OnTabPressed")
    editbox:SetScript("OnTabPressed", function(self, ...)
        local cfg = Cfg()
        if active and cfg and cfg.tabSwitch ~= false then
            if TabPressedInner(self) then
                return
            end
        end
        if type(orig) == "function" then
            return orig(self, ...)
        end
    end)
end

local function HookAllChatEditBoxes()
    HookEditBoxTab(_G.ChatFrameEditBox)
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        HookEditBoxTab(_G["ChatFrame" .. i .. "EditBox"])
    end
end

local function InstallTabHandler()
    if not tabHandler then
        tabHandler = function(...)
            local cfg = Cfg()
            local editbox = ResolveEditBox(...)
            if active and cfg and cfg.tabSwitch ~= false then
                if TabPressedInner(editbox) then
                    return true
                end
            end
            if type(prevTabHandler) == "function" and prevTabHandler ~= tabHandler then
                return prevTabHandler(...)
            end
        end
    end
    -- Some clients never call this global; editbox OnTabPressed hook is the reliable path.
    if _G.ChatEdit_CustomTabPressed ~= tabHandler then
        local current = _G.ChatEdit_CustomTabPressed
        if type(current) == "function" and current ~= tabHandler then
            prevTabHandler = current
        end
        _G.ChatEdit_CustomTabPressed = tabHandler
    end
    HookAllChatEditBoxes()
    if not tabClaimFrame then
        tabClaimFrame = CreateFrame("Frame")
        tabClaimFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        tabClaimFrame:SetScript("OnEvent", function()
            if active then
                InstallTabHandler()
            end
        end)
    end
end

local function RegisterDiceSlash()
    if slashRegistered then return end
    if addon.core and addon.core.RegisterChatCommand then
        addon.core:RegisterChatCommand("duieroll", function()
            if active then
                RandomRoll(1, 100)
            end
        end)
    else
        SLASH_DUIEROLL1 = "/duieroll"
        SlashCmdList.DUIEROLL = function()
            if active then
                RandomRoll(1, 100)
            end
        end
    end
    slashRegistered = true
end

-- ---------------------------------------------------------------------------
-- Persistent editbox history (↑/↓ across reload / logout)
-- ---------------------------------------------------------------------------

local function GetEditHistory()
    if not addon.db or not addon.db.char then
        return nil
    end
    local history = addon.db.char.chatEditHistory
    if type(history) ~= "table" then
        history = {}
        addon.db.char.chatEditHistory = history
    end
    return history
end

local function TrimText(text)
    if strtrim then
        return strtrim(text)
    end
    return (tostring(text or ""):match("^%s*(.-)%s*$")) or ""
end

local function IsSecureSlash(text)
    for i = 1, #SECURE_SLASH do
        if find(text, SECURE_SLASH[i]) then
            return true
        end
    end
    return false
end

local function PersistEditHistory(text)
    if restoringHistory or not active then
        return
    end
    local cfg = Cfg()
    if not cfg or cfg.editHistory == false then
        return
    end

    text = TrimText(text)
    if text == "" or IsSecureSlash(text) then
        return
    end

    local history = GetEditHistory()
    if not history then
        return
    end

    for i = 1, #history do
        if history[i] == text then
            tremove(history, i)
            break
        end
    end
    tinsert(history, text)

    local maxSize = tonumber(cfg.editHistorySize) or 20
    if maxSize < 1 then
        maxSize = 1
    end
    while #history > maxSize do
        tremove(history, 1)
    end
end

local function ClearEditHistory()
    local history = GetEditHistory()
    if history then
        wipe(history)
    end
end

local function RestoreEditHistory()
    local history = GetEditHistory()
    if not history or #history == 0 then
        return
    end

    restoringHistory = true
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local editbox = _G["ChatFrame" .. i .. "EditBox"]
        if editbox and editbox.AddHistoryLine then
            for j = 1, #history do
                editbox:AddHistoryLine(history[j])
            end
        end
    end
    restoringHistory = false
end

local function HookEditBoxHistory(editbox)
    if not editbox or editbox.DragonUIEnhancedHistoryHooked then
        return
    end
    local orig = editbox.AddHistoryLine
    if type(orig) ~= "function" then
        return
    end
    editbox.AddHistoryLine = function(self, text)
        orig(self, text)
        PersistEditHistory(text)
    end
    editbox.DragonUIEnhancedHistoryHooked = true
end

local function InstallEditHistory()
    if historyInstalled then
        return
    end
    -- Restore before hooks so replaying AddHistoryLine does not re-persist.
    RestoreEditHistory()
    local n = NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        HookEditBoxHistory(_G["ChatFrame" .. i .. "EditBox"])
    end
    historyInstalled = true
end

local function RefreshAddMessageState()
    -- Wrappers stay installed; ProcessMessage checks cfg flags while active.
end

local function OnEnable()
    active = true
    WrapAllChatFrames()
    ApplyChatTags()
    InstallTabHandler()
    RegisterDiceSlash()
    InstallEditHistory()
    RefreshAddMessageState()
    addon:StartFeature("chatBar")
end

local function OnDisable()
    active = false
    RestoreChatTags()
    addon:StopFeature("chatBar")
    -- AddMessage / Tab / history wrappers stay for safety (requiresReload recommended for full undo)
end

addon:RegisterFeature(KEY, {
    category = "chat",
    default = true,
    requiresReload = true,
    label = function() return L["Chat Enhance"] end,
    desc = function()
        return L["Channel shorten, quick chat bar, timestamps, Tab channel cycle, edit history, and /duieroll."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        if type(addon.BuildChatBarOptions) == "function" then
            addon.BuildChatBarOptions(section, C)
        end
        C:AddToggle(section, {
            label = L["Chat Timestamps"],
            desc = L["Prefix chat lines with HH:MM:SS in cyan."],
            getFunc = function() return Cfg().timestamp and true or false end,
            setFunc = function(val)
                Cfg().timestamp = val and true or false
            end,
        })
        C:AddToggle(section, {
            label = L["Tab Channel Switch"],
            desc = L["Cycle Say/Yell/Party/Raid/BG/Guild/World with Tab (Shift reverse, Ctrl whisper)."],
            getFunc = function() return Cfg().tabSwitch ~= false end,
            setFunc = function(val)
                Cfg().tabSwitch = val and true or false
            end,
        })
        C:AddEditBox(section, {
            label = L["World Channel Keywords"],
            desc = L["Comma-separated names matched for Tab world-channel step. Default: 大脚世界频道, 世界频道, 寻求组队."],
            getFunc = function()
                local list = Cfg().worldChannelKeywords
                if type(list) ~= "table" or #list == 0 then
                    return "大脚世界频道, 世界频道, 寻求组队"
                end
                return table.concat(list, ", ")
            end,
            setFunc = function(val)
                local list = {}
                val = gsub(val or "", "[,;，；]+", "\n")
                for line in string.gmatch(val .. "\n", "([^\n]*)\n") do
                    line = strtrim and strtrim(line) or line:match("^%s*(.-)%s*$")
                    if line and line ~= "" then
                        list[#list + 1] = line
                    end
                end
                Cfg().worldChannelKeywords = (#list > 0) and list or nil
            end,
        })
        C:AddToggle(section, {
            label = L["Remember Chat Input History"],
            desc = L["Keep sent chat lines across reload and logout. Use Up/Down to browse."],
            getFunc = function() return Cfg().editHistory ~= false end,
            setFunc = function(val)
                Cfg().editHistory = val and true or false
            end,
        })
        C:AddSlider(section, {
            label = L["Chat Input History Size"],
            desc = L["Maximum number of remembered input lines."],
            min = 5,
            max = 50,
            step = 1,
            getFunc = function() return Cfg().editHistorySize or 20 end,
            setFunc = function(val)
                Cfg().editHistorySize = math.floor(val + 0.5)
                local history = GetEditHistory()
                if history then
                    local maxSize = Cfg().editHistorySize or 20
                    while #history > maxSize do
                        tremove(history, 1)
                    end
                end
            end,
            disabled = function() return Cfg().editHistory == false end,
        })
        C:AddButton(section, {
            label = L["Clear Chat Input History"],
            desc = L["Clear saved history for this character. Reload to clear the current session list."],
            callback = function()
                ClearEditHistory()
            end,
            disabled = function() return Cfg().editHistory == false end,
        })
    end,
})
