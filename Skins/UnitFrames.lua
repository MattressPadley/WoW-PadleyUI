local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local UnitFrameSkin = {}
ns.UnitFrameSkin = UnitFrameSkin

-- External tracking tables (never write keys to Blizzard frames)
local skinnedFrames = {}
local hookedBars = {}
local hookedRegions = {}
local frameUnits = {}
local powerBarUnits = {}

-- Guard against recursive hook calls
local settingTexture = {}
local settingColor = {}

-- Hidden parent for reparenting decorative frames off-screen
local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

-- Bar dimensions matching BetterBlizzFrames pixel border mode
local BorderPositions = {
    player = {
        health = { width = 123, height = 19, startX = 0, startY = 0 },
        mana   = { width = 123, height = 8,  startX = 0, startY = -2 },
    },
    target = {
        health = { width = 123, height = 19, startX = 0, startY = -1 },
        mana   = { width = 123, height = 8,  startX = 0, startY = -2 },
    },
}

---------------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------------

local function GetUnitHealthColor(unit)
    -- Class color for players, reaction color for NPCs
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                return color.r, color.g, color.b
            end
        end
    else
        local r, g, b = UnitSelectionColor(unit)
        if r then
            return r, g, b
        end
    end
    return 0.5, 0.5, 0.5
end

local function GetPowerColor(unit)
    local _, powerToken = UnitPowerType(unit)
    local color = PowerBarColor[powerToken]
    if color then
        return color.r, color.g, color.b
    end
    return 0.0, 0.0, 1.0
end

local function KillRegion(region)
    if not region or hookedRegions[region] then return end
    hookedRegions[region] = true
    region:SetAlpha(0)
    if region.SetAlpha then
        hooksecurefunc(region, "SetAlpha", function(self, a)
            if a ~= 0 then self:SetAlpha(0) end
        end)
    end
end

---------------------------------------------------------------------------
-- Bar Background (no borders, just dark bg behind the fill)
---------------------------------------------------------------------------

local barBgFrames = {}

local function CreateBarBackground(bar)
    if not bar or barBgFrames[bar] then return end

    local bd = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bd:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    bd:SetAllPoints(bar)
    SE:ApplyBackdrop(bd)
    barBgFrames[bar] = bd
end

---------------------------------------------------------------------------
-- Remove all mask textures from a bar (Blizzard adds shaped masks that
-- round corners — we want fully rectangular flat bars)
---------------------------------------------------------------------------

local strippedMasks = {}

local function RemoveMasksFromTexture(tex)
    if not tex or not tex.RemoveMaskTexture or not tex.GetMaskTextures then return end
    local masks = {tex:GetMaskTextures()}
    for _, mask in ipairs(masks) do
        tex:RemoveMaskTexture(mask)
        mask:Hide()
    end
end

local function RemoveBarMasks(bar)
    if not bar or strippedMasks[bar] then return end
    strippedMasks[bar] = true

    -- Remove masks from the fill texture (only StatusBars have this)
    if bar.GetStatusBarTexture then
        local fill = bar:GetStatusBarTexture()
        RemoveMasksFromTexture(fill)
    end

    -- Remove masks from all texture regions on the bar
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and (region:GetObjectType() == "Texture" or region:GetObjectType() == "MaskTexture") then
            RemoveMasksFromTexture(region)
        end
    end

    -- Hide known mask objects so they can't be re-added
    if bar.HealthBarMask then bar.HealthBarMask:Hide() end
    if bar.ManaBarMask then bar.ManaBarMask:Hide() end
end

---------------------------------------------------------------------------
-- Texture enforcement
---------------------------------------------------------------------------

local function EnforceFlatTexture(bar)
    if settingTexture[bar] then return end
    local tex = bar:GetStatusBarTexture()
    if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
        settingTexture[bar] = true
        bar:SetStatusBarTexture(C.BAR_TEXTURE)
        settingTexture[bar] = nil
    end
end

---------------------------------------------------------------------------
-- Health / Power color
---------------------------------------------------------------------------

local function ApplyHealthColor(healthBar)
    if settingColor[healthBar] then return end
    local unit = frameUnits[healthBar]
    if not unit or not UnitExists(unit) then return end

    local r, g, b = GetUnitHealthColor(unit)
    settingColor[healthBar] = true
    healthBar:SetStatusBarColor(r, g, b)
    settingColor[healthBar] = nil
