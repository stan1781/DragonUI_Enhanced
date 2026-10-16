-- DragonUI_Enhanced — ChatBar P1: channel shorten, timestamp, Tab cycle, dice.
-- Uses chained wrappers (no blind global overwrite). No chat-copy / link-hover.

local ADDON_NAME, addon = ...
local L = addon.L

local format = string.format
local gsub = string.gsub
local find = string.find
local strsub = string.sub
local tostring = tostring
local ipairs = ipairs

local KEY = "chatEnhance"

local active = false
local originals = {} -- ChatFrame AddMessage backups
local prevTabHandler
local tabInstalled = false
local tagsApplied = false
local savedTags = {}
local slashRegistered = false

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
    return { "大脚世界频道", "世界频道" }
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

local function ProcessMessage(text)
    local cfg = Cfg()
    if type(text) ~= "string" then
        text = tostring(text)
    end
    if cfg.shortChannel ~= false then
        text = ShortenChannels(text)
    end
    if cfg.timestamp then
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
            local currNum
            if currChatType ~= "CHANNEL" then
                currNum = IsShiftKeyDown() and 21 or 0
            else
                currNum = editbox:GetAttribute("channelTarget")
            end
            local h, r, step = currNum + 1, 20, 1
            if IsShiftKeyDown() then
                h, r, step = currNum - 1, 1, -1
            end
            for i = h, r, step do
                local channelNum, channelName = GetChannelName(i)
                if channelNum and channelNum > 0 and ChannelNameMatchesWorld(channelName) then
                    editbox:SetAttribute("channelTarget", i)
                    return true
                end
            end
        end,
    },
    {
        chatType = "SAY",
        use = function() return true end,
    },
}

local function TabPressedInner(self)
    if strsub(tostring(self:GetText()), 1, 1) == "/" then
        return
    end
    local currChatType = self:GetAttribute("chatType")
    if IsControlKeyDown() then
        if currChatType == "WHISPER" or currChatType == "BN_WHISPER" then
            self:SetAttribute("chatType", chatTypeBeforeSwitch or "SAY")
            ChatEdit_UpdateHeader(self)
            chatTypeBeforeSwitch = currChatType
            tellTargetBeforeSwitch = self:GetAttribute("tellTarget")
            return
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
                    return
                end
            end
        end
    end
end

local function InstallTabHandler()
    if tabInstalled then return end
    prevTabHandler = _G.ChatEdit_CustomTabPressed
    _G.ChatEdit_CustomTabPressed = function(...)
        local cfg = Cfg()
        if active and cfg.tabSwitch ~= false then
            return TabPressedInner(...)
        end
        if type(prevTabHandler) == "function" then
            return prevTabHandler(...)
        end
    end
    tabInstalled = true
end

local function RegisterDiceSlash()
    if slashRegistered then return end
    if addon.core and addon.core.RegisterChatCommand then
        addon.core:RegisterChatCommand("duieroll", function()
            if active and Cfg().dice ~= false then
                RandomRoll(1, 100)
            end
        end)
    else
        SLASH_DUIEROLL1 = "/duieroll"
        SlashCmdList.DUIEROLL = function()
            if active and Cfg().dice ~= false then
                RandomRoll(1, 100)
            end
        end
    end
    slashRegistered = true
end

local function RefreshAddMessageState()
    -- Wrappers stay installed; ProcessMessage checks cfg flags while active.
end

local function OnEnable()
    active = true
    WrapAllChatFrames()
    if Cfg().shortChannel ~= false then
        ApplyChatTags()
    end
    InstallTabHandler()
    RegisterDiceSlash()
    RefreshAddMessageState()
end

local function OnDisable()
    active = false
    RestoreChatTags()
    -- AddMessage / Tab wrappers stay for safety (requiresReload recommended for full undo)
end

addon:RegisterFeature(KEY, {
    category = "chat",
    default = true,
    requiresReload = true,
    label = function() return L["Chat Enhance"] end,
    desc = function()
        return L["Channel shorten, timestamps, Tab channel cycle, and /duieroll dice."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddToggle(section, {
            label = L["Shorten Channel Names"],
            desc = L["Show abbreviated public channel tags like [1综合]."],
            getFunc = function() return Cfg().shortChannel ~= false end,
            setFunc = function(val)
                Cfg().shortChannel = val and true or false
                if val then ApplyChatTags() else RestoreChatTags() end
            end,
        })
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
        C:AddToggle(section, {
            label = L["Dice (/duieroll)"],
            desc = L["Enable /duieroll to roll 1-100."],
            getFunc = function() return Cfg().dice ~= false end,
            setFunc = function(val)
                Cfg().dice = val and true or false
            end,
        })
        C:AddEditBox(section, {
            label = L["World Channel Keywords"],
            desc = L["Comma-separated names matched for Tab world-channel step. Default: 大脚世界频道, 世界频道."],
            getFunc = function()
                local list = Cfg().worldChannelKeywords
                if type(list) ~= "table" or #list == 0 then
                    return "大脚世界频道, 世界频道"
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
    end,
})
