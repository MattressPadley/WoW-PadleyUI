local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

-- Binding header/name globals (read by WoW's Key Bindings UI)
BINDING_HEADER_PADLEYUI = "PadleyUI"
BINDING_NAME_PADLEYUI_TOGGLE_ACTIONBAR_MOUSEOVER = "Toggle Action Bar Mouseover"
BINDING_NAME_PADLEYUI_TOGGLE_QUEST_TRACKER = "Toggle Quest Tracker"

local ActionBarSkin = {}
ns.ActionBarSkin = ActionBarSkin

-- External tracking table (avoids writing keys to Blizzard frames)
local skinnedButtons = {}
local mouseoverMode = false
local hookedBars = {}

local FADE_IN_TIME = 0.2
local FADE_OUT_TIME = 0.3
local FADE_OUT_DELAY = 0.15

local function FadeBar(bar, targetAlpha)
    if bar._padleyFading == targetAlpha then return end
    bar._padleyFading = targetAlpha
    if bar._padleyFadeTimer then bar._padleyFadeTimer:Cancel() end
    if targetAlpha == 1 then
        UIFrameFadeIn(bar, FADE_IN_TIME, bar:GetAlpha(), 1)
    else
        bar._padleyFadeTimer = C_Timer.NewTimer(FADE_OUT_DELAY, function()
            UIFrameFadeOut(bar, FADE_OUT_TIME, bar:GetAlpha(), 0)
            bar._padleyFadeTimer = nil
        end)
    end
end

-- All action bars and their button naming patterns
-- container = buttons are unnamed children of container frames (Patch 12.0+)
-- prefix    = buttons are direct globals by name
local ACTION_BARS = {
    { bar = "MainActionBar",       prefix = "ActionButton",             count = 12 },
    { bar = "MultiBarBottomLeft", prefix = "MultiBarBottomLeftButton", count = 12 },
    { bar = "MultiBarBottomRight",prefix = "MultiBarBottomRightButton",count = 12 },
    { bar = "MultiBarRight",      prefix = "MultiBarRightButton",      count = 12 },
    { bar = "MultiBarLeft",       prefix = "MultiBarLeftButton",       count = 12 },
    { bar = "MultiBar5",          prefix = "MultiBar5Button",          count = 12 },
    { bar = "MultiBar6",          prefix = "MultiBar6Button",          count = 12 },
    { bar = "MultiBar7",          prefix = "MultiBar7Button",          count = 12 },
    { bar = "StanceBar",          prefix = "StanceButton",             count = 10 },
    { bar = "PetActionBar",       prefix = "PetActionButton",          count = 10 },
}

-- Prevent double-hooking the same region
local persistedRegions = {}

-- Keep a texture region permanently hidden by hooking SetTexture/SetAtlas/SetAlpha
local function PersistAlphaZero(region)
    if persistedRegions[region] then return end
    persistedRegions[region] = true

    region:SetAlpha(0)
    hooksecurefunc(region, "SetTexture", function(self) self:SetAlpha(0) end)
    hooksecurefunc(region, "SetAtlas", function(self) self:SetAlpha(0) end)
    hooksecurefunc(region, "SetAlpha", function(self)
        if self:GetAlpha() ~= 0 then
            self:SetAlpha(0)
        end
    end)
end

-- Skin a single action button with flat/minimal style
local function SkinActionButton(button)
    if not button or skinnedButtons[button] then return end
    skinnedButtons[button] = true

    local buttonName = button:GetName()
    local icon = button.icon or button.Icon or (buttonName and _G[buttonName .. "Icon"])

    -- 1) Alpha-zero all texture regions persistently (hooks keep them hidden)
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= icon then
            PersistAlphaZero(region)
        end
    end

    -- 2) Restore the icon and crop for clean edges
    if icon then
        icon:SetAlpha(1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- 3) Remove rounded icon mask
    if button.IconMask then
        if icon then icon:RemoveMaskTexture(button.IconMask) end
        button.IconMask:Hide()
    end

    -- 4) Persistently hide named button art elements
    if button.Border then PersistAlphaZero(button.Border) end
    if button.SlotArt then PersistAlphaZero(button.SlotArt) end
    if button.SlotBackground then PersistAlphaZero(button.SlotBackground) end
    if button.RightDivider then button.RightDivider:Hide() end
    if button.BottomDivider then button.BottomDivider:Hide() end
    if button.NewActionTexture then PersistAlphaZero(button.NewActionTexture) end
    if button.BorderShadow then PersistAlphaZero(button.BorderShadow) end

    -- 5) Persistently hide NormalTexture (border graphic)
    local normalTex = button:GetNormalTexture()
    if normalTex then
        normalTex:SetTexture(0)
        PersistAlphaZero(normalTex)
    end

    -- 6) Persistently hide pushed and checked textures
    local pushedTex = button:GetPushedTexture()
    if pushedTex then PersistAlphaZero(pushedTex) end

    if button.GetCheckedTexture then
        local checkedTex = button:GetCheckedTexture()
        if checkedTex then PersistAlphaZero(checkedTex) end
    end

    -- 6) Restyle highlight with flat overlay
    local highlightTex = button:GetHighlightTexture()
    if highlightTex then
        highlightTex:SetTexture(C.BAR_TEXTURE)
        highlightTex:SetVertexColor(1, 1, 1, 0.25)
        if icon then
            highlightTex:SetAllPoints(icon)
        end
    end

    -- 7) Strip textures on child frames (bar 1 template has extra art children)
    --    Snapshot existing children BEFORE we add our backdrop
    local existingChildren = { button:GetChildren() }
    for _, child in ipairs(existingChildren) do
        if child and child.GetNumRegions then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "Texture" and region ~= icon then
                    PersistAlphaZero(region)
                end
            end
        end
    end

    -- 8) Child backdrop frame (never Mixin on Blizzard frames)
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:EnableMouse(false)

    -- 9) Style font strings
    local hotKey = button.HotKey or (buttonName and _G[buttonName .. "HotKey"])
    if hotKey then hotKey:SetAlpha(0) end

    local count = button.Count or (buttonName and _G[buttonName .. "Count"])
    SE:StyleFont(count, 12)

    -- Hide macro name text (clutters icon)
    local macroName = button.Name or (buttonName and _G[buttonName .. "Name"])
    if macroName and macroName.SetAlpha then
        macroName:SetAlpha(0)
    end

    -- Re-hide art that Blizzard may reapply via button:UpdateButtonArt()
    if button.UpdateButtonArt then
        hooksecurefunc(button, "UpdateButtonArt", function(btn)
            if btn.SlotArt then btn.SlotArt:SetAlpha(0) end
            if btn.SlotBackground then btn.SlotBackground:SetAlpha(0) end
            local nt = btn:GetNormalTexture()
            if nt then nt:SetAlpha(0) end
        end)
    end
