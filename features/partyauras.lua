-- DragonUI_Enhanced — party frame important buffs + dispellable/important debuffs.
-- Show-when-present only; mounts on PartyMemberFrame1-4. Unit-list ready for future raid.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "partyauras"
local MAX_PARTY = 4
local POOL_SIZE = 12

local UnitExists = UnitExists
local UnitBuff = UnitBuff
local UnitDebuff = UnitDebuff
local UnitClass = UnitClass
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local CreateFrame = CreateFrame
local pairs = pairs
local wipe = wipe
local strlower = string.lower
local floor = math.floor
local ceil = math.ceil
local format = string.format

-- name(lower) -> { group, priority } built from buff spell IDs (fallback if spellId missing).
local buffByName
-- name(lower) -> priority for important debuffs without spellId.
local importantByName

local eventFrame
local hosts = {} -- [index] = host
local pendingLayout = false
local playerDispel
local playerClass

local scratchBuffBest = {}
local scratchDebuffs = {}
local scratchSeen = {}

local RefreshHost -- forward decl for timer OnUpdate

local function Cfg()
    local cfg = addon:GetFeatureConfig(KEY)
    if not cfg then
        return nil
    end
    -- AceDB may leave new keys as { enabled = true } only; treat nil as default-on.
    local defaults = addon.defaults
        and addon.defaults.profile
        and addon.defaults.profile.features
        and addon.defaults.profile.features.partyauras
    if defaults then
        for k, v in pairs(defaults) do
            if cfg[k] == nil then
                cfg[k] = v
            end
        end
    end
    return cfg
end

local function RefreshPlayerDispel()
    playerClass = select(2, UnitClass("player"))
    local map = addon.data and addon.data.partyAuraDispelByClass
    playerDispel = map and map[playerClass] or nil
end

local function GetDebuffBorderColor(debuffType)
    local colors = _G.DebuffTypeColor
    local c = colors and colors[debuffType or ""]
    if c then
        return c.r, c.g, c.b
    end
    return 0.8, 0, 0
end

-- e.g. 5m / 12s (permanent auras return "").
local function FormatTimeLeft(seconds)
    if not seconds or seconds <= 0 then
        return ""
    end
    if seconds >= 60 then
        return format("%dm", ceil(seconds / 60))
    end
    return format("%ds", ceil(seconds))
end

local function UpdateIconTimer(btn, now)
    if not btn or not btn:IsShown() or not btn.timer then
        return
    end
    if not btn.expiration or btn.expiration <= 0 then
        if btn._lastTimerText ~= "" then
            btn.timer:SetText("")
            btn.timer:Hide()
            btn._lastTimerText = ""
        end
        return
    end
    local remaining = btn.expiration - (now or GetTime())
    if remaining <= 0 then
        if btn._lastTimerText ~= "" then
            btn.timer:SetText("")
            btn.timer:Hide()
            btn._lastTimerText = ""
        end
        return true -- expired
    end
    local txt = FormatTimeLeft(remaining)
    if btn._lastTimerText ~= txt then
        btn.timer:SetText(txt)
        btn.timer:Show()
        btn._lastTimerText = txt
        if remaining < 5 then
            btn.timer:SetTextColor(1, 0.2, 0.2)
        elseif remaining < 30 then
            btn.timer:SetTextColor(1, 0.82, 0)
        else
            btn.timer:SetTextColor(1, 1, 1)
        end
    end
end

local function HostOnUpdate(self, elapsed)
    self._timerElapsed = (self._timerElapsed or 0) + elapsed
    if self._timerElapsed < 0.2 then
        return
    end
    self._timerElapsed = 0
    local now = GetTime()
    local anyExpired = false
    local icons = self.icons
    if not icons then
        return
    end
    for i = 1, #icons do
        local btn = icons[i]
        if btn and btn:IsShown() then
            if UpdateIconTimer(btn, now) then
                anyExpired = true
            end
        end
    end
    if anyExpired then
        local id = self.partyIndex
        if id then
            RefreshHost(id)
        end
    end
end

