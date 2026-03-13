local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local ProfessionsSkin = {}
ns.ProfessionsSkin = ProfessionsSkin

-- External tracking tables (avoid writing keys to Blizzard frames)
local skinnedRecipeEntries = {}
local skinnedReagentSlots = {}
local skinnedGearSlots = {}
local skinnedTabs = {}
local skinnedOutputButtons = {}
local mainFrameSkinned = false

---------------------------------------------------------------------------
-- Reagent / Salvage / Enchant slot buttons
---------------------------------------------------------------------------

local function SkinReagentSlot(button)
    if not button or skinnedReagentSlots[button] then return end
    skinnedReagentSlots[button] = true

    -- Hide ornate crop frame and slot background
    if button.CropFrame then button.CropFrame:SetAlpha(0) end
    if button.SlotBackground then button.SlotBackground:SetAlpha(0) end

    -- Clear normal/pushed textures but preserve green plus icon
    local normalTex = button:GetNormalTexture()
    if normalTex then
        local atlas = normalTex.GetAtlas and normalTex:GetAtlas()
        if atlas ~= "ItemUpgrade_GreenPlusIcon" then
            normalTex:SetAlpha(0)
        end
    end
    local pushedTex = button:GetPushedTexture()
    if pushedTex then pushedTex:SetAlpha(0) end

    -- Crop icon and remove masks
    local icon = button.Icon
    if icon then
        icon:SetTexCoord(unpack(C.ICON_CROP))
        -- Remove circle/rounded masks
        for i = 1, button:GetNumRegions() do
            local region = select(i, button:GetRegions())
            if region and region:GetObjectType() == "MaskTexture" then
                icon:RemoveMaskTexture(region)
                region:Hide()
            end
        end
    end

    -- Child backdrop with flat border
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop(C.FLAT_BACKDROP)
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    bdFrame:EnableMouse(false)

    -- Anchor icon inside the border
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", bdFrame, "TOPLEFT", C.BORDER_SIZE, -C.BORDER_SIZE)
        icon:SetPoint("BOTTOMRIGHT", bdFrame, "BOTTOMRIGHT", -C.BORDER_SIZE, C.BORDER_SIZE)
    end

    -- Flat highlight
    local hl = button:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(C.HIGHLIGHT_OVERLAY[1], C.HIGHLIGHT_OVERLAY[2], C.HIGHLIGHT_OVERLAY[3], C.HIGHLIGHT_OVERLAY[4])
        if icon then hl:SetAllPoints(icon) end
    end

    -- Hook IconBorder for quality colors
    if button.IconBorder then
        button.IconBorder:Hide()
        hooksecurefunc(button.IconBorder, "SetVertexColor", function(self, r, g, b)
            if r then bdFrame:SetBackdropBorderColor(r, g, b, 1) end
        end)
        hooksecurefunc(button.IconBorder, "Show", function(self)
            self:Hide()
        end)
        hooksecurefunc(button.IconBorder, "Hide", function()
            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end)
    end
end

---------------------------------------------------------------------------
-- Profession gear slots (tool / gear equipped items)
---------------------------------------------------------------------------

local function SkinGearSlot(button)
    if not button or skinnedGearSlots[button] then return end
    skinnedGearSlots[button] = true

    SE:StripTextures(button)
    if button:GetNormalTexture() then button:GetNormalTexture():SetAlpha(0) end
    if button:GetPushedTexture() then button:GetPushedTexture():SetAlpha(0) end

    local icon = button.icon
    if icon then
        icon:SetTexCoord(unpack(C.ICON_CROP))
        -- Remove masks
        for i = 1, button:GetNumRegions() do
            local region = select(i, button:GetRegions())
            if region and region:GetObjectType() == "MaskTexture" then
                icon:RemoveMaskTexture(region)
                region:Hide()
            end
        end
    end

    -- Child backdrop
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop(C.FLAT_BACKDROP)
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    bdFrame:EnableMouse(false)

    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", bdFrame, "TOPLEFT", C.BORDER_SIZE, -C.BORDER_SIZE)
        icon:SetPoint("BOTTOMRIGHT", bdFrame, "BOTTOMRIGHT", -C.BORDER_SIZE, C.BORDER_SIZE)
    end

    -- Flat highlight
    local hl = button:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(C.HIGHLIGHT_OVERLAY[1], C.HIGHLIGHT_OVERLAY[2], C.HIGHLIGHT_OVERLAY[3], C.HIGHLIGHT_OVERLAY[4])
        if icon then hl:SetAllPoints(icon) end
    end

    -- Hook IconBorder for quality colors
    if button.IconBorder then
        button.IconBorder:Hide()
        hooksecurefunc(button.IconBorder, "SetVertexColor", function(self, r, g, b)
            if r then bdFrame:SetBackdropBorderColor(r, g, b, 1) end
        end)
        hooksecurefunc(button.IconBorder, "Show", function(self)
            self:Hide()
        end)
        hooksecurefunc(button.IconBorder, "Hide", function()
            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end)
    end
