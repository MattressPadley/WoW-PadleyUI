local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local NameplateSkin = {}
ns.NameplateSkin = NameplateSkin

-- External tracking tables (never write keys to Blizzard frames)
local skinnedFrames = {}
local hookedBars = {}
local nameOverlays = {}  -- keyed by UnitFrame → our custom FontString
local focusOverlays = {} -- keyed by UnitFrame → diagonal stripe Texture
local targetArrows = {}  -- keyed by UnitFrame → { left, right }
local questIndicators = {} -- keyed by UnitFrame → FontString
local hoverBorders = {}   -- keyed by UnitFrame → backdrop Frame
local kickOverlays = {}   -- keyed by UnitFrame → { frame, bar, icon, text, timer }

-- Custom bars overlaid on Blizzard's (alpha-zeroed) bars
local customHealthBars = {}   -- Blizzard healthBar → our StatusBar
local customCastBars = {}     -- UnitFrame → { bar, icon, text, startTime, endTime, channel }
local blizzardHealthColors = {} -- Blizzard healthBar → { r, g, b } (cached reaction color)
local absorbBars = {}            -- UnitFrame → our absorb StatusBar
local healCalcs = {}             -- UnitFrame → per-instance calculator

-- Threat color tables
-- nil = no override, use Blizzard's default reaction color
local NOCOMBAT_COLOR = { 0.06, 0.59, 0.90 }  -- blue — hostile but not in combat
local THREAT_DPS = {
    [0] = { 0.0, 1.0, 0.0 },             -- no aggro: green (good for DPS)
    [1] = { 1.0, 0.7, 0.0 },             -- pulling threat: orange
    [2] = { 1.0, 1.0, 0.0 },             -- tanking insecure: yellow
    [3] = { 1.0, 0.0, 0.0 },             -- has aggro: red (bad for DPS/healer)
}
local THREAT_TANK = {
    [0] = { 1.0, 0.0, 0.0 },             -- no aggro: red (bad for tank)
    [1] = { 1.0, 0.7, 0.0 },             -- losing aggro: orange
    [2] = { 1.0, 1.0, 0.0 },             -- tanking insecure: yellow
    [3] = { 0.0, 1.0, 0.0 },             -- securely tanking: green (good for tanks)
}

-- Hidden tooltip for scanning quest objectives on nameplate units
local scanTip = CreateFrame("GameTooltip", "PadleyUIScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local KICK_DISPLAY_DURATION = 2  -- seconds to show "Kicked: Name"
local KICK_BAR_COLOR = { 0.7, 0.0, 0.0 }  -- dark red for interrupted bar

local QUESTION_MARK = 134400  -- INV_Misc_QuestionMark, neutral placeholder

local threatOverrides = {}  -- unitFrame → { r, g, b } or nil

local function GetThreatColor(unit)
    local status = UnitThreatSituation("player", unit)
    if status == nil then return nil end  -- not on threat table (e.g. neutral/unpulled)
    local spec = GetSpecialization()
    local isTank = spec and GetSpecializationRole(spec) == "TANK"
    local colors = isTank and THREAT_TANK or THREAT_DPS
    return colors[status]
end

local function UpdateThreatColor(unitFrame)
    local unit = unitFrame.unit
    if not unit or not UnitExists(unit) or not UnitCanAttack("player", unit) then
        threatOverrides[unitFrame] = nil
        -- Restore Blizzard's reaction color on our custom bar
        local custom = customHealthBars[unitFrame.healthBar]
        local bc = blizzardHealthColors[unitFrame.healthBar]
        if custom and bc then
            custom:SetStatusBarColor(bc[1], bc[2], bc[3])
        end
        return
    end

    if not UnitAffectingCombat(unit) then
        local reaction = UnitReaction(unit, "player")
        threatOverrides[unitFrame] = (reaction and reaction < 4) and NOCOMBAT_COLOR or nil
    else
        threatOverrides[unitFrame] = GetThreatColor(unit)
    end

    local color = threatOverrides[unitFrame]
    local custom = customHealthBars[unitFrame.healthBar]
    if custom then
        if color then
            custom:SetStatusBarColor(color[1], color[2], color[3])
        else
            local bc = blizzardHealthColors[unitFrame.healthBar]
            if bc then
                custom:SetStatusBarColor(bc[1], bc[2], bc[3])
            end
        end
    end
end

local NAMEPLATE_FONT_SIZE = C.FONT_SIZE + 2

local function StyleFontString(fs)
    if not fs or not fs.SetFont then return end
    SE:StyleFont(fs, NAMEPLATE_FONT_SIZE, "")
    fs:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    fs:SetShadowColor(unpack(C.SHADOW_COLOR))
end

local function HideCustomCastBar(unitFrame)
    local custom = customCastBars[unitFrame]
    if not custom then return end
    custom.container:Hide()
end

local function ShowCustomCastBar(unitFrame, spellID, isChannelKnown)
    local custom = customCastBars[unitFrame]
    if not custom or not unitFrame.unit then return end
    local unit = unitFrame.unit

    -- Get non-secret spell info from spellID (event args) when available
    local spellName, spellIcon
    if spellID then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            spellName = info.name
            spellIcon = info.iconID
        end
    end

    -- Determine cast type, get duration object and metadata
    local notInterruptible
    local isChannel
    local castDuration

    if isChannelKnown == true then
        isChannel = true
        castDuration = UnitChannelDuration(unit)
        local n, _, t, _, _, _, ni = UnitChannelInfo(unit)
        notInterruptible = ni
        if not spellName then spellName = n end
        if not spellIcon then spellIcon = t end
    elseif isChannelKnown == false then
        isChannel = false
        castDuration = UnitCastingDuration(unit)
        local n, _, t, _, _, _, _, ni = UnitCastingInfo(unit)
        notInterruptible = ni
        if not spellName then spellName = n end
        if not spellIcon then spellIcon = t end
    else
        -- RefreshNamePlate path: detect cast type
        castDuration = UnitCastingDuration(unit)
        if castDuration then
            isChannel = false
            local cn, _, ct, _, _, _, _, cni = UnitCastingInfo(unit)
            notInterruptible = cni
            if not spellName then spellName = cn end
            if not spellIcon then spellIcon = ct end
        else
            castDuration = UnitChannelDuration(unit)
            if castDuration then
                isChannel = true
                local hn, _, ht, _, _, _, hni = UnitChannelInfo(unit)
                notInterruptible = hni
                if not spellName then spellName = hn end
                if not spellIcon then spellIcon = ht end
            else
                HideCustomCastBar(unitFrame)
                return
            end
        end
    end

    if not castDuration then
        HideCustomCastBar(unitFrame)
        return
    end

    -- spellIcon is a plain fileID on the common GetSpellInfo(spellID) path, but
    -- the UnitCastingInfo/UnitChannelInfo fallback can be secret on a restricted
    -- unit. SetTexture(secret) silently renders a white box, so swap to a neutral
    -- placeholder. (This icon is also read back via GetTexture() for the kick
    -- overlay, so guarding here keeps that path non-secret too.)
    if custom.icon then
        if issecretvalue and issecretvalue(spellIcon) then
            custom.icon:SetTexture(QUESTION_MARK)
        else
            custom.icon:SetTexture(spellIcon)
        end
    end
    if custom.text and spellName then custom.text:SetText(spellName) end

    -- SetTimerDuration handles bar animation natively — no OnUpdate needed
    custom.bar:SetTimerDuration(
        castDuration, nil,
        isChannel and Enum.StatusBarTimerDirection.RemainingTime
                  or Enum.StatusBarTimerDirection.ElapsedTime
    )

    -- Secret-safe color via EvaluateColorValueFromBoolean (handles secret booleans)
    local r = C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0.7, 1)
    local b = C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0.7, 0)
    custom.bar:GetStatusBarTexture():SetVertexColor(r, 0.7, b)

    custom.container:Show()
