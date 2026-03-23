local _, ns = ...
local C = ns.C
local SE = ns.SkinEngine

local EncounterBarSkin = {}
ns.EncounterBarSkin = EncounterBarSkin

local skinnedWidgets = {}
local settingTexture = {}

local function SkinWidgetBar(widget)
    if skinnedWidgets[widget] then return end
    if widget:IsForbidden() then return end

    local bar = widget.Bar
    if not bar then return end

    skinnedWidgets[widget] = true

    -- Alpha-zero 3-piece background
    if bar.BGLeft then bar.BGLeft:SetAlpha(0) end
    if bar.BGRight then bar.BGRight:SetAlpha(0) end
    if bar.BGCenter then bar.BGCenter:SetAlpha(0) end

    -- Alpha-zero 3-piece border
    if bar.BorderLeft then bar.BorderLeft:SetAlpha(0) end
    if bar.BorderRight then bar.BorderRight:SetAlpha(0) end
    if bar.BorderCenter then bar.BorderCenter:SetAlpha(0) end

    -- Alpha-zero spark
    if bar.Spark then bar.Spark:SetAlpha(0) end

    -- Flat bar texture (preserve Blizzard colors)
    SE:SkinStatusBar(bar)

    -- Dark backdrop via child frame
    local bd = CreateFrame("Frame", nil, bar)
    bd:SetAllPoints()
    bd:SetFrameLevel(bar:GetFrameLevel())
    local bgTex = bd:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Style label text
    if widget.Label then SE:StyleFont(widget.Label) end
    if bar.Label then SE:StyleFont(bar.Label) end

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

function EncounterBarSkin:Apply()
    if not UIWidgetPowerBarContainerFrame then return end

    -- Skin any existing widget bars
    if UIWidgetPowerBarContainerFrame.widgetFrames then
        for _, widget in pairs(UIWidgetPowerBarContainerFrame.widgetFrames) do
            SkinWidgetBar(widget)
        end
    end

    -- Hook ProcessWidget on the container INSTANCE (safe — never hook mixin tables)
    if UIWidgetPowerBarContainerFrame.ProcessWidget then
        hooksecurefunc(UIWidgetPowerBarContainerFrame, "ProcessWidget", function(self, widgetID)
            local widget = self.widgetFrames and self.widgetFrames[widgetID]
            if widget then
                SkinWidgetBar(widget)
            end
        end)
    else
        -- Fallback: event-based approach (no hooks on Blizzard frames at all)
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
        eventFrame:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
        eventFrame:SetScript("OnEvent", function()
            if UIWidgetPowerBarContainerFrame.widgetFrames then
                for _, widget in pairs(UIWidgetPowerBarContainerFrame.widgetFrames) do
                    SkinWidgetBar(widget)
                end
            end
        end)
    end
end