local function AcquireIcon(host, index)
    local icons = host.icons
    local btn = icons[index]
    if btn then
        return btn
    end
    btn = CreateFrame("Button", nil, host)
    btn:SetFrameLevel(host:GetFrameLevel() + 1)
    btn:EnableMouse(true)
    btn:Hide()

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    border:SetAllPoints(btn)
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    btn.border = border

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 0)
    btn.count = count

    local timer = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    timer:SetPoint("CENTER", btn, "CENTER", 0, 0)
    timer:SetJustifyH("CENTER")
    timer:SetShadowOffset(1, -1)
    timer:Hide()
    btn.timer = timer
    btn._lastTimerText = ""

    local ok, cd = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints(btn)
        cd:SetFrameLevel(btn:GetFrameLevel() + 1)
        -- Keep swipe under the timer text.
        if cd.SetDrawEdge then
            cd:SetDrawEdge(false)
        end
        btn.cd = cd
    end

    btn:SetScript("OnEnter", function(self)
        if not self.auraIndex or not self.filter then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.filter == "HARMFUL" then
            GameTooltip:SetUnitDebuff(host.unit, self.auraIndex)
        else
            GameTooltip:SetUnitBuff(host.unit, self.auraIndex)
        end
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    icons[index] = btn
    return btn
end

local function HideIconFrom(host, fromIndex)
    local icons = host.icons
    for i = fromIndex, #icons do
        local btn = icons[i]
        if btn then
            btn:Hide()
            btn.auraIndex = nil
            btn.filter = nil
            btn.expiration = nil
            btn.duration = nil
            btn._lastTimerText = ""
            if btn.timer then
                btn.timer:SetText("")
                btn.timer:Hide()
            end
            if btn.cd then
                btn.cd:Hide()
            end
        end
    end
end

local function PaintIcon(btn, size, entry, showTimers)
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn.icon:SetTexture(entry.texture)
    btn.auraIndex = entry.index
    btn.filter = entry.filter
    btn.expiration = entry.expiration
    btn.duration = entry.duration

    local fontSize = floor(size * 0.55 + 0.5)
    if fontSize < 8 then fontSize = 8 end
    if fontSize > 14 then fontSize = 14 end
    if btn.timer then
        btn.timer:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    end
    if btn.count then
        btn.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, fontSize - 1), "OUTLINE")
    end

    if entry.count and entry.count > 1 then
        btn.count:SetText(entry.count)
        btn.count:Show()
    else
        btn.count:SetText("")
        btn.count:Hide()
    end

    if entry.isDebuff then
        local r, g, b = GetDebuffBorderColor(entry.debuffType)
        btn.border:SetVertexColor(r, g, b)
        btn.border:Show()
    else
        btn.border:Hide()
    end

    local hasDuration = entry.duration and entry.duration > 0 and entry.expiration and entry.expiration > 0
    if btn.cd then
        if hasDuration then
            btn.cd:SetCooldown(entry.expiration - entry.duration, entry.duration)
            btn.cd:Show()
        else
            btn.cd:Hide()
        end
    end

    if showTimers and hasDuration then
        UpdateIconTimer(btn, GetTime())
    elseif btn.timer then
        btn.timer:SetText("")
        btn.timer:Hide()
        btn._lastTimerText = ""
        btn.expiration = nil
    end

    btn:Show()
end

local function EnsureBuffNameLookup()
    if buffByName then
        return
    end
    buffByName = {}
    local lookup = addon.data and addon.data.partyAuraBuffById
    if not lookup then
        return
    end
    for spellId, meta in pairs(lookup) do
        local name = GetSpellInfo(spellId)
        if name then
            local key = strlower(name)
            local prev = buffByName[key]
            if not prev or meta.priority > prev.priority then
                buffByName[key] = { group = meta.group, priority = meta.priority }
            end
        end
    end
end