end

local function SkinHealthBar(unitFrame)
    local healthBar = unitFrame.healthBar
    if not healthBar then return end

    -- Alpha-zero all Blizzard regions (fill, borders, decorations)
    for i = 1, healthBar:GetNumRegions() do
        local region = select(i, healthBar:GetRegions())
        if region then region:SetAlpha(0) end
    end

    if not hookedBars[healthBar] then
        hookedBars[healthBar] = true

        -- Our own StatusBar, child of Blizzard's healthBar
        local bar = CreateFrame("StatusBar", nil, healthBar)
        bar:SetStatusBarTexture(C.BAR_TEXTURE)
        bar:SetPoint("CENTER", healthBar, "CENTER")
        bar:SetSize(ns.Config:Get("nameplates", "width"),
                    ns.Config:Get("nameplates", "height"))
        bar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
        customHealthBars[healthBar] = bar

        -- Backdrop
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                           C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

        -- Per-unitFrame heal prediction calculator (pcall in case API unavailable)
        pcall(function()
            local calc = CreateUnitHealPredictionCalculator()
            calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
            calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
            healCalcs[unitFrame] = calc
        end)

        -- Absorb bar (behind health bar, like Platynator's layout)
        local absorbBar = CreateFrame("StatusBar", nil, bar)
        absorbBar:SetStatusBarTexture(C.BAR_TEXTURE)
        absorbBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 0.35)
        absorbBar:SetPoint("LEFT", bar:GetStatusBarTexture(), "RIGHT")
        absorbBar:SetPoint("TOP", bar, "TOP")
        absorbBar:SetPoint("BOTTOM", bar, "BOTTOM")
        absorbBar:SetFrameLevel(bar:GetFrameLevel() - 1)
        absorbBar:SetClipsChildren(true)
        absorbBars[unitFrame] = absorbBar

        -- Mirror progress from Blizzard's healthBar to our custom bar
        hooksecurefunc(healthBar, "SetMinMaxValues", function(self, min, max)
            local c = customHealthBars[self]
            if c then c:SetMinMaxValues(min, max) end
        end)
        hooksecurefunc(healthBar, "SetValue", function(self, val)
            local c = customHealthBars[self]
            if c then c:SetValue(val) end
        end)

        -- Capture Blizzard's color; apply reaction color or threat override
        hooksecurefunc(healthBar, "SetStatusBarColor", function(self, r, g, b)
            blizzardHealthColors[self] = { r, g, b }
            local c = customHealthBars[self]
            if not c then return end
            local color = threatOverrides[unitFrame]
            if color then
                c:SetStatusBarColor(color[1], color[2], color[3])
            else
                c:SetStatusBarColor(r, g, b)
            end
        end)

        -- Keep Blizzard's fill invisible on texture changes
        hooksecurefunc(healthBar, "SetStatusBarTexture", function(self)
            local tex = self:GetStatusBarTexture()
            if tex then tex:SetAlpha(0) end
        end)
    end
end

local neutralizedCastBars = {} -- castBar → true (already neutralized)
local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

