-- DragonUI_Enhanced — LFG bot / Telegram system tip chat filter.
-- Ported from ElvUI_Enhanced SystemMessageFilter (logic only; storage → DragonUI_EnhancedDB).

local ADDON_NAME, addon = ...
local L = addon.L

local find = string.find
local format = string.format
local gsub = string.gsub
local match = string.match
local ipairs = ipairs
local pairs = pairs

local KEY = "chatFilter"

local filterPatterns = {
    "小窍门：你可以关注官方Telegram频道",
    "不在你的队伍中",
}

local blockedGuilds = {
    ["鲜血与荣耀"] = "Horde",
    ["乘风破浪"] = "Alliance",
}

-- Capital / hub zone IDs used for daily auto /who (WotLK private-server map IDs).
local AUTO_WHO_ZONES = {
    [302] = true, [342] = true, [382] = true, [472] = true,
    [322] = true, [383] = true, [363] = true, [481] = true, [482] = true,
    [478] = true, [504] = true, [505] = true,
    [301] = true, [321] = true, [341] = true, [362] = true, [381] = true, [471] = true,
    [1453] = true, [1537] = true, [1657] = true, [1947] = true,
    [1637] = true, [1638] = true, [1954] = true, [3703] = true, [4395] = true,
}

local staticBlockedPlayers
local state = {
    guildCache = {},
    blockedPlayers = {},
    systemFilterFunc = nil,
    channelFilterFunc = nil,
    systemRegistered = false,
    channelRegistered = false,
    eventsRegistered = false,
    eventFrame = nil,
    autoWhoCollecting = false,
    autoWhoStats = nil,
}

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function StaticList()
    if not staticBlockedPlayers then
        staticBlockedPlayers = (addon.data and addon.data.staticBlockedPlayers) or {}
    end
    return staticBlockedPlayers
end

local function GetGlobal()
    if not addon.db then return nil end
    addon.db.global = addon.db.global or {}
    local g = addon.db.global
    g.lfgBlockedPlayers = g.lfgBlockedPlayers or {}
    g.autoWhoLastScan = g.autoWhoLastScan or {}
    g.migrated = g.migrated or {}
    return g
end

local function After(delay, callback)
    local DUI = _G.DragonUI
    if DUI and DUI.After then
        DUI:After(delay, callback)
        return
    end
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(callback, delay)
        return
    end
    local f = CreateFrame("Frame")
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
end

local function CleanColorCodes(msg)
    local cleanMsg = msg
    if find(msg, "|cff") then
        cleanMsg = gsub(cleanMsg, "|cff%w%w%w%w%w%w", "")
        cleanMsg = gsub(cleanMsg, "|r", "")
    end
    return cleanMsg
end

local function StripRealm(name)
    if not name then return nil end
    return match(name, "^([^%-]+)") or name
end

local function MessageMentionsBlockedGuild(msg)
    local cleanMsg = CleanColorCodes(msg)
    for guildName in pairs(blockedGuilds) do
        if find(cleanMsg, guildName, 1, true) then
            return true
        end
        if find(cleanMsg, "<" .. guildName .. ">", 1, true) then
            return true
        end
    end
    return false
end

