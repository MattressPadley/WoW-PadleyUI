local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local DamageMeterSkin = {}
ns.DamageMeterSkin = DamageMeterSkin

-- Track skinned frames externally (avoids writing keys to Blizzard frames)
local skinnedWindows = {}
local buttonDecorations = {}

---------------------------------------------------------------------------
-- Window background helpers
--
-- Blizzard's window background/border art has moved fields across 12.0.x
-- patches (the same field->method restructure that removed ScrollBox). Hide
-- every candidate region that exists so only our flat backdrop shows, instead
-- of relying on a single field name that can go stale (which left Blizzard's
-- background stacked behind ours).
---------------------------------------------------------------------------

local BLIZZARD_BG_FIELDS = { "NineSlice", "Background", "Bg", "Border", "Header" }

local function HideBlizzardBackground(frame)
    for _, key in ipairs(BLIZZARD_BG_FIELDS) do
        local region = frame[key]
        if region and region.SetAlpha then
            region:SetAlpha(0)
            -- Only textures get their atlas/texture cleared + Hide; NineSlice is
            -- a container frame, so alpha-0 alone (layout-preserving) is enough.
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                if region.SetAtlas then region:SetAtlas("") end
                if region.SetTexture then region:SetTexture(nil) end
                region:Hide()
            end
        end
    end
end

-- Flat backdrop via a plain frame + texture (NOT BackdropTemplate). SetAllPoints
-- on a Blizzard window means BackdropTemplate's SetupTextureCoordinates would do
-- arithmetic on the window's GetWidth(), which is a secret value during
-- encounters -> taint. A plain texture anchors at the C level. Mirrors Tooltip.
local function ApplyFlatWindowBackdrop(frame)
    local bdFrame = CreateFrame("Frame", nil, frame)
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(frame:GetFrameLevel())
    local tex = bdFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    local bgc = C.BACKDROP_COLOR
    tex:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
    return bdFrame
end

---------------------------------------------------------------------------
-- Entry Bars
---------------------------------------------------------------------------

-- Locate the row's StatusBar. Prefer the documented `.StatusBar` field, but
-- fall back to structural discovery so a 12.0.x field rename doesn't silently
-- leave bars unskinned. Mirrors CooldownTracker.lua's FindStatusBar idiom.
local function FindEntryStatusBar(entry)
    -- Documented field (fast path — identical behaviour when it still exists).
    local sb = entry.StatusBar
    if sb and sb.GetObjectType and sb:GetObjectType() == "StatusBar" then
        return sb
    end
    -- The row itself might be the StatusBar in a reworked layout.
    if entry.GetObjectType and entry:GetObjectType() == "StatusBar" then
        return entry
    end
    -- Otherwise scan direct children for the fill bar.
    if entry.GetChildren then
        for i = 1, select("#", entry:GetChildren()) do
            local child = select(i, entry:GetChildren())
            if child and child.GetObjectType and child:GetObjectType() == "StatusBar" then
                return child
            end
        end
    end
end

local function SkinEntry(entry)
    if not entry then return end
    local statusBar = FindEntryStatusBar(entry)
    if not statusBar then return end

    -- Always re-apply flat texture (SetStyle resets it during Init)
    statusBar:SetStatusBarTexture(C.BAR_TEXTURE)

    -- NOTE: Do NOT call StyleFont on statusBar.Name or statusBar.Value.
    -- These FontStrings are read during secure Init/Refresh execution;
    -- tainting them causes GetText() to return secret values.

    -- Hide the shadow background and edge regions
    local bgRegions = statusBar.BackgroundRegions
    if bgRegions then
        for _, region in ipairs(bgRegions) do
            region:SetAtlas("")
            region:SetTexture(nil)
            region:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Entry iteration / hook wiring
--
-- A 12.0.x patch moved the session window from FIELD access (window.ScrollBox,
-- window.LocalPlayerEntry) to METHOD access (window:SetupEntry,
-- window:ForEachEntryFrame, window:GetLocalPlayerEntry). SkinEntry is now
-- reached through those methods; every call is guarded so a future structure
-- change fails soft instead of erroring.
---------------------------------------------------------------------------

-- Skin whichever argument is a Frame. Defensive against SetupEntry's exact
-- signature (self is the explicit first param, so it is never in ...).
local function SkinFrameArgs(...)
    for i = 1, select("#", ...) do
        local arg = select(i, ...)
        if type(arg) == "table" and arg.IsObjectType and arg:IsObjectType("Frame") then
            SkinEntry(arg)
        end
    end
end

local function WireEntrySkinning(window)
    if not window then return end

    -- Primary re-skin trigger: Blizzard calls SetupEntry per row when it builds
    -- or refreshes an entry. Hook the instance and skin the entry frame it hands
    -- us. Only applies textures (SkinEntry reads no values), so it is safe on
    -- this potentially-secure path.
    if window.SetupEntry then
        hooksecurefunc(window, "SetupEntry", function(self, ...)
            SkinFrameArgs(...)
        end)
    end

    -- Initial sweep for rows that already exist at install time.
    if window.ForEachEntryFrame then
        window:ForEachEntryFrame(function(...)
            SkinFrameArgs(...)
        end)
    end

    -- Local player row (fixed bar). SetupEntry covers its subsequent refreshes.
    if window.GetLocalPlayerEntry then
        local localEntry = window:GetLocalPlayerEntry()
        if localEntry then
            SkinEntry(localEntry)
        end
    end
