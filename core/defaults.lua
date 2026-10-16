-- DragonUI_Enhanced — AceDB defaults schema.

local ADDON_NAME, addon = ...

addon.defaults = {
    profile = {
        features = {
            motionSpeed = {
                enabled = true,
                fontSize = 11,
                scale = 1,
                anchor = "CENTER",
                posX = 0,
                posY = 120,
            },
            buffKeyword = {
                enabled = true,
                -- keywords = nil means use built-in DEFAULT_KEYWORDS
            },
            partyauras = {
                enabled = true,
                anchor = "LEFT",
                size = 18,
                spacing = 1,
                maxBuffs = 8,
                rows = 2,
                showTimers = true,
            },
            chatFilter = {
                enabled = true,
                filterTelegramTip = true,
                filterLFGGuilds = true,
                autoWho = true,
            },
            chatEnhance = {
                enabled = true,
                shortChannel = true,
                timestamp = true,
                tabSwitch = true,
                dice = true,
                -- worldChannelKeywords = nil → defaults
            },
            chatBar = {
                enabled = true,
                scale = 1,
                -- 默认贴在 ChatFrame1 上方；拖动后改为 UIParent 绝对坐标
                anchorToChat = true,
                chatOffsetX = 0,
                chatOffsetY = 4,
                anchor = "BOTTOMLEFT",
                posX = 16,
                posY = 30,
                -- lfgChannelName = nil → "寻求组队"
            },
            runeBar = {
                enabled = true,
            },
            inspectPanel = {
                enabled = true,
                charWindow = true,
                inspectWindow = true,
                -- Negative X pulls the list toward Character/Inspect (ForeverUI chrome needs a bit of overlap).
                offsetX = -20,
                offsetY = 10,
            },
            equipmentHelper = {
                enabled = true,
                anchor = "CENTER",
                posX = 0,
                posY = -180,
                scale = 1,
            },
            friendSync = {
                enabled = true,
            },
            friendsMenuXP = {
                enabled = true,
            },
            visualprocs = {
                enabled = true,
                overlay = true,
                buttonGlow = true,
                overlayScale = 0.8,
                disableSound = false,
            },
        },
    },
    global = {
        migrated = {},
        lfgBlockedPlayers = {},
        autoWhoLastScan = {},
        runeActionBar = { chars = {} },
        equipment = { chars = {} },
        friendSync = {
            friendsByFaction = { Alliance = {}, Horde = {} },
            removedByFaction = { Alliance = {}, Horde = {} },
            friends = {},
            chars = {},
            settings = {
                autoSyncOnLogin = false,
                autoCleanOnLogin = true,
            },
        },
        version = 1,
    },
}
