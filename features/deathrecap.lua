-- DragonUI_Enhanced — death recap and a manual release-spirit dialog.
-- WotLK has no Blizzard recap. Recent damage is taken from the combat log.
-- The Blizzard DEATH popup is closed, and RepopMe is ignored until the player
-- clicks Release on this dialog, so an auto-confirm cannot release the spirit.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "deathRecap"
local MAX_HITS = 5
local MAX_DEATHS = 30
local HIT_GAP = 10
local LINK_PREFIX = "duideath:"

local active = false
local blockRepop = false
local releaseAllowed = false
local hooksReady = false

local eventList = {}
local deathList = {}
local lastRecapID

local releaseFrame
local recapFrame
local eventFrame

local function CopyRecord(src)
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            local inner = {}
            for ik, iv in pairs(v) do
                inner[ik] = iv
            end
            copy[k] = inner
        else
            copy[k] = v
        end
    end
    return copy
end

local function Wipe(t)
    if wipe then
        wipe(t)
    else
        for k in pairs(t) do
            t[k] = nil
        end
    end
end

local function MakeButton(parent, text, width)
    local FUI = addon.theme:GetForeverUI()
    local button
    if FUI and FUI.CreateButton then
        button = FUI.CreateButton(parent, text, width, 22)
    else
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(text)
    end
    return button
end

local function SkinPanel(frame, title, closable)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local skinned = addon.theme:SkinDialog(frame, {
        title = title,
        closable = closable,
        movable = true,
        strata = "FULLSCREEN_DIALOG",
    })
    if not skinned then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", 0, -16)
        titleText:SetText(title or "")
        frame.TitleText = titleText
        frame.SetTitle = function(self, value)
            self.TitleText:SetText(value or "")
        end
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    end
end

local function HideForeignDeathPopups()
    if StaticPopup_Hide then
        StaticPopup_Hide("DEATH")
    end
    for i = 1, 4 do
        local popup = _G["ElvUI_StaticPopup" .. i]
        if popup and popup.which == "DEATH" and popup.IsShown and popup:IsShown() then
            popup:Hide()
        end
    end
end

local function FallingLocked()
    if type(IsFalling) ~= "function" or not IsFalling() then
        return false
    end
    if type(IsOutOfBounds) == "function" and IsOutOfBounds() then
        return false
    end
    return true
end

local function HasRecap()
    return lastRecapID and deathList[lastRecapID] and true or false
end

