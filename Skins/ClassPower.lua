local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local ClassPowerSkin = {}
ns.ClassPowerSkin = ClassPowerSkin

---------------------------------------------------------------------------
-- Class → power type mapping
---------------------------------------------------------------------------

local CLASS_POWER_MAP = {
    PALADIN       = Enum.PowerType.HolyPower,
    MONK          = Enum.PowerType.Chi,
    ROGUE         = Enum.PowerType.ComboPoints,
    DRUID         = Enum.PowerType.ComboPoints,  -- cat form only
    WARLOCK       = Enum.PowerType.SoulShards,
    MAGE          = Enum.PowerType.ArcaneCharges, -- arcane spec only
    DEATHKNIGHT   = Enum.PowerType.Runes,
    EVOKER        = Enum.PowerType.Essence,
}

---------------------------------------------------------------------------
-- Power type → pip color
---------------------------------------------------------------------------

local POWER_COLORS = {
    [Enum.PowerType.HolyPower]     = { 0.95, 0.90, 0.60 },
    [Enum.PowerType.Chi]           = { 0.71, 1.00, 0.92 },
    [Enum.PowerType.ComboPoints]   = { 1.00, 0.61, 0.00 },
    [Enum.PowerType.SoulShards]    = { 0.58, 0.51, 0.79 },
    [Enum.PowerType.ArcaneCharges] = { 0.10, 0.57, 0.98 },
    [Enum.PowerType.Runes]         = { 0.50, 0.50, 0.50 },
    [Enum.PowerType.Essence]       = { 0.00, 0.80, 0.60 },
}

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local TOTAL_WIDTH = 250
local PIP_HEIGHT = 8
local PIP_GAP = 2

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local container       -- addon-owned parent frame
local pips = {}       -- indexed pip frames
local pipFills = {}   -- indexed fill textures
local activePower     -- current Enum.PowerType or nil
local activeMax = 0   -- current max pips
local activeColor     -- {r, g, b}
local _, playerClass = UnitClass("player")

---------------------------------------------------------------------------
-- Detect active class power type (handles Druid cat form, Arcane spec)
---------------------------------------------------------------------------

local function GetClassPowerType()
    local powerType = CLASS_POWER_MAP[playerClass]
    if not powerType then return nil end

    -- Druid: combo points only in Cat Form (shapeshift index 2)
    if playerClass == "DRUID" then
        local form = GetShapeshiftFormID()
        if form ~= CAT_FORM then return nil end
    end

    -- Mage: arcane charges only for Arcane spec (spec index 1)
    if playerClass == "MAGE" then
        local spec = GetSpecialization()
        if spec ~= 1 then return nil end
    end

    return powerType
end

---------------------------------------------------------------------------
-- Create container frame
---------------------------------------------------------------------------

local function CreateContainer()
    container = CreateFrame("Frame", "PadleyClassPowerFrame", UIParent)
    container:SetSize(TOTAL_WIDTH, PIP_HEIGHT)
    container:SetFrameStrata("LOW")
    container:SetClampedToScreen(true)
end

---------------------------------------------------------------------------
-- Create a single pip
---------------------------------------------------------------------------

local function CreatePip(index)
    local pip = CreateFrame("Frame", nil, container, "BackdropTemplate")
    pip:SetHeight(PIP_HEIGHT)
    SE:ApplyBackdrop(pip)

    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(C.BAR_TEXTURE)
    fill:SetAllPoints(pip)
    fill:Hide()

    pips[index] = pip
    pipFills[index] = fill
end

---------------------------------------------------------------------------
-- Layout pips for a given max count
---------------------------------------------------------------------------