local function MigrateFromLegacy()
    local g = GetGlobal()
    if not g or g.migrated.lfgBlocked then
        return
    end
    g.migrated.lfgBlocked = true

    local sources = {}
    if _G.ElvUIDB and _G.ElvUIDB.global and _G.ElvUIDB.global.enhanced
        and type(_G.ElvUIDB.global.enhanced.lfgBlockedPlayers) == "table" then
        sources[#sources + 1] = _G.ElvUIDB.global.enhanced.lfgBlockedPlayers
    end
    if _G.EnhancedDB and type(_G.EnhancedDB.LFGBlockedPlayers) == "table" then
        sources[#sources + 1] = _G.EnhancedDB.LFGBlockedPlayers
    end

    local imported = 0
    for i = 1, #sources do
        for name, guildName in pairs(sources[i]) do
            if name and guildName and not g.lfgBlockedPlayers[name] and not StaticList()[name] then
                g.lfgBlockedPlayers[name] = guildName
                imported = imported + 1
            end
        end
    end
    if imported > 0 then
        print(format("|cff1784d1[LFG屏蔽]|r 已从旧存档导入 %d 名动态屏蔽玩家。", imported))
    end
end

local function IsBlockedPlayer(name)
    if not name then return nil end
    if StaticList()[name] then
        return StaticList()[name]
    end
    return state.blockedPlayers[name]
end

local function CacheBlockedPlayer(name, guildName)
    if not name or not guildName then return false end
    local g = GetGlobal()
    if not g then return false end
    if g.lfgBlockedPlayers[name] then
        return false
    end
    if StaticList()[name] then
        return false
    end
    g.lfgBlockedPlayers[name] = guildName
    state.blockedPlayers[name] = guildName
    state.guildCache[name] = guildName
    return true
end

local function LoadBlockedPlayers()
    state.blockedPlayers = {}
    local g = GetGlobal()
    if not g then return end
    local pruned = 0
    local static = StaticList()
    for name, guildName in pairs(g.lfgBlockedPlayers) do
        if static[name] then
            g.lfgBlockedPlayers[name] = nil
            pruned = pruned + 1
        else
            state.blockedPlayers[name] = guildName
        end
    end
    if pruned > 0 then
        print(format("|cff1784d1[LFG屏蔽]|r 已从存档中清理 %d 条静态表重复记录。", pruned))
    end
end

local function GetBlockedPlayerCount()
    local count = 0
    local seen = {}
    for name in pairs(StaticList()) do
        seen[name] = true
        count = count + 1
    end
    local g = GetGlobal()
    if g then
        for name in pairs(g.lfgBlockedPlayers) do
            if not seen[name] then
                count = count + 1
            end
        end
    end
    return count
end

local function GetGuildsForPlayer()
    local playerFaction = UnitFactionGroup("player")
    local guilds = {}
    for guildName, faction in pairs(blockedGuilds) do
        if not playerFaction or faction == playerFaction then
            guilds[#guilds + 1] = guildName
        end
    end
    return guilds
end

local function GetSenderGuild(sender)
    if not sender or sender == "" then
        return nil
    end
    local name = StripRealm(sender)
    if not name then
        return nil
    end

    local blockedGuild = IsBlockedPlayer(name)
    if blockedGuild then
        return blockedGuild
    end

    if state.guildCache[name] then
        return state.guildCache[name]
    end

    if _G.EnhancedDB and _G.EnhancedDB.UnitTitle and _G.EnhancedDB.UnitTitle[name]
        and _G.EnhancedDB.GuildList then
        local titleId = _G.EnhancedDB.UnitTitle[name]
        local guildName = _G.EnhancedDB.GuildList[titleId]
        if guildName then
            state.guildCache[name] = guildName
            return guildName
        end
    end

    local units = { "target", "mouseover", "focus" }
    for i = 1, 4 do
        units[#units + 1] = "party" .. i
    end
    for i = 1, 40 do
        units[#units + 1] = "raid" .. i
    end

    for _, unit in ipairs(units) do
        if UnitIsPlayer(unit) then
            local unitName = UnitName(unit)
            if unitName and (unitName == name or StripRealm(unitName) == name) then
                local guildName = GetGuildInfo(unit)
                if guildName then
                    state.guildCache[name] = guildName
                    return guildName
                end
            end
        end
    end

    local playerName = UnitName("player")
    if playerName and (name == StripRealm(playerName) or sender == playerName) then
        local guildName = GetGuildInfo("player")
        if guildName then
            state.guildCache[name] = guildName
            return guildName
        end
    end

    return nil
end

local function ParseSystemEvent(_, event, msg)
    if event ~= "CHAT_MSG_SYSTEM" then
        return false
    end
    local cfg = Cfg()
    if cfg.filterTelegramTip == false then
        return false
    end
    local cleanMsg = CleanColorCodes(msg)
    for _, pattern in ipairs(filterPatterns) do
        if find(cleanMsg, pattern, 1, true) then
            return true
        end
    end
    return false
end

local function ParseChannelEvent(_, event, msg, sender, _, channelString, _, _, _, _, channelName)
    if event ~= "CHAT_MSG_CHANNEL" then
        return false
    end
    local cfg = Cfg()
    if cfg.filterLFGGuilds == false then
        return false
    end

    local name = StripRealm(sender)

    if name and IsBlockedPlayer(name) then
        return true
    end

    if MessageMentionsBlockedGuild(msg) then
        if name then
            for guildName in pairs(blockedGuilds) do
                if find(CleanColorCodes(msg), guildName, 1, true) then
                    CacheBlockedPlayer(name, guildName)
                    break
                end
            end
        end
        return true
    end

    if name then
        local guildName = GetSenderGuild(sender)
        if guildName and blockedGuilds[guildName] then
            CacheBlockedPlayer(name, guildName)
            return true
        end
    end

    return false
end

local function RecordWhoResults()
    local numWhos = GetNumWhoResults()
    if not numWhos or numWhos == 0 then return end

    local recorded, newCount, skippedStatic = 0, 0, 0
    local static = StaticList()
    for i = 1, numWhos do
        local name, guildName = GetWhoInfo(i)
        if name and guildName and blockedGuilds[guildName] then
            name = StripRealm(name)
            recorded = recorded + 1
            if static[name] then
                skippedStatic = skippedStatic + 1
            elseif CacheBlockedPlayer(name, guildName) then
                newCount = newCount + 1
            end
        end
    end

    if recorded > 0 then
        if state.autoWhoCollecting and state.autoWhoStats then
            state.autoWhoStats.recorded = state.autoWhoStats.recorded + recorded
            state.autoWhoStats.newCount = state.autoWhoStats.newCount + newCount
            state.autoWhoStats.skippedStatic = state.autoWhoStats.skippedStatic + skippedStatic
        else
            local msg = format("|cff1784d1[LFG屏蔽]|r 本次 /who 收录 %d 人，新增 %d 人", recorded, newCount)
            if skippedStatic > 0 then
                msg = msg .. format("，%d 人已在静态表中跳过", skippedStatic)
            end
            msg = msg .. format("，合计 %d 人。", GetBlockedPlayerCount())
            print(msg)
        end
    end
end

local function GetCurrentDate()
    return date("%Y%m%d")
end

local function CheckAutoWho()
    local cfg = Cfg()
    if cfg.filterLFGGuilds == false or cfg.autoWho == false then
        return
    end

    local zoneID = GetCurrentMapAreaID and GetCurrentMapAreaID()
    if not zoneID or not AUTO_WHO_ZONES[zoneID] then
        return
    end

    local g = GetGlobal()
    if not g then return end
    local visitedZones = g.autoWhoLastScan
    local currentDate = GetCurrentDate()
    local playerFaction = UnitFactionGroup("player") or "Unknown"
    local zoneKey = format("%d_%s", zoneID, playerFaction)

    for key, scanDate in pairs(visitedZones) do
        if scanDate ~= currentDate then
            local daysDiff = tonumber(currentDate) - tonumber(scanDate)
            if daysDiff and (daysDiff > 7 or daysDiff < 0) then
                visitedZones[key] = nil
            end
        end
    end

    if visitedZones[zoneKey] == currentDate then
        return
    end

    local guilds = GetGuildsForPlayer()
    if #guilds == 0 then
        return
    end

    state.autoWhoCollecting = true
    state.autoWhoStats = { recorded = 0, newCount = 0, skippedStatic = 0 }

    local queryDelay = 0
    for _, guildName in ipairs(guilds) do
        local delay = queryDelay
        local gName = guildName
        After(delay, function()
            if SendWho then
                SendWho(format("g-%s", gName))
            end
        end)
        queryDelay = queryDelay + 2
    end

    After(queryDelay + 1, function()
        visitedZones[zoneKey] = currentDate
        local s = state.autoWhoStats or { recorded = 0, newCount = 0, skippedStatic = 0 }
        state.autoWhoCollecting = false
        state.autoWhoStats = nil
        local factionText = playerFaction == "Alliance" and "联盟" or "部落"
        local msg = format("|cff1784d1[LFG屏蔽]|r %s主城自动收集：收录 %d，新增 %d", factionText, s.recorded, s.newCount)
        if s.skippedStatic > 0 then
            msg = msg .. format("，静态跳过 %d", s.skippedStatic)
        end
        msg = msg .. format("，合计 |cff00ff00%d|r。", GetBlockedPlayerCount())
        print(msg)
    end)
end

local function OnEvent(_, event)
    if event == "WHO_LIST_UPDATE" then
        RecordWhoResults()
    elseif event == "PLAYER_ENTERING_WORLD" then
        LoadBlockedPlayers()
        CheckAutoWho()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        CheckAutoWho()
    end
end

local function EnsureEventFrame()
    if state.eventFrame then return state.eventFrame end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", OnEvent)
    state.eventFrame = f
    return f
end

local function UpdateFilters()
    local cfg = Cfg()
    local filterSystem = cfg.filterTelegramTip ~= false
    local filterLFG = cfg.filterLFGGuilds ~= false

    if not state.systemFilterFunc then
        state.systemFilterFunc = function(chatFrame, event, msg, ...)
            return ParseSystemEvent(chatFrame, event, msg, ...)
        end
    end
    if not state.channelFilterFunc then
        state.channelFilterFunc = function(chatFrame, event, msg, sender, ...)
            return ParseChannelEvent(chatFrame, event, msg, sender, ...)
        end
    end

    if filterSystem then
        if not state.systemRegistered then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", state.systemFilterFunc)
            state.systemRegistered = true
        end
    elseif state.systemRegistered then
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", state.systemFilterFunc)
        state.systemRegistered = false
    end

    if filterLFG then
        if not state.channelRegistered then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", state.channelFilterFunc)
            state.channelRegistered = true
        end
        local f = EnsureEventFrame()
        if not state.eventsRegistered then
            f:RegisterEvent("WHO_LIST_UPDATE")
            f:RegisterEvent("PLAYER_ENTERING_WORLD")
            f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            state.eventsRegistered = true
        end
    else
        if state.channelRegistered then
            ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL", state.channelFilterFunc)
            state.channelRegistered = false
        end
        if state.eventsRegistered and state.eventFrame then
            state.eventFrame:UnregisterEvent("WHO_LIST_UPDATE")
            state.eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            state.eventFrame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
            state.eventsRegistered = false
        end
    end
end

local function OnEnable()
    MigrateFromLegacy()
    LoadBlockedPlayers()
    UpdateFilters()
    CheckAutoWho()
end

local function OnDisable()
    if state.systemRegistered and state.systemFilterFunc then
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", state.systemFilterFunc)
        state.systemRegistered = false
    end
    if state.channelRegistered and state.channelFilterFunc then
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_CHANNEL", state.channelFilterFunc)
        state.channelRegistered = false
    end
    if state.eventsRegistered and state.eventFrame then
        state.eventFrame:UnregisterAllEvents()
        state.eventsRegistered = false
    end
end

addon:RegisterFeature(KEY, {
    category = "chat",
    default = true,
    label = function() return L["LFG Bot Filter"] end,
    desc = function()
        return L["Block bot guild chat, cached bot players, and Telegram system tips."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddToggle(section, {
            label = L["Filter Telegram Tips"],
            desc = L["Hide system messages advertising the official Telegram channel."],
            getFunc = function()
                return Cfg().filterTelegramTip ~= false
            end,
            setFunc = function(val)
                Cfg().filterTelegramTip = val and true or false
                if addon:IsFeatureEnabled(KEY) then
                    UpdateFilters()
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Filter Bot Guild Chat"],
            desc = L["Hide channel messages from blocked bot guilds and known bot characters."],
            getFunc = function()
                return Cfg().filterLFGGuilds ~= false
            end,
            setFunc = function(val)
                Cfg().filterLFGGuilds = val and true or false
                if addon:IsFeatureEnabled(KEY) then
                    UpdateFilters()
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Auto /who in Capitals"],
            desc = L["Once per day per capital, silently /who blocked guilds to grow the player list."],
            getFunc = function()
                return Cfg().autoWho ~= false
            end,
            setFunc = function(val)
                Cfg().autoWho = val and true or false
            end,
        })
        C:AddDescription(section, format(L["Blocked players (static + dynamic): %d."], GetBlockedPlayerCount()))
    end,
})