local function AddEvent(entry)
    local previous = eventList[#eventList]
    if previous and entry.timestamp and previous.timestamp and (entry.timestamp - previous.timestamp) > HIT_GAP then
        Wipe(eventList)
    end
    eventList[#eventList + 1] = entry
    while #eventList > MAX_HITS do
        table.remove(eventList, 1)
    end
end

local function AddDeath()
    if #eventList == 0 then
        lastRecapID = nil
        return false
    end
    local copy = {}
    for i = 1, #eventList do
        copy[i] = CopyRecord(eventList[i])
    end
    Wipe(eventList)
    if #deathList >= MAX_DEATHS then
        table.remove(deathList, 1)
    end
    deathList[#deathList + 1] = copy
    lastRecapID = #deathList
    local message = string.format("|cff71d5ff|H%s%d|h[%s]|h|r", LINK_PREFIX, lastRecapID, L["You died."])
    DEFAULT_CHAT_FRAME:AddMessage(message)
    return true
end

local function SpellVisual(data)
    local spellId = data.spellId
    local spellName = data.spellName
    local texture = data.texture

    if data.event == "SWING_DAMAGE" then
        spellId = 6603
        spellName = ACTION_SWING or L["Melee"]
    elseif data.event == "ENVIRONMENTAL_DAMAGE" then
        local kind = string.upper(data.environmentalType or "")
        spellName = _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. kind] or data.environmentalType or L["Environment"]
        local icon = "ability_creature_cursed_05"
        if kind == "DROWNING" then
            icon = "spell_shadow_demonbreath"
        elseif kind == "FALLING" then
            icon = "ability_rogue_quickrecovery"
        elseif kind == "FIRE" or kind == "LAVA" then
            icon = "spell_fire_fire"
        elseif kind == "SLIME" then
            icon = "inv_misc_slime_01"
        end
        texture = "Interface\\Icons\\" .. icon
    end

    if spellId and not texture and GetSpellInfo then
        texture = select(3, GetSpellInfo(spellId))
    end
    if not texture then
        texture = "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return spellId, spellName or UNKNOWN, texture
end

local function EnsureRecap()
    if recapFrame then
        return recapFrame
    end

    local frame = CreateFrame("Frame", "DragonUI_DeathRecap", UIParent)
    frame:SetSize(420, 292)
    frame:SetPoint("CENTER", 0, 40)
    frame:Hide()
    SkinPanel(frame, L["Death Recap"], true)
    if frame:GetName() then
        tinsert(UISpecialFrames, frame:GetName())
    end
    frame:SetScript("OnHide", function(self)
        self.recapID = nil
    end)

    frame.Unavailable = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Unavailable:SetPoint("CENTER", 0, 10)
    frame.Unavailable:SetText(L["Death Recap unavailable."])
    addon.theme:ApplyFont(frame.Unavailable, 13)

    frame.Rows = {}
    for i = 1, MAX_HITS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(380, 36)
        if i == 1 then
            row:SetPoint("TOPLEFT", 20, -46)
        else
            row:SetPoint("TOPLEFT", frame.Rows[i - 1], "BOTTOMLEFT", 0, -6)
        end
        frame.Rows[i] = row

        row.Amount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.Amount:SetPoint("LEFT", 18, 0)
        row.Amount:SetWidth(72)
        row.Amount:SetJustifyH("RIGHT")
        row.Amount:SetTextColor(1, 0.15, 0.15)
        addon.theme:ApplyFont(row.Amount, 13)

        row.Skull = row:CreateTexture(nil, "ARTWORK")
        row.Skull:SetSize(16, 16)
        row.Skull:SetPoint("RIGHT", row.Amount, "LEFT", -2, 0)
        row.Skull:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
        row.Skull:Hide()

        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(32, 32)
        row.Icon:SetPoint("LEFT", row.Amount, "RIGHT", 12, 0)
        row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.IconBorder = row:CreateTexture(nil, "BACKGROUND")
        row.IconBorder:SetPoint("TOPLEFT", row.Icon, "TOPLEFT", -1, 1)
        row.IconBorder:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 1, -1)
        row.IconBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.IconBorder:SetVertexColor(0, 0, 0, 0.9)

        row.Hit = CreateFrame("Button", nil, row)
        row.Hit:SetPoint("TOPLEFT", row.Icon, "TOPLEFT", -2, 2)
        row.Hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.Hit:SetScript("OnLeave", GameTooltip_Hide)
        row.Hit:SetScript("OnEnter", function(self)
            if self.spellId and GetSpellLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(GetSpellLink(self.spellId))
                GameTooltip:Show()
            end
        end)

        row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -1)
        row.Name:SetPoint("RIGHT", -4, 0)
        row.Name:SetJustifyH("LEFT")
        addon.theme:ApplyFont(row.Name, 12)

        row.Caster = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.Caster:SetPoint("BOTTOMLEFT", row.Icon, "BOTTOMRIGHT", 8, 1)
        row.Caster:SetPoint("RIGHT", -4, 0)
        row.Caster:SetJustifyH("LEFT")
        row.Caster:SetTextColor(0.7, 0.7, 0.7)
        addon.theme:ApplyFont(row.Caster, 11)

        row.AmountHit = CreateFrame("Button", nil, row)
        row.AmountHit:SetPoint("TOPLEFT", row.Skull, "TOPLEFT", 0, 0)
        row.AmountHit:SetPoint("BOTTOMRIGHT", row.Amount, "BOTTOMRIGHT", 0, 0)
        row.AmountHit:SetScript("OnLeave", GameTooltip_Hide)
        row.AmountHit:SetScript("OnEnter", function(self)
            local info = self.info
            if not info then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            if info.amount then
                local school = info.school and CombatLog_String_SchoolString and CombatLog_String_SchoolString(info.school)
                local value = school and string.format("%d %s", info.amount, school) or tostring(info.amount)
                GameTooltip:AddLine(value .. (info.extra or ""), 1, 0.2, 0.2)
            end
            if info.spellName then
                if info.caster then
                    GameTooltip:AddLine(string.format(L["%s by %s"], info.spellName, info.caster), 1, 1, 1, true)
                else
                    GameTooltip:AddLine(info.spellName, 1, 1, 1, true)
                end
            end
            if info.seconds and info.seconds > 0 then
                GameTooltip:AddLine(string.format(L["%s sec before death at %s%% health."], string.format("%.1f", info.seconds), info.hpPercent or 0), 1, 0.82, 0, true)
            else
                GameTooltip:AddLine(string.format(L["Killing blow at %s%% health."], info.hpPercent or 0), 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        end)
    end

    recapFrame = frame
    return frame
end

local function OpenRecap(recapID)
    recapID = tonumber(recapID)
    local events = recapID and deathList[recapID]
    if not events then
        return
    end

    local frame = EnsureRecap()
    if frame:IsShown() and frame.recapID == recapID then
        frame:Hide()
        return
    end

    local ordered = {}
    for i = 1, #events do
        ordered[i] = events[i]
    end
    table.sort(ordered, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    frame.recapID = recapID
    frame.Unavailable:Hide()

    local deathTime = ordered[1] and ordered[1].timestamp
    local topAmount, topIndex = 0, 1

    for i = 1, MAX_HITS do
        local row = frame.Rows[i]
        local data = ordered[i]
        if not data then
            row:Hide()
        else
            local spellId, spellName, texture = SpellVisual(data)
            local amount = tonumber(data.amount) or 0
            local extra = ""
            local shown = amount
            if data.overkill and data.overkill > 0 then
                extra = extra .. " " .. string.format(L["(%d Overkill)"], data.overkill)
                shown = shown - data.overkill
            end
            if data.absorbed and data.absorbed > 0 then
                extra = extra .. " " .. string.format(L["(%d Absorbed)"], data.absorbed)
                shown = shown - data.absorbed
            end
            if data.resisted and data.resisted > 0 then
                extra = extra .. " " .. string.format(L["(%d Resisted)"], data.resisted)
                shown = shown - data.resisted
            end
            if data.blocked and data.blocked > 0 then
                extra = extra .. " " .. string.format(L["(%d Blocked)"], data.blocked)
                shown = shown - data.blocked
            end
            if shown < 0 then
                shown = 0
            end

            row.Amount:SetText(amount > 0 and ("-" .. amount) or "")
            addon.theme:ApplyFont(row.Amount, 13)
            row.Amount:SetTextColor(0.9, 0.15, 0.15)
            if amount > topAmount then
                topAmount = amount
                topIndex = i
            end

            row.Icon:SetTexture(texture)
            if data.school and data.school > 1 and CombatLog_Color_ColorArrayBySchool then
                local color = CombatLog_Color_ColorArrayBySchool(data.school)
                if color then
                    row.IconBorder:SetVertexColor(color.r, color.g, color.b, 1)
                end
            else
                row.IconBorder:SetVertexColor(0, 0, 0, 0.85)
            end

            row.Name:SetText(spellName)
            local caster = data.sourceName or COMBATLOG_UNKNOWN_UNIT
            row.Caster:SetText(caster or "")
            row.Hit.spellId = spellId

            local hp = 0
            if data.maxHP and data.maxHP > 0 then
                hp = math.floor((data.currentHP or 0) / data.maxHP * 100 + 0.5)
            end
            local seconds = 0
            if deathTime and data.timestamp then
                seconds = deathTime - data.timestamp
            end
            row.AmountHit.info = {
                amount = shown,
                extra = extra,
                school = data.school,
                spellName = spellName,
                caster = caster,
                seconds = seconds,
                hpPercent = hp,
            }
            if i == 1 then
                row.Skull:Show()
            else
                row.Skull:Hide()
            end
            row:Show()
        end
    end

    local top = frame.Rows[topIndex]
    if top and top:IsShown() and topAmount > 0 then
        addon.theme:ApplyFont(top.Amount, 16)
        top.Amount:SetTextColor(1, 0.07, 0.07)
    end

    frame:SetFrameLevel(80)
    frame:Show()
end

local function RefreshRelease()
    local frame = releaseFrame
    if not frame or not frame:IsShown() then
        return
    end

    local falling = FallingLocked()
    if falling then
        frame.Release:Disable()
        frame.Soulstone:Disable()
    else
        frame.Release:Enable()
        if type(HasSoulstone) == "function" and HasSoulstone() then
            frame.Soulstone:Enable()
            frame.Soulstone:SetText(HasSoulstone())
        else
            frame.Soulstone:Disable()
            frame.Soulstone:SetText(USE_SOULSTONE or L["Use Soulstone"])
        end
    end

    if HasRecap() then
        frame.Recap:Enable()
    else
        frame.Recap:Disable()
    end

    local arena = type(IsActiveBattlefieldArena) == "function" and IsActiveBattlefieldArena()
    if arena and DEATH_RELEASE_SPECTATOR then
        frame.Body:SetText(DEATH_RELEASE_SPECTATOR)
        return
    end

    local remain
    if frame.deadline then
        remain = frame.deadline - GetTime()
    end
    if not remain or remain <= 0 then
        frame.Body:SetText(DEATH_RELEASE_NOTIMER or L["You died."])
        return
    end
    local count, unit
    if remain < 60 then
        count = math.max(1, math.floor(remain + 0.5))
        unit = SECONDS or ""
    else
        count = math.ceil(remain / 60)
        unit = MINUTES or ""
    end
    if DEATH_RELEASE_TIMER then
        frame.Body:SetFormattedText(DEATH_RELEASE_TIMER, count, unit)
    else
        frame.Body:SetFormattedText(L["Release in %d %s"], count, unit)
    end
end

local function ShowRelease()
    if not active then
        return
    end
    HideForeignDeathPopups()

    if not releaseFrame then
        local frame = CreateFrame("Frame", "DragonUI_DeathRelease", UIParent)
        frame:SetSize(460, 168)
        frame:SetPoint("CENTER", 0, 120)
        frame:Hide()
        SkinPanel(frame, DEATH_RELEASE or L["Release Spirit"], false)

        frame.Body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.Body:SetPoint("TOP", 0, -48)
        frame.Body:SetWidth(400)
        frame.Body:SetJustifyH("CENTER")
        addon.theme:ApplyFont(frame.Body, 13)

        frame.Release = MakeButton(frame, DEATH_RELEASE or L["Release Spirit"], 120)
        frame.Release:SetPoint("BOTTOM", -136, 22)
        frame.Release:SetScript("OnClick", function()
            if FallingLocked() then
                return
            end
            if type(IsActiveBattlefieldArena) == "function" and IsActiveBattlefieldArena() and ARENA_SPECTATOR then
                local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
                if info then
                    DEFAULT_CHAT_FRAME:AddMessage(ARENA_SPECTATOR, info.r, info.g, info.b, info.id)
                end
            end
            releaseAllowed = true
            RepopMe()
        end)

        frame.Soulstone = MakeButton(frame, USE_SOULSTONE or L["Use Soulstone"], 120)
        frame.Soulstone:SetPoint("BOTTOM", 0, 22)
        frame.Soulstone:SetScript("OnClick", function()
            if FallingLocked() then
                return
            end
            if type(HasSoulstone) == "function" and HasSoulstone() and UseSoulstone then
                blockRepop = false
                frame:Hide()
                UseSoulstone()
            end
        end)

        frame.Recap = MakeButton(frame, L["Death Recap"], 120)
        frame.Recap:SetPoint("BOTTOM", 136, 22)
        frame.Recap:SetScript("OnClick", function()
            if HasRecap() then
                OpenRecap(lastRecapID)
            end
        end)

        releaseFrame = frame
    end

    if not releaseFrame:IsShown() then
        local remain = type(GetReleaseTimeRemaining) == "function" and GetReleaseTimeRemaining() or -1
        if remain and remain > 0 then
            releaseFrame.deadline = GetTime() + remain
        else
            releaseFrame.deadline = nil
        end
        releaseFrame:Show()
    end
    RefreshRelease()
end

local function ClearDeathState()
    blockRepop = false
    releaseAllowed = false
    if releaseFrame then
        releaseFrame:Hide()
    end
end

local function OnCombatLog(timestamp, event, _, sourceName, sourceFlags, _, _, destFlags, ...)
    if bit.band(destFlags or 0, COMBATLOG_FILTER_ME) ~= COMBATLOG_FILTER_ME then
        return
    end
    if sourceFlags and bit.band(sourceFlags, COMBATLOG_FILTER_ME) == COMBATLOG_FILTER_ME and event ~= "ENVIRONMENTAL_DAMAGE" then
        return
    end

    local spellId, spellName, environmentalType, amount, overkill, school, resisted, blocked, absorbed
    if event == "SWING_DAMAGE" then
        amount, overkill, school, resisted, blocked, absorbed = ...
    elseif event == "RANGE_DAMAGE" or event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "SPELL_BUILDING_DAMAGE" then
        spellId, spellName, _, amount, overkill, school, resisted, blocked, absorbed = ...
    elseif event == "ENVIRONMENTAL_DAMAGE" then
        environmentalType, amount, overkill, school, resisted, blocked, absorbed = ...
    elseif event == "SPELL_INSTAKILL" then
        spellId, spellName = ...
        amount = UnitHealth("player")
        if not amount or amount <= 0 then
            amount = UnitHealthMax("player")
        end
    else
        return
    end

    amount = tonumber(amount)
    if not amount then
        return
    end

    AddEvent({
        timestamp = timestamp,
        event = event,
        sourceName = sourceName,
        spellId = spellId,
        spellName = spellName,
        environmentalType = environmentalType,
        amount = amount,
        overkill = tonumber(overkill),
        school = school,
        resisted = tonumber(resisted),
        blocked = tonumber(blocked),
        absorbed = tonumber(absorbed),
        currentHP = UnitHealth("player") or 0,
        maxHP = UnitHealthMax("player") or 1,
    })
end

local function OnLink(link)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then
        return
    end
    if not active then
        return
    end
    OpenRecap(link:sub(#LINK_PREFIX + 1))
end

local function InstallHooks()
    if hooksReady then
        return
    end
    hooksReady = true

    if type(RepopMe) == "function" then
        local blizzRepop = RepopMe
        RepopMe = function(...)
            if active and blockRepop and not releaseAllowed then
                ShowRelease()
                return
            end
            releaseAllowed = false
            blizzRepop(...)
            if UnitIsGhost("player") or not UnitIsDeadOrGhost("player") then
                blockRepop = false
                if releaseFrame then
                    releaseFrame:Hide()
                end
            end
        end
    end

    local deathDialog = StaticPopupDialogs and StaticPopupDialogs.DEATH
    if deathDialog and not deathDialog._duiDeathWrapped then
        local origShow = deathDialog.OnShow
        local origAccept = deathDialog.OnAccept
        local origCancel = deathDialog.OnCancel
        deathDialog.OnShow = function(self, ...)
            if not active then
                if origShow then
                    return origShow(self, ...)
                end
                return
            end
            ShowRelease()
            if self.Hide then
                self:Hide()
            end
        end
        deathDialog.OnAccept = function(self, ...)
            if not active then
                if origAccept then
                    return origAccept(self, ...)
                end
                return
            end
            if releaseAllowed then
                releaseAllowed = false
                if origAccept then
                    return origAccept(self, ...)
                end
                return
            end
            ShowRelease()
            if self.Hide then
                self:Hide()
            end
            return 1
        end
        deathDialog.OnCancel = function(self, data, reason)
            if not active then
                if origCancel then
                    return origCancel(self, data, reason)
                end
                return
            end
            if reason == "clicked" then
                ShowRelease()
                if self.Hide then
                    self:Hide()
                end
                return 1
            end
            if origCancel then
                return origCancel(self, data, reason)
            end
        end
        deathDialog._duiDeathWrapped = true
    end

    hooksecurefunc("SetItemRef", OnLink)
end

local function OnEvent(_, event, ...)
    if not active then
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog(...)
        return
    end
    if event == "PLAYER_DEAD" then
        blockRepop = true
        AddDeath()
        ShowRelease()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if UnitIsGhost("player") or not UnitIsDeadOrGhost("player") then
            ClearDeathState()
        elseif UnitIsDead("player") then
            blockRepop = true
            ShowRelease()
        end
        return
    end
    ClearDeathState()
end

local function OnEnable()
    active = true
    InstallHooks()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
        eventFrame:SetScript("OnUpdate", function(_, elapsed)
            if not active then
                return
            end
            eventFrame.elapsed = (eventFrame.elapsed or 0) + elapsed
            if eventFrame.elapsed < 0.2 then
                return
            end
            eventFrame.elapsed = 0
            if blockRepop then
                HideForeignDeathPopups()
            end
            RefreshRelease()
        end)
    end
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    eventFrame:RegisterEvent("RESURRECT_REQUEST")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("RAISED_AS_GHOUL")
    if UnitIsDead("player") and not UnitIsGhost("player") then
        blockRepop = true
        ShowRelease()
    end
end

local function OnDisable()
    active = false
    ClearDeathState()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if recapFrame then
        recapFrame:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Death Recap"]
    end,
    desc = function()
        return L["Replace the release-spirit popup so it is not auto-confirmed, and show the last hits that killed you."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
