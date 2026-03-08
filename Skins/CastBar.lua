local _, ns = ...
local C = ns.C
local SE = ns.SkinEngine

local CastBarSkin = {}
ns.CastBarSkin = CastBarSkin

local skinnedBars = {}
local settingTexture = {}

local function StripGlowElements(castBar)
    -- Named glow/effect children that Blizzard re-applies via atlas
    local glowKeys = {
        "StandardGlow", "EnergyGlow", "EnergyMask", "ChargeFlash",
        "ChannelShadow", "BaseGlow", "WispGlow", "WispMask",
        "Shine", "CraftGlow",
    }
    for _, key in ipairs(glowKeys) do
        if castBar[key] then castBar[key]:SetAtlas(nil) end
    end

    -- Numbered particle children
    for i = 1, 3 do
        local flake = castBar["Flakes0" .. i]
        if flake then flake:SetAtlas(nil) end
    end
    for i = 1, 2 do
        local sparkle = castBar["Sparkles0" .. i]
        if sparkle then sparkle:SetAtlas(nil) end
    end

    -- Charge tier overlays
    for i = 1, 4 do
        local tier = castBar["ChargeTier" .. i]
        if tier then tier:Hide() end
    end
end

local function SkinCastBar(castBar)
    if not castBar or skinnedBars[castBar] then return end
    skinnedBars[castBar] = true

    -- Flat bar texture
    SE:SkinStatusBar(castBar)

    -- Alpha-zero all unnamed texture regions, preserve fill and icon
    local fillTex = castBar:GetStatusBarTexture()
    for i = 1, castBar:GetNumRegions() do
        local region = select(i, castBar:GetRegions())
        if region and region:GetObjectType() == "Texture"
           and region ~= fillTex
           and region ~= castBar.Icon then
            region:SetAlpha(0)
        end
    end

    -- Strip named glow/effect elements
    StripGlowElements(castBar)

    -- Hide named decorative elements
    if castBar.Border then castBar.Border:SetAlpha(0) end
    if castBar.BorderShield then castBar.BorderShield:SetAlpha(0) end
    if castBar.TextBorder then castBar.TextBorder:SetAlpha(0) end
    if castBar.Spark then castBar.Spark:SetAlpha(0) end
    if castBar.Flash then castBar.Flash:SetAlpha(0) end
    if castBar.Background then castBar.Background:SetAlpha(0) end

    -- Dark backdrop via child frame (no border)
    local bd = CreateFrame("Frame", nil, castBar, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(castBar:GetFrameLevel())
    SE:ApplyBackdrop(bd)

    -- Move spell text inside the bar (centered)
    if castBar.Text then
        castBar.Text:ClearAllPoints()
        castBar.Text:SetPoint("CENTER", castBar, "CENTER", 0, 0)
        local font, size = castBar.Text:GetFont()
        castBar.Text:SetFont(font, size, "OUTLINE")
    end

    -- Crop spell icon
    if castBar.Icon then castBar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    -- Enforce flat texture with re-entrancy guard
    hooksecurefunc(castBar, "SetStatusBarTexture", function(self)
        if settingTexture[self] then return end
        local tex = self:GetStatusBarTexture()
        if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
            settingTexture[self] = true
            self:SetStatusBarTexture(C.BAR_TEXTURE)
            settingTexture[self] = nil
        end
    end)

    -- Re-apply on every cast event (Blizzard resets text position and decorations)
    castBar:HookScript("OnEvent", function(self)
        StripGlowElements(self)
        if self.Border then self.Border:SetAlpha(0) end
        if self.TextBorder then self.TextBorder:SetAlpha(0) end
        if self.Background then self.Background:SetAlpha(0) end
        if self.Text then
            self.Text:ClearAllPoints()
            self.Text:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
    end)

    -- Keep border shield hidden if re-shown
    if castBar.BorderShield then
        hooksecurefunc(castBar.BorderShield, "Show", function(self)
            self:SetAlpha(0)
        end)
    end
end

function CastBarSkin:Apply()
    SkinCastBar(PlayerCastingBarFrame)
    SkinCastBar(PetCastingBarFrame)
end
