local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local PartyFrameSkin = {}
ns.PartyFrameSkin = PartyFrameSkin

-- External tracking tables (never write keys to Blizzard frames)
local skinnedFrames = {}
local hookedBars = {}
local barBackdrops = {}
local skinnedAuras = {}

-- Guard against recursive hook calls
local settingTexture = {}
local settingColor = {}

-- Spacing re-anchor state. CompactRaidFrame*/CompactPartyFrameMember* are
-- PROTECTED frames — re-anchoring them in combat raises ADDON_ACTION_BLOCKED,
-- so we queue the nudge and flush it on PLAYER_REGEN_ENABLED. spacedOffsets
-- records the offset we last applied per frame so we don't re-nudge (and double
-- the gap) when Blizzard hasn't reset the layout.
local spacedOffsets = {}
local spacingPending = false

---------------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------------

local function GetClassColor(unit)
    if not unit or not UnitExists(unit) then return 0.5, 0.5, 0.5 end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                return color.r, color.g, color.b
            end
        end
    end
    -- Fallback: reaction color for NPCs (pets, etc.)
    local r, g, b = UnitSelectionColor(unit)
    if r then return r, g, b end
    return 0.5, 0.5, 0.5
end

local function GetPowerColor(unit)
    if not unit or not UnitExists(unit) then return 0.0, 0.0, 1.0 end
    local _, powerToken = UnitPowerType(unit)
    local color = PowerBarColor[powerToken]
    if color then
        return color.r, color.g, color.b
    end
    return 0.0, 0.0, 1.0
end

local function CreateBarBackdrop(bar)
    -- Plain frame + SetColorTexture instead of BackdropTemplate to avoid
    -- secret-value taint (BackdropTemplate's SetupTextureCoordinates calls
    -- GetWidth() which returns a secret number on secure-parented frames).
    local bd = CreateFrame("Frame", nil, bar)
    bd:SetAllPoints()
    bd:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    local tex = bd:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    return bd
end

local function EnforceFlatTexture(bar)
    if settingTexture[bar] then return end
    local tex = bar:GetStatusBarTexture()
    if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
        settingTexture[bar] = true
        bar:SetStatusBarTexture(C.BAR_TEXTURE)
        settingTexture[bar] = nil
    end
end

local function RemoveMasksFromTexture(tex)
    if not tex or not tex.RemoveMaskTexture or not tex.GetMaskTextures then return end
    local masks = { tex:GetMaskTextures() }
    for _, mask in ipairs(masks) do
        tex:RemoveMaskTexture(mask)
        mask:Hide()
    end
end

local function RemoveBarMasks(bar)
    if not bar then return end
    if bar.GetStatusBarTexture then
        RemoveMasksFromTexture(bar:GetStatusBarTexture())
    end
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and (region:GetObjectType() == "Texture" or region:GetObjectType() == "MaskTexture") then
            RemoveMasksFromTexture(region)
        end
    end
end

---------------------------------------------------------------------------
-- Skin Health Bar
---------------------------------------------------------------------------

local function SkinHealthBar(frame)
    local bar = frame.healthBar
    if not bar then return end

    SE:SkinStatusBar(bar)
    RemoveBarMasks(bar)

    -- Alpha-zero all non-fill texture regions
    local fillTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex then
            region:SetAlpha(0)
        end
    end

    -- Backdrop behind bar
    if not barBackdrops[bar] then
        barBackdrops[bar] = CreateBarBackdrop(bar)
    end

    -- Apply class color
    local unit = frame.unit
    if unit and UnitExists(unit) then
        local r, g, b = GetClassColor(unit)
        settingColor[bar] = true
        bar:SetStatusBarColor(r, g, b)
        settingColor[bar] = nil
    end

    -- Hook for enforcement
    if not hookedBars[bar] then
        hookedBars[bar] = true

        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            EnforceFlatTexture(self)
        end)

        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            local u = frame.unit
            if u and UnitExists(u) then
                local r, g, b = GetClassColor(u)
                settingColor[self] = true
                self:SetStatusBarColor(r, g, b)
                settingColor[self] = nil
            end
        end)

        hooksecurefunc(bar, "SetValue", function(self)
            EnforceFlatTexture(self)
        end)
    end
