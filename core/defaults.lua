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
            chatFilter = {
                enabled = true,
                filterTelegramTip = true,
                filterLFGGuilds = true,
                autoWho = true,
            },
        },
    },
    global = {
        migrated = {},
        lfgBlockedPlayers = {},
        autoWhoLastScan = {},
        version = 1,
    },
}
