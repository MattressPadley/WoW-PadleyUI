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

-- Guard against recursive SetStatusBarTexture / SetStatusBarColor hook calls
local settingTexture = {}
local settingColor = {}
local nonInterruptible = {}  -- castBar → true/false

-- Threat color tables (Plater-style defaults)
-- nil = no override, use Blizzard's default reaction color
local SAFE_COLOR = { 0.06, 0.59, 0.90 }  -- #0F96E6
local THREAT_DPS = {
    [0] = SAFE_COLOR,                     -- safe: blue
    [1] = { 1.0, 0.7, 0.0 },             -- pulling threat: orange
    [2] = { 1.0, 1.0, 0.0 },             -- tanking insecure: yellow
    [3] = { 1.0, 0.0, 0.0 },             -- has aggro: red (bad for DPS/healer)
}
local THREAT_TANK = {
    [0] = SAFE_COLOR,                     -- safe: blue
    [1] = { 1.0, 0.7, 0.0 },             -- losing aggro: orange
    [2] = { 1.0, 1.0, 0.0 },             -- tanking insecure: yellow
    [3] = { 0.0, 1.0, 0.0 },             -- securely tanking: green (good for tanks)
}

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
        return
    end
    threatOverrides[unitFrame] = GetThreatColor(unit)
    local color = threatOverrides[unitFrame]
    if color and unitFrame.healthBar then
        settingColor[unitFrame.healthBar] = true
        unitFrame.healthBar:SetStatusBarColor(color[1], color[2], color[3])
        settingColor[unitFrame.healthBar] = nil
    end
end

local function EnforceFlatTexture(bar)
    if settingTexture[bar] then return end
    local tex = bar:GetStatusBarTexture()
    if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
        -- Use SetStatusBarTexture on the bar (not SetTexture on the region)
        -- to preserve the bar's SetStatusBarColor tint
        settingTexture[bar] = true
        bar:SetStatusBarTexture(C.BAR_TEXTURE)
        settingTexture[bar] = nil
    end
end

local function CreateBarBackdrop(bar)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
end

