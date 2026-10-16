-- DragonUI_Enhanced — party frame buff icons (all helpful auras).
-- Debuffs stay on Blizzard/DragonUI PartyMemberFrameNDebuff*. Mounts on PartyMemberFrame1-4.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "partyauras"
local MAX_PARTY = 4
local MAX_NATIVE_BUFFS = 4
local POOL_SIZE = 20
local TIMER_FONT_SIZE = 11
-- Reserved space below each icon row so duration text does not sit inside the icon.
local TIMER_BELOW_PAD = 12

local UnitExists = UnitExists
local UnitBuff = UnitBuff
local GetTime = GetTime
local CreateFrame = CreateFrame
local pairs = pairs
local wipe = wipe
local ceil = math.ceil
local format = string.format
local hooksecurefunc = hooksecurefunc

local eventFrame
local hosts = {} -- [index] = host
local pendingLayout = false
local nativeBuffSuppress = false
local nativeBuffHooked = {}

local scratchBuffs = {}

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
    border:Hide()
    btn.border = border

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 0)
    btn.count = count

    local timer = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    timer:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    timer:SetJustifyH("CENTER")
    timer:SetShadowOffset(1, -1)
    timer:Hide()
    btn.timer = timer
    btn._lastTimerText = ""

    btn:SetScript("OnEnter", function(self)
        if not self.auraIndex then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetUnitBuff(host.unit, self.auraIndex)
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
        end
    end
end

local function PaintIcon(btn, size, entry, showTimers)
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn.icon:SetTexture(entry.texture)
    btn.auraIndex = entry.index
    btn.filter = "HELPFUL"
    btn.expiration = entry.expiration
    btn.duration = entry.duration

    if btn.timer then
        btn.timer:ClearAllPoints()
        btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -1)
        btn.timer:SetFont("Fonts\\FRIZQT__.TTF", TIMER_FONT_SIZE, "OUTLINE")
    end
    if btn.count then
        btn.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, TIMER_FONT_SIZE - 1), "OUTLINE")
    end

    if entry.count and entry.count > 1 then
        btn.count:SetText(entry.count)
        btn.count:Show()
    else
        btn.count:SetText("")
        btn.count:Hide()
    end

    if btn.border then
        btn.border:Hide()
    end

    -- No cooldown swipe; duration is shown as text below the icon only.
    if btn.cd then
        btn.cd:Hide()
    end

    local hasDuration = entry.duration and entry.duration > 0 and entry.expiration and entry.expiration > 0
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