end

-- Persistently strip all textures from a frame and children (skips skinned buttons)
local function PersistStripFrame(frame)
    if not frame or skinnedButtons[frame] then return end
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            PersistAlphaZero(region)
        end
    end
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and child.GetNumRegions then
            PersistStripFrame(child)
        end
    end
end

-- Strip ornamental art from the main bar area (containers, backgrounds, end caps)
local function StripMainBarArt()
    if not MainActionBar then return end

    for i = 1, select("#", MainActionBar:GetChildren()) do
        local child = select(i, MainActionBar:GetChildren())
        if child and child.GetNumRegions and not skinnedButtons[child] then
            PersistStripFrame(child)
        end
    end
end

-- Skin all buttons on a bar and strip bar-level textures
local function SkinBar(barDef)
    local bar = _G[barDef.bar]
    if not bar then return end

    -- Persistently strip bar-level decorative textures
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            PersistAlphaZero(region)
        end
    end

    for i = 1, barDef.count do
        local button = _G[barDef.prefix .. i]
        if button then
            SkinActionButton(button)
        end
    end
end

local function SkinAllBars()
    for _, barDef in ipairs(ACTION_BARS) do
        SkinBar(barDef)
    end
    StripMainBarArt()
end

-- Hook bar OnShow for Edit Mode toggling
local function HookBarVisibility()
    for _, barDef in ipairs(ACTION_BARS) do
        local bar = _G[barDef.bar]
        if bar then
            bar:HookScript("OnShow", function()
                SkinBar(barDef)
            end)
        end
    end
