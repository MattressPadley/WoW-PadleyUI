local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local WorldMapSkin = {}
ns.WorldMapSkin = WorldMapSkin

local frameSkinned = false

-- External tracking tables (avoid writing keys to Blizzard frames)
local skinnedNavButtons = {}
local skinnedMaxMinButtons = {}
local skinnedScrollEntries = {}
local skinnedSideTabs = {}
local skinnedRewardItems = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function CreateBackdropFrame(parent, offsets)
    local bd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if offsets then
        bd:SetPoint("TOPLEFT", offsets[1], offsets[2])
        bd:SetPoint("BOTTOMRIGHT", offsets[3], offsets[4])
    else
        bd:SetAllPoints()
    end
    bd:SetFrameLevel(parent:GetFrameLevel() + 1)
    bd:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    return bd
end

---------------------------------------------------------------------------
-- Reward item skinning
---------------------------------------------------------------------------

local function SkinRewardItem(frame)
    if not frame or skinnedRewardItems[frame] then return end
    skinnedRewardItems[frame] = true

    -- Hide the ornate name background
    if frame.NameFrame then frame.NameFrame:SetAlpha(0) end

    -- Hide icon overlay and circle backgrounds
    if frame.IconOverlay then frame.IconOverlay:SetAlpha(0) end
    if frame.CircleBackground then frame.CircleBackground:SetAlpha(0) end
    if frame.CircleBackgroundGlow then frame.CircleBackgroundGlow:SetAlpha(0) end

    -- Clean up the icon
    if frame.Icon then
        frame.Icon:SetDrawLayer("ARTWORK")
        frame.Icon:SetTexCoord(C.ICON_CROP[1], C.ICON_CROP[2], C.ICON_CROP[3], C.ICON_CROP[4])
    end

    -- Strip any Spellbook textures
    for _, region in next, { frame:GetRegions() } do
        if region:IsObjectType("Texture") and region:GetTexture() == [[Interface\Spellbook\Spellbook-Parts]] then
            region:SetTexture(nil)
        end
    end

    -- White item name
    if frame.Name then frame.Name:SetTextColor(1, 1, 1) end

    -- Count overlay
    if frame.Count then frame.Count:SetDrawLayer("OVERLAY") end
end

--- Set all quest info text to white for readability on dark backdrop
local function SkinQuestInfoText()
    -- Headers
    local headers = {
        _G.QuestInfoTitleHeader,
        _G.QuestInfoDescriptionHeader,
        _G.QuestInfoObjectivesHeader,
    }
    for _, h in ipairs(headers) do
        if h then h:SetTextColor(1, 1, 1) end
    end
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.Header then
        _G.QuestInfoRewardsFrame.Header:SetTextColor(1, 1, 1)
    end

    -- Body text
    local texts = {
        _G.QuestInfoDescriptionText,
        _G.QuestInfoObjectivesText,
        _G.QuestInfoGroupSize,
        _G.QuestInfoRewardText,
        _G.QuestInfoQuestType,
    }
    for _, t in ipairs(texts) do
        if t then t:SetTextColor(1, 1, 1) end
    end

    -- Rewards frame labels
    local rf = _G.QuestInfoRewardsFrame
    if rf then
        if rf.ItemChooseText then rf.ItemChooseText:SetTextColor(1, 1, 1) end
        if rf.ItemReceiveText then rf.ItemReceiveText:SetTextColor(1, 1, 1) end
        if rf.SpellLearnText then rf.SpellLearnText:SetTextColor(1, 1, 1) end
        if rf.PlayerTitleText then rf.PlayerTitleText:SetTextColor(1, 1, 1) end
        if rf.XPFrame and rf.XPFrame.ReceiveText then
            rf.XPFrame.ReceiveText:SetTextColor(1, 1, 1)
        end
    end
end

--- Hook called every time quest info is displayed — skins reward items and text
local function OnQuestInfoDisplay()
    SkinQuestInfoText()

    local rewardsFrame = _G.QuestInfoFrame and _G.QuestInfoFrame.rewardsFrame
    if not rewardsFrame then return end

    -- Skin all reward buttons
    if rewardsFrame.RewardButtons then
        for _, button in ipairs(rewardsFrame.RewardButtons) do
            SkinRewardItem(button)
            -- Re-set name color every display (Blizzard resets it)
            if button.Name then button.Name:SetTextColor(1, 1, 1) end
        end
    end

    -- Skin dynamic spell reward pool
    if rewardsFrame.spellRewardPool then
        for spellIcon in rewardsFrame.spellRewardPool:EnumerateActive() do
            SkinRewardItem(spellIcon)
        end
    end

    -- Skin dynamic reputation reward pool
    if rewardsFrame.reputationRewardPool then
        for repIcon in rewardsFrame.reputationRewardPool:EnumerateActive() do
            SkinRewardItem(repIcon)
        end
    end

    -- Spell header text → white
    if rewardsFrame.spellHeaderPool then
        for spellHeader in rewardsFrame.spellHeaderPool:EnumerateActive() do
            spellHeader:SetVertexColor(1, 1, 1)
        end
    end
