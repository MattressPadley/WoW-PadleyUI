local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local StatusBarSkin = {}
ns.StatusBarSkin = StatusBarSkin

-- External tracking table (avoids writing keys to Blizzard frames)
local skinnedBars = {}

local NUM_TICKS = 19  -- 20 segments = 19 dividers

-- Default bar color (matches Blizzard XP bar blue)
local XP_BAR_COLOR = { 0.0, 0.39, 0.88, 1 }
local RESTED_XP_BAR_COLOR = { 0.0, 0.39, 0.88, 0.35 }

---------------------------------------------------------------------------
-- Find the StatusBar child of a bar slot frame (by object type, not key)
---------------------------------------------------------------------------

local function FindStatusBar(frame)
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and child:GetObjectType() == "StatusBar" then
            return child
        end
    end
end

---------------------------------------------------------------------------
-- Create flat tick marks on a bar
---------------------------------------------------------------------------

local function CreateTicks(parent, statusBar)
    local tickFrame = CreateFrame("Frame", nil, parent)
    tickFrame:SetAllPoints(statusBar)
    tickFrame:SetFrameLevel(statusBar:GetFrameLevel() + 2)

    for i = 1, NUM_TICKS do
        local tick = tickFrame:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(C.BAR_TEXTURE)
        tick:SetVertexColor(0, 0, 0, 0.6)
        tick:SetWidth(1)
        tick:SetPoint("TOP", tickFrame, "TOPLEFT", 0, 0)
        tick:SetPoint("BOTTOM", tickFrame, "BOTTOMLEFT", 0, 0)

        -- Position each tick at i/20 of the bar width
        tickFrame:HookScript("OnSizeChanged", function(self)
            local w = self:GetWidth()
            tick:ClearAllPoints()
            tick:SetPoint("TOP", self, "TOPLEFT", w * (i / (NUM_TICKS + 1)), 0)
            tick:SetPoint("BOTTOM", self, "BOTTOMLEFT", w * (i / (NUM_TICKS + 1)), 0)
        end)
    end

    -- Trigger initial positioning
    C_Timer.After(0, function()
        local w = tickFrame:GetWidth()
        if w and w > 0 then
            for idx = 1, NUM_TICKS do
                local tick = select(idx, tickFrame:GetRegions())
                if tick then
                    tick:ClearAllPoints()
                    tick:SetPoint("TOP", tickFrame, "TOPLEFT", w * (idx / (NUM_TICKS + 1)), 0)
                    tick:SetPoint("BOTTOM", tickFrame, "BOTTOMLEFT", w * (idx / (NUM_TICKS + 1)), 0)
                end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Force flat texture on a StatusBar (handles atlas override)
---------------------------------------------------------------------------

local function FlattenStatusBar(statusBar)
    -- Clear any atlas on the fill texture so our flat texture takes effect
    local fillTexture = statusBar:GetStatusBarTexture()
    if fillTexture then
        fillTexture:SetAtlas("")
        fillTexture:SetTexture(C.BAR_TEXTURE)
    end

    -- Set flat texture and blue color via the StatusBar API
    statusBar:SetStatusBarTexture(C.BAR_TEXTURE)
    statusBar:SetStatusBarColor(XP_BAR_COLOR[1], XP_BAR_COLOR[2], XP_BAR_COLOR[3], XP_BAR_COLOR[4])

    -- Hook SetStatusBarTexture to persist flat texture
    hooksecurefunc(statusBar, "SetStatusBarTexture", function(self)
        local tex = self:GetStatusBarTexture()
        if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
            tex:SetAtlas("")
            tex:SetTexture(C.BAR_TEXTURE)
        end
    end)

    -- Hook SetStatusBarAtlas to block atlas re-application
    if statusBar.SetStatusBarAtlas then
        hooksecurefunc(statusBar, "SetStatusBarAtlas", function(self)
            local tex = self:GetStatusBarTexture()
            if tex then
                tex:SetAtlas("")
                tex:SetTexture(C.BAR_TEXTURE)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Rested XP overlay texture on an XP StatusBar
---------------------------------------------------------------------------

local function CreateRestedOverlay(statusBar)
    local overlay = statusBar:CreateTexture(nil, "ARTWORK", nil, -1)
    overlay:SetTexture(C.BAR_TEXTURE)
    overlay:SetVertexColor(RESTED_XP_BAR_COLOR[1], RESTED_XP_BAR_COLOR[2], RESTED_XP_BAR_COLOR[3], RESTED_XP_BAR_COLOR[4])
    overlay:Hide()

    local function UpdateRested()
        local exhaustion = GetXPExhaustion()
        if not exhaustion or exhaustion <= 0 then
            overlay:Hide()
            return
        end

        local currXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        if not maxXP or maxXP <= 0 then
            overlay:Hide()
            return
        end

        -- Only show on the XP bar (verify bar values match player XP)
        local barVal = statusBar:GetValue()
        local _, barMax = statusBar:GetMinMaxValues()
        if barMax ~= maxXP or barVal ~= currXP then
            overlay:Hide()
            return
        end

        local barWidth = statusBar:GetWidth()
        if not barWidth or barWidth <= 0 then
            overlay:Hide()
            return
        end

        local startFrac = currXP / maxXP
        local endFrac = math.min((currXP + exhaustion) / maxXP, 1.0)

        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", statusBar, "TOPLEFT", barWidth * startFrac, 0)
        overlay:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMLEFT", barWidth * endFrac, 0)
        overlay:Show()
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    eventFrame:SetScript("OnEvent", UpdateRested)

    statusBar:HookScript("OnSizeChanged", UpdateRested)

    C_Timer.After(0, UpdateRested)
end

---------------------------------------------------------------------------
-- Individual tracking bar slot skinning
---------------------------------------------------------------------------

local function SkinBarSlot(slot)
    if not slot or skinnedBars[slot] then return end

    local statusBar = FindStatusBar(slot)
    if not statusBar then return end

    skinnedBars[slot] = true

    -- Alpha-zero all texture regions on the slot frame
    for i = 1, slot:GetNumRegions() do
        local region = select(i, slot:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end

    -- Alpha-zero textures on all child frames (overlay, button, etc.)
    for i = 1, select("#", slot:GetChildren()) do
        local child = select(i, slot:GetChildren())
        if child and child:GetObjectType() == "Frame" then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "Texture" then
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Alpha-zero the StatusBar's own background/overlay textures
    for i = 1, statusBar:GetNumRegions() do
        local region = select(i, statusBar:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            if region ~= statusBar:GetStatusBarTexture() then
                region:SetAlpha(0)
            end
        end
    end

    -- Force flat texture on the StatusBar
    FlattenStatusBar(statusBar)

    -- Rested XP overlay (only visible when this bar is the XP bar)
    CreateRestedOverlay(statusBar)

    -- Child backdrop frame (avoids Mixin on Blizzard frames)
    local bdFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(slot:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:EnableMouse(false)

    -- Add flat tick marks
    CreateTicks(slot, statusBar)
end

---------------------------------------------------------------------------
-- Skin all bar slots on the container
---------------------------------------------------------------------------

local function SkinAllBars(container)
    for i = 1, select("#", container:GetChildren()) do
        local child = select(i, container:GetChildren())
        if child then
            SkinBarSlot(child)
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function StatusBarSkin:Apply()
    local container = MainStatusTrackingBarContainer
    if not container then return end

    -- Strip container-level textures
    for i = 1, container:GetNumRegions() do
        local region = select(i, container:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end

    -- Skin existing bar slots
    SkinAllBars(container)

    -- Hook the manager to catch dynamic bar changes (XP → Rep, etc.)
    local manager = StatusTrackingBarManager
    if manager and manager.UpdateBarsShown then
        hooksecurefunc(manager, "UpdateBarsShown", function()
            SkinAllBars(container)
        end)
    end
end