end

-- Apply mouseover alpha to all bars based on current mode (instant, no fade)
local function SetMouseoverMode(enabled)
    mouseoverMode = enabled
    for _, barDef in ipairs(ACTION_BARS) do
        local bar = _G[barDef.bar]
        if bar then
            if bar._padleyFadeTimer then bar._padleyFadeTimer:Cancel() end
            bar._padleyFading = nil
            UIFrameFadeRemoveFrame(bar)
            bar:SetAlpha(enabled and 0 or 1)
        end
    end
end

-- Hook enter/leave on bars and their buttons for mouseover fade
local function HookBarMouseover()
    for _, barDef in ipairs(ACTION_BARS) do
        local bar = _G[barDef.bar]
        if bar and not hookedBars[bar] then
            hookedBars[bar] = true

            bar:HookScript("OnEnter", function(self)
                if mouseoverMode then FadeBar(self, 1) end
            end)
            bar:HookScript("OnLeave", function(self)
                if mouseoverMode and not self:IsMouseOver() then FadeBar(self, 0) end
            end)

            -- Buttons are the actual mouse targets
            for i = 1, barDef.count do
                local button = _G[barDef.prefix .. i]
                if button then
                    button:HookScript("OnEnter", function()
                        if mouseoverMode and bar then FadeBar(bar, 1) end
                    end)
                    button:HookScript("OnLeave", function()
                        if mouseoverMode and bar and not bar:IsMouseOver() then FadeBar(bar, 0) end
                    end)
                end
            end
        end
    end
end

-- Global toggle function called by Bindings.xml
function PadleyUI_ToggleActionBarMouseover()
    mouseoverMode = not mouseoverMode
    if not PadleyUI_DB then PadleyUI_DB = {} end
    PadleyUI_DB.actionBarMouseover = mouseoverMode
    SetMouseoverMode(mouseoverMode)
end

function PadleyUI_ToggleQuestTracker()
    if not PadleyUI_DB then PadleyUI_DB = {} end
    local hidden = not PadleyUI_DB.questTrackerHidden
    PadleyUI_DB.questTrackerHidden = hidden
    if ObjectiveTrackerFrame then
        ObjectiveTrackerFrame:SetShown(not hidden)
    end
end

function ActionBarSkin:Apply()
    SkinAllBars()
    HookBarVisibility()

    -- Hook MainMenuBar art refresh (Edit Mode / login re-applies button art)
    if MainActionBar then
        if MainActionBar.UpdateButtonArt then
            hooksecurefunc(MainActionBar, "UpdateButtonArt", StripMainBarArt)
        end
        if MainActionBar.RefreshButtonArt then
            hooksecurefunc(MainActionBar, "RefreshButtonArt", StripMainBarArt)
        end
    end

    -- Deferred pass for late-initialized buttons
    C_Timer.After(0, SkinAllBars)

    -- Restore saved mouseover state
    if PadleyUI_DB and PadleyUI_DB.actionBarMouseover then
        mouseoverMode = true
    end

    -- Hook mouseover enter/leave on all bars, then apply saved state
    C_Timer.After(0, function()
        HookBarMouseover()
        SetMouseoverMode(mouseoverMode)
    end)

    -- Restore saved quest tracker state
    if PadleyUI_DB and PadleyUI_DB.questTrackerHidden and ObjectiveTrackerFrame then
        ObjectiveTrackerFrame:SetShown(false)
    end
end