end

---------------------------------------------------------------------------
-- NavBar breadcrumb buttons
---------------------------------------------------------------------------

local function SkinNavBarButton(button)
    if not button or skinnedNavButtons[button] then return end
    skinnedNavButtons[button] = true

    -- One-time skin: backdrop, hover, text styling
    -- Never re-parent text, never re-strip on reuse
    SE:SkinDropdownButton(button)

    -- Set text white (SkinDropdownButton styles font but not color)
    local text = button:GetFontString()
    if text then
        text:SetTextColor(1, 1, 1)
    end

    -- Skin the dropdown arrow on breadcrumb buttons
    local arrow = button.MenuArrowButton
    if arrow then
        SE:StripTextures(arrow)
        if arrow.Art then
            arrow.Art:SetAlpha(0.6)
        end
    end
end

local function SkinNavBar()
    local navBar = WorldMapFrame.NavBar
    if not navBar then return end

    SE:StripTextures(navBar)

    if navBar.overlay then
        SE:StripTextures(navBar.overlay)
    end

    -- Skin home button
    if navBar.homeButton then
        SkinNavBarButton(navBar.homeButton)
    end

    -- Skin overflow button
    if navBar.overflowButton then
        SkinNavBarButton(navBar.overflowButton)
    end

    -- Skin all existing breadcrumb buttons
    if navBar.navList then
        for _, button in ipairs(navBar.navList) do
            SkinNavBarButton(button)
        end
    end

    -- Hook NavBar_AddButton — only skin the newly-added last button
    hooksecurefunc("NavBar_AddButton", function(bar)
        if bar == navBar and bar.navList then
            local newButton = bar.navList[#bar.navList]
            if newButton then
                SkinNavBarButton(newButton)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Quest detail view
---------------------------------------------------------------------------

local skinnedQuestDetails = false

local function SkinQuestDetails()
    if skinnedQuestDetails then return end

    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if not details then return end

    skinnedQuestDetails = true

    SE:StripTextures(details)
    CreateBackdropFrame(details)

    -- Skin action buttons — pre-strip ShareButton (extra Blizz art)
    if details.ShareButton then
        SE:StripTextures(details.ShareButton)
        SE:SkinDropdownButton(details.ShareButton)
        details.ShareButton:SetFrameLevel(5)
    end

    if details.AbandonButton then
        SE:SkinDropdownButton(details.AbandonButton)
        details.AbandonButton:SetFrameLevel(5)
    end

    if details.TrackButton then
        SE:SkinDropdownButton(details.TrackButton)
        details.TrackButton:SetFrameLevel(5)
    end

    -- Back button
    if details.BackFrame then
        SE:StripTextures(details.BackFrame)
        if details.BackFrame.BackButton then
            SE:SkinDropdownButton(details.BackFrame.BackButton)
            details.BackFrame.BackButton:SetFrameLevel(5)
        end
    end

    -- Background textures
    if details.Bg then details.Bg:SetAlpha(0) end
    if details.SealMaterialBG then details.SealMaterialBG:SetAlpha(0) end

    -- Map background (parchment behind quest text)
    if QuestMapFrame.Background then QuestMapFrame.Background:SetAlpha(0) end

    -- Rewards container — strip ornate border/background
    if details.RewardsFrameContainer then
        SE:StripTextures(details.RewardsFrameContainer)
        if details.RewardsFrameContainer.RewardsFrame then
            SE:StripTextures(details.RewardsFrameContainer.RewardsFrame)
        end
    end

    -- One-time skinning of static reward sub-frames
    local rewardSubFrames = { "HonorFrame", "XPFrame", "SpellFrame", "SkillPointFrame", "ArtifactXPFrame", "TitleFrame", "WarModeBonusFrame" }
    for _, name in ipairs(rewardSubFrames) do
        if _G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame[name] then
            SkinRewardItem(_G.MapQuestInfoRewardsFrame[name])
        end
        if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame[name] then
            SkinRewardItem(_G.QuestInfoRewardsFrame[name])
        end
    end
    if _G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame.MoneyFrame then
        SkinRewardItem(_G.MapQuestInfoRewardsFrame.MoneyFrame)
    end

    -- Title reward frame — hide ornate textures
    local titleFrame = _G.QuestInfoPlayerTitleFrame
    if titleFrame then
        if titleFrame.FrameLeft then titleFrame.FrameLeft:SetTexture(nil) end
        if titleFrame.FrameCenter then titleFrame.FrameCenter:SetTexture(nil) end
        if titleFrame.FrameRight then titleFrame.FrameRight:SetTexture(nil) end
        if titleFrame.Icon then
            titleFrame.Icon:SetTexCoord(C.ICON_CROP[1], C.ICON_CROP[2], C.ICON_CROP[3], C.ICON_CROP[4])
        end
    end

    -- Item highlight — flat style
    local highlight = _G.QuestInfoItemHighlight
    if highlight then
        SE:StripTextures(highlight)
    end

    -- Hook QuestInfo_Display to skin text and rewards every time a quest is viewed
    hooksecurefunc("QuestInfo_Display", OnQuestInfoDisplay)
    OnQuestInfoDisplay()
end

---------------------------------------------------------------------------
-- Quest log panel (QuestMapFrame)
---------------------------------------------------------------------------

local questMapSkinned = false

--- Skin campaign story header (purple banner)
local function SkinStoryHeader(header)
    if not header then return end
    if header.TopFiligree then header.TopFiligree:Hide() end
    if header.Divider then header.Divider:Hide() end
    if header.Background then header.Background:SetAlpha(0) end
    if header.HighlightTexture then header.HighlightTexture:SetAlpha(0) end
end

--- Skin entries from frame pools after QuestLogQuests_Update
local function SkinQuestLogEntries()
    local qsf = _G.QuestScrollFrame
    if not qsf then return end

    -- Zone/category headers
    if qsf.headerFramePool then
        for button in qsf.headerFramePool:EnumerateActive() do
            if not skinnedScrollEntries[button] then
                skinnedScrollEntries[button] = true
                SE:StripTextures(button)
            end
        end
    end

    -- Quest title rows
    if qsf.titleFramePool then
        for button in qsf.titleFramePool:EnumerateActive() do
            if not skinnedScrollEntries[button] then
                skinnedScrollEntries[button] = true
            end
        end
    end

    -- Campaign headers (the purple "Midnight" banner)
    if qsf.campaignHeaderFramePool then
        for header in qsf.campaignHeaderFramePool:EnumerateActive() do
            if not skinnedScrollEntries[header] then
                skinnedScrollEntries[header] = true
                SkinStoryHeader(header)
            end
        end
    end

    -- Minimal/collapsed campaign headers
    if qsf.campaignHeaderMinimalFramePool then
        for header in qsf.campaignHeaderMinimalFramePool:EnumerateActive() do
            if not skinnedScrollEntries[header] then
                skinnedScrollEntries[header] = true
                SE:StripTextures(header)
            end
        end
    end
end

local function SkinQuestMapFrame()
    if questMapSkinned then return end
    if not QuestMapFrame then return end
    questMapSkinned = true

    SE:StripTextures(QuestMapFrame)

    -- Hide the vertical separator between quest list and map
    if QuestMapFrame.VerticalSeparator then
        QuestMapFrame.VerticalSeparator:Hide()
    end

    local questsFrame = QuestMapFrame.QuestsFrame
    if questsFrame then
        SE:StripTextures(questsFrame)
        CreateBackdropFrame(questsFrame)

        -- Campaign overview panel
        if questsFrame.CampaignOverview then
            SE:StripTextures(questsFrame.CampaignOverview)
        end
    end

    -- QuestScrollFrame — the actual scroll container with frame pools
    local qsf = _G.QuestScrollFrame
    if qsf then
        -- Hide the parchment background
        if qsf.Background then qsf.Background:SetAlpha(0) end
        if qsf.Center then qsf.Center:Hide() end

        -- Hide Edge, BorderFrame, Separator (ElvUI pattern)
        if qsf.Edge then qsf.Edge:SetAlpha(0) end
        if qsf.BorderFrame then qsf.BorderFrame:SetAlpha(0) end
        if qsf.Contents and qsf.Contents.Separator then
            qsf.Contents.Separator:SetAlpha(0)
        end

        -- Story header (campaign banner at the top)
        if qsf.Contents and qsf.Contents.StoryHeader then
            SkinStoryHeader(qsf.Contents.StoryHeader)
        end

        -- Search box
        if qsf.SearchBox then
            SE:StripTextures(qsf.SearchBox)
            CreateBackdropFrame(qsf.SearchBox)
        end

        -- Hook QuestLogQuests_Update to skin pool entries as they spawn
        hooksecurefunc("QuestLogQuests_Update", SkinQuestLogEntries)
        SkinQuestLogEntries()
    end

    -- Party Sync button at the bottom
    if QuestMapFrame.QuestSessionManagement then
        SE:StripTextures(QuestMapFrame.QuestSessionManagement)
        local execBtn = QuestMapFrame.QuestSessionManagement.ExecuteSessionCommand
        if execBtn then
            SE:SkinDropdownButton(execBtn)
        end
    end

    SkinQuestDetails()
end

---------------------------------------------------------------------------
-- Main border frame
---------------------------------------------------------------------------

local mainBackdrop

local function SkinBorderFrame()
    local borderFrame = WorldMapFrame.BorderFrame
    if not borderFrame then return end

    -- Strip main WorldMapFrame textures
    SE:StripTextures(WorldMapFrame)

    -- Sync BorderFrame strata with WorldMapFrame
    borderFrame:SetFrameStrata(WorldMapFrame:GetFrameStrata())

    -- Kill NineSlice
    if borderFrame.NineSlice then
        borderFrame.NineSlice:Hide()
        SE:StripTextures(borderFrame.NineSlice, true)
    end

    SE:StripTextures(borderFrame, true)

    if borderFrame.Bg then borderFrame.Bg:SetAlpha(0) end
    if borderFrame.TopTileStreaks then borderFrame.TopTileStreaks:SetAlpha(0) end
    if borderFrame.PortraitContainer then borderFrame.PortraitContainer:SetAlpha(0) end
    if borderFrame.Underlay then borderFrame.Underlay:SetAlpha(0) end
    if borderFrame.InsetBorderTop then borderFrame.InsetBorderTop:SetAlpha(0) end

    -- Create backdrop on WorldMapFrame with offsets for proper coverage
    mainBackdrop = CreateFrame("Frame", nil, WorldMapFrame, "BackdropTemplate")
    mainBackdrop:SetPoint("TOPLEFT", -8, 0)
    mainBackdrop:SetPoint("BOTTOMRIGHT", 0, -8)
    mainBackdrop:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 1)
    mainBackdrop:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    mainBackdrop:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Style title
    if borderFrame.TitleContainer and borderFrame.TitleContainer.TitleText then
        SE:StyleFont(borderFrame.TitleContainer.TitleText)
    elseif borderFrame.TitleText then
        SE:StyleFont(borderFrame.TitleText)
    end

    -- Skin close button
    SE:SkinCloseButton(borderFrame.CloseButton)

    -- Maximize/Minimize buttons
    local maxMin = borderFrame.MaximizeMinimizeFrame or borderFrame.MaxMinButtonFrame
    if maxMin then
        SE:StripTextures(maxMin)
        for i = 1, maxMin:GetNumChildren() do
            local child = select(i, maxMin:GetChildren())
            if child and child:GetObjectType() == "Button" and not skinnedMaxMinButtons[child] then
                skinnedMaxMinButtons[child] = true
                SE:SkinDropdownButton(child)
            end
        end
    end

    -- Tutorial button
    if borderFrame.Tutorial then
        borderFrame.Tutorial:SetAlpha(0)
    end
end

---------------------------------------------------------------------------
-- Mode switching hooks (windowed <-> maximized)
---------------------------------------------------------------------------

local function HookModeSwitching()
    local function RefreshSkin()
        local borderFrame = WorldMapFrame.BorderFrame
        if not borderFrame then return end

        SE:StripTextures(WorldMapFrame)

        if borderFrame.NineSlice then
            borderFrame.NineSlice:Hide()
            SE:StripTextures(borderFrame.NineSlice, true)
        end
        SE:StripTextures(borderFrame, true)
        if borderFrame.Bg then borderFrame.Bg:SetAlpha(0) end
        if borderFrame.TopTileStreaks then borderFrame.TopTileStreaks:SetAlpha(0) end
        if borderFrame.PortraitContainer then borderFrame.PortraitContainer:SetAlpha(0) end
        if borderFrame.Underlay then borderFrame.Underlay:SetAlpha(0) end
        if borderFrame.InsetBorderTop then borderFrame.InsetBorderTop:SetAlpha(0) end

        if WorldMapFrame.BlackoutFrame and WorldMapFrame.BlackoutFrame.Blackout then
            WorldMapFrame.BlackoutFrame.Blackout:SetColorTexture(0, 0, 0, 0.85)
        end
    end

    hooksecurefunc(WorldMapFrame, "Maximize", RefreshSkin)
    hooksecurefunc(WorldMapFrame, "Minimize", RefreshSkin)
end

---------------------------------------------------------------------------
-- Sidebar toggle button
---------------------------------------------------------------------------

local function SkinSidebarToggle()
    local toggle = WorldMapFrame.SidePanelToggle
    if not toggle then return end

    if toggle.CloseButton then
        SE:SkinDropdownButton(toggle.CloseButton)
    end
    if toggle.OpenButton then
        SE:SkinDropdownButton(toggle.OpenButton)
    end
end

---------------------------------------------------------------------------
-- ScrollContainer (map canvas area)
---------------------------------------------------------------------------

local function SkinScrollContainer()
    local sc = WorldMapFrame.ScrollContainer
    if not sc then return end

    SE:StripTextures(sc)
end

---------------------------------------------------------------------------
-- Map Legend panel
---------------------------------------------------------------------------

local function SkinMapLegend()
    local legend = QuestMapFrame and QuestMapFrame.MapLegend
    if not legend then return end

    -- Title
    if legend.TitleText then
        SE:StyleFont(legend.TitleText)
    end

    -- Border frame around legend
    if legend.BorderFrame then
        legend.BorderFrame:SetAlpha(0)
    end

    -- ScrollFrame inside legend
    local scroll = legend.ScrollFrame
    if scroll then
        SE:StripTextures(scroll)
        CreateBackdropFrame(scroll)
    end
end

---------------------------------------------------------------------------
-- Side tabs (11.1: Quests, Events, Map Legend)
---------------------------------------------------------------------------

local SELECTION_COLOR = { 0.3, 0.3, 0.3, 1 }

local function SkinSideTabs()
    local tabs = {
        QuestMapFrame and QuestMapFrame.QuestsTab,
        QuestMapFrame and QuestMapFrame.EventsTab,
        QuestMapFrame and QuestMapFrame.MapLegendTab,
    }

    for _, tab in ipairs(tabs) do
        if tab and not skinnedSideTabs[tab] then
            skinnedSideTabs[tab] = true

            -- Hide the default background texture
            if tab.Background then
                tab.Background:SetAlpha(0)
            end

            SE:StripTextures(tab)

            -- Create flat backdrop
            local bd = CreateFrame("Frame", nil, tab, "BackdropTemplate")
            bd:SetAllPoints()
            bd:SetFrameLevel(tab:GetFrameLevel() + 1)
            bd:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
            bd:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])

            -- Keep the icon visible above the backdrop
            if tab.Icon then
                tab.Icon:SetParent(bd)
            end

            -- Handle SelectedTexture — flat color overlay instead of Blizz texture
            if tab.SelectedTexture then
                tab.SelectedTexture:SetColorTexture(SELECTION_COLOR[1], SELECTION_COLOR[2], SELECTION_COLOR[3], SELECTION_COLOR[4])
                tab.SelectedTexture:SetAllPoints(tab)
            end

            -- Find and replace hover glow region (atlas-based highlight)
            for i = 1, tab:GetNumRegions() do
                local region = select(i, tab:GetRegions())
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    local atlas = region.GetAtlas and region:GetAtlas()
                    if atlas and (atlas:find("Highlight") or atlas:find("highlight") or atlas:find("Glow") or atlas:find("glow")) then
                        region:SetColorTexture(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
                        region:SetAllPoints(tab)
                    end
                end
            end

            -- Hook icon position to keep it centered
            if tab.Icon then
                hooksecurefunc(tab.Icon, "SetPoint", function(self)
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", tab, "CENTER", 0, 0)
                end)
            end

            tab:HookScript("OnEnter", function()
                bd:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
            end)
            tab:HookScript("OnLeave", function()
                bd:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function WorldMapSkin:Apply()
    if frameSkinned then return end
    frameSkinned = true

    SkinBorderFrame()
    HookModeSwitching()
    SkinNavBar()
    SkinSidebarToggle()
    SkinScrollContainer()
    SkinQuestMapFrame()
    SkinMapLegend()
    SkinSideTabs()

    -- Deferred skinning for elements that populate after show
    WorldMapFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            SkinQuestMapFrame()
            SkinQuestDetails()
        end)
    end)
end