local function CollectBuffs(unit, cfg, out)
    wipe(scratchBuffBest)
    -- nil means default-on (existing profiles may only have { enabled = true }).
    if cfg.showClassBuffs == false then
        return out
    end
    local lookup = addon.data and addon.data.partyAuraBuffById
    if not lookup then
        return out
    end
    EnsureBuffNameLookup()

    local i = 1
    while true do
        local name, _, texture, count, _, duration, expiration, _, _, _, spellId = UnitBuff(unit, i)
        if not name then
            break
        end
        local meta = (spellId and lookup[spellId]) or nil
        if not meta and buffByName and name then
            meta = buffByName[strlower(name)]
        end
        if meta then
            local prev = scratchBuffBest[meta.group]
            if not prev or meta.priority > prev.priority then
                scratchBuffBest[meta.group] = {
                    priority = meta.priority,
                    texture = texture,
                    count = count,
                    duration = duration,
                    expiration = expiration,
                    index = i,
                    filter = "HELPFUL",
                    isDebuff = false,
                    group = meta.group,
                }
            end
        end
        i = i + 1
        if i > 40 then
            break
        end
    end

    for _, entry in pairs(scratchBuffBest) do
        out[#out + 1] = entry
    end
    table.sort(out, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)
    return out
end

local function CanDispel(debuffType, cfg)
    if not debuffType or debuffType == "" then
        return false
    end
    if cfg.showAllDispellable then
        return debuffType == "Magic"
            or debuffType == "Curse"
            or debuffType == "Disease"
            or debuffType == "Poison"
    end
    return playerDispel and playerDispel[debuffType] and true or false
end

local function EnsureImportantNameLookup()
    if importantByName then
        return
    end
    importantByName = {}
    local important = addon.data and addon.data.partyAuraImportantDebuffs
    if not important then
        return
    end
    for spellId, pri in pairs(important) do
        local name = GetSpellInfo(spellId)
        if name then
            local key = strlower(name)
            local prev = importantByName[key]
            if not prev or pri > prev then
                importantByName[key] = pri
            end
        end
    end
end

local function CollectDebuffs(unit, cfg, out)
    wipe(scratchDebuffs)
    wipe(scratchSeen)
    local showDispellable = cfg.showDispellable ~= false
    local showImportant = cfg.showImportantDebuffs ~= false
    if not showDispellable and not showImportant then
        return out
    end

    local important = addon.data and addon.data.partyAuraImportantDebuffs
    if showImportant then
        EnsureImportantNameLookup()
    end
    local i = 1
    while true do
        local name, _, texture, count, debuffType, duration, expiration, _, _, _, spellId = UnitDebuff(unit, i)
        if not name then
            break
        end

        local impPri = spellId and important and important[spellId]
        if not impPri and importantByName then
            impPri = importantByName[strlower(name)]
        end
        local isImportant = showImportant and impPri ~= nil
        local isDispellable = showDispellable and CanDispel(debuffType, cfg)

        if isImportant or isDispellable then
            local key = spellId or (name .. tostring(i))
            if not scratchSeen[key] then
                scratchSeen[key] = true
                scratchDebuffs[#scratchDebuffs + 1] = {
                    texture = texture,
                    count = count,
                    duration = duration,
                    expiration = expiration,
                    index = i,
                    filter = "HARMFUL",
                    isDebuff = true,
                    debuffType = debuffType,
                    priority = isImportant and (impPri or 1) or 0,
                }
            end
        end
        i = i + 1
        if i > 40 then
            break
        end
    end

    table.sort(scratchDebuffs, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return (a.index or 0) < (b.index or 0)
    end)

    for n = 1, #scratchDebuffs do
        out[#out + 1] = scratchDebuffs[n]
    end
    return out
end

local function PlaceHost(host, parent, anchor)
    host:ClearAllPoints()
    if anchor == "RIGHT" then
        host:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -2)
    elseif anchor == "BOTTOM" then
        host:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 2, -2)
    else
        -- LEFT default
        host:SetPoint("TOPRIGHT", parent, "TOPLEFT", -2, -2)
    end
end

local function LayoutRow(host, entries, startIconIndex, size, spacing, growLeft, y, showTimers)
    local x = 0
    local used = 0
    for n = 1, #entries do
        used = used + 1
        local btn = AcquireIcon(host, startIconIndex + used - 1)
        PaintIcon(btn, size, entries[n], showTimers)
        btn:ClearAllPoints()
        if growLeft then
            btn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -x, y)
        else
            btn:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
        end
        x = x + size + spacing
    end
    return used, x > 0 and (x - spacing) or 0
end

