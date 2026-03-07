local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local LootSkin = {}
ns.LootSkin = LootSkin

-- External tracking tables (avoids writing keys to Blizzard frames)
local skinnedElements = {}
local mainFrameSkinned = false

---------------------------------------------------------------------------
-- Loot element skinning
---------------------------------------------------------------------------

local function SkinLootElement(element)
    if not element or skinnedElements[element] then return end
    skinnedElements[element] = true

    -- Hide BACKGROUND and BORDER layer textures (itemcard bg/border atlases)
    -- Keep OVERLAY textures (quest icon, highlight, pushed)
    for i = 1, element:GetNumRegions() do
        local region = select(i, element:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            local layer = region:GetDrawLayer()
            if layer == "BACKGROUND" or layer == "BORDER" then
                region:SetAlpha(0)
            end
            -- Also hide QualityStripe (OVERLAY layer, raritytag atlas)
            local atlas = region:GetAtlas()
            if atlas and atlas:find("raritytag") then
                region:SetAlpha(0)
            end
        end
    end

    -- Create a flat backdrop child frame for the element
    local bdFrame = CreateFrame("Frame", nil, element, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(element:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
        edgeFile = C.FLAT_BACKDROP.edgeFile,
        edgeSize = C.BORDER_SIZE,
    })
    local bg = C.HEADER_COLOR
    bdFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    local border = C.BORDER_COLOR
    bdFrame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])

    -- Style font strings (item name, quality text)
    for i = 1, element:GetNumRegions() do
        local region = select(i, element:GetRegions())
        if region and region:GetObjectType() == "FontString" then
            SE:StyleFont(region)
        end
    end
end

---------------------------------------------------------------------------
-- Main frame skinning
---------------------------------------------------------------------------

local function SkinLootFrame()
    if mainFrameSkinned then return end
    mainFrameSkinned = true

    local lf = LootFrame

    -- Hide NineSlice border
    if lf.NineSlice then
        lf.NineSlice:SetAlpha(0)
    end

    -- Hide background regions
    if lf.Bg then
        if lf.Bg.TopSection then lf.Bg.TopSection:SetAlpha(0) end
        if lf.Bg.BottomLeft then lf.Bg.BottomLeft:SetAlpha(0) end
        if lf.Bg.BottomRight then lf.Bg.BottomRight:SetAlpha(0) end
        if lf.Bg.BottomEdge then lf.Bg.BottomEdge:SetAlpha(0) end
    end

    -- Apply flat backdrop
    SE:ApplyBackdrop(lf)

    -- Style the title text
    if lf.TitleContainer and lf.TitleContainer.TitleText then
        SE:StyleFont(lf.TitleContainer.TitleText)
    end

    -- Skin the close button
    if lf.ClosePanelButton then
        SE:StripTextures(lf.ClosePanelButton)
        lf.ClosePanelButton:SetNormalTexture("")
        lf.ClosePanelButton:SetHighlightTexture("")
        lf.ClosePanelButton:SetPushedTexture("")
        lf.ClosePanelButton:SetSize(22, 22)

        local closeBd = CreateFrame("Frame", nil, lf.ClosePanelButton, "BackdropTemplate")
        closeBd:SetPoint("TOPLEFT", 1, -1)
        closeBd:SetPoint("BOTTOMRIGHT", -1, 1)
        closeBd:SetFrameLevel(lf.ClosePanelButton:GetFrameLevel())
        closeBd:SetBackdrop({
            bgFile   = C.FLAT_BACKDROP.bgFile,
            edgeFile = C.FLAT_BACKDROP.edgeFile,
            edgeSize = C.BORDER_SIZE,
        })
        closeBd:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
        closeBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

        -- Add an "X" label
        local xText = closeBd:CreateFontString(nil, "OVERLAY")
        xText:SetFont(C.FONT, 10, C.FONT_FLAGS)
        xText:SetPoint("CENTER", 0, 0)
        xText:SetText("x")

        -- Hover highlight
        lf.ClosePanelButton:HookScript("OnEnter", function()
            closeBd:SetBackdropBorderColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
        end)
        lf.ClosePanelButton:HookScript("OnLeave", function()
            closeBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end)
    end

    -- Helper to skin all current ScrollBox elements
    local function SkinAllElements()
        if lf.ScrollBox and lf.ScrollBox.ForEachFrame then
            lf.ScrollBox:ForEachFrame(SkinLootElement)
        end
    end

    -- Hook ScrollBox to skin loot elements as they're acquired
    if lf.ScrollBox then
        hooksecurefunc(lf.ScrollBox, "Update", function()
            SkinAllElements()
        end)
    end

    -- Hook OnShow to skin elements after the frame is displayed
    -- Deferred to next frame so ScrollBox has populated its elements
    lf:HookScript("OnShow", function()
        C_Timer.After(0, SkinAllElements)
    end)

    -- Skin any elements already visible
    SkinAllElements()
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function LootSkin:Apply()
    SkinLootFrame()
end
