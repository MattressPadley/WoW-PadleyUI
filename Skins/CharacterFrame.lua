local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local CharacterFrameSkin = {}
ns.CharacterFrameSkin = CharacterFrameSkin

local frameSkinned = false

-- External tracking tables (avoid writing keys to Blizzard frames)
local skinnedCategories = {}
local skinnedStatFrames = {}
local skinnedSidebarTabs = {}
local skinnedEquipEntries = {}
local skinnedTitleEntries = {}
local skinnedFactionEntries = {}
local skinnedTokenEntries = {}

---------------------------------------------------------------------------
-- Stats pane skinning
---------------------------------------------------------------------------

local function SkinCategoryHeader(header)
    if not header or skinnedCategories[header] then return end
    skinnedCategories[header] = true

    SE:StripTextures(header)

    local bdFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(header:GetFrameLevel())
    bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    -- Re-parent text so it draws above the backdrop
    for i = 1, header:GetNumRegions() do
        local region = select(i, header:GetRegions())
        if region and region:GetObjectType() == "FontString" then
            region:SetParent(bdFrame)
            SE:StyleFont(region)
        end
    end
end

local function SkinStatsPane()
    local pane = CharacterStatsPane
    if not pane then return end

    -- Strip background textures
    SE:StripTextures(pane)

    -- Style category headers and stat labels
    if pane.ClassBackground then pane.ClassBackground:SetAlpha(0) end

    -- Item level display — larger font
    if pane.ItemLevelFrame and pane.ItemLevelFrame.Value then
        SE:StyleFont(pane.ItemLevelFrame.Value, 20)
    end

    -- Skin known category headers
    local categories = { "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }
    for _, name in ipairs(categories) do
        if pane[name] then
            SkinCategoryHeader(pane[name])
        end
    end

    -- Style all child FontStrings
    for i = 1, pane:GetNumChildren() do
        local child = select(i, pane:GetChildren())
        if child then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "FontString" then
                    SE:StyleFont(region)
                end
            end
        end
    end

    -- Hide stat row backgrounds
    if pane.statsFramePool then
        for frame in pane.statsFramePool:EnumerateActive() do
            if frame.Background and not skinnedStatFrames[frame] then
                skinnedStatFrames[frame] = true
                frame.Background:SetAlpha(0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Sidebar tabs (Titles, Equipment Sets icons on right edge)
---------------------------------------------------------------------------

-- Prevent Blizzard from resetting texcoords on tab 1 regions
local function TabTexCoordHook(tex, x1)
    if x1 ~= 0.16001 then
        tex:SetTexCoord(0.16001, 0.86, 0.16, 0.86)
    end
end

local function SkinSidebarTab(tab, index)
    if not tab or skinnedSidebarTabs[tab] then return end
    skinnedSidebarTabs[tab] = true

    if tab.TabBg then tab.TabBg:SetAlpha(0) end

    -- Flat backdrop behind icon
    local bdFrame = CreateFrame("Frame", nil, tab, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(tab:GetFrameLevel())
    bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    if tab.Icon then
        tab.Icon:SetParent(bdFrame)
        tab.Icon:SetAllPoints()
    end

    -- Tab 1 (Stats) has texcoords that Blizzard keeps resetting — hook all regions
    if index == 1 then
        for _, region in next, { tab:GetRegions() } do
            region:SetTexCoord(0.16001, 0.86, 0.16, 0.86)
            hooksecurefunc(region, "SetTexCoord", TabTexCoordHook)
        end
    end

    if tab.Highlight then
        tab.Highlight:SetParent(bdFrame)
        tab.Highlight:SetColorTexture(C.HIGHLIGHT_OVERLAY[1], C.HIGHLIGHT_OVERLAY[2], C.HIGHLIGHT_OVERLAY[3], C.HIGHLIGHT_OVERLAY[4])
        tab.Highlight:SetAllPoints()
    end

    if tab.Hider then
        tab.Hider:SetParent(bdFrame)
        tab.Hider:SetColorTexture(0, 0, 0, 0.6)
        tab.Hider:SetAllPoints()
    end
end

local function SkinSidebarTabs()
    local index = 1
    local tab = _G["PaperDollSidebarTab" .. index]
    while tab do
        SkinSidebarTab(tab, index)
        index = index + 1
        tab = _G["PaperDollSidebarTab" .. index]
    end
end

---------------------------------------------------------------------------
-- Equipment Manager pane ScrollBox entries
---------------------------------------------------------------------------

local function SkinEquipmentEntry(entry)
    if not entry or skinnedEquipEntries[entry] then return end
    skinnedEquipEntries[entry] = true

    if entry.BgTop then entry.BgTop:SetTexture(0) end
    if entry.BgMiddle then entry.BgMiddle:SetTexture(0) end
    if entry.BgBottom then entry.BgBottom:SetTexture(0) end

    if entry.HighlightBar then
        entry.HighlightBar:SetColorTexture(1, 1, 1, 0.25)
        entry.HighlightBar:SetDrawLayer("BACKGROUND")
    end
    if entry.SelectedBar then
        entry.SelectedBar:SetColorTexture(0.8, 0.8, 0.8, 0.25)
        entry.SelectedBar:SetDrawLayer("BACKGROUND")
    end

    if entry.icon then
        entry.icon:SetTexCoord(unpack(C.ICON_CROP))
    end
end

local function HookEquipmentScrollBox()
    local equipPane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if not equipPane or not equipPane.ScrollBox then return end

    hooksecurefunc(equipPane.ScrollBox, "Update", function(self)
        self:ForEachFrame(function(entry)
            SkinEquipmentEntry(entry)
        end)
    end)
end

---------------------------------------------------------------------------
-- Title Manager pane ScrollBox entries
---------------------------------------------------------------------------

local function SkinTitleEntry(entry)
    if not entry or skinnedTitleEntries[entry] then return end
    skinnedTitleEntries[entry] = true

    entry:DisableDrawLayer("BACKGROUND")
end

local function HookTitleScrollBox()
    local titlePane = PaperDollFrame and PaperDollFrame.TitleManagerPane
    if not titlePane or not titlePane.ScrollBox then return end

    hooksecurefunc(titlePane.ScrollBox, "Update", function(self)
        self:ForEachFrame(function(entry)
            SkinTitleEntry(entry)
        end)
    end)
end

---------------------------------------------------------------------------
-- Reputation Frame
---------------------------------------------------------------------------

local function SkinFactionEntry(entry)
    if not entry or skinnedFactionEntries[entry] then return end
    skinnedFactionEntries[entry] = true

    entry:DisableDrawLayer("BACKGROUND")

    local bar = entry.Content and entry.Content.ReputationBar
    if bar then
        SE:StripTextures(bar)
        SE:SkinStatusBar(bar)

        -- Dark backdrop behind the bar
        local bdFrame = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        bdFrame:SetAllPoints()
        bdFrame:SetFrameLevel(bar:GetFrameLevel())
        bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
        bdFrame:SetBackdropColor(0, 0, 0, 0.5)
    end
end

local function HookReputationScrollBox()
    local repFrame = ReputationFrame
    if not repFrame or not repFrame.ScrollBox then return end

    hooksecurefunc(repFrame.ScrollBox, "Update", function(self)
        self:ForEachFrame(function(entry)
            SkinFactionEntry(entry)
        end)
    end)
end

local function SkinReputationFrame()
    local repFrame = ReputationFrame
    if not repFrame then return end

    SE:StripTextures(repFrame)

    -- Detail popup frame
    local detail = repFrame.ReputationDetailFrame
    if detail then
        SE:StripTextures(detail)

        local bdFrame = CreateFrame("Frame", nil, detail, "BackdropTemplate")
        bdFrame:SetAllPoints()
        bdFrame:SetFrameLevel(detail:GetFrameLevel())
        bdFrame:SetBackdrop(C.FLAT_BACKDROP)
        bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

        if detail.CloseButton then
            SE:SkinCloseButton(detail.CloseButton)
        end
    end

    HookReputationScrollBox()
end

---------------------------------------------------------------------------
-- Token (Currency) Frame
---------------------------------------------------------------------------

local function SkinTokenEntry(entry)
    if not entry or skinnedTokenEntries[entry] then return end
    skinnedTokenEntries[entry] = true

    entry:DisableDrawLayer("BACKGROUND")

    if entry.CurrencyIcon then
        entry.CurrencyIcon:SetTexCoord(unpack(C.ICON_CROP))
    end
end

local function HookTokenScrollBox()
    if not TokenFrame or not TokenFrame.ScrollBox then return end

    hooksecurefunc(TokenFrame.ScrollBox, "Update", function(self)
        self:ForEachFrame(function(entry)
            SkinTokenEntry(entry)
        end)
    end)
end

local function SkinTokenFrame()
    if not TokenFrame then return end

    SE:StripTextures(TokenFrame)

    -- Token popup frame
    if TokenFramePopup then
        SE:StripTextures(TokenFramePopup)

        local bdFrame = CreateFrame("Frame", nil, TokenFramePopup, "BackdropTemplate")
        bdFrame:SetAllPoints()
        bdFrame:SetFrameLevel(TokenFramePopup:GetFrameLevel())
        bdFrame:SetBackdrop(C.FLAT_BACKDROP)
        bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

        if TokenFramePopup.CloseButton then
            SE:SkinCloseButton(TokenFramePopup.CloseButton)
        end
    end

    HookTokenScrollBox()
end

---------------------------------------------------------------------------
-- Main frame skinning
---------------------------------------------------------------------------

local function SkinCharacterFrame()
    if frameSkinned then return end
    frameSkinned = true

    local cf = CharacterFrame

    -- Skin the main window (NineSlice, Bg, portrait, title, close button)
    SE:SkinWindow(cf)

    -- Hide the inset NineSlice (ButtonFrameTemplate sunken panel)
    if cf.Inset and cf.Inset.NineSlice then
        cf.Inset.NineSlice:SetAlpha(0)
    end
    -- Hide inset background
    if cf.Inset and cf.Inset.Bg then
        cf.Inset.Bg:SetAlpha(0)
    end
    -- Hide the content-area atlas overlay (character-panel-background)
    if cf.Background then
        cf.Background:SetAlpha(0)
    end

    -- Skin tabs
    for i = 1, 5 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
            SE:SkinTab(tab)
        end
    end

    -- Character model scene — strip ornate frame, solid black bg
    if CharacterModelScene then
        SE:StripTextures(CharacterModelScene)
    end
    if CharacterModelFrameBackgroundOverlay then
        CharacterModelFrameBackgroundOverlay:SetColorTexture(0, 0, 0)
    end

    -- Character level text
    if CharacterLevelText then
        SE:StyleFont(CharacterLevelText)
    end

    -- Right inset panel (Equipment Manager / Title Manager container)
    if CharacterFrameInsetRight then
        SE:StripTextures(CharacterFrameInsetRight)
        if CharacterFrameInsetRight.NineSlice then
            CharacterFrameInsetRight.NineSlice:SetAlpha(0)
        end
        if CharacterFrameInsetRight.Bg then
            CharacterFrameInsetRight.Bg:SetAlpha(0)
        end
    end

    -- Sidebar tabs (Titles, Equipment Sets icons)
    SkinSidebarTabs()
    if PaperDollFrame_UpdateSidebarTabs then
        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", SkinSidebarTabs)
    end

    -- Hook stat row backgrounds via PaperDollFrame_UpdateStats
    if PaperDollFrame_UpdateStats then
        hooksecurefunc("PaperDollFrame_UpdateStats", SkinStatsPane)
    end

    -- Equipment Manager ScrollBox
    HookEquipmentScrollBox()

    -- EquipSet / SaveSet buttons
    if PaperDollFrameEquipSet then
        SE:SkinDropdownButton(PaperDollFrameEquipSet)
    end
    if PaperDollFrameSaveSet then
        SE:SkinDropdownButton(PaperDollFrameSaveSet)
    end

    -- Title Manager ScrollBox
    HookTitleScrollBox()

    -- Reputation Frame
    SkinReputationFrame()

    -- Deferred skinning for elements that populate after show
    cf:HookScript("OnShow", function()
        C_Timer.After(0, SkinStatsPane)
    end)

    -- Skin stats pane if already visible
    SkinStatsPane()
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function CharacterFrameSkin:Apply()
    SkinCharacterFrame()
end

function CharacterFrameSkin:ApplyTokenFrame()
    SkinTokenFrame()
end