end

---------------------------------------------------------------------------
-- Skin Power Bar
---------------------------------------------------------------------------

local function SkinPowerBar(frame)
    local bar = frame.powerBar
    if not bar then return end

    SE:SkinStatusBar(bar)
    RemoveBarMasks(bar)

    -- Alpha-zero all non-fill texture regions
    local fillTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex then
            region:SetAlpha(0)
        end
    end

    -- Backdrop behind bar
    if not barBackdrops[bar] then
        barBackdrops[bar] = CreateBarBackdrop(bar)
    end

    -- Apply power color
    local unit = frame.unit
    if unit and UnitExists(unit) then
        local r, g, b = GetPowerColor(unit)
        settingColor[bar] = true
        bar:SetStatusBarColor(r, g, b)
        settingColor[bar] = nil
    end

    -- Hook for enforcement
    if not hookedBars[bar] then
        hookedBars[bar] = true

        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            EnforceFlatTexture(self)
        end)

        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            local u = frame.unit
            if u and UnitExists(u) then
                local r, g, b = GetPowerColor(u)
                settingColor[self] = true
                self:SetStatusBarColor(r, g, b)
                settingColor[self] = nil
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Strip Chrome / Decorative Elements
---------------------------------------------------------------------------

local function StripChrome(frame)
    -- Alpha-zero background and highlights
    if frame.background then frame.background:SetAlpha(0) end
    if frame.aggroHighlight then frame.aggroHighlight:SetAlpha(0) end
    if frame.selectionHighlight then frame.selectionHighlight:SetAlpha(0) end
    -- Heal prediction / absorb overlays
    if frame.myHealPrediction then frame.myHealPrediction:SetAlpha(0) end
    if frame.otherHealPrediction then frame.otherHealPrediction:SetAlpha(0) end
    if frame.totalAbsorb then frame.totalAbsorb:SetAlpha(0) end
    if frame.totalAbsorbOverlay then frame.totalAbsorbOverlay:SetAlpha(0) end
    if frame.myHealAbsorb then frame.myHealAbsorb:SetAlpha(0) end
    if frame.myHealAbsorbLeftShadow then frame.myHealAbsorbLeftShadow:SetAlpha(0) end
    if frame.myHealAbsorbRightShadow then frame.myHealAbsorbRightShadow:SetAlpha(0) end
    if frame.overAbsorbGlow then frame.overAbsorbGlow:SetAlpha(0) end
    if frame.overHealAbsorbGlow then frame.overHealAbsorbGlow:SetAlpha(0) end

    -- Strip all decorative texture regions, but preserve icons Blizzard manages
    local preserve = {}
    if frame.roleIcon then preserve[frame.roleIcon] = true end
    if frame.readyCheckIcon then preserve[frame.readyCheckIcon] = true end
    if frame.centerStatusIcon then preserve[frame.centerStatusIcon] = true end

    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "Texture" and not preserve[region] then
            region:SetAlpha(0)
        end
    end

    -- Ensure the PartyMemberOverlay (leader crown, role, PvP icons) stays visible
    local overlay = frame.PartyMemberOverlay
    if overlay then
        overlay:SetAlpha(1)
        if overlay.LeaderIcon then overlay.LeaderIcon:SetAlpha(1) end
    end
end

---------------------------------------------------------------------------
-- Skin Aura Icons (Buffs/Debuffs)
---------------------------------------------------------------------------