local function SkinCastBar(unitFrame)
    local castBar = unitFrame.castBar
    if not castBar then return end

    -- Always neutralize Blizzard's castBar (even before custom HB exists)
    if not neutralizedCastBars[castBar] then
        neutralizedCastBars[castBar] = true
        castBar:UnregisterAllEvents()
        -- Reparent to a hidden frame — strictly stronger than alpha-zero.
        -- Even if Blizzard calls Show() or SetAlpha(1), the frame stays
        -- invisible because its parent is hidden.
        castBar:SetParent(hiddenFrame)
    end

    if customCastBars[unitFrame] then return end

    local customHB = customHealthBars[unitFrame.healthBar]
    if not customHB then return end

    local plate = unitFrame:GetParent()

    local barWidth = ns.Config:Get("nameplates", "width")
    local barHeight = ns.Config:Get("nameplates", "height")
    local iconSize = barHeight
    local iconGap = 2

    -- Container frame parented to nameplate (not castBar) — fully addon-owned
    local container = CreateFrame("Frame", nil, plate)
    container:SetPoint("TOPLEFT", customHB, "BOTTOMLEFT", 0, -2)
    container:SetSize(barWidth, barHeight)
    container:SetFrameLevel(castBar:GetFrameLevel() + 2)
    container:Hide()

    -- Our own StatusBar, addon-owned — no taint
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetStatusBarTexture(C.BAR_TEXTURE)
    bar:SetPoint("TOPLEFT", container, "TOPLEFT", iconSize + iconGap, 0)
    bar:SetSize(barWidth - iconSize - iconGap, barHeight)

    -- Backdrop
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                       C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Spell icon (square, left of bar)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOPRIGHT", bar, "TOPLEFT", -iconGap, 0)
    icon:SetTexCoord(unpack(C.ICON_CROP))

    -- Icon backdrop
    local iconBg = bar:CreateTexture(nil, "BACKGROUND")
    iconBg:SetPoint("TOPLEFT", icon, "TOPLEFT")
    iconBg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
    iconBg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                           C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Spell name text
    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", bar, "LEFT", 4, 0)
    text:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    StyleFontString(text)

    customCastBars[unitFrame] = { bar = bar, icon = icon, text = text, container = container }
end

local function CleanupChrome(unitFrame)
    if unitFrame.ClassificationFrame then
        unitFrame.ClassificationFrame:SetAlpha(0)
        hooksecurefunc(unitFrame.ClassificationFrame, "Show", function(self)
            self:SetAlpha(0)
        end)
    end

    if unitFrame.selectionHighlight then
        unitFrame.selectionHighlight:SetAlpha(0)
    end

    if unitFrame.aggroHighlight then
        unitFrame.aggroHighlight:SetAlpha(0)
    end

    -- Blizzard's aura display stays visible from 12.1 on — we reskin its buttons
    -- in place (see "Blizzard aura button reskin" below) instead of hiding it and
    -- painting our own icons from aura reads that are no longer permitted.
end

local function CreateNameOverlay(unitFrame)
    local custom = customHealthBars[unitFrame.healthBar]
    if not custom then return end

    local overlay = custom:CreateFontString(nil, "OVERLAY")
    overlay:SetPoint("LEFT", custom, "LEFT", 4, 0)
    overlay:SetPoint("RIGHT", custom, "RIGHT", -4, 0)
    overlay:SetJustifyH("CENTER")
    overlay:SetWordWrap(false)
    StyleFontString(overlay)

    nameOverlays[unitFrame] = overlay

    -- Hide Blizzard's name text
    if unitFrame.name then
        unitFrame.name:SetAlpha(0)
    end
end

local function SyncNameText(unitFrame)
    local overlay = nameOverlays[unitFrame]
    if not overlay then return end
    if not unitFrame.unit then return end

    -- 12.0.5: UnitName can return a secret string on restricted maps (instances).
    -- `secret or ""` would be a boolean test on a secret value -> Lua error.
    -- SetText accepts a secret string directly (marks the Text aspect secret),
    -- so pass it through when secret and only apply the "" fallback for nil.
    local name = UnitName(unitFrame.unit)
    if issecretvalue and issecretvalue(name) then
        overlay:SetText(name)
    else
        overlay:SetText(name or "")
    end
end

local function StyleAllText(unitFrame)
    CreateNameOverlay(unitFrame)
    -- Level text if present
    if unitFrame.LevelFrame then
        StyleFontString(unitFrame.LevelFrame.LevelText)
    end
    -- Health value text (CompactUnitFrame uses statusText)
    StyleFontString(unitFrame.statusText)
    if unitFrame.healthBar then
        StyleFontString(unitFrame.healthBar.text)
        StyleFontString(unitFrame.healthBar.Text)
    end
end

local function CreateFocusOverlay(unitFrame)
    local custom = customHealthBars[unitFrame.healthBar]
    if not custom or focusOverlays[unitFrame] then return end

    local overlay = custom:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints(custom)
    overlay:SetTexture("Interface\\AddOns\\PadleyUI\\Textures\\DiagonalStripes", "REPEAT", "REPEAT")
    overlay:SetHorizTile(true)
    overlay:SetVertTile(true)
    overlay:SetVertexColor(0, 0, 0, 0.2)
    overlay:Hide()

    focusOverlays[unitFrame] = overlay
end

local function UpdateFocusOverlay(unitFrame)
    local overlay = focusOverlays[unitFrame]
    if not overlay then return end

    local unit = unitFrame.unit
    if unit and UnitExists("focus") and UnitIsUnit(unit, "focus") then
        overlay:Show()
    else
        overlay:Hide()
    end
end

local function RefreshAllFocusOverlays()
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
            UpdateFocusOverlay(plate.UnitFrame)
        end
    end
end

-- Target arrow indicators (two chevrons pointing inward at the health bar)
local ARROW_PAD       = 4   -- gap between arrow tip and health bar edge
local ARROW_COLOR     = { 1, 1, 1, 1 }
local ARROW_TEXTURE   = "Interface\\AddOns\\PadleyUI\\Textures\\TargetArrow.png"