end

---------------------------------------------------------------------------
-- Output icon (crafted item preview)
---------------------------------------------------------------------------

local function SkinOutputIcon(outputIcon)
    if not outputIcon then return end

    -- Remove circle mask
    if outputIcon.CircleMask then
        if outputIcon.Icon then outputIcon.Icon:RemoveMaskTexture(outputIcon.CircleMask) end
        outputIcon.CircleMask:Hide()
    end

    if outputIcon.Icon then
        outputIcon.Icon:SetTexCoord(unpack(C.ICON_CROP))
    end

    -- Hide highlight
    if outputIcon.HighlightTexture then
        outputIcon.HighlightTexture:SetAlpha(0)
    end

    -- Child backdrop
    local bdFrame = CreateFrame("Frame", nil, outputIcon, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(outputIcon:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop(C.FLAT_BACKDROP)
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    bdFrame:EnableMouse(false)

    if outputIcon.Icon then
        outputIcon.Icon:ClearAllPoints()
        outputIcon.Icon:SetPoint("TOPLEFT", bdFrame, "TOPLEFT", C.BORDER_SIZE, -C.BORDER_SIZE)
        outputIcon.Icon:SetPoint("BOTTOMRIGHT", bdFrame, "BOTTOMRIGHT", -C.BORDER_SIZE, C.BORDER_SIZE)
    end

    -- Hook IconBorder for quality colors
    if outputIcon.IconBorder then
        outputIcon.IconBorder:Hide()
        hooksecurefunc(outputIcon.IconBorder, "SetVertexColor", function(self, r, g, b)
            if r then bdFrame:SetBackdropBorderColor(r, g, b, 1) end
        end)
        hooksecurefunc(outputIcon.IconBorder, "Show", function(self)
            self:Hide()
        end)
        hooksecurefunc(outputIcon.IconBorder, "Hide", function()
            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end)
    end
end

---------------------------------------------------------------------------
-- Recipe list entries (ScrollBox rows)
---------------------------------------------------------------------------

local function SkinRecipeEntry(entry)
    if not entry or skinnedRecipeEntries[entry] then return end
    skinnedRecipeEntries[entry] = true

    entry:DisableDrawLayer("BACKGROUND")
end

local function HookRecipeScrollBox(craftingPage)
    local recipeList = craftingPage.RecipeList
    if not recipeList or not recipeList.ScrollBox then return end

    hooksecurefunc(recipeList.ScrollBox, "Update", function(self)
        self:ForEachFrame(function(entry)
            SkinRecipeEntry(entry)
        end)
    end)
end

---------------------------------------------------------------------------
-- Recipe list panel (left side)
---------------------------------------------------------------------------

local function SkinRecipeList(craftingPage)
    local recipeList = craftingPage.RecipeList
    if not recipeList then return end

    SE:StripTextures(recipeList)

    if recipeList.BackgroundNineSlice then
        recipeList.BackgroundNineSlice:Hide()
    end

    -- Search box
    if recipeList.SearchBox then
        SE:StripTextures(recipeList.SearchBox)
        local searchBd = CreateFrame("Frame", nil, recipeList.SearchBox, "BackdropTemplate")
        searchBd:SetAllPoints()
        searchBd:SetFrameLevel(recipeList.SearchBox:GetFrameLevel())
        searchBd:SetBackdrop(C.FLAT_BACKDROP)
        searchBd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        searchBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    end

    -- Filter dropdown
    if recipeList.FilterDropdown then
        SE:SkinDropdownButton(recipeList.FilterDropdown)
    end

    HookRecipeScrollBox(craftingPage)
end

---------------------------------------------------------------------------
-- Schematic form (right side crafting details)
---------------------------------------------------------------------------

local function SkinSchematicForm(form)
    if not form then return end

    SE:StripTextures(form)

    if form.Background then form.Background:SetAlpha(0) end
    if form.MinimalBackground then form.MinimalBackground:SetAlpha(0) end

    -- Flat backdrop child
    local formBd = CreateFrame("Frame", nil, form, "BackdropTemplate")
    formBd:SetAllPoints()
    formBd:SetFrameLevel(form:GetFrameLevel())
    formBd:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    formBd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Output icon
    if form.OutputIcon then
        SkinOutputIcon(form.OutputIcon)
    end

    -- Hook Init to skin reagent slots as they're created
    hooksecurefunc(form, "Init", function(self)
        if self.reagentSlotPool then
            for slot in self.reagentSlotPool:EnumerateActive() do
                if slot.Button then
                    SkinReagentSlot(slot.Button)
                end
            end
        end
        if self.salvageSlot and self.salvageSlot.Button then
            SkinReagentSlot(self.salvageSlot.Button)
        end
        if self.enchantSlot and self.enchantSlot.Button then
            SkinReagentSlot(self.enchantSlot.Button)
        end
    end)

    -- Quality dialog
    if form.QualityDialog then
        SE:StripTextures(form.QualityDialog)
        local qdBd = CreateFrame("Frame", nil, form.QualityDialog, "BackdropTemplate")
        qdBd:SetAllPoints()
        qdBd:SetFrameLevel(form.QualityDialog:GetFrameLevel())
        qdBd:SetBackdrop(C.FLAT_BACKDROP)
        qdBd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        qdBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

        if form.QualityDialog.ClosePanelButton then
            SE:SkinCloseButton(form.QualityDialog.ClosePanelButton)
        elseif form.QualityDialog.CloseButton then
            SE:SkinCloseButton(form.QualityDialog.CloseButton)
        end

        -- Skin accept/cancel buttons
        if form.QualityDialog.AcceptButton then
            SE:SkinDropdownButton(form.QualityDialog.AcceptButton)
        end
        if form.QualityDialog.CancelButton then
            SE:SkinDropdownButton(form.QualityDialog.CancelButton)
        end
    end
end

---------------------------------------------------------------------------
-- Rank bar (profession skill progress)
---------------------------------------------------------------------------

local function SkinRankBar(rankBar)
    if not rankBar then return end

    if rankBar.Border then rankBar.Border:Hide() end
    if rankBar.Background then rankBar.Background:Hide() end

    -- Flat backdrop behind the rank bar (Fill is a Texture, not a Frame)
    do
        local fillBd = CreateFrame("Frame", nil, rankBar, "BackdropTemplate")
        fillBd:SetAllPoints(rankBar)
        fillBd:SetFrameLevel(math.max(rankBar:GetFrameLevel() - 1, 0))
        fillBd:SetBackdrop(C.FLAT_BACKDROP)
        fillBd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        fillBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    end

    -- Style rank text
    if rankBar.Rank and rankBar.Rank.Text then
        SE:StyleFont(rankBar.Rank.Text)
    end

    -- Expansion dropdown
    if rankBar.ExpansionDropdownButton then
        SE:SkinDropdownButton(rankBar.ExpansionDropdownButton)
    end
end

---------------------------------------------------------------------------
-- Profession tabs (tab system at top)
---------------------------------------------------------------------------

local function SkinTabs()
    if not ProfessionsFrame or not ProfessionsFrame.TabSystem then return end

    for _, tab in next, { ProfessionsFrame.TabSystem:GetChildren() } do
        if tab and not skinnedTabs[tab] then
            SE:SkinTab(tab)
            skinnedTabs[tab] = true
        end
    end
end

---------------------------------------------------------------------------
-- Specialization page
---------------------------------------------------------------------------

local function SkinSpecPage()
    local specPage = ProfessionsFrame.SpecPage
    if not specPage then return end

    if specPage.TreeView then
        SE:StripTextures(specPage.TreeView)
        if specPage.TreeView.Background then
            specPage.TreeView.Background:SetAlpha(0)
        end
    end

    if specPage.DetailedView then
        SE:StripTextures(specPage.DetailedView)
        if specPage.DetailedView.UnlockPathButton then
            SE:SkinDropdownButton(specPage.DetailedView.UnlockPathButton)
        end
        if specPage.DetailedView.SpendPointsButton then
            SE:SkinDropdownButton(specPage.DetailedView.SpendPointsButton)
        end
    end

    if specPage.PanelFooter then
        SE:StripTextures(specPage.PanelFooter)
    end

    -- Hide dividers
    if specPage.TopDivider then specPage.TopDivider:Hide() end
    if specPage.VerticalDivider then specPage.VerticalDivider:Hide() end

    -- Hook spec tabs if they use a pool
    if specPage.tabsPool then
        local function SkinSpecTabs()
            for tab in specPage.tabsPool:EnumerateActive() do
                if not skinnedTabs[tab] then
                    SE:SkinTab(tab)
                    skinnedTabs[tab] = true
                end
            end
        end
        hooksecurefunc(specPage, "UpdateTabs", SkinSpecTabs)
        SkinSpecTabs()
    end
end

---------------------------------------------------------------------------
-- Crafting orders page
---------------------------------------------------------------------------

local function SkinOrdersPage()
    local ordersPage = ProfessionsFrame.OrdersPage
    if not ordersPage then return end

    -- Order type tabs
    local orderTabs = { "PublicOrdersButton", "NpcOrdersButton", "GuildOrdersButton", "PersonalOrdersButton" }
    for _, tabName in ipairs(orderTabs) do
        if ordersPage[tabName] then
            SE:SkinDropdownButton(ordersPage[tabName])
        end
    end

    -- Browse frame
    if ordersPage.BrowseFrame then
        local browse = ordersPage.BrowseFrame

        if browse.RecipeList then
            SE:StripTextures(browse.RecipeList)
            if browse.RecipeList.BackgroundNineSlice then
                browse.RecipeList.BackgroundNineSlice:Hide()
            end
        end

        if browse.OrderList then
            SE:StripTextures(browse.OrderList)
        end

        if browse.BackButton then
            SE:SkinDropdownButton(browse.BackButton)
        end
    end

    -- Order view
    if ordersPage.OrderView then
        local orderView = ordersPage.OrderView

        -- Rank bar in order view
        if orderView.RankBar then
            SkinRankBar(orderView.RankBar)
        end

        -- Create button
        if orderView.CreateButton then
            SE:SkinDropdownButton(orderView.CreateButton)
        end

        -- Schematic form in order details
        if orderView.OrderDetails and orderView.OrderDetails.SchematicForm then
            SkinSchematicForm(orderView.OrderDetails.SchematicForm)
        end

        -- Order info section
        if orderView.OrderInfo then
            SE:StripTextures(orderView.OrderInfo)

            if orderView.OrderInfo.BackButton then
                SE:SkinDropdownButton(orderView.OrderInfo.BackButton)
            end
            if orderView.OrderInfo.StartOrderButton then
                SE:SkinDropdownButton(orderView.OrderInfo.StartOrderButton)
            end
            if orderView.OrderInfo.DeclineOrderButton then
                SE:SkinDropdownButton(orderView.OrderInfo.DeclineOrderButton)
            end
            if orderView.OrderInfo.ReleaseOrderButton then
                SE:SkinDropdownButton(orderView.OrderInfo.ReleaseOrderButton)
            end
        end

        -- Decline dialog
        if orderView.DeclineOrderDialog then
            SE:StripTextures(orderView.DeclineOrderDialog)
            local declineBd = CreateFrame("Frame", nil, orderView.DeclineOrderDialog, "BackdropTemplate")
            declineBd:SetAllPoints()
            declineBd:SetFrameLevel(orderView.DeclineOrderDialog:GetFrameLevel())
            declineBd:SetBackdrop(C.FLAT_BACKDROP)
            declineBd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
            declineBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end
    end
end

---------------------------------------------------------------------------
-- Crafting output log popup
---------------------------------------------------------------------------

local function SkinCraftingOutputLog(outputLog)
    if not outputLog then return end

    SE:StripTextures(outputLog)

    local logBd = CreateFrame("Frame", nil, outputLog, "BackdropTemplate")
    logBd:SetAllPoints()
    logBd:SetFrameLevel(outputLog:GetFrameLevel())
    logBd:SetBackdrop(C.FLAT_BACKDROP)
    logBd:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    logBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

    local closeBtn = outputLog.ClosePanelButton or outputLog.CloseButton
    if closeBtn then
        SE:SkinCloseButton(closeBtn)
    end

    -- Skin output log items as they scroll
    if outputLog.ScrollBox then
        hooksecurefunc(outputLog.ScrollBox, "Update", function(self)
            self:ForEachFrame(function(button)
                if not button or skinnedOutputButtons[button] then return end
                skinnedOutputButtons[button] = true

                if button.ItemContainer then
                    local item = button.ItemContainer.Item
                    if item then
                        if item.NameFrame then item.NameFrame:Hide() end
                        if item.Icon then
                            item.Icon:SetTexCoord(unpack(C.ICON_CROP))
                        end
                    end
                end
            end)
        end)
    end
end

---------------------------------------------------------------------------
-- Gear slot names
---------------------------------------------------------------------------

local GEAR_SLOT_NAMES = {
    "Prof0ToolSlot", "Prof0Gear0Slot", "Prof0Gear1Slot",
    "Prof1ToolSlot", "Prof1Gear0Slot", "Prof1Gear1Slot",
    "CookingToolSlot", "CookingGear0Slot",
    "FishingToolSlot", "FishingGear0Slot", "FishingGear1Slot",
}

---------------------------------------------------------------------------
-- Main frame orchestration
---------------------------------------------------------------------------

local function SkinMainFrame()
    if mainFrameSkinned then return end
    if not ProfessionsFrame then return end
    mainFrameSkinned = true

    local pf = ProfessionsFrame

    -- 1) Main window chrome
    SE:SkinWindow(pf)

    -- 2) Tabs
    SkinTabs()

    -- 3) Crafting page
    local craftingPage = pf.CraftingPage
    if craftingPage then
        -- Recipe list (left side)
        SkinRecipeList(craftingPage)

        -- Schematic form (right side)
        if craftingPage.SchematicForm then
            SkinSchematicForm(craftingPage.SchematicForm)
        end

        -- Rank bar
        if craftingPage.RankBar then
            SkinRankBar(craftingPage.RankBar)
        end

        -- Create / CreateAll buttons
        if craftingPage.CreateButton then
            SE:SkinDropdownButton(craftingPage.CreateButton)
        end
        if craftingPage.CreateAllButton then
            SE:SkinDropdownButton(craftingPage.CreateAllButton)
        end
        if craftingPage.ViewGuildCraftersButton then
            SE:SkinDropdownButton(craftingPage.ViewGuildCraftersButton)
        end

        -- Link button
        if craftingPage.LinkButton then
            SE:SkinDropdownButton(craftingPage.LinkButton)
        end

        -- Gear slots
        for _, slotName in ipairs(GEAR_SLOT_NAMES) do
            if craftingPage[slotName] then
                SkinGearSlot(craftingPage[slotName])
            end
        end

        -- Crafting output log
        if craftingPage.CraftingOutputLog then
            SkinCraftingOutputLog(craftingPage.CraftingOutputLog)
        end

        -- Guild frame
        if craftingPage.GuildFrame then
            SE:StripTextures(craftingPage.GuildFrame)
            if craftingPage.GuildFrame.Container then
                SE:StripTextures(craftingPage.GuildFrame.Container)
            end
        end
    end

    -- 4) Specialization page
    if pf.SpecPage then
        SkinSpecPage()
    end

    -- 5) Orders page
    if pf.OrdersPage then
        SkinOrdersPage()
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function ProfessionsSkin:Apply()
    SkinMainFrame()
end