local function LayoutPips(maxPower)
    if maxPower < 1 then return end

    -- Ensure we have enough pips
    for i = #pips + 1, maxPower do
        CreatePip(i)
    end

    local totalGap = PIP_GAP * (maxPower - 1)
    local pipWidth = (TOTAL_WIDTH - totalGap) / maxPower

    for i = 1, maxPower do
        local pip = pips[i]
        pip:ClearAllPoints()
        pip:SetWidth(pipWidth)

        if i == 1 then
            pip:SetPoint("LEFT", container, "LEFT", 0, 0)
        else
            pip:SetPoint("LEFT", pips[i - 1], "RIGHT", PIP_GAP, 0)
        end

        pip:Show()
    end

    -- Hide excess pips
    for i = maxPower + 1, #pips do
        pips[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- Color pips
---------------------------------------------------------------------------

local function ColorPips(color)
    for i = 1, #pipFills do
        pipFills[i]:SetVertexColor(color[1], color[2], color[3])
    end
end

---------------------------------------------------------------------------
-- Update pip fill states
---------------------------------------------------------------------------

local function UpdatePipStates()
    if not activePower then return end

    if activePower == Enum.PowerType.Runes then
        -- Runes: each pip tracks its own cooldown
        for i = 1, activeMax do
            if pipFills[i] then
                local start, duration, ready = GetRuneCooldown(i)
                if ready then
                    pipFills[i]:Show()
                else
                    pipFills[i]:Hide()
                end
            end
        end
    else
        local current = UnitPower("player", activePower)
        for i = 1, activeMax do
            if pipFills[i] then
                if i <= current then
                    pipFills[i]:Show()
                else
                    pipFills[i]:Hide()
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Full refresh: detect power type, layout, color, update states
---------------------------------------------------------------------------

local function FullRefresh()
    local powerType = GetClassPowerType()
    activePower = powerType

    if not powerType then
        if container then container:Hide() end
        return
    end

    local maxPower
    if powerType == Enum.PowerType.Runes then
        maxPower = 6
    else
        maxPower = UnitPowerMax("player", powerType)
    end

    if maxPower < 1 then
        container:Hide()
        return
    end

    activeMax = maxPower
    activeColor = POWER_COLORS[powerType] or { 1, 1, 1 }

    LayoutPips(maxPower)
    ColorPips(activeColor)
    UpdatePipStates()
    container:Show()
end

---------------------------------------------------------------------------
-- Attach to Blizzard class resource frame (for Edit Mode positioning)
---------------------------------------------------------------------------

local BLIZZARD_CLASS_FRAMES = {
    PALADIN       = "PaladinPowerBarFrame",
    MONK          = "MonkHarmonyBarFrame",
    WARLOCK       = "WarlockPowerFrame",
    MAGE          = "MageArcaneChargesFrame",
    DEATHKNIGHT   = "RuneFrame",
    EVOKER        = "EssencePlayerFrame",
    DRUID         = "DruidComboPointBarFrame",
    ROGUE         = "RogueComboPointBarFrame",
}

local classBarHidden = false
local attached = false

local function AttachToBlizzardFrame()
    -- Hide the player-frame class resource bar (once)
    if not classBarHidden then
        local frameName = BLIZZARD_CLASS_FRAMES[playerClass]
        local classFrame = frameName and _G[frameName]
        if classFrame then
            classBarHidden = true
            classFrame:SetAlpha(0)
            hooksecurefunc(classFrame, "SetAlpha", function(self, alpha)
                if alpha > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end

    -- Parent to Personal Resource Display (once)
    if attached then return end

    local prd = PersonalResourceDisplayFrame
    if prd then
        attached = true

        -- Hide PRD's own visuals but keep the frame alive for Edit Mode
        prd:SetAlpha(0)
        hooksecurefunc(prd, "SetAlpha", function(self, alpha)
            if alpha > 0 then
                self:SetAlpha(0)
            end
        end)

        container:SetParent(prd)
        container:SetIgnoreParentAlpha(true)
        container:ClearAllPoints()
        container:SetPoint("BOTTOM", prd, "BOTTOM", 0, 0)
        container:SetFrameStrata("LOW")
    else
        -- Fallback if PRD doesn't exist (disabled in settings)
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

local function OnEvent(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        AttachToBlizzardFrame()
        FullRefresh()
    elseif event == "UNIT_POWER_FREQUENT" then
        if arg1 == "player" then
            UpdatePipStates()
        end
    elseif event == "UNIT_MAXPOWER" then
        if arg1 == "player" then
            FullRefresh()
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        FullRefresh()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        FullRefresh()
    elseif event == "RUNE_POWER_UPDATE" then
        UpdatePipStates()
    elseif event == "UNIT_DISPLAYPOWER" then
        if arg1 == "player" then
            FullRefresh()
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function ClassPowerSkin:Apply()
    -- Skip classes without a secondary resource entirely
    if not CLASS_POWER_MAP[playerClass] then return end

    CreateContainer()

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")

    -- DK runes have their own event
    if playerClass == "DEATHKNIGHT" then
        eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    end

    eventFrame:SetScript("OnEvent", OnEvent)

    -- Try initial attachment (Blizzard frame may already exist)
    AttachToBlizzardFrame()
    FullRefresh()
end