local function CreateTargetArrows(unitFrame)
    local custom = customHealthBars[unitFrame.healthBar]
    if not custom or targetArrows[unitFrame] then return end

    local nameplate = unitFrame:GetParent()

    local arrowH = 24
    local arrowW = 12

    -- Left chevron ">" pointing right — left half of texture
    local leftFrame = CreateFrame("Frame", nil, nameplate)
    leftFrame:SetFrameStrata("MEDIUM")
    leftFrame:SetFrameLevel(custom:GetFrameLevel() + 1)
    leftFrame:SetSize(arrowW, arrowH)
    leftFrame:SetPoint("RIGHT", custom, "LEFT", -ARROW_PAD, 0)
    local leftTex = leftFrame:CreateTexture(nil, "ARTWORK")
    leftTex:SetAllPoints()
    leftTex:SetTexture(ARROW_TEXTURE)
    leftTex:SetTexCoord(0, 0.5, 0, 1)
    leftTex:SetVertexColor(ARROW_COLOR[1], ARROW_COLOR[2], ARROW_COLOR[3], ARROW_COLOR[4])
    leftFrame:Hide()

    -- Right chevron "<" pointing left — right half of texture
    local rightFrame = CreateFrame("Frame", nil, nameplate)
    rightFrame:SetFrameStrata("MEDIUM")
    rightFrame:SetFrameLevel(custom:GetFrameLevel() + 1)
    rightFrame:SetSize(arrowW, arrowH)
    rightFrame:SetPoint("LEFT", custom, "RIGHT", ARROW_PAD, 0)
    local rightTex = rightFrame:CreateTexture(nil, "ARTWORK")
    rightTex:SetAllPoints()
    rightTex:SetTexture(ARROW_TEXTURE)
    rightTex:SetTexCoord(0.5, 1, 0, 1)
    rightTex:SetVertexColor(ARROW_COLOR[1], ARROW_COLOR[2], ARROW_COLOR[3], ARROW_COLOR[4])
    rightFrame:Hide()

    targetArrows[unitFrame] = { leftFrame, rightFrame }
end

local function UpdateTargetArrows(unitFrame)
    local arrows = targetArrows[unitFrame]
    if not arrows then return end

    local unit = unitFrame.unit
    local show = unit and UnitExists("target") and UnitIsUnit(unit, "target")
    for _, frame in ipairs(arrows) do
        if show then frame:Show() else frame:Hide() end
    end
end

local function RefreshAllTargetArrows()
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
            UpdateTargetArrows(plate.UnitFrame)
        end
    end
end

local function GetQuestProgressForUnit(unit)
    if not unit or not UnitExists(unit) then return nil end
    if C_Secrets.ShouldUnitIdentityBeSecret(unit) then return nil end

    local info = C_TooltipInfo.GetUnit(unit)
    if not info or not info.lines then return nil end

    -- Filter to quest-typed lines only; their leftText is never secret.
    -- Non-quest lines (unit name, guild, etc.) carry secret text on nameplates.
    local ignoreUntilTitle = false
    for _, line in ipairs(info.lines) do
        if line.type == Enum.TooltipDataLineType.QuestPlayer then
            ignoreUntilTitle = (line.leftText ~= UnitName("player"))
        elseif line.type == Enum.TooltipDataLineType.QuestTitle then
            ignoreUntilTitle = false
        elseif line.type == Enum.TooltipDataLineType.QuestObjective and not ignoreUntilTitle then
            local text = line.leftText
            if text then
                -- Kill/collect quests: "3/5" pattern
                local cur, req = text:match("(%d+)/(%d+)")
                if cur and req then
                    cur, req = tonumber(cur), tonumber(req)
                    if cur < req then
                        return cur .. "/" .. req
                    end
                end
                -- Percentage quests: "45%" pattern
                local pct = text:match("(%d+)%%")
                if pct then
                    pct = tonumber(pct)
                    if pct < 100 then
                        return pct .. "%"
                    end
                end
            end
        end
    end

    return nil
end

local function CreateQuestIndicator(unitFrame)
    local custom = customHealthBars[unitFrame.healthBar]
    if not custom or questIndicators[unitFrame] then return end

    local text = custom:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", custom, "RIGHT", 4, 0)
    StyleFontString(text)
    text:SetTextColor(1, 0.82, 0)
    text:Hide()

    questIndicators[unitFrame] = text
end

local function UpdateQuestIndicatorPosition(unitFrame)
    local indicator = questIndicators[unitFrame]
    if not indicator then return end
    local custom = customHealthBars[unitFrame.healthBar]
    if not custom then return end

    local unit = unitFrame.unit
    local offset = 4
    if unit and UnitExists("target") and UnitIsUnit(unit, "target") then
        offset = ARROW_PAD + 12 + 4  -- clear the target arrow
    end
    indicator:ClearAllPoints()
    indicator:SetPoint("LEFT", custom, "RIGHT", offset, 0)
end

local function UpdateQuestIndicator(unitFrame)
    local indicator = questIndicators[unitFrame]
    if not indicator then return end

    local unit = unitFrame.unit
    C_Timer.After(0, function()
        if not UnitExists(unit) then
            indicator:Hide()
            return
        end
        local progress = GetQuestProgressForUnit(unit)
        if progress then
            indicator:SetText(progress)
            indicator:Show()
            UpdateQuestIndicatorPosition(unitFrame)
        else
            indicator:Hide()
        end
    end)
end