local function SkinHealthBar(unitFrame)
    local healthBar = unitFrame.healthBar
    if not healthBar then return end

    SE:SkinStatusBar(healthBar)

    -- Alpha-zero all texture regions except the fill texture
    local fillTex = healthBar:GetStatusBarTexture()
    for i = 1, healthBar:GetNumRegions() do
        local region = select(i, healthBar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex then
            region:SetAlpha(0)
        end
    end

    -- Hook instance to persist flat texture and enforce threat colors
    if not hookedBars[healthBar] then
        hookedBars[healthBar] = true
        hooksecurefunc(healthBar, "SetStatusBarTexture", function(self)
            EnforceFlatTexture(self)
        end)
        -- After Blizzard sets color (reaction/class), override with threat color
        hooksecurefunc(healthBar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            local color = threatOverrides[unitFrame]
            if color then
                settingColor[self] = true
                self:SetStatusBarColor(color[1], color[2], color[3])
                settingColor[self] = nil
            end
        end)
    end

    CreateBarBackdrop(healthBar)
end

local function SkinCastBar(unitFrame)
    local castBar = unitFrame.castBar
    if not castBar then return end

    SE:SkinStatusBar(castBar)

    -- Alpha-zero border textures, preserve fill and icon
    local fillTex = castBar:GetStatusBarTexture()
    for i = 1, castBar:GetNumRegions() do
        local region = select(i, castBar:GetRegions())
        if region and region:GetObjectType() == "Texture"
           and region ~= fillTex
           and region ~= castBar.Icon then
            region:SetAlpha(0)
        end
    end

    if castBar.BorderShield then
        castBar.BorderShield:SetAlpha(0)
    end

    if not hookedBars[castBar] then
        hookedBars[castBar] = true

        local lastR, lastG, lastB = 1, 0.7, 0

        -- Capture Blizzard's color; guard prevents our overrides from polluting
        hooksecurefunc(castBar, "SetStatusBarColor", function(self, r, g, b)
            if settingColor[self] then return end
            lastR, lastG, lastB = r, g, b
            if nonInterruptible[self] then
                settingColor[self] = true
                self:SetStatusBarColor(0.7, 0.7, 0.7)
                settingColor[self] = nil
            end
        end)

        -- Enforce flat texture, replay color (or grey override)
        hooksecurefunc(castBar, "SetStatusBarTexture", function(self)
            if settingTexture[self] then return end
            local tex = self:GetStatusBarTexture()
            if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
                settingTexture[self] = true
                self:SetStatusBarTexture(C.BAR_TEXTURE)
                settingColor[self] = true
                if nonInterruptible[self] then
                    self:SetStatusBarColor(0.7, 0.7, 0.7)
                else
                    self:SetStatusBarColor(lastR, lastG, lastB)
                end
                settingColor[self] = nil
                settingTexture[self] = nil
            end
        end)

        -- Detect interruptibility via BorderShield visibility
        if castBar.BorderShield then
            hooksecurefunc(castBar.BorderShield, "Show", function()
                nonInterruptible[castBar] = true
                settingColor[castBar] = true
                castBar:SetStatusBarColor(0.7, 0.7, 0.7)
                settingColor[castBar] = nil
            end)
            hooksecurefunc(castBar.BorderShield, "Hide", function()
                nonInterruptible[castBar] = false
                settingColor[castBar] = true
                castBar:SetStatusBarColor(lastR, lastG, lastB)
                settingColor[castBar] = nil
            end)
        end
    end

    -- Match cast bar dimensions to health bar (size only, no re-anchoring)
    local healthBar = unitFrame.healthBar
    if healthBar then
        castBar:SetSize(healthBar:GetWidth(), healthBar:GetHeight())
    end

    -- Crop icon border
    if castBar.Icon then
        castBar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    CreateBarBackdrop(castBar)
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

local NAMEPLATE_FONT_SIZE = C.FONT_SIZE + 2

local function StyleFontString(fs)
    if not fs or not fs.SetFont then return end
    SE:StyleFont(fs, NAMEPLATE_FONT_SIZE, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
end

local function CreateNameOverlay(unitFrame)
    if not unitFrame.healthBar then return end

    -- Create our own FontString on the health bar (like Plater does)
    -- This avoids taint from repositioning Blizzard's unitFrame.name
    local overlay = unitFrame.healthBar:CreateFontString(nil, "OVERLAY")
    overlay:SetPoint("CENTER", unitFrame.healthBar, "CENTER", 0, 0)
    overlay:SetJustifyH("CENTER")
    overlay:SetWidth(unitFrame.healthBar:GetWidth() - 8)
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
    if not unitFrame.name then return end

    local fullName = unitFrame.name:GetText() or ""
    overlay:SetText(fullName)

    -- Truncate with ellipsis if the name overflows the health bar
    local maxWidth = unitFrame.healthBar:GetWidth() - 8
    if overlay:GetStringWidth() > maxWidth and #fullName > 0 then
        local name = fullName
        while #name > 0 and overlay:GetStringWidth() > maxWidth do
            name = name:sub(1, #name - 1)
            overlay:SetText(name .. "...")
        end
    end
end

local function StyleAllText(unitFrame)
    CreateNameOverlay(unitFrame)
    if unitFrame.castBar then
        StyleFontString(unitFrame.castBar.Text)
    end
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
    if not unitFrame.healthBar or focusOverlays[unitFrame] then return end

    local overlay = unitFrame.healthBar:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints(unitFrame.healthBar)
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
    if not unitFrame.healthBar or targetArrows[unitFrame] then return end

    local hb = unitFrame.healthBar
    local nameplate = unitFrame:GetParent()

    local arrowH = 24
    local arrowW = 12

    -- Left chevron ">" pointing right — left half of texture
    local leftFrame = CreateFrame("Frame", nil, nameplate)
    leftFrame:SetFrameStrata("MEDIUM")
    leftFrame:SetFrameLevel(hb:GetFrameLevel() + 2)
    leftFrame:SetSize(arrowW, arrowH)
    leftFrame:SetPoint("RIGHT", hb, "LEFT", -ARROW_PAD, 0)
    local leftTex = leftFrame:CreateTexture(nil, "ARTWORK")
    leftTex:SetAllPoints()
    leftTex:SetTexture(ARROW_TEXTURE)
    leftTex:SetTexCoord(0, 0.5, 0, 1)
    leftTex:SetVertexColor(ARROW_COLOR[1], ARROW_COLOR[2], ARROW_COLOR[3], ARROW_COLOR[4])
    leftFrame:Hide()

    -- Right chevron "<" pointing left — right half of texture
    local rightFrame = CreateFrame("Frame", nil, nameplate)
    rightFrame:SetFrameStrata("MEDIUM")
    rightFrame:SetFrameLevel(hb:GetFrameLevel() + 2)
    rightFrame:SetSize(arrowW, arrowH)
    rightFrame:SetPoint("LEFT", hb, "RIGHT", ARROW_PAD, 0)
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

    -- UnitName returns secret values for nameplate units in 12.0;
    -- pcall to detect and bail out gracefully
    local ok, unitName = pcall(UnitName, unit)
    if not ok or not unitName then return nil end

    -- Verify the name is usable (not a secret value)
    local nameOk = pcall(string.len, unitName)
    if not nameOk then return nil end

    -- Scan quest log for objectives mentioning this unit
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                for _, obj in ipairs(objectives) do
                    if not obj.finished and obj.text
                        and obj.numRequired and obj.numRequired > 0
                        and obj.text:find(unitName, 1, true) then
                        return obj.numFulfilled .. "/" .. obj.numRequired
                    end
                end
            end
        end
    end

    return nil
end

local function CreateQuestIndicator(unitFrame)
    if not unitFrame.healthBar or questIndicators[unitFrame] then return end

    local text = unitFrame.healthBar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", unitFrame.healthBar, "RIGHT", 4, 0)
    StyleFontString(text)
    text:SetTextColor(1, 0.82, 0)
    text:Hide()

    questIndicators[unitFrame] = text
end

local function UpdateQuestIndicator(unitFrame)
    local indicator = questIndicators[unitFrame]
    if not indicator then return end

    -- Defer to next frame to escape any tainted execution context
    -- (UnitName returns secret values when called from hook chains)
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
        else
            indicator:Hide()
        end
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
end

local function RefreshNamePlate(unitFrame)
    if unitFrame.healthBar then
        EnforceFlatTexture(unitFrame.healthBar)
    end
    UpdateThreatColor(unitFrame)
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

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("NAME_PLATE_CREATED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
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
            or event == "UNIT_THREAT_SITUATION_UPDATE" then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                    UpdateThreatColor(plate.UnitFrame)
                end
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            RefreshAllFocusOverlays()
        elseif event == "PLAYER_TARGET_CHANGED" then
            RefreshAllTargetArrows()
        elseif event == "QUEST_LOG_UPDATE" then
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                    UpdateQuestIndicator(plate.UnitFrame)
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
