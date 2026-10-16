-- Party aura spell data for partyauras (WotLK 3.3.5a).
-- Buff groups: higher priority wins when multiple ranks/group versions are present.

local ADDON_NAME, addon = ...

addon.data = addon.data or {}

-- spellId -> { group = string, priority = number }
-- Greater / raid versions use higher priority so they win over singles.
local buffById = {}

local function AddBuffGroup(group, entries)
    for i = 1, #entries do
        local spellId, priority = entries[i][1], entries[i][2]
        buffById[spellId] = { group = group, priority = priority }
    end
end

-- Power Word: Fortitude / Prayer of Fortitude
AddBuffGroup("fortitude", {
    { 48162, 40 }, { 25392, 39 }, { 21564, 38 }, { 21562, 37 }, -- Prayer
    { 48161, 30 }, { 25389, 29 }, { 10938, 28 }, { 10937, 27 },
    { 2791, 26 }, { 1245, 25 }, { 1244, 24 }, { 1243, 23 },
})

-- Mark of the Wild / Gift of the Wild
AddBuffGroup("motw", {
    { 48470, 40 }, { 26991, 39 }, { 21850, 38 }, { 21849, 37 }, -- Gift
    { 48469, 30 }, { 26990, 29 }, { 9885, 28 }, { 9884, 27 },
    { 8907, 26 }, { 5234, 25 }, { 6756, 24 }, { 5232, 23 }, { 1126, 22 },
})

-- Blessing of Kings / Greater Blessing of Kings
AddBuffGroup("kings", {
    { 25898, 40 }, -- Greater
    { 20217, 30 },
})

-- Blessing of Might / Greater Blessing of Might
AddBuffGroup("might", {
    { 48934, 40 }, { 48933, 39 }, { 27141, 38 }, { 25916, 37 }, { 25782, 36 }, -- Greater
    { 48932, 30 }, { 48931, 29 }, { 27140, 28 }, { 25291, 27 },
    { 19838, 26 }, { 19837, 25 }, { 19836, 24 }, { 19835, 23 },
    { 19834, 22 }, { 19740, 21 },
})

-- Arcane Intellect / Arcane Brilliance
AddBuffGroup("intellect", {
    { 43002, 40 }, { 27127, 39 }, { 23028, 38 }, -- Brilliance
    { 42995, 30 }, { 27126, 29 }, { 10157, 28 }, { 10156, 27 },
    { 1461, 26 }, { 1460, 25 }, { 1459, 24 },
})

-- Divine Spirit / Prayer of Spirit
AddBuffGroup("spirit", {
    { 48074, 40 }, { 32999, 39 }, { 27681, 38 }, -- Prayer
    { 48073, 30 }, { 25312, 29 }, { 27841, 28 },
    { 14819, 27 }, { 14818, 26 }, { 14752, 25 },
})

-- Thorns (荆棘术)
AddBuffGroup("thorns", {
    { 53307, 30 }, { 26992, 29 }, { 9910, 28 }, { 9756, 27 },
    { 8914, 26 }, { 1075, 25 }, { 782, 24 }, { 467, 23 },
})

addon.data.partyAuraBuffById = buffById

-- Important / boss debuffs (spellId -> priority; higher shows first).
-- Focused on ICC / ToC / common raid callouts; extend as needed.
addon.data.partyAuraImportantDebuffs = {
    -- Icecrown Citadel
    [70337] = 100, -- Necrotic Plague
    [70338] = 100,
    [73785] = 100,
    [73786] = 100,
    [73787] = 100,
    [73912] = 100,
    [73913] = 100,
    [73914] = 100,
    [72754] = 95,  -- Defile
    [73708] = 95,
    [73709] = 95,
    [73710] = 95,
    [70126] = 90,  -- Frost Beacon
    [71053] = 90,
    [71054] = 90,
    [71055] = 90,
    [69762] = 88,  -- Unchained Magic
    [69766] = 87,  -- Instability
    [70106] = 86,  -- Chilled to the Bone
    [70157] = 85,  -- Ice Tomb
    [71265] = 84,  -- Swarming Shadows
    [71237] = 83,  -- Curse of Torpor
    [73022] = 92,  -- Mutated Infection (H)
    [71224] = 92,
    [72672] = 91,  -- Mutated Plague
    [72451] = 91,
    [70447] = 80,  -- Volatile Ooze Adhesive
    [70672] = 80,  -- Gaseous Bloat
    [72832] = 79,
    [72836] = 79,
    [71289] = 78,  -- Dominate Mind
    [71340] = 77,  -- Pact of the Darkfallen
    [71341] = 77,
    [69279] = 76,  -- Gas Spore
    [71278] = 75,  -- Choking Gas Bomb
    [72619] = 74,  -- Inoculated
    [72620] = 74,
    [73001] = 73,  -- Shadow Prison
    [74325] = 98,  -- Harvest Soul
    [69483] = 97,  -- Dark Reckoning
    [72293] = 96,  -- Mark of the Fallen Champion
    [72385] = 70,  -- Boiling Blood
    [72442] = 70,
    [72441] = 70,
    [72443] = 70,
    [70435] = 69,  -- Rend Flesh
    [70503] = 68,  -- Spirit Alarm
    -- Trial of the Crusader
    [66823] = 85,  -- Paralytic Toxin
    [67618] = 85,
    [66869] = 84,  -- Burning Bile
    [66870] = 84,
    [66237] = 83,  -- Incinerate Flesh
    [67049] = 83,
    [67050] = 83,
    [67051] = 83,
    [66013] = 82,  -- Penetrating Cold
    [67700] = 82,
    [68509] = 82,
    [68510] = 82,
    [67574] = 81,  -- Pursued by Anub'arak
    [67847] = 80,  -- Expose Weakness
    [66331] = 79,  -- Impale
    [65950] = 78,  -- Touch of Light / Darkness (twins)
    [66001] = 78,
    -- Ulduar / Naxx callouts often still used
    [63138] = 60,  -- Sara's Anger
    [63134] = 60,  -- Sara's Blessing (misdirect-ish; skip if noise — keep as medium)
    [64290] = 65,  -- Stone Grip
    [64292] = 65,
    [61888] = 64,  -- Overwhelming Power
    [64637] = 63,  -- Overwhelming Power (H)
    [62130] = 62,  -- Unbalancing Strike
    -- Common PvE / healer-relevant
    [12294] = 50,  -- Mortal Strike
    [21551] = 50,
    [21552] = 50,
    [21553] = 50,
    [25248] = 50,
    [47486] = 50,
    [47485] = 50,
    [19434] = 49,  -- Aimed Shot
    [20904] = 49,
    [27065] = 49,
    [49050] = 49,
    [49051] = 49,
    [13218] = 48,  -- Wound Poison
    [13222] = 48,
    [13223] = 48,
    [13224] = 48,
    [27189] = 48,
    [57975] = 48,
    [48301] = 47,  -- Mind Trauma
    [57723] = 40,  -- Exhaustion (Bloodlust)
    [57724] = 40,  -- Sated
}

-- Class -> dispel types the player can remove (WotLK).
addon.data.partyAuraDispelByClass = {
    PRIEST = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    SHAMAN = { Curse = true, Poison = true, Disease = true },
    MAGE = { Curse = true },
    DRUID = { Curse = true, Poison = true },
}