end

local function ApplyPowerColor(manaBar)
    if settingColor[manaBar] then return end
    local unit = powerBarUnits[manaBar]
    if not unit or not UnitExists(unit) then return end

    local r, g, b = GetPowerColor(unit)
    settingColor[manaBar] = true
    manaBar:SetStatusBarColor(r, g, b)
    settingColor[manaBar] = nil
end

---------------------------------------------------------------------------
-- Skin Health Bar
---------------------------------------------------------------------------

local function SkinHealthBar(bar, unit, cfg)
    if not bar then return end

    SE:SkinStatusBar(bar)

    -- Persistently hide ALL non-fill texture regions on the bar
    local fillTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex then
            KillRegion(region)
        end
    end

    -- Persistently hide ALL child frames of the health bar
    -- (TotalAbsorbBar, TiledFillOverlay, absorb glows, etc.)
    for i = 1, select("#", bar:GetChildren()) do
        local child = select(i, bar:GetChildren())
        if child and child ~= barBgFrames[bar] then
            KillRegion(child)
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "Texture" then
                    KillRegion(region)
                end
            end
        end
    end

    -- Create background, remove Blizzard masks, size bar to match background
    CreateBarBackground(bar)
    RemoveBarMasks(bar)
    bar:SetSize(cfg.width, cfg.height)

    frameUnits[bar] = unit
    ApplyHealthColor(bar)

    if not hookedBars[bar] then
        hookedBars[bar] = true
        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            EnforceFlatTexture(self)
        end)
        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            ApplyHealthColor(self)
        end)

        -- Hook the fill texture's SetVertexColor — Blizzard uses this when
        -- lockColor is true, bypassing SetStatusBarColor entirely
        if fillTex and fillTex.SetVertexColor then
            hooksecurefunc(fillTex, "SetVertexColor", function()
                if settingColor[bar] then return end
                ApplyHealthColor(bar)
            end)
        end

        -- Hook fill texture's SetTexture to force flat texture back
        if fillTex and fillTex.SetTexture then
            hooksecurefunc(fillTex, "SetTexture", function(self)
                if settingTexture[bar] then return end
                EnforceFlatTexture(bar)
            end)
        end

        -- Hook SetValue — Blizzard calls this on health updates, can reset visuals
        hooksecurefunc(bar, "SetValue", function(self)
            EnforceFlatTexture(self)
        end)
    end
end

---------------------------------------------------------------------------
-- Skin Power Bar
---------------------------------------------------------------------------

local function SkinPowerBar(bar, unit, cfg)
    if not bar then return end

    SE:SkinStatusBar(bar)

    -- Alpha-zero ALL decorative texture regions on the bar
    local fillTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex then
            region:SetAlpha(0)
        end
    end

    -- Create background, remove Blizzard masks, size bar to match background
    CreateBarBackground(bar)
    RemoveBarMasks(bar)
    bar:SetSize(cfg.width, cfg.height)

    powerBarUnits[bar] = unit
    ApplyPowerColor(bar)

    if not hookedBars[bar] then
        hookedBars[bar] = true
        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            EnforceFlatTexture(self)
            ApplyPowerColor(self)
        end)
        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            ApplyPowerColor(self)
        end)

        -- Enforce our width when Blizzard resets it
        local enforceWidth = cfg.width
        hooksecurefunc(bar, "SetWidth", function(self, w)
            if w ~= enforceWidth then
                self:SetWidth(enforceWidth)
            end
        end)
    end

    -- Hide full-power glow and feedback
    if bar.FullPowerFrame then KillRegion(bar.FullPowerFrame) end
    if bar.FeedbackFrame then KillRegion(bar.FeedbackFrame) end

    -- Hook mana bar Hide/Show to toggle background visibility
    hooksecurefunc(bar, "Hide", function()
        local bg = barBgFrames[bar]
        if bg then bg:SetAlpha(0) end
    end)
    hooksecurefunc(bar, "Show", function()
        local bg = barBgFrames[bar]
        if bg then bg:SetAlpha(1) end
    end)
end

