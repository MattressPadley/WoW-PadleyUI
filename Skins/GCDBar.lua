local _, ns = ...
local C = ns.C
local SE = ns.SkinEngine

local GCDBarSkin = {}
ns.GCDBarSkin = GCDBarSkin

local GCD_SPELL_ID = 61304
local GCD_COLOR = { 1, 1, 1 }
local BAR_HEIGHT = 4
local BAR_OFFSET_Y = -2

function GCDBarSkin:Apply()
    -- Create the status bar anchored below PlayerCastingBarFrame
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetPoint("TOPLEFT", PlayerCastingBarFrame, "BOTTOMLEFT", 0, BAR_OFFSET_Y)
    bar:SetPoint("TOPRIGHT", PlayerCastingBarFrame, "BOTTOMRIGHT", 0, BAR_OFFSET_Y)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:Hide()

    SE:SkinStatusBar(bar, { color = GCD_COLOR })

    -- Dark backdrop via child frame
    local bd = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(bar:GetFrameLevel())
    SE:ApplyBackdrop(bd)

    -- GCD state
    local gcdStart = 0
    local gcdDuration = 0

    -- OnUpdate: drain bar from 1 to 0
    bar:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - gcdStart
        local progress = 1 - (elapsed / gcdDuration)
        if progress <= 0 then
            self:Hide()
            return
        end
        self:SetValue(progress)
    end)

    -- Event handler
    local events = CreateFrame("Frame")
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    events:SetScript("OnEvent", function()
        local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
        if not info or info.duration == 0 or info.duration > 1.5 then
            return
        end

        local duration = info.duration
        if info.modRate and info.modRate > 0 then
            duration = duration / info.modRate
        end

        gcdStart = info.startTime
        gcdDuration = duration
        bar:SetValue(1)
        bar:Show()
    end)
end
