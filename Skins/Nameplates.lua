local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local NameplateSkin = {}
ns.NameplateSkin = NameplateSkin

-- External tracking tables (never write keys to Blizzard frames)
local skinnedFrames = {}
local healthBackdrops = {}
local castBarBackdrops = {}
local hookedBars = {}
local nameOverlays = {}  -- keyed by UnitFrame → our custom FontString

-- Borderless backdrop definition (flat, no edge)
local FLAT_BG = { bgFile = C.FLAT_BACKDROP.bgFile }

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
    local status = UnitThreatSituation("player", unit) or 0
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
    local bdFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop(FLAT_BG)
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    return bdFrame
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

    healthBackdrops[unitFrame] = CreateBarBackdrop(healthBar)
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

    castBarBackdrops[unitFrame] = CreateBarBackdrop(castBar)
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

    -- Copy text from Blizzard's name FontString to our overlay
    if unitFrame.name then
        overlay:SetText(unitFrame.name:GetText() or "")
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

local function SkinNamePlate(unitFrame)
    if not unitFrame or skinnedFrames[unitFrame] then return end
    skinnedFrames[unitFrame] = true

    SkinHealthBar(unitFrame)
    SkinCastBar(unitFrame)
    CleanupChrome(unitFrame)
    StyleAllText(unitFrame)
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
end

function NameplateSkin:Apply()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("NAME_PLATE_CREATED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
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
            -- Update all visible nameplates (threat can shift across multiple)
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                if plate.UnitFrame and skinnedFrames[plate.UnitFrame] then
                    UpdateThreatColor(plate.UnitFrame)
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
