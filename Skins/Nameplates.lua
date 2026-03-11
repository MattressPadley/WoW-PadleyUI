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
local customCastBars = {}     -- Blizzard castBar → { bar, icon, text }
local blizzardHealthColors = {} -- Blizzard healthBar → { r, g, b } (cached reaction color)

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
        threatOverrides[unitFrame] = NOCOMBAT_COLOR
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
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
end

local function UpdateCastBarInterruptColor(unitFrame)
    local castBar = unitFrame.castBar
    if not castBar or not unitFrame.unit then return end
    local custom = customCastBars[castBar]
    if not custom then return end

    local name, _, texture, _, _, _, _, ni = UnitCastingInfo(unitFrame.unit)
    if type(name) == "nil" then
        name, _, texture, _, _, _, ni = UnitChannelInfo(unitFrame.unit)
    end
    if type(name) == "nil" then return end

    -- Sync icon and text
    if custom.icon and texture then custom.icon:SetTexture(texture) end
    if custom.text then custom.text:SetText(name) end

    -- Color via secret-safe path: EvaluateColorValueFromBoolean(bool, trueVal, falseVal)
    -- SetVertexColor on the fill texture accepts secret numbers and persists through SetValue
    local r = C_CurveUtil.EvaluateColorValueFromBoolean(ni, 0.7, 1)
    local b = C_CurveUtil.EvaluateColorValueFromBoolean(ni, 0.7, 0)
    custom.bar:GetStatusBarTexture():SetVertexColor(r, 0.7, b)
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
        bar:SetAllPoints()
        bar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
        customHealthBars[healthBar] = bar

        -- Backdrop
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                           C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

        -- Mirror progress
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

local function SkinCastBar(unitFrame)
    local castBar = unitFrame.castBar
    if not castBar then return end

    -- Alpha-zero ALL regions on Blizzard's cast bar
    for i = 1, castBar:GetNumRegions() do
        local region = select(i, castBar:GetRegions())
        if region then region:SetAlpha(0) end
    end
    if castBar.BorderShield then castBar.BorderShield:SetAlpha(0) end
    if castBar.Text then castBar.Text:SetAlpha(0) end

    -- Never call castBar:SetSize() — taints dimensions, causing secret values
    -- in BorderShield's Backdrop.lua when secure code queries GetSize()
    local healthBar = unitFrame.healthBar

    if not hookedBars[castBar] then
        hookedBars[castBar] = true

        local barHeight = healthBar and healthBar:GetHeight() or castBar:GetHeight()
        local barWidth = healthBar and healthBar:GetWidth() or castBar:GetWidth()
        local iconSize = barHeight
        local iconGap = 2

        -- Our own StatusBar, child of Blizzard's castBar (inherits show/hide)
        local bar = CreateFrame("StatusBar", nil, castBar)
        bar:SetStatusBarTexture(C.BAR_TEXTURE)
        bar:SetPoint("TOPLEFT", castBar, "TOPLEFT", iconSize + iconGap, 0)
        bar:SetSize(barWidth - iconSize - iconGap, barHeight)
        bar:SetFrameLevel(castBar:GetFrameLevel() + 2)

        -- Backdrop
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                           C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

        -- Spell icon (square, left of bar)
        local icon = bar:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("TOPRIGHT", bar, "TOPLEFT", -iconGap, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

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

        customCastBars[castBar] = { bar = bar, icon = icon, text = text }

        -- Mirror progress
        hooksecurefunc(castBar, "SetMinMaxValues", function(self, min, max)
            local c = customCastBars[self]
            if c then c.bar:SetMinMaxValues(min, max) end
        end)
        hooksecurefunc(castBar, "SetValue", function(self, val)
            local c = customCastBars[self]
            if c then c.bar:SetValue(val) end
        end)

        -- Keep Blizzard's fill invisible on texture changes
        hooksecurefunc(castBar, "SetStatusBarTexture", function(self)
            local tex = self:GetStatusBarTexture()
            if tex then tex:SetAlpha(0) end
        end)
    end
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

    overlay:SetText(UnitName(unitFrame.unit) or "")
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
    for _, tex in ipairs(arrows) do
        if show then tex:Show() else tex:Hide() end
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

    -- Tooltip scanning: SetUnit populates the tooltip with exactly the quest
    -- objectives relevant to this mob. No UnitName call needed (avoids taint).
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetUnit(unit)

    for i = 2, scanTip:NumLines() do
        local line = _G["PadleyUIScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
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

    scanTip:Hide()
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

    local border = CreateFrame("Frame", nil, plate, "BackdropTemplate")
    border:EnableMouse(false)
    border:SetFrameLevel(custom:GetFrameLevel() + 1)
    border:SetPoint("TOPLEFT", custom, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", custom, "BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    border:SetBackdropBorderColor(1, 1, 1, 1)
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
    local custom = customHealthBars[unitFrame.healthBar]
    local castBar = unitFrame.castBar
    if not custom or not castBar or kickOverlays[unitFrame] then return end

    local plate = unitFrame:GetParent()

    local healthBar = unitFrame.healthBar
    local barHeight = healthBar and healthBar:GetHeight() or castBar:GetHeight()
    local barWidth = healthBar and healthBar:GetWidth() or castBar:GetWidth()
    local iconSize = barHeight
    local iconGap = 2

    -- Container frame parented to the nameplate (not castBar) so it stays visible
    -- when Blizzard hides castBar on interrupt
    local frame = CreateFrame("Frame", nil, plate)
    frame:SetPoint("TOPLEFT", castBar, "TOPLEFT")
    frame:SetSize(barWidth, barHeight)
    frame:SetFrameLevel(castBar:GetFrameLevel() + 4)
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
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

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
    UpdateThreatColor(unitFrame)
    UpdateCastBarInterruptColor(unitFrame)
    -- Keep Blizzard's name hidden, sync text to our overlay
    if unitFrame.name then
        unitFrame.name:SetAlpha(0)
    end
    SyncNameText(unitFrame)
    UpdateFocusOverlay(unitFrame)
    UpdateTargetArrows(unitFrame)
    UpdateQuestIndicator(unitFrame)
end

function NameplateSkin:Apply()
    -- Make nameplates less wide (default horizontalScale is 1.0)
    SetCVar("NamePlateHorizontalScale", 0.7)
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
            local unitId = ...
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                UpdateCastBarInterruptColor(plate.UnitFrame)
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE"
            or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- Event name tells us the state directly; no API query needed
            local unitId = ...
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                local custom = customCastBars[plate.UnitFrame.castBar]
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
            local plate = C_NamePlate.GetNamePlateForUnit(unitId)
            if plate and plate.UnitFrame and skinnedFrames[plate.UnitFrame]
                and interrupterGUID then
                local name = UnitNameFromGUID(interrupterGUID)
                if name then
                    local custom = customCastBars[plate.UnitFrame.castBar]
                    local texture = custom and custom.icon and custom.icon:GetTexture()
                    ShowKickOverlay(plate.UnitFrame, name, texture)
                end
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
