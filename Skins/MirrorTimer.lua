local _, ns = ...
local C = ns.C
local SE = ns.SkinEngine

local MirrorTimerSkin = {}
ns.MirrorTimerSkin = MirrorTimerSkin

local skinnedBars = {}
local settingTexture = {}

local timerColors = {
    BREATH     = { 0.0, 0.5, 1.0 },
    EXHAUSTION = { 1.0, 0.7, 0.0 },
    DEATH      = { 1.0, 0.2, 0.2 },
    FEIGNDEATH = { 1.0, 0.7, 0.0 },
}
local defaultColor = { 0.8, 0.8, 0.8 }

local function SkinMirrorBar(bar)
    if skinnedBars[bar] then return end
    skinnedBars[bar] = true

    local statusBar = bar.StatusBar

    -- Flat bar texture
    SE:SkinStatusBar(statusBar)

    -- Alpha-zero decorative textures on the bar frame
    if bar.Border then bar.Border:SetAlpha(0) end
    if bar.TextBorder then bar.TextBorder:SetAlpha(0) end

    -- Alpha-zero unnamed background textures
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end

    -- Dark backdrop via child frame anchored to the StatusBar
    local bd = CreateFrame("Frame", nil, statusBar, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(statusBar:GetFrameLevel())
    SE:ApplyBackdrop(bd)

    -- Style the timer text and center it on the bar
    if bar.Text then
        SE:StyleFont(bar.Text)
        bar.Text:ClearAllPoints()
        bar.Text:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
    end

    -- Enforce flat texture with re-entrancy guard
    hooksecurefunc(statusBar, "SetStatusBarTexture", function(self)
        if settingTexture[self] then return end
        local tex = self:GetStatusBarTexture()
        if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
            settingTexture[self] = true
            self:SetStatusBarTexture(C.BAR_TEXTURE)
            settingTexture[self] = nil
        end
    end)
end

local function ColorMirrorBar(bar, timer)
    local col = timerColors[timer] or defaultColor
    bar.StatusBar:SetStatusBarColor(col[1], col[2], col[3])
end

function MirrorTimerSkin:Apply()
    if not MirrorTimerContainer then return end

    -- Pre-skin all three timer frames
    for _, bar in ipairs(MirrorTimerContainer.mirrorTimers) do
        SkinMirrorBar(bar)
    end

    -- Apply color and ensure skinned on each timer activation
    hooksecurefunc(MirrorTimerContainer, "SetupTimer", function(self, timer)
        local bar = self:GetAvailableTimer(timer)
        if bar then
            SkinMirrorBar(bar)
            ColorMirrorBar(bar, timer)
        end
    end)
end