---------------------------------------------------------------------------
-- Resolve bars from frame hierarchy
---------------------------------------------------------------------------

local function GetBars(frame)
    local content = frame.PlayerFrameContent or frame.TargetFrameContent
    local contentMain = content and (content.PlayerFrameContentMain or content.TargetFrameContentMain)

    local healthBar
    if contentMain then
        local hbc = contentMain.HealthBarsContainer
        healthBar = hbc and hbc.HealthBar
    end
    if not healthBar then
        healthBar = frame.healthbar or frame.HealthBar
    end

    local manaBar
    if contentMain then
        if contentMain.ManaBarArea then
            manaBar = contentMain.ManaBarArea.ManaBar
        end
        if not manaBar then
            manaBar = contentMain.ManaBar
        end
    end
    if not manaBar then
        manaBar = frame.manabar or frame.ManaBar
    end

    return healthBar, manaBar, contentMain
end

---------------------------------------------------------------------------
-- Strip all texture regions from a frame (utility for thorough cleanup)
---------------------------------------------------------------------------

local function StripAllTextures(frame)
    if not frame then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

-- Persistently hide all textures and overlay children on HealthBarsContainer
local function StripHealthBarsContainer(hbc, healthBar)
    if not hbc then return end
    for i = 1, hbc:GetNumRegions() do
        local region = select(i, hbc:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            KillRegion(region)
        end
    end
    for i = 1, select("#", hbc:GetChildren()) do
        local child = select(i, hbc:GetChildren())
        if child and child ~= healthBar then
            KillRegion(child)
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "Texture" then
                    KillRegion(region)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Skin Player Frame
---------------------------------------------------------------------------

local function SkinPlayerFrame()
    local frame = PlayerFrame
    if not frame or skinnedFrames[frame] then return end
    skinnedFrames[frame] = true

    local container = frame.PlayerFrameContainer
    local content = frame.PlayerFrameContent
    local contentMain = content and content.PlayerFrameContentMain
    local contentContext = content and content.PlayerFrameContentContextual
    local healthBar, manaBar = GetBars(frame)

    -- Skin bars BEFORE reparenting container
    SkinHealthBar(healthBar, "player", BorderPositions.player.health)
    SkinPowerBar(manaBar, "player", BorderPositions.player.mana)

    -- Strip masks from parent containers that clip the bars
    if contentMain and contentMain.HealthBarsContainer then
        RemoveBarMasks(contentMain.HealthBarsContainer)
    end
    if contentMain and contentMain.ManaBarArea then
        RemoveBarMasks(contentMain.ManaBarArea)
    end

    -- Ensure backgrounds are visible
    if barBgFrames[healthBar] then barBgFrames[healthBar]:SetAlpha(1) end
    if barBgFrames[manaBar] then barBgFrames[manaBar]:SetAlpha(1) end

    -- Hide chrome: reparent container to hidden frame (purely decorative)
    if container then
        container:SetParent(hiddenFrame)
    end

    -- Hide contextual elements (rest, PvP, level, group icons)
    if contentContext then
        contentContext:SetAlpha(0)
        hooksecurefunc(contentContext, "SetAlpha", function(self, a)
            if a ~= 0 then self:SetAlpha(0) end
        end)
    end

    -- Hide individual elements
    if contentMain then
        KillRegion(contentMain.StatusTexture)
        if contentMain.HitIndicator then
            KillRegion(contentMain.HitIndicator)
        end
    end

    -- Hide threat indicators
    KillRegion(frame.threatIndicator)
    if frame.threatNumericIndicator then
        KillRegion(frame.threatNumericIndicator)
    end

    -- Hide selection highlight
    if frame.Selection then
        KillRegion(frame.Selection)
    end

    -- Strip HealthBarsContainer overlays
    if contentMain and contentMain.HealthBarsContainer then
        StripHealthBarsContainer(contentMain.HealthBarsContainer, healthBar)
    end

    -- Style name
    if frame.name then
        SE:StyleFont(frame.name)
    end
end

---------------------------------------------------------------------------
-- Skin Target Frame
---------------------------------------------------------------------------

local targetHealthBar, targetManaBar

local function SkinTargetFrame()
    local frame = TargetFrame
    if not frame or skinnedFrames[frame] then return end
    skinnedFrames[frame] = true

    local container = frame.TargetFrameContainer
    local content = frame.TargetFrameContent
    local contentMain = content and content.TargetFrameContentMain
    local contentContext = content and content.TargetFrameContentContextual
    local healthBar, manaBar = GetBars(frame)
    targetHealthBar = healthBar
    targetManaBar = manaBar

    -- Skin bars
    SkinHealthBar(healthBar, "target", BorderPositions.target.health)
    SkinPowerBar(manaBar, "target", BorderPositions.target.mana)

    -- Align mana bar directly under health bar
    if manaBar and healthBar then
        manaBar:ClearAllPoints()
        manaBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, BorderPositions.target.mana.startY)
    end

    -- Strip masks from parent containers that clip the bars
    if contentMain and contentMain.HealthBarsContainer then
        RemoveBarMasks(contentMain.HealthBarsContainer)
    end
    if contentMain and contentMain.ManaBarArea then
        RemoveBarMasks(contentMain.ManaBarArea)
    end

    -- Ensure backgrounds are visible
    if barBgFrames[healthBar] then barBgFrames[healthBar]:SetAlpha(1) end
    if barBgFrames[manaBar] then barBgFrames[manaBar]:SetAlpha(1) end

    -- Hide container art (aggressively kill FrameTexture — it bleeds through as name/level highlight)
    if container then
        container:SetAlpha(0)
        KillRegion(container.FrameTexture)
        KillRegion(container.Flash)
        KillRegion(container.FrameFlash)
        KillRegion(container.Portrait)
        KillRegion(container.PortraitMask)
        KillRegion(container.BossPortraitFrameTexture)
        KillRegion(container.AlternatePowerFrameTexture)
    end

    -- Hide contextual elements + HighLevelTexture (bright glow behind level)
    if contentContext then
        contentContext:SetAlpha(0)
        hooksecurefunc(contentContext, "SetAlpha", function(self, a)
            if a ~= 0 then self:SetAlpha(0) end
        end)
        KillRegion(contentContext.HighLevelTexture)
    end

    -- Hide individual elements
    if contentMain then
        KillRegion(contentMain.StatusTexture)
        KillRegion(contentMain.ReputationColor)
        -- Kill level text background if present
        if contentMain.LevelText then
            KillRegion(contentMain.LevelText)
        end
    end

    -- Hide threat indicators
    KillRegion(frame.threatIndicator)
    if frame.threatNumericIndicator then
        KillRegion(frame.threatNumericIndicator)
    end

    -- Hide selection highlight
    if frame.Selection then
        KillRegion(frame.Selection)
    end

    -- Strip ALL textures from content hierarchy (catches name background, etc.)
    StripAllTextures(content)
    StripAllTextures(contentMain)
    if contentMain and contentMain.HealthBarsContainer then
        StripHealthBarsContainer(contentMain.HealthBarsContainer, healthBar)
    end

    -- Style name
    if frame.name then
        SE:StyleFont(frame.name)
    end

    -- Hook CheckClassification — fires every target change
    hooksecurefunc(frame, "CheckClassification", function(self)
        -- Re-hide container art (Blizzard resets alpha on classification change)
        if container then
            container:SetAlpha(0)
            if container.FrameTexture then container.FrameTexture:SetAlpha(0) end
            if container.BossPortraitFrameTexture then container.BossPortraitFrameTexture:SetAlpha(0) end
        end

        -- Re-hide contextual elements
        if contentContext then
            contentContext:SetAlpha(0)
            if contentContext.HighLevelTexture then contentContext.HighLevelTexture:SetAlpha(0) end
        end

        -- Re-strip content textures (Blizzard may re-show name background, etc.)
        StripAllTextures(content)
        StripAllTextures(contentMain)

        -- Re-strip HealthBarsContainer overlays
        if contentMain and contentMain.HealthBarsContainer then
            StripHealthBarsContainer(contentMain.HealthBarsContainer, targetHealthBar)
        end

        -- Re-strip health bar children (AnimatedLossBar, absorb bars, etc.)
        -- Blizzard may re-show them on target change
        if targetHealthBar then
            local fillTex = targetHealthBar:GetStatusBarTexture()
            for i = 1, targetHealthBar:GetNumRegions() do
                local region = select(i, targetHealthBar:GetRegions())
                if region and region:GetObjectType() == "Texture" and region ~= fillTex then
                    KillRegion(region)
                end
            end
            for i = 1, select("#", targetHealthBar:GetChildren()) do
                local child = select(i, targetHealthBar:GetChildren())
                if child and child ~= barBgFrames[targetHealthBar] then
                    KillRegion(child)
                    for j = 1, child:GetNumRegions() do
                        local region = select(j, child:GetRegions())
                        if region and region:GetObjectType() == "Texture" then
                            KillRegion(region)
                        end
                    end
                end
            end
            -- Re-enforce flat texture
            EnforceFlatTexture(targetHealthBar)
        end

        -- Re-remove masks (Blizzard may re-add them on target change)
        if targetHealthBar then
            strippedMasks[targetHealthBar] = nil
            RemoveBarMasks(targetHealthBar)
        end
        if targetManaBar then
            strippedMasks[targetManaBar] = nil
            RemoveBarMasks(targetManaBar)

            -- Handle mana bar visibility for the background
            local bg = barBgFrames[targetManaBar]
            if bg then
                if not targetManaBar:IsShown() then
                    bg:SetAlpha(0)
                else
                    bg:SetAlpha(1)
                end
            end
        end

        -- Re-apply colors
        if targetHealthBar and UnitExists("target") then
            ApplyHealthColor(targetHealthBar)
        end
        if targetManaBar and UnitExists("target") then
            ApplyPowerColor(targetManaBar)
        end
    end)