RefreshHost = function(index)
    local host = hosts[index]
    if not host then
        return
    end
    local unit = host.unit
    local parent = host.parentFrame
    local cfg = Cfg()
    if not cfg or not parent then
        return
    end

    if not UnitExists(unit) or not parent:IsShown() then
        host:SetScript("OnUpdate", nil)
        host:Hide()
        HideIconFrom(host, 1)
        return
    end

    local size = cfg.size or 18
    if size < 12 then size = 12 end
    if size > 32 then size = 32 end
    local spacing = cfg.spacing or 1
    if spacing < 0 then spacing = 0 end
    local maxBuffs = cfg.maxBuffs or 6
    local maxDebuffs = cfg.maxDebuffs or 4
    local anchor = cfg.anchor or "LEFT"
    local growLeft = (anchor == "LEFT")
    local showTimers = cfg.showTimers ~= false

    PlaceHost(host, parent, anchor)

    local buffs, debuffs = {}, {}
    CollectBuffs(unit, cfg, buffs)
    CollectDebuffs(unit, cfg, debuffs)

    while #buffs > maxBuffs do
        buffs[#buffs] = nil
    end
    while #debuffs > maxDebuffs do
        debuffs[#debuffs] = nil
    end

    local iconIndex = 1
    local buffW, debuffW = 0, 0
    local rowH = size
    local gap = 2
    local needsTimer = false

    if #buffs > 0 then
        local used, width = LayoutRow(host, buffs, iconIndex, size, spacing, growLeft, 0, showTimers)
        iconIndex = iconIndex + used
        buffW = width
        if showTimers then
            for n = 1, #buffs do
                if buffs[n].duration and buffs[n].duration > 0 then
                    needsTimer = true
                    break
                end
            end
        end
    end

    local debuffY = (#buffs > 0) and -(size + gap) or 0
    if #debuffs > 0 then
        local used, width = LayoutRow(host, debuffs, iconIndex, size, spacing, growLeft, debuffY, showTimers)
        iconIndex = iconIndex + used
        debuffW = width
        if showTimers and not needsTimer then
            for n = 1, #debuffs do
                if debuffs[n].duration and debuffs[n].duration > 0 then
                    needsTimer = true
                    break
                end
            end
        end
    end

    HideIconFrom(host, iconIndex)

    local width = buffW
    if debuffW > width then
        width = debuffW
    end
    local height = 0
    if #buffs > 0 then
        height = height + rowH
    end
    if #debuffs > 0 then
        if height > 0 then
            height = height + gap
        end
        height = height + rowH
    end

    if width < 1 then
        width = 1
    end
    if height < 1 then
        height = 1
    end
    host:SetWidth(width)
    host:SetHeight(height)
    host.partyIndex = index

    if #buffs > 0 or #debuffs > 0 then
        host:Show()
        if needsTimer then
            host._timerElapsed = 0
            host:SetScript("OnUpdate", HostOnUpdate)
        else
            host:SetScript("OnUpdate", nil)
        end
    else
        host:SetScript("OnUpdate", nil)
        host:Hide()
    end
end

local function RefreshAll()
    for i = 1, MAX_PARTY do
        RefreshHost(i)
    end
end

local function EnsureHosts()
    for i = 1, MAX_PARTY do
        local parent = _G["PartyMemberFrame" .. i]
        if not parent then
            -- keep going; other frames may exist
        elseif not hosts[i] then
            -- Parent to UIParent so DragonUI party restyle / clip cannot hide icons.
            local host = CreateFrame("Frame", "DragonUI_Enhanced_PartyAura" .. i, UIParent)
            host:SetFrameStrata("MEDIUM")
            host:SetFrameLevel(50)
            host.unit = "party" .. i
            host.partyIndex = i
            host.parentFrame = parent
            host.icons = {}
            host:Hide()
            for n = 1, math.min(POOL_SIZE, 6) do
                AcquireIcon(host, n)
            end
            hosts[i] = host
        else
            hosts[i].parentFrame = parent
        end
    end
end

local function DestroyHosts()
    for i = 1, MAX_PARTY do
        local host = hosts[i]
        if host then
            host:Hide()
            host:SetParent(nil)
            host:SetScript("OnEvent", nil)
            hosts[i] = nil
        end
    end
end

local function UnitToPartyIndex(unit)
    if not unit then
        return nil
    end
    local n = unit:match("^party(%d+)$")
    return n and tonumber(n) or nil
end

local function OnEvent(self, event, arg1)
    if event == "UNIT_AURA" then
        local index = UnitToPartyIndex(arg1)
        if index and index >= 1 and index <= MAX_PARTY then
            RefreshHost(index)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingLayout then
            pendingLayout = false
            RefreshAll()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PARTY_MEMBERS_CHANGED"
        or event == "PARTY_MEMBER_ENABLE"
        or event == "PARTY_MEMBER_DISABLE"
        or event == "RAID_ROSTER_UPDATE"
    then
        RefreshPlayerDispel()
        EnsureHosts()
        RefreshAll()
        return
    end
end

local function RequestRefreshAll()
    if InCombatLockdown and InCombatLockdown() then
        -- Icon paint is safe; re-anchor may still run on non-protected frames.
        -- Prefer full refresh; host is not protected.
        RefreshAll()
        return
    end
    RefreshAll()
end

local function OnEnable()
    RefreshPlayerDispel()
    EnsureHosts()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    if not addon._partyAurasUpdateHooked and type(PartyMemberFrame_UpdateMember) == "function" then
        hooksecurefunc("PartyMemberFrame_UpdateMember", function(frame)
            if not frame or not frame.GetID then
                return
            end
            local id = frame:GetID()
            if id and id >= 1 and id <= MAX_PARTY then
                EnsureHosts()
                if hosts[id] then
                    RefreshHost(id)
                end
            end
        end)
        addon._partyAurasUpdateHooked = true
    end
    RefreshAll()
    -- Party frames may finish Blizzard layout a tick later.
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(function()
            EnsureHosts()
            RefreshAll()
        end, 0.5)
    end
end

local function OnDisable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
    end
    DestroyHosts()
    pendingLayout = false
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Party Auras"]
    end,
    desc = function()
        return L["Show important class buffs and dispellable/important debuffs on party frames."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Icons appear only when present. Default anchor is left of the party frame."])

        C:AddDropdown(section, {
            label = L["Aura Anchor"],
            desc = L["Where to place aura icons relative to each party member frame."],
            values = {
                LEFT = L["Left"],
                RIGHT = L["Right"],
                BOTTOM = L["Bottom"],
            },
            getFunc = function()
                return (Cfg() and Cfg().anchor) or "LEFT"
            end,
            setFunc = function(val)
                Cfg().anchor = val
            end,
            callback = RequestRefreshAll,
            width = 180,
        })

        C:AddSlider(section, {
            label = L["Icon Size"],
            getFunc = function()
                return (Cfg() and Cfg().size) or 18
            end,
            setFunc = function(val)
                Cfg().size = val
            end,
            min = 12,
            max = 32,
            step = 1,
            width = 200,
            callback = RequestRefreshAll,
        })

        C:AddSlider(section, {
            label = L["Icon Spacing"],
            getFunc = function()
                return (Cfg() and Cfg().spacing) or 1
            end,
            setFunc = function(val)
                Cfg().spacing = val
            end,
            min = 0,
            max = 8,
            step = 1,
            width = 200,
            callback = RequestRefreshAll,
        })

        C:AddSlider(section, {
            label = L["Max Buff Icons"],
            getFunc = function()
                return (Cfg() and Cfg().maxBuffs) or 6
            end,
            setFunc = function(val)
                Cfg().maxBuffs = val
            end,
            min = 1,
            max = 8,
            step = 1,
            width = 200,
            callback = RequestRefreshAll,
        })

        C:AddSlider(section, {
            label = L["Max Debuff Icons"],
            getFunc = function()
                return (Cfg() and Cfg().maxDebuffs) or 4
            end,
            setFunc = function(val)
                Cfg().maxDebuffs = val
            end,
            min = 1,
            max = 8,
            step = 1,
            width = 200,
            callback = RequestRefreshAll,
        })

        C:AddToggle(section, {
            label = L["Show Class Buffs"],
            desc = L["Fortitude, Mark of the Wild, Thorns, Kings, Might, Intellect, Spirit (and greater/group versions)."],
            getFunc = function()
                return Cfg().showClassBuffs ~= false
            end,
            setFunc = function(val)
                Cfg().showClassBuffs = val
            end,
            callback = RequestRefreshAll,
        })

        C:AddToggle(section, {
            label = L["Show Dispellable Debuffs"],
            desc = L["Show debuffs your class can dispel (by default)."],
            getFunc = function()
                return Cfg().showDispellable ~= false
            end,
            setFunc = function(val)
                Cfg().showDispellable = val
            end,
            callback = RequestRefreshAll,
        })

        C:AddToggle(section, {
            label = L["Show All Dispellable Types"],
            desc = L["Show Magic/Curse/Disease/Poison even if you cannot dispel them."],
            getFunc = function()
                return Cfg().showAllDispellable == true
            end,
            setFunc = function(val)
                Cfg().showAllDispellable = val
            end,
            callback = RequestRefreshAll,
        })

        C:AddToggle(section, {
            label = L["Show Important Debuffs"],
            desc = L["Boss/callout debuffs from the built-in priority list."],
            getFunc = function()
                return Cfg().showImportantDebuffs ~= false
            end,
            setFunc = function(val)
                Cfg().showImportantDebuffs = val
            end,
            callback = RequestRefreshAll,
        })

        C:AddToggle(section, {
            label = L["Show Aura Timers"],
            desc = L["Show remaining time on icons as 5m / 12s. Hidden for permanent auras."],
            getFunc = function()
                return Cfg().showTimers ~= false
            end,
            setFunc = function(val)
                Cfg().showTimers = val
            end,
            callback = RequestRefreshAll,
        })
    end,
})

addon.PartyAuras = {
    Refresh = RequestRefreshAll,
    RefreshHost = RefreshHost,
}