local function CreateHoverBorder(unitFrame)
    local custom = customHealthBars[unitFrame.healthBar]
    if not custom or hoverBorders[unitFrame] then return end

    local plate = unitFrame:GetParent()
    local borderSize = 2

    local border = CreateFrame("Frame", nil, plate)
    border:EnableMouse(false)
    border:SetFrameLevel(custom:GetFrameLevel() + 1)
    border:SetPoint("TOPLEFT", custom, "TOPLEFT", -borderSize, borderSize)
    border:SetPoint("BOTTOMRIGHT", custom, "BOTTOMRIGHT", borderSize, -borderSize)

    local top = border:CreateTexture(nil, "BORDER")
    top:SetColorTexture(1, 1, 1, 1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(borderSize)

    local bottom = border:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(1, 1, 1, 1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(borderSize)

    local left = border:CreateTexture(nil, "BORDER")
    left:SetColorTexture(1, 1, 1, 1)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
    left:SetWidth(borderSize)

    local right = border:CreateTexture(nil, "BORDER")
    right:SetColorTexture(1, 1, 1, 1)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    right:SetWidth(borderSize)

    border:Hide()

    hoverBorders[unitFrame] = border
end

local function UpdateHoverBorder(unitFrame)
    local border = hoverBorders[unitFrame]
    if not border then return end

    local unit = unitFrame.unit
    if unit and UnitExists("mouseover") and UnitIsUnit(unit, "mouseover") then
        border:Show()
    else
        border:Hide()
    end
end

local mouseoverTicker = nil

local function RefreshAllHoverBorders()
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
            UpdateHoverBorder(plate.UnitFrame)
        end
    end

    -- Start polling to detect when mouseover ends (no event fires for that)
    if UnitExists("mouseover") and not mouseoverTicker then
        mouseoverTicker = C_Timer.NewTicker(0.1, function()
            if not UnitExists("mouseover") then
                mouseoverTicker:Cancel()
                mouseoverTicker = nil
                RefreshAllHoverBorders()
            end
        end)
    end
end

local function CreateKickOverlay(unitFrame)
    local customHB = customHealthBars[unitFrame.healthBar]
    if not customHB or kickOverlays[unitFrame] then return end

    local plate = unitFrame:GetParent()
    local castBar = unitFrame.castBar

    local barWidth = ns.Config:Get("nameplates", "width")
    local barHeight = ns.Config:Get("nameplates", "height")
    local iconSize = barHeight
    local iconGap = 2

    -- Container frame parented to the nameplate (not castBar) so it stays visible
    -- when Blizzard hides castBar on interrupt
    local frame = CreateFrame("Frame", nil, plate)
    frame:SetPoint("TOPLEFT", customHB, "BOTTOMLEFT", 0, -2)
    frame:SetSize(barWidth, barHeight)
    frame:SetFrameLevel((castBar and castBar:GetFrameLevel() or 5) + 4)
    frame:Hide()

    -- Status bar (always full, dark red)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(C.BAR_TEXTURE)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", iconSize + iconGap, 0)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarColor(KICK_BAR_COLOR[1], KICK_BAR_COLOR[2], KICK_BAR_COLOR[3])

    -- Backdrop
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                       C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Spell icon (square, left of bar)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOPRIGHT", bar, "TOPLEFT", -iconGap, 0)
    icon:SetTexCoord(unpack(C.ICON_CROP))

    -- Icon backdrop
    local iconBg = bar:CreateTexture(nil, "BACKGROUND")
    iconBg:SetPoint("TOPLEFT", icon, "TOPLEFT")
    iconBg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
    iconBg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                           C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- "Kicked: Name" text
    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", bar, "LEFT", 4, 0)
    text:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    StyleFontString(text)

    kickOverlays[unitFrame] = { frame = frame, bar = bar, icon = icon, text = text, timer = nil }
end

local function ShowKickOverlay(unitFrame, sourceName, spellTexture)
    local overlay = kickOverlays[unitFrame]
    if not overlay then return end

    overlay.text:SetText("Kicked: " .. sourceName)
    if spellTexture then
        overlay.icon:SetTexture(spellTexture)
    end
    overlay.frame:Show()

    -- Cancel existing timer
    if overlay.timer then
        overlay.timer:Cancel()
    end

    overlay.timer = C_Timer.NewTimer(KICK_DISPLAY_DURATION, function()
        overlay.frame:Hide()
        overlay.timer = nil
    end)
end

----------------------------------------------------------------------------
-- Blizzard aura button reskin (12.1)
--
-- 12.1 closed every path for reading auras ourselves: GetUnitAuras returns a
-- secret vector, GetAuraDataByAuraInstanceID/GetAuraDuration error while auras
-- are secret, and a spellID can't be read off a restricted unit at all. The old
-- read-and-rebuild pipeline (our own buff/CC/debuff slots, filtering, blacklist)
-- is therefore gone. Blizzard renders its own aura buttons as flat <Button>
-- children of the base nameplate — icon Texture + border Texture + a <Cooldown>
-- with the aura-display-time API. We restyle those in place and show whatever
-- Blizzard shows.
--
-- Every write to a Blizzard-owned button is pcall-guarded. It is not yet
-- established which writes/hooks these buttons tolerate under 12.1 restrictions;
-- if one is refused we report it once and leave that button unstyled rather
-- than erroring out of the whole skin.
----------------------------------------------------------------------------

local styledAuraButtons = {}   -- Blizzard aura Button → true (one-time pass done)
local auraBackdrops = {}       -- Blizzard aura Button → our backdrop Frame
local pendingAuraSweeps = {}   -- UnitFrame → true (deferred sweep already queued)

-- Diagnostic: surface each refused write once, then go quiet.
local auraSkinErrors = {}
local auraSkinErrorCount = 0
local MAX_AURA_SKIN_ERRORS = 4

local function ReportAuraSkinError(what, err)
    -- An error object could itself carry a secret; never key a table or print
    -- with one (both would throw and turn a handled refusal into a red error).
    if issecretvalue and issecretvalue(err) then err = "<secret error value>" end
    if type(err) ~= "string" and type(err) ~= "number" then err = "<non-string error>" end
    local key = what .. "|" .. tostring(err)
    if auraSkinErrors[key] then return end
    auraSkinErrors[key] = true
    if auraSkinErrorCount >= MAX_AURA_SKIN_ERRORS then return end
    auraSkinErrorCount = auraSkinErrorCount + 1
    print("|cff00ccffPadleyUI:|r nameplate aura skin refused (" .. what .. "): "
          .. tostring(err))
end

-- Every touch of a Blizzard aura button goes through this.
local function TryWrite(what, fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then ReportAuraSkinError(what, err) end
    return ok
end

local function SafeGet(obj, key)
    if not obj then return nil end
    local ok, v = pcall(function() return obj[key] end)
    if not ok then return nil end
    return v
end

local function SafeObjectType(obj)
    if not obj then return nil end
    local ok, t = pcall(function() return obj:GetObjectType() end)
    if not ok then return nil end
    return t
end

local function GetChildList(frame)
    if not frame then return {} end
    local ok, list = pcall(function() return { frame:GetChildren() } end)
    if not ok then return {} end
    return list
end

local function GetRegionList(frame)
    if not frame then return {} end
    local ok, list = pcall(function() return { frame:GetRegions() } end)
    if not ok then return {} end
    return list
end

-- Which Texture on the button is the spell icon? The icon carries a fileID (a
-- secret one on a restricted unit); Blizzard's border/overlay carries an atlas
-- or a literal texture path.
local function IsIconTexture(tex)
    local ok, atlas = pcall(function() return tex:GetAtlas() end)
    if ok and type(atlas) == "string" then return false end
    local ok2, file = pcall(function() return tex:GetTexture() end)
    if not ok2 then return false end
    if issecretvalue and issecretvalue(file) then return true end
    return type(file) == "number"
end

local function FindIconTexture(button)
    -- Named parentKey first (NameplateBuffButtonTemplate exposes .Icon)
    local named = SafeGet(button, "Icon") or SafeGet(button, "icon")
    if SafeObjectType(named) == "Texture" then return named end

    local found
    for _, region in ipairs(GetRegionList(button)) do
        if SafeObjectType(region) == "Texture" and IsIconTexture(region) then
            -- Ambiguous: better an unstyled aura than an alpha-zeroed icon
            if found then return nil end
            found = region
        end
    end
    return found
end

local function StripMasks(tex)
    if not tex or not tex.GetMaskTextures then return end
    local ok, masks = pcall(function() return { tex:GetMaskTextures() } end)
    if not ok then return end
    for _, mask in ipairs(masks) do
        TryWrite("icon mask remove", tex.RemoveMaskTexture, tex, mask)
        TryWrite("icon mask hide", mask.Hide, mask)
    end
end

-- Plain frame + texture, NOT BackdropTemplate: BackdropTemplate's
-- SetupTextureCoordinates calls GetWidth() in Lua, and an aura button on a
-- restricted unit carries a secret width. Mirrors UnitFrames / PartyFrames.
local function CreateAuraBackdrop(button)
    local bd = CreateFrame("Frame", nil, button)
    bd:SetAllPoints(button)
    local tex = bd:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                        C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    local level = button:GetFrameLevel()
    if type(level) == "number" then
        bd:SetFrameLevel(math.max(level - 1, 0))
    end
    bd:EnableMouse(false)
    return bd
end

local function StyleAuraButton(button)
    local icon = FindIconTexture(button)

    -- Per-refresh: Blizzard resets the crop and re-adds masks when it recycles
    -- a button, so these two run on every sweep.
    if icon then
        TryWrite("icon texcoord", icon.SetTexCoord, icon,
                 C.ICON_CROP[1], C.ICON_CROP[2], C.ICON_CROP[3], C.ICON_CROP[4])
        StripMasks(icon)
    end

    if styledAuraButtons[button] then return end
    styledAuraButtons[button] = true

    -- Alpha-zero Blizzard's border/overlay textures, hide shaping masks
    for _, region in ipairs(GetRegionList(button)) do
        local rt = SafeObjectType(region)
        if rt == "MaskTexture" then
            TryWrite("mask hide", region.Hide, region)
        elseif rt == "Texture" and region ~= icon then
            TryWrite("border alpha", region.SetAlpha, region, 0)
        end
    end

    -- Cooldown children: flat swipe, no edge/bling. Deliberately NOT touching
    -- the countdown FontString's font — it is read during secure execution.
    for _, child in ipairs(GetChildList(button)) do
        if SafeGet(child, "SetSwipeColor") then
            TryWrite("cooldown swipe", child.SetSwipeColor, child, 0, 0, 0, 0.6)
            TryWrite("cooldown edge", child.SetDrawEdge, child, false)
            TryWrite("cooldown bling", child.SetDrawBling, child, false)
        end
        for _, region in ipairs(GetRegionList(child)) do
            if SafeObjectType(region) == "MaskTexture" then
                TryWrite("cooldown mask hide", region.Hide, region)
            end
        end
    end

    if not auraBackdrops[button] then
        local ok, bd = pcall(CreateAuraBackdrop, button)
        if ok then
            auraBackdrops[button] = bd
        else
            ReportAuraSkinError("backdrop", bd)
        end
    end

    -- Re-apply triggers. Blizzard swaps the icon on a recycled button and resets
    -- its crop; hooking the instance methods catches that without putting a
    -- script on the button (addon scripts wouldn't run there anyway).
    if icon then
        TryWrite("hook icon SetTexture", hooksecurefunc, icon, "SetTexture", function(self)
            pcall(self.SetTexCoord, self,
                  C.ICON_CROP[1], C.ICON_CROP[2], C.ICON_CROP[3], C.ICON_CROP[4])
        end)
    end
    TryWrite("hook button Show", hooksecurefunc, button, "Show", function(self)
        pcall(StyleAuraButton, self)
    end)
end

-- Blizzard's nameplate aura buttons are flat <Button> children of the base
-- nameplate, each owning a <Cooldown> with the aura-display-time API. The
-- nameplate's own UnitFrame is a Button too, so exclude anything that carries
-- nameplate parts.
local function IsAuraButton(frame)
    if SafeObjectType(frame) ~= "Button" then return false end
    if SafeGet(frame, "healthBar") or SafeGet(frame, "castBar") then return false end
    for _, child in ipairs(GetChildList(frame)) do
        if SafeGet(child, "GetUseAuraDisplayTime") then return true end
    end
    return false
end

local function SweepAuraButtons(unitFrame)
    if not unitFrame then return end
    local ok, plate = pcall(function() return unitFrame:GetParent() end)
    if not ok or not plate then return end

    -- Buttons sit directly on the base nameplate in 12.1; also scan the legacy
    -- aura containers in case a build parents them there instead.
    local scan = { plate }
    local aurasFrame = SafeGet(unitFrame, "AurasFrame")
    if aurasFrame then scan[#scan + 1] = aurasFrame end
    local buffFrame = SafeGet(unitFrame, "BuffFrame")
    if buffFrame then scan[#scan + 1] = buffFrame end

    for _, parent in ipairs(scan) do
        for _, child in ipairs(GetChildList(parent)) do
            if child ~= unitFrame and IsAuraButton(child) then
                StyleAuraButton(child)
            end
        end
    end
end

-- Sweep now, and again next frame: Blizzard may create or recycle a button
-- after the event that told us the unit's auras changed.
local function ScheduleAuraSweep(unitFrame)
    if not unitFrame then return end
    SweepAuraButtons(unitFrame)
    if pendingAuraSweeps[unitFrame] then return end
    pendingAuraSweeps[unitFrame] = true
    C_Timer.After(0, function()
        pendingAuraSweeps[unitFrame] = nil
        SweepAuraButtons(unitFrame)
    end)
end

local function UpdateAbsorbs(unitFrame)
    local absorbBar = absorbBars[unitFrame]
    if not absorbBar or not unitFrame.unit then return end
    local customHB = customHealthBars[unitFrame.healthBar]
    local calc = healCalcs[unitFrame]
    if not customHB or not calc then
        if absorbBar then absorbBar:Hide() end
        return
    end

    -- All calculator values may be secret — pcall guards all arithmetic/comparison
    local ok, absorbs, maxWithAbsorbs = pcall(function()
        UnitGetDetailedHealPrediction(unitFrame.unit, nil, calc)
        calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
        local mwa = calc:GetMaximumHealth()
        local ab = calc:GetDamageAbsorbs()
        -- Force arithmetic to detect secrets (throws on secret values)
        return ab + 0, mwa + 0
    end)

    if ok and absorbs and absorbs > 0 and maxWithAbsorbs and maxWithAbsorbs > 0 then
        -- Adjust both bars to the health+absorb range
        customHB:SetMinMaxValues(0, maxWithAbsorbs)
        absorbBar:SetMinMaxValues(0, maxWithAbsorbs)
        -- Health value: read from Blizzard's bar (already resolved, non-secret)
        customHB:SetValue(unitFrame.healthBar:GetValue())
        absorbBar:SetValue(absorbs)
        absorbBar:Show()
    else
        absorbBar:Hide()
        -- Restore health bar to standard range (hooks keep it in sync)
        local min, max = unitFrame.healthBar:GetMinMaxValues()
        customHB:SetMinMaxValues(min, max)
        customHB:SetValue(unitFrame.healthBar:GetValue())
    end
end

local function IsNamePlateUnit(unitId)
    return unitId and unitId:sub(1, 9) == "nameplate"
end

local function SkinNamePlate(unitFrame)
    if not unitFrame or skinnedFrames[unitFrame] then return end
    skinnedFrames[unitFrame] = true

    SkinHealthBar(unitFrame)
    SkinCastBar(unitFrame)
    CleanupChrome(unitFrame)
    StyleAllText(unitFrame)
    CreateFocusOverlay(unitFrame)
    CreateTargetArrows(unitFrame)
    CreateQuestIndicator(unitFrame)
    CreateHoverBorder(unitFrame)
    CreateKickOverlay(unitFrame)
    ScheduleAuraSweep(unitFrame)
end

local function RefreshNamePlate(unitFrame)
    -- Sync initial health bar state (needed when nameplate appears with existing unit)
    local customHB = customHealthBars[unitFrame.healthBar]
    if customHB and unitFrame.healthBar then
        local min, max = unitFrame.healthBar:GetMinMaxValues()
        customHB:SetMinMaxValues(min, max)
        customHB:SetValue(unitFrame.healthBar:GetValue())
        local r, g, b = unitFrame.healthBar:GetStatusBarColor()
        blizzardHealthColors[unitFrame.healthBar] = { r, g, b }
    end
    UpdateAbsorbs(unitFrame)
    UpdateThreatColor(unitFrame)
    -- ShowCustomCastBar auto-detects cast/channel and bails if neither
    if unitFrame.unit then
        ShowCustomCastBar(unitFrame)
    end
    -- Keep Blizzard's name hidden, sync text to our overlay
    if unitFrame.name then
        unitFrame.name:SetAlpha(0)
    end
    SyncNameText(unitFrame)
    UpdateFocusOverlay(unitFrame)
    ScheduleAuraSweep(unitFrame)
    UpdateTargetArrows(unitFrame)
    UpdateQuestIndicator(unitFrame)
end

function NameplateSkin:ResizeAll()
    local w = ns.Config:Get("nameplates", "width")
    local h = ns.Config:Get("nameplates", "height")
    for _, bar in pairs(customHealthBars) do
        bar:SetSize(w, h)
    end
    -- Re-anchor absorb bars after health bar resize
    for unitFrame, absorbBar in pairs(absorbBars) do
        local customHB = customHealthBars[unitFrame.healthBar]
        if customHB then
            absorbBar:SetPoint("LEFT", customHB:GetStatusBarTexture(), "RIGHT")
        end
    end
    -- Resize cast bars to match
    local iconGap = 2
    for unitFrame, custom in pairs(customCastBars) do
        local customHB = customHealthBars[unitFrame.healthBar]
        if customHB and custom.container then
            custom.container:ClearAllPoints()
            custom.container:SetPoint("TOPLEFT", customHB, "BOTTOMLEFT", 0, -2)
            custom.container:SetSize(w, h)
        end
        custom.bar:ClearAllPoints()
        custom.bar:SetPoint("TOPLEFT", custom.container or custom.bar:GetParent(), "TOPLEFT", h + iconGap, 0)
        custom.bar:SetSize(w - h - iconGap, h)
        custom.icon:SetSize(h, h)
    end
    -- Resize kick overlays to match
    for _, overlay in pairs(kickOverlays) do
        overlay.bar:ClearAllPoints()
        overlay.bar:SetPoint("TOPLEFT", overlay.frame, "TOPLEFT", h + iconGap, 0)
        overlay.bar:SetPoint("BOTTOMRIGHT", overlay.frame, "BOTTOMRIGHT", 0, 0)
        overlay.icon:SetSize(h, h)
        overlay.frame:SetSize(w, h)
    end
    -- Aura icons are Blizzard's own buttons now; Blizzard owns their layout.
end

function NameplateSkin:Apply()
    SetCVar("nameplateShowFriendlyNPCs", 0)

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("NAME_PLATE_CREATED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    eventFrame:RegisterEvent("UNIT_FLAGS")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    eventFrame:RegisterEvent("UNIT_AURA")  -- re-style trigger only, no aura reads
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "NAME_PLATE_CREATED" then
            local plate = ...
            if plate and plate.UnitFrame then
                SkinNamePlate(plate.UnitFrame)
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            local unitId = ...
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if not plate or not plate.UnitFrame then return end

            if not skinnedFrames[plate.UnitFrame] then
                SkinNamePlate(plate.UnitFrame)
            end
            RefreshNamePlate(plate.UnitFrame)
        elseif event == "UNIT_THREAT_LIST_UPDATE"
            or event == "UNIT_THREAT_SITUATION_UPDATE"
            or event == "UNIT_FLAGS" then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                    UpdateThreatColor(plate.UnitFrame)
                end
            end
        elseif event == "UNIT_NAME_UPDATE" then
            local unitId = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                SyncNameText(plate.UnitFrame)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            RefreshAllFocusOverlays()
        elseif event == "PLAYER_TARGET_CHANGED" then
            RefreshAllTargetArrows()
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                    UpdateQuestIndicatorPosition(plate.UnitFrame)
                end
            end
        elseif event == "QUEST_LOG_UPDATE" then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                    UpdateQuestIndicator(plate.UnitFrame)
                end
            end
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            RefreshAllHoverBorders()
        elseif event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START" then
            local unitId, _, spellID = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                local isChannel = (event == "UNIT_SPELLCAST_CHANNEL_START")
                ShowCustomCastBar(plate.UnitFrame, spellID, isChannel)
            end
        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local unitId = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                HideCustomCastBar(plate.UnitFrame)
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE"
            or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Event name tells us the state directly; no API query needed
            local unitId = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                local custom = customCastBars[plate.UnitFrame]
                if custom then
                    local r, g, b
                    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
                        r, g, b = 0.7, 0.7, 0.7
                    else
                        r, g, b = 1, 0.7, 0
                    end
                    custom.bar:GetStatusBarTexture():SetVertexColor(r, g, b)
                end
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            local unitId, _, _, interrupterGUID = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame]
                and interrupterGUID then
                local name = UnitNameFromGUID(interrupterGUID)
                if name then
                    local custom = customCastBars[plate.UnitFrame]
                    local texture = custom and custom.icon and custom.icon:GetTexture()
                    ShowKickOverlay(plate.UnitFrame, name, texture)
                end
                HideCustomCastBar(plate.UnitFrame)
            end
        elseif event == "UNIT_AURA" then
            -- Not an aura read: this is our re-style trigger. Blizzard adds or
            -- recycles its aura buttons here, and a recycled button comes back
            -- with Blizzard's crop/border restored.
            local unitId = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                ScheduleAuraSweep(plate.UnitFrame)
            end
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
            or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            local unitId = ...
            if not IsNamePlateUnit(unitId) then return end
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                UpdateAbsorbs(plate.UnitFrame)
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            local unitId = ...
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            -- Reparent Blizzard castBar back so the nameplate can be reused cleanly
            if plate and plate.UnitFrame and neutralizedCastBars[plate.UnitFrame.castBar] then
                plate.UnitFrame.castBar:SetParent(plate.UnitFrame)
            end
            if plate and plate.UnitFrame then
                HideCustomCastBar(plate.UnitFrame)
            end
        end
    end)

    -- Skin any nameplates already visible
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        if plate.UnitFrame then
            SkinNamePlate(plate.UnitFrame)
        end
    end

end