end

---------------------------------------------------------------------------
-- Source / Detail Window
---------------------------------------------------------------------------

local function SkinSourceWindow(sourceWindow)
    if not sourceWindow or skinnedWindows[sourceWindow] then return end
    skinnedWindows[sourceWindow] = true

    -- Hide Blizzard's own background/border, then apply our flat one.
    HideBlizzardBackground(sourceWindow)
    ApplyFlatWindowBackdrop(sourceWindow)

    -- Skin spell entry bars in the source window (method-based API).
    WireEntrySkinning(sourceWindow)
end

---------------------------------------------------------------------------
-- Session Window
---------------------------------------------------------------------------

local function SkinSessionWindow(window)
    if skinnedWindows[window] then return end
    skinnedWindows[window] = true

    -- Hide Blizzard's own background/border/header, then apply our flat one.
    HideBlizzardBackground(window)
    ApplyFlatWindowBackdrop(window)

    -- NOTE: Do NOT call StyleFont on window.NotActive or window.SessionTimer.
    -- These FontStrings are read during secure Refresh execution.

    -- Skin the dropdown buttons (no SetHeight — triggers layout cascades that
    -- cause Refresh to re-enter in our tainted context, producing secret values)
    local settingsDD = window.SettingsDropdown
    if settingsDD then
        SE:SkinDropdownButton(settingsDD)
        if not buttonDecorations[settingsDD] then
            local icon = settingsDD:CreateTexture(nil, "ARTWORK")
            icon:SetAtlas("GM-icon-settings")
            icon:SetSize(14, 14)
            icon:SetPoint("CENTER")
            buttonDecorations[settingsDD] = icon
        end
    end

    local sessionDD = window.SessionDropdown
    if sessionDD then
        SE:SkinDropdownButton(sessionDD)
        -- NOTE: Do NOT call StyleFont on sessionDD.SessionName — read during secure Refresh.
    end

    local typeDD = window.DamageMeterTypeDropdown
    if typeDD then
        SE:SkinDropdownButton(typeDD)
        -- NOTE: Do NOT call StyleFont on typeDD.TypeName — read during secure Refresh.
        if not buttonDecorations[typeDD] then
            local arrow = typeDD:CreateTexture(nil, "ARTWORK")
            arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Down")
            arrow:SetSize(10, 10)
            arrow:SetPoint("CENTER")
            arrow:SetVertexColor(0.8, 0.8, 0.8, 1)
            buttonDecorations[typeDD] = arrow
        end
    end

    -- NOTE: Do NOT reposition window.NotActive or window.SessionTimer.
    -- Their layout state is read during secure Refresh execution; tainting
    -- position properties causes the entire Refresh context to become tainted,
    -- making combat API data return as secret values.

    -- Style the resize button
    local resize = window.ResizeButton
    if resize then
        local normalTex = resize:GetNormalTexture()
        if normalTex then
            normalTex:SetAlpha(0.3)
        end
    end

    -- Wire up entry bar skinning via the method-based API. Blizzard manages the
    -- scroll area's layout internally now (the old ScrollBox / LocalPlayerEntry
    -- fields were removed), so we no longer custom-anchor it — we only skin the
    -- rows Blizzard lays out.
    WireEntrySkinning(window)

    -- Skin the source window
    local sourceWindow = window.SourceWindow
    if sourceWindow then
        SkinSourceWindow(sourceWindow)
    end
end

---------------------------------------------------------------------------
-- Hook Installation
---------------------------------------------------------------------------

function DamageMeterSkin:Apply()
    local dmFrame = DamageMeter

    -- CRITICAL: Only hook INSTANCES, never mixin tables.
    --
    -- When hooksecurefunc is used on a mixin table (e.g. DamageMeterEntryMixin),
    -- Mixin() copies the hooked function to new instances as a plain Lua value.
    -- securecallfunction doesn't recognise the copy as a proper hooksecurefunc
    -- wrapper, so the entire function — including the original — runs insecurely.
    -- On an insecure execution path the Secret Values system (Patch 12.0) returns
    -- combat API data as un-comparable "secret" values, causing taint errors.
    --
    -- Instance hooks work correctly because the C-level hooksecurefunc wrapper
    -- lives directly on the frame, where securecallfunction can identify it and
    -- properly isolate the hook's taint from the original function's execution.

    if dmFrame and dmFrame.SetupSessionWindow then
        hooksecurefunc(dmFrame, "SetupSessionWindow", function(self, windowData, windowIndex)
            local window = windowData and windowData.sessionWindow
            if window then
                SkinSessionWindow(window)
            end
        end)
    end

    -- Skin any session windows that already exist
    if dmFrame and dmFrame.windowDataList then
        for _, windowData in ipairs(dmFrame.windowDataList) do
            if windowData.sessionWindow then
                SkinSessionWindow(windowData.sessionWindow)
            end
        end
    end

    print("|cff00ccffPadleyUI|r: Damage Meter skin applied")
end
