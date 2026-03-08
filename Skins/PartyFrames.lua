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

-- Borderless backdrop definition (flat, no edge)
local FLAT_BG = { bgFile = C.FLAT_BACKDROP.bgFile }

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
    local bd = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    bd:SetBackdrop(FLAT_BG)
    bd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
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
    if frame.roleIcon then frame.roleIcon:SetAlpha(0) end

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

    -- Strip all decorative texture regions from the frame itself
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            -- Keep the background region reference but alpha-zero it
            region:SetAlpha(0)
        end
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

    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Hide named border elements
    if button.Border then button.Border:SetAlpha(0) end
    if button.border then button.border:SetAlpha(0) end

    -- Flat backdrop behind icon
    local bd = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bd:SetAllPoints(button)
    bd:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    SE:ApplyBackdrop(bd)
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
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
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
end

local function ScanRaidFrames()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            SkinMemberFrame(frame)
            RefreshColors(frame)
        end
    end
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
        if not frame then return end
        local name = frame:GetName()
        if not name then return end
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
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            -- Defer to next frame so Blizzard has time to create/assign frames
            C_Timer.After(0, function()
                ScanPartyFrames()
                ScanRaidFrames()
                HideTitles()
            end)
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
