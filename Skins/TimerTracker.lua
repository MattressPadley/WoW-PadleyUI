local _, ns = ...
local C = ns.C
local SE = ns.SkinEngine

local TimerTrackerSkin = {}
ns.TimerTrackerSkin = TimerTrackerSkin

local skinnedBars = {}
local settingTexture = {}

local function SkinTimerBar(bar)
    if skinnedBars[bar] then return end
    skinnedBars[bar] = true

    -- Alpha-zero decorative textures, style any text
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region then
            local objType = region:GetObjectType()
            if objType == "Texture" then
                region:SetAlpha(0)
            elseif objType == "FontString" then
                SE:StyleFont(region)
            end
        end
    end

    -- Flat bar texture (preserve Blizzard colors)
    SE:SkinStatusBar(bar)

    -- Dark backdrop via child frame behind the bar fill
    local bd = CreateFrame("Frame", nil, bar)
    bd:SetAllPoints()
    bd:SetFrameLevel(0)
    local bgTex = bd:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Enforce flat texture with re-entrancy guard
    hooksecurefunc(bar, "SetStatusBarTexture", function(self)
        if settingTexture[self] then return end
        local tex = self:GetStatusBarTexture()
        if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
            settingTexture[self] = true
            self:SetStatusBarTexture(C.BAR_TEXTURE)
            settingTexture[self] = nil
        end
    end)
end

local function SkinExisting()
    if not TimerTracker or not TimerTracker.timerList then return end
    for _, entry in pairs(TimerTracker.timerList) do
        if entry.bar then
            SkinTimerBar(entry.bar)
        end
    end
end

function TimerTrackerSkin:Apply()
    if not TimerTracker then return end

    SkinExisting()

    -- Catch newly created timer bars via event
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("START_TIMER")
    eventFrame:SetScript("OnEvent", SkinExisting)
end