local function SkinAuraIcon(button)
    if not button or skinnedAuras[button] then return end
    skinnedAuras[button] = true

    local icon = button.Icon or button.icon
    if not icon then return end

    -- Alpha-zero decorative textures (keep only the icon)
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= icon then
            region:SetAlpha(0)
        end
    end

    -- Remove masks for square corners
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "MaskTexture" then
            icon:RemoveMaskTexture(region)
            region:Hide()
        end
    end

    icon:SetTexCoord(unpack(C.ICON_CROP))

    -- Hide named border elements
    if button.Border then button.Border:SetAlpha(0) end
    if button.border then button.border:SetAlpha(0) end

    -- Plain frame + texture instead of BackdropTemplate to avoid secret-value taint
    local bd = CreateFrame("Frame", nil, button)
    bd:SetAllPoints(button)
    bd:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    local bgTex = bd:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
end

local function SkinAuraFrames(frame)
    if frame.buffFrames then
        for _, buff in ipairs(frame.buffFrames) do
            SkinAuraIcon(buff)
        end
    end
    if frame.debuffFrames then
        for _, debuff in ipairs(frame.debuffFrames) do
            SkinAuraIcon(debuff)
        end
    end
end

---------------------------------------------------------------------------
-- Style Name
---------------------------------------------------------------------------

local function StyleFontString(fs)
    if not fs or not fs.SetFont then return end
    SE:StyleFont(fs, nil, "")
    fs:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    fs:SetShadowColor(unpack(C.SHADOW_COLOR))
end

local function StyleName(frame)
    if frame.name then
        StyleFontString(frame.name)
    end
end

---------------------------------------------------------------------------
-- Per-Frame Skinning
---------------------------------------------------------------------------

local function SkinMemberFrame(frame)
    if not frame or skinnedFrames[frame] then return end
    skinnedFrames[frame] = true

    SkinHealthBar(frame)
    SkinPowerBar(frame)
    StripChrome(frame)
    StyleName(frame)
    SkinAuraFrames(frame)

    -- Hook CompactUnitFrame_UpdateAll on instance to re-apply visuals
    if frame.UpdateAll then
        hooksecurefunc(frame, "UpdateAll", function(self)
            -- Re-enforce flat textures
            if self.healthBar then
                EnforceFlatTexture(self.healthBar)
                RemoveBarMasks(self.healthBar)
            end
            if self.powerBar then
                EnforceFlatTexture(self.powerBar)
                RemoveBarMasks(self.powerBar)
            end
            StripChrome(self)
            SkinAuraFrames(self)
        end)
    end
end

---------------------------------------------------------------------------
-- Refresh colors (called on unit change)
---------------------------------------------------------------------------

local function RefreshColors(frame)
    if not frame or not frame.unit or not UnitExists(frame.unit) then return end

    if frame.healthBar then
        local r, g, b = GetClassColor(frame.unit)
        settingColor[frame.healthBar] = true
        frame.healthBar:SetStatusBarColor(r, g, b)
        settingColor[frame.healthBar] = nil
    end

    if frame.powerBar then
        local r, g, b = GetPowerColor(frame.unit)
        settingColor[frame.powerBar] = true
        frame.powerBar:SetStatusBarColor(r, g, b)
        settingColor[frame.powerBar] = nil
    end
end

---------------------------------------------------------------------------
-- Spacing
---------------------------------------------------------------------------

