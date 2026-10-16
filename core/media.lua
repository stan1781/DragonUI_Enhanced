-- DragonUI_Enhanced — centralized media paths.

local ADDON_NAME, addon = ...

addon.media = addon.media or {}

local ROOT = "Interface\\AddOns\\DragonUI_Enhanced\\"

addon.media.root = ROOT
addon.media.textures = ROOT .. "Textures\\"
addon.media.sounds = ROOT .. "Sounds\\"
addon.media.emotion = ROOT .. "media\\Emotion\\"

-- Shared Blizzard / DragonUI-friendly fallbacks used by early features.
addon.media.icons = {
    dash = "Interface\\Icons\\Ability_Druid_Dash",
}

function addon:GetMediaPath(subpath)
    if not subpath or subpath == "" then
        return ROOT
    end
    return ROOT .. subpath
end
