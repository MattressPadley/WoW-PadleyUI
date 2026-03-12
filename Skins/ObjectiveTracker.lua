local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local ObjectiveTrackerSkin = {}
ns.ObjectiveTrackerSkin = ObjectiveTrackerSkin

-- External tracking tables (never write keys to Blizzard frames)
local skinnedHeaders = {}
local skinnedProgressBars = {}
local hookedModules = {}
local mainFrameSkinned = false

-- Module-level backdrop references for collapse handling
local bdFrame, bgPanel

---------------------------------------------------------------------------
-- Main container backdrop (square, replaces Blizzard's clipped-corner bg)
---------------------------------------------------------------------------

local function HideBackgroundsRecursive(frame, depth)
    if depth > 3 then return end -- don't go too deep

    -- Hide texture regions that look like backgrounds
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            local drawLayer = region:GetDrawLayer()
            if drawLayer == "BACKGROUND" or drawLayer == "BORDER" then
                region:SetAlpha(0)
            end
        end
    end

    -- Recurse into children
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child then
            HideBackgroundsRecursive(child, depth + 1)
        end
    end
end

local function SkinMainFrame(trackerFrame)
    if mainFrameSkinned then return end
    mainFrameSkinned = true

    -- Hide all background/border textures throughout the tracker
    HideBackgroundsRecursive(trackerFrame, 0)

    -- Child 2 is the content-sized background panel (has 9 border textures)
    bgPanel = select(2, trackerFrame:GetChildren())
    if not bgPanel then return end

    -- Parent to trackerFrame (avoids alpha inheritance) but anchor to bgPanel size
    bdFrame = CreateFrame("Frame", nil, trackerFrame, "BackdropTemplate")
    bdFrame:SetAllPoints(bgPanel)
    bdFrame:SetFrameLevel(math.max(bgPanel:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:EnableMouse(false)
end

---------------------------------------------------------------------------
-- Module header skinning
---------------------------------------------------------------------------

local function SkinModuleHeader(header)
    if not header or skinnedHeaders[header] then return end
    skinnedHeaders[header] = true

    -- Strip ALL texture regions on the header
    local headerText = header.Text
    for i = 1, header:GetNumRegions() do
        local region = select(i, header:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
            region:SetTexture(nil)
            region:SetAtlas("")
            SE:HookTextureRemoval(region)
            SE:HookAtlasRemoval(region)
        end
    end

    -- Also hide named background if it exists
    if header.Background then
        header.Background:Hide()
        header.Background.Show = header.Background.Hide
    end

    -- Style header text
    if headerText then
        SE:StyleFont(headerText)
    end
end

---------------------------------------------------------------------------
-- Minimize button skinning
---------------------------------------------------------------------------

local skinnedMinimize = {}
local alphaHooked = {}

-- Persistently keep a texture region at alpha 0
local function PersistHideTexture(tex)
    if not tex or alphaHooked[tex] then return end
    alphaHooked[tex] = true
    tex:SetAlpha(0)
    hooksecurefunc(tex, "SetAlpha", function(self)
        if self:GetAlpha() ~= 0 then self:SetAlpha(0) end
    end)
end

-- Hide all button-specific textures (Normal, Highlight, Pushed)
local function SuppressButtonTextures(btn)
    for _, getter in pairs({"GetNormalTexture", "GetHighlightTexture", "GetPushedTexture"}) do
        if btn[getter] then
            local tex = btn[getter](btn)
            if tex then PersistHideTexture(tex) end
        end
    end
end

local function SkinMinimizeButton(button)
    if not button or skinnedMinimize[button] then return end
    skinnedMinimize[button] = true

    -- Kill all region textures permanently
    SE:StripTextures(button, true)

    -- Hide button-specific textures and persist via alpha hook
    SuppressButtonTextures(button)

    -- Re-suppress whenever Blizzard sets new textures or atlases
    for _, method in pairs({"SetNormalTexture", "SetHighlightTexture", "SetPushedTexture"}) do
        if button[method] then
            hooksecurefunc(button, method, SuppressButtonTextures)
        end
    end
    for _, method in pairs({"SetNormalAtlas", "SetHighlightAtlas", "SetPushedAtlas"}) do
        if button[method] then
            hooksecurefunc(button, method, SuppressButtonTextures)
        end
    end

    -- Child backdrop
    local btnBd = CreateFrame("Frame", nil, button, "BackdropTemplate")
    btnBd:SetAllPoints()
    btnBd:SetFrameLevel(button:GetFrameLevel())
    btnBd:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    btnBd:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    btnBd:EnableMouse(false)

    -- Indicator text
    local indicator = btnBd:CreateFontString(nil, "OVERLAY")
    indicator:SetFont(C.FONT, C.FONT_SIZE_SMALL, C.FONT_FLAGS)
    indicator:SetPoint("CENTER", 0, 0)
    indicator:SetText("-")

    -- Hover highlight
    button:HookScript("OnEnter", function()
        btnBd:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    button:HookScript("OnLeave", function()
        btnBd:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    end)

    -- Update indicator and backdrop on collapse/expand
    local function UpdateCollapseState()
        local trackerFrame = ObjectiveTrackerFrame
        if not trackerFrame then return end

        -- Detect collapsed state: check isCollapsed property or if content is hidden
        local collapsed = trackerFrame.isCollapsed
        if collapsed == nil and bgPanel then
            collapsed = not bgPanel:IsShown() or bgPanel:GetHeight() < 2
        end

        indicator:SetText(collapsed and "+" or "-")

        if bdFrame then
            bdFrame:ClearAllPoints()
            if collapsed and trackerFrame.Header then
                bdFrame:SetAllPoints(trackerFrame.Header)
            elseif bgPanel then
                bdFrame:SetAllPoints(bgPanel)
            end
        end
    end

    -- Hook OnClick to catch collapse toggle (fires for both button click and :Click())
    button:HookScript("OnClick", function()
        C_Timer.After(0, UpdateCollapseState)
    end)

    -- Sync initial state after tracker has loaded
    C_Timer.After(0.5, UpdateCollapseState)
end

---------------------------------------------------------------------------
-- Progress bar skinning
---------------------------------------------------------------------------

local function SkinProgressBar(progressBar)
    if not progressBar or skinnedProgressBars[progressBar] then return end
    skinnedProgressBars[progressBar] = true

    local bar = progressBar.Bar
    if not bar then return end

    -- Flat status bar texture
    SE:SkinStatusBar(bar)

    -- Strip decorative textures
    if bar.BarBG then bar.BarBG:SetAlpha(0) end
    if bar.BorderLeft then bar.BorderLeft:SetAlpha(0) end
    if bar.BorderRight then bar.BorderRight:SetAlpha(0) end
    if bar.BorderMid then bar.BorderMid:SetAlpha(0) end

    -- Strip any remaining decorative textures
    local statusBarTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= statusBarTex then
            region:SetAlpha(0)
        end
    end

    -- Backdrop behind bar
    local bdFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:EnableMouse(false)

    -- Style percentage label
    if bar.Label then
        SE:StyleFont(bar.Label)
    end
end

---------------------------------------------------------------------------
-- Block skinning (idempotent — blocks are recycled)
---------------------------------------------------------------------------

local function SkinBlock(block)
    if not block then return end

    if block.ProgressBar then
        SkinProgressBar(block.ProgressBar)
    end

    -- Timer bar (timed quests)
    if block.TimerBar then
        SkinProgressBar(block.TimerBar)
    end
end

---------------------------------------------------------------------------
-- Skin all modules and hook updates
---------------------------------------------------------------------------

local function SkinAllModules(trackerFrame)
    -- Main header
    if trackerFrame.Header then
        SkinModuleHeader(trackerFrame.Header)
        if trackerFrame.Header.MinimizeButton then
            SkinMinimizeButton(trackerFrame.Header.MinimizeButton)
        end
    end

    -- Iterate modules
    if not trackerFrame.modules then return end

    for _, module in ipairs(trackerFrame.modules) do
        -- Skin module header
        if module.Header then
            SkinModuleHeader(module.Header)
        end

        -- Hook module update to catch block creation/recycling
        if not hookedModules[module] then
            hookedModules[module] = true

            -- Try hooking Update (primary) or LayoutContents (fallback)
            local hookTarget = module.Update and "Update" or
                               module.LayoutContents and "LayoutContents" or nil

            if hookTarget then
                hooksecurefunc(module, hookTarget, function(self)
                    C_Timer.After(0, function()
                        if self.EnumerateBlocks then
                            for block in self:EnumerateBlocks() do
                                SkinBlock(block)
                            end
                        end
                    end)
                end)
            end
        end

        -- Skin existing blocks
        if module.EnumerateBlocks then
            for block in module:EnumerateBlocks() do
                SkinBlock(block)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function ObjectiveTrackerSkin:Apply()
    local trackerFrame = ObjectiveTrackerFrame
    if not trackerFrame then return end

    SkinMainFrame(trackerFrame)
    SkinAllModules(trackerFrame)

    -- Hook top-level Update to catch new modules and blocks
    if trackerFrame.Update then
        hooksecurefunc(trackerFrame, "Update", function(self)
            SkinAllModules(self)
        end)
    end
end
