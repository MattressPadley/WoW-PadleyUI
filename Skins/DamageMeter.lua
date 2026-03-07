local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local DamageMeterSkin = {}
ns.DamageMeterSkin = DamageMeterSkin

-- Track skinned frames externally (avoids writing keys to Blizzard frames)
local skinnedWindows = {}
local buttonDecorations = {}

---------------------------------------------------------------------------
-- Entry Bars
---------------------------------------------------------------------------

local function SkinEntry(entry)
    local statusBar = entry.StatusBar
    if not statusBar then return end

    -- Always re-apply flat texture (SetStyle resets it during Init)
    statusBar:SetStatusBarTexture(C.BAR_TEXTURE)

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
-- Source / Detail Window
---------------------------------------------------------------------------

local function SkinSourceWindow(sourceWindow)
    if not sourceWindow or skinnedWindows[sourceWindow] then return end
    skinnedWindows[sourceWindow] = true

    -- Strip the dropdown-style background
    local bg = sourceWindow.Background
    if bg then
        bg:SetAtlas("")
        bg:SetTexture(nil)
        bg:Hide()
    end

    -- Separate backdrop frame (avoids Mixin on Blizzard frame)
    local bdFrame = CreateFrame("Frame", nil, sourceWindow, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(sourceWindow:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    local bgc = C.BACKDROP_COLOR
    bdFrame:SetBackdropColor(bgc[1], bgc[2], bgc[3], bgc[4])

    -- Skin spell entry bars in the source window ScrollBox
    local scrollBox = sourceWindow.ScrollBox
    if scrollBox then
        if scrollBox.Update then
            hooksecurefunc(scrollBox, "Update", function(self)
                if self.ForEachFrame then
                    self:ForEachFrame(function(entry)
                        SkinEntry(entry)
                    end)
                end
            end)
        end

        -- Skin any entries already visible
        if scrollBox.ForEachFrame then
            scrollBox:ForEachFrame(function(entry)
                SkinEntry(entry)
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Session Window
---------------------------------------------------------------------------

local function SkinSessionWindow(window)
    if skinnedWindows[window] then return end
    skinnedWindows[window] = true

    -- Strip the default background atlas
    local bg = window.Background
    if bg then
        bg:SetAtlas("")
        bg:SetTexture(nil)
        bg:Hide()
    end

    -- Strip the header bar atlas
    local header = window.Header
    if header then
        header:SetAtlas("")
        header:SetTexture(nil)
        header:Hide()
    end

    -- Flat backdrop via a separate frame (avoids Mixin/writing keys on window)
    local bdFrame = CreateFrame("Frame", nil, window, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(window:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    local bgc = C.BACKDROP_COLOR
    bdFrame:SetBackdropColor(bgc[1], bgc[2], bgc[3], bgc[4])

    -- Flat header overlay on the backdrop frame (not the window)
    local hdr = bdFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    hdr:SetTexture(C.BAR_TEXTURE)
    hdr:SetVertexColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    hdr:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    hdr:SetPoint("TOPRIGHT", window, "TOPRIGHT", -1, 0)
    hdr:SetHeight(28)

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
        if sessionDD.SessionName then
            SE:StyleFont(sessionDD.SessionName)
        end
    end

    local typeDD = window.DamageMeterTypeDropdown
    if typeDD then
        SE:SkinDropdownButton(typeDD)
        if typeDD.TypeName then
            SE:StyleFont(typeDD.TypeName)
        end
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

    -- Register hooks immediately (safe — no layout changes)
    local scrollBox = window.ScrollBox
    if scrollBox then
        -- Hook ScrollBox Update on the INSTANCE to skin entries after
        -- secure Init/SetStyle calls are complete.
        if scrollBox.Update then
            hooksecurefunc(scrollBox, "Update", function(self)
                if self.ForEachFrame then
                    self:ForEachFrame(function(entry)
                        SkinEntry(entry)
                    end)
                end
            end)
        end

        -- Skin any entries already visible
        if scrollBox.ForEachFrame then
            scrollBox:ForEachFrame(function(entry)
                SkinEntry(entry)
            end)
        end
    end

    -- Local player entry (fixed bar, not in ScrollBox)
    local localEntry = window.LocalPlayerEntry
    if localEntry then
        SkinEntry(localEntry)

        -- Hook Init on the INSTANCE to re-skin after data updates
        if localEntry.Init then
            hooksecurefunc(localEntry, "Init", function(self)
                SkinEntry(self)
            end)
        end
    end

    -- Hook RefreshLayout on the INSTANCE to re-apply ScrollBox anchors
    -- after Blizzard resets them during layout updates.
    if window.RefreshLayout then
        hooksecurefunc(window, "RefreshLayout", function(self)
            local sb = self.ScrollBox
            if sb then
                sb:ClearAllPoints()
                sb:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -30)
                sb:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
            end
        end)
    end

    -- Defer layout-changing repositioning to next frame.
    -- ClearAllPoints/SetPoint on the ScrollBox triggers a layout cascade
    -- (SetDataProvider → Refresh) that runs synchronously inside our
    -- tainted SetupSessionWindow post-hook, causing secret value errors.
    C_Timer.After(0, function()
        if scrollBox then
            scrollBox:ClearAllPoints()
            scrollBox:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -30)
            scrollBox:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)
        end
        if localEntry then
            localEntry:ClearAllPoints()
            localEntry:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 1, 1)
            localEntry:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)
        end
    end)

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