local function ApplySpacing(prefix, count)
    -- Never re-anchor protected raid/party frames during combat — every
    -- ClearAllPoints/SetPoint is blocked (ADDON_ACTION_BLOCKED). Queue it and
    -- flush once combat ends (PLAYER_REGEN_ENABLED).
    if InCombatLockdown() then
        spacingPending = true
        return
    end

    for i = 2, count do
        local frame = _G[prefix .. i]
        if not frame then break end
        local point, rel, relPoint, x, y = frame:GetPoint()
        if not point then break end

        -- Idempotent: if the frame is already at the offset we last applied,
        -- Blizzard hasn't reset the layout, so skip it. This avoids re-adding
        -- FRAME_SPACING every roster tick (which would compound the gap and
        -- thrash the layout).
        local last = spacedOffsets[frame]
        if not (last and last.point == point and last.rel == rel
                and last.relPoint == relPoint and last.x == x and last.y == y) then
            -- Determine axis from the anchor and nudge the offset
            local isVertical = (y ~= 0 and x == 0)
            local isHorizontal = (x ~= 0 and y == 0)
            local nx, ny = x, y

            if isVertical then
                local sign = y < 0 and -1 or 1
                ny = y + sign * C.FRAME_SPACING
            elseif isHorizontal then
                local sign = x < 0 and -1 or 1
                nx = x + sign * C.FRAME_SPACING
            end

            if nx ~= x or ny ~= y then
                frame:ClearAllPoints()
                frame:SetPoint(point, rel, relPoint, nx, ny)
                spacedOffsets[frame] = {
                    point = point, rel = rel, relPoint = relPoint, x = nx, y = ny,
                }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Frame Discovery
---------------------------------------------------------------------------

local function ScanPartyFrames()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            SkinMemberFrame(frame)
            RefreshColors(frame)
        end
    end
    ApplySpacing("CompactPartyFrameMember", 5)
end

local function ScanRaidFrames()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            SkinMemberFrame(frame)
            RefreshColors(frame)
        end
    end
    ApplySpacing("CompactRaidFrame", 40)
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

local function HideTitles()
    -- Party title
    if CompactPartyFrameTitle then
        CompactPartyFrameTitle:SetAlpha(0)
    end
    if CompactPartyFrame and CompactPartyFrame.title then
        CompactPartyFrame.title:SetAlpha(0)
    end
    -- Raid container chrome
    if CompactRaidFrameContainer and CompactRaidFrameContainer.title then
        CompactRaidFrameContainer.title:SetAlpha(0)
    end
    if CompactRaidFrameContainerBorderFrame then
        CompactRaidFrameContainerBorderFrame:SetAlpha(0)
    end
end

function PartyFrameSkin:Apply()
    HideTitles()

    -- Hook CompactUnitFrame_SetUnit to catch newly assigned party/raid frames
    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
        if not frame or not frame.GetName then return end
        local ok, name = pcall(frame.GetName, frame)
        if not ok or not name then return end
        if not name:find("^CompactPartyFrameMember") and not name:find("^CompactRaidFrame%d") then return end

        if not skinnedFrames[frame] then
            SkinMemberFrame(frame)
        end
        RefreshColors(frame)
    end)

    -- Event-driven discovery
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            -- Defer to next frame so Blizzard has time to create/assign frames
            C_Timer.After(0, function()
                ScanPartyFrames()
                ScanRaidFrames()
                HideTitles()
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Combat ended: flush any spacing re-anchor that was blocked in combat.
            if spacingPending then
                spacingPending = false
                C_Timer.After(0, function()
                    ApplySpacing("CompactPartyFrameMember", 5)
                    ApplySpacing("CompactRaidFrame", 40)
                end)
            end
        elseif event == "UNIT_DISPLAYPOWER" then
            -- Refresh power color when power type changes
            for i = 1, 5 do
                local frame = _G["CompactPartyFrameMember" .. i]
                if frame and frame.unit and frame.unit == arg1 then
                    if frame.powerBar then
                        local r, g, b = GetPowerColor(frame.unit)
                        settingColor[frame.powerBar] = true
                        frame.powerBar:SetStatusBarColor(r, g, b)
                        settingColor[frame.powerBar] = nil
                    end
                end
            end
            for i = 1, 40 do
                local frame = _G["CompactRaidFrame" .. i]
                if frame and frame.unit and frame.unit == arg1 then
                    if frame.powerBar then
                        local r, g, b = GetPowerColor(frame.unit)
                        settingColor[frame.powerBar] = true
                        frame.powerBar:SetStatusBarColor(r, g, b)
                        settingColor[frame.powerBar] = nil
                    end
                end
            end
        end
    end)

    -- Skin any frames already visible
    ScanPartyFrames()
    ScanRaidFrames()
end