end

---------------------------------------------------------------------------
-- Refresh colors on events
---------------------------------------------------------------------------

local function RefreshTargetColors()
    for bar, unit in pairs(frameUnits) do
        if unit == "target" and UnitExists("target") then
            ApplyHealthColor(bar)
        end
    end
    for bar, unit in pairs(powerBarUnits) do
        if unit == "target" and UnitExists("target") then
            ApplyPowerColor(bar)
        end
    end
end

---------------------------------------------------------------------------
-- Buff / Debuff (Aura) Skinning
---------------------------------------------------------------------------

local skinnedAuras = {}

local function SkinAuraButton(button)
    if not button or skinnedAuras[button] then return end
    skinnedAuras[button] = true

    local icon = button.Icon or button.icon

    -- Alpha-zero decorative textures (keep only the icon)
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= icon then
            region:SetAlpha(0)
        end
    end

    -- Remove masks for square corners
    if icon then
        for i = 1, button:GetNumRegions() do
            local region = select(i, button:GetRegions())
            if region and region:GetObjectType() == "MaskTexture" then
                icon:RemoveMaskTexture(region)
                region:Hide()
            end
        end
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Hide named border elements
    if button.Border then button.Border:SetAlpha(0) end
    if button.Stealable then button.Stealable:SetAlpha(0) end

    -- Flat backdrop behind icon
    local bd = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bd:SetAllPoints(button)
    bd:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    SE:ApplyBackdrop(bd)
end

local function SkinTargetAuras()
    for i = 1, 32 do
        local buff = _G["TargetFrameBuff" .. i]
        if buff then SkinAuraButton(buff) end
    end
    for i = 1, 16 do
        local debuff = _G["TargetFrameDebuff" .. i]
        if debuff then SkinAuraButton(debuff) end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function UnitFrameSkin:Apply()
    SkinPlayerFrame()
    SkinTargetFrame()

    -- Global hook: fires AFTER Blizzard's full health bar update (including color reset)
    -- This catches lockColor/desaturated/vertex-color recoloring that bypasses SetStatusBarColor
    hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar)
        if frameUnits[statusbar] then
            ApplyHealthColor(statusbar)
            EnforceFlatTexture(statusbar)
        end
    end)

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "target")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_TARGET_CHANGED" then
            RefreshTargetColors()
            C_Timer.After(0, SkinTargetAuras)
        elseif event == "UNIT_AURA" then
            C_Timer.After(0, SkinTargetAuras)
        elseif event == "UNIT_DISPLAYPOWER" then
            for bar, unit in pairs(powerBarUnits) do
                if unit == arg1 then
                    ApplyPowerColor(bar)
                end
            end
        end
    end)
end