-- All helpful auras in UnitBuff order (buffkeyword wrap already filters junk on party).
local function CollectBuffs(unit, maxBuffs, out)
    wipe(scratchBuffs)
    local i = 1
    while #scratchBuffs < maxBuffs do
        local name, _, texture, count, _, duration, expiration = UnitBuff(unit, i)
        if not name then
            break
        end
        scratchBuffs[#scratchBuffs + 1] = {
            texture = texture,
            count = count,
            duration = duration,
            expiration = expiration,
            index = i,
        }
        i = i + 1
        if i > 40 then
            break
        end
    end
    for n = 1, #scratchBuffs do
        out[#out + 1] = scratchBuffs[n]
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

-- Layout entries[fromIndex..toIndex] as one horizontal row. Returns used count and row width.
local function LayoutRow(host, entries, fromIndex, toIndex, startIconIndex, size, spacing, growLeft, y, showTimers)
    local x = 0
    local used = 0
    for n = fromIndex, toIndex do
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

local function SuppressNativeBuffButton(btn)
    if not btn then
        return
    end
    if not nativeBuffHooked[btn] then
        hooksecurefunc(btn, "Show", function(self)
            if nativeBuffSuppress then
                self:Hide()
            end
        end)
        nativeBuffHooked[btn] = true
    end
    btn:Hide()
end

local function ApplyNativeBuffSuppress()
    for i = 1, MAX_PARTY do
        for auraIndex = 1, MAX_NATIVE_BUFFS do
            SuppressNativeBuffButton(_G["PartyMemberFrame" .. i .. "Buff" .. auraIndex])
        end
    end
end

local function SetNativeBuffSuppress(enabled)
    nativeBuffSuppress = enabled and true or false
    if nativeBuffSuppress then
        ApplyNativeBuffSuppress()
    end
    -- When disabled, leave icons alone; Blizzard/DragonUI will Show them on the next aura update.
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

    if nativeBuffSuppress then
        ApplyNativeBuffSuppress()
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
    local maxBuffs = cfg.maxBuffs or 8
    if maxBuffs < 1 then maxBuffs = 1 end
    if maxBuffs > POOL_SIZE then maxBuffs = POOL_SIZE end
    local rows = tonumber(cfg.rows) or 2
    if rows < 1 then rows = 1 end
    if rows > 2 then rows = 2 end
    local anchor = cfg.anchor or "LEFT"
    local growLeft = (anchor == "LEFT")
    local showTimers = cfg.showTimers ~= false

    PlaceHost(host, parent, anchor)

    local buffs = {}
    CollectBuffs(unit, maxBuffs, buffs)

    local iconIndex = 1
    local buffW = 0
    local rowH = size
    local rowGap = 2
    local timerPad = showTimers and TIMER_BELOW_PAD or 0
    local rowStride = rowH + timerPad + rowGap
    local needsTimer = false
    local usedRows = 0

    if #buffs > 0 then
        -- Fill row 1 first (capacity = ceil(maxBuffs / rows)); overflow goes to later rows.
        local perRow = maxBuffs
        if rows > 1 then
            perRow = ceil(maxBuffs / rows)
        end
        local from = 1
        while from <= #buffs do
            local to = from + perRow - 1
            if to > #buffs then
                to = #buffs
            end
            usedRows = usedRows + 1
            local y = -(usedRows - 1) * rowStride
            local used, width = LayoutRow(host, buffs, from, to, iconIndex, size, spacing, growLeft, y, showTimers)
            iconIndex = iconIndex + used
            if width > buffW then
                buffW = width
            end
            from = to + 1
            if usedRows >= rows then
                break
            end
        end
        if showTimers then
            for n = 1, #buffs do
                if buffs[n].duration and buffs[n].duration > 0 then
                    needsTimer = true
                    break
                end
            end
        end
    end

    HideIconFrom(host, iconIndex)

    local width = buffW
    local height = 0
    if usedRows > 0 then
        height = usedRows * (rowH + timerPad) + (usedRows - 1) * rowGap
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

    if #buffs > 0 then
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
            for n = 1, math.min(POOL_SIZE, 8) do
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
        EnsureHosts()
        if nativeBuffSuppress then
            ApplyNativeBuffSuppress()
        end
        RefreshAll()
        return
    end
end

local function RequestRefreshAll()
    RefreshAll()
end

local function OnEnable()
    EnsureHosts()
    SetNativeBuffSuppress(true)
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
                if nativeBuffSuppress then
                    ApplyNativeBuffSuppress()
                end
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
            SetNativeBuffSuppress(true)
            RefreshAll()
        end, 0.5)
    end
end

local function OnDisable()
    SetNativeBuffSuppress(false)
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
    end
    DestroyHosts()
    pendingLayout = false
    -- Nudge Blizzard to re-show native buffs if units still exist.
    if type(PartyMemberFrame_UpdateMember) == "function" then
        for i = 1, MAX_PARTY do
            local frame = _G["PartyMemberFrame" .. i]
            if frame and UnitExists("party" .. i) then
                PartyMemberFrame_UpdateMember(frame)
            end
        end
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Party Auras"]
    end,
    desc = function()
        return L["Show all party member buffs on the party frames. Hides the default party buff icons. Debuffs stay on the Blizzard/DragonUI frames."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Shows every helpful aura (junk keywords still filtered). Default anchor is left of the party frame; native buff icons are hidden while enabled."])

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
                return (Cfg() and Cfg().maxBuffs) or 8
            end,
            setFunc = function(val)
                Cfg().maxBuffs = val
            end,
            min = 1,
            max = 20,
            step = 1,
            width = 200,
            callback = RequestRefreshAll,
        })

        C:AddSlider(section, {
            label = L["Buff Rows"],
            desc = L["Layout buff icons in one or two rows."],
            getFunc = function()
                return (Cfg() and Cfg().rows) or 2
            end,
            setFunc = function(val)
                Cfg().rows = val
            end,
            min = 1,
            max = 2,
            step = 1,
            width = 200,
            callback = RequestRefreshAll,
        })

        C:AddToggle(section, {
            label = L["Show Aura Timers"],
            desc = L["Show remaining time below icons as 5m / 12s. Hidden for permanent auras."],
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
