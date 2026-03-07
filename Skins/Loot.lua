local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local LootSkin = {}
ns.LootSkin = LootSkin

-- External tracking tables (avoids writing keys to Blizzard frames)
local skinnedElements = {}   -- element -> bdFrame
local mainFrameSkinned = false

---------------------------------------------------------------------------
-- Quality border color
---------------------------------------------------------------------------

local function UpdateElementBorder(element, bdFrame)
    local quality
    if element.GetElementData then
        local ok, data = pcall(element.GetElementData, element)
        if ok and data then
            quality = data.quality or data.itemQuality
        end
    end
    if quality and quality > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
    else
        bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    end
end

---------------------------------------------------------------------------
-- Loot element skinning
---------------------------------------------------------------------------

local function SkinLootElement(element)
    if not element then return end

    local bdFrame = skinnedElements[element]

    if not bdFrame then
        -- Hide all non-quest texture regions (bg, border, highlight, raritytag)
        for i = 1, element:GetNumRegions() do
            local region = select(i, element:GetRegions())
            if region and region:GetObjectType() == "Texture" then
                local layer = region:GetDrawLayer()
                if layer == "BACKGROUND" or layer == "BORDER" or layer == "HIGHLIGHT" then
                    region:SetAlpha(0)
                end
                local atlas = region:GetAtlas()
                if atlas and atlas:find("raritytag") then
                    region:SetAlpha(0)
                end
            end
        end

        -- Kill highlight/pushed textures on child buttons (SetTexture clears the
        -- rounded default art so the button's built-in hover can't show it)
        for i = 1, select("#", element:GetChildren()) do
            local child = select(i, element:GetChildren())
            local ctype = child:GetObjectType()
            if ctype == "Button" or ctype == "ItemButton" then
                if child:GetHighlightTexture() then child:GetHighlightTexture():SetTexture("") end
                if child:GetPushedTexture() then child:GetPushedTexture():SetTexture("") end
                child:SetHighlightTexture("")
            end
        end

        -- Create flat backdrop
        bdFrame = CreateFrame("Frame", nil, element, "BackdropTemplate")
        bdFrame:SetAllPoints()
        bdFrame:SetFrameLevel(element:GetFrameLevel())
        bdFrame:SetBackdrop({
            bgFile   = C.FLAT_BACKDROP.bgFile,
            edgeFile = C.FLAT_BACKDROP.edgeFile,
            edgeSize = C.BORDER_SIZE,
        })
        bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
        bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        bdFrame:EnableMouse(false)

        skinnedElements[element] = bdFrame

        -- Hover highlight via child ItemButton (not the element frame)
        for i = 1, select("#", element:GetChildren()) do
            local child = select(i, element:GetChildren())
            local ctype = child:GetObjectType()
            if ctype == "Button" or ctype == "ItemButton" then
                child:HookScript("OnEnter", function()
                    bdFrame:SetBackdropBorderColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
                end)
                child:HookScript("OnLeave", function()
                    UpdateElementBorder(element, bdFrame)
                end)
                break
            end
        end

        -- Style font strings
        for i = 1, element:GetNumRegions() do
            local region = select(i, element:GetRegions())
            if region and region:GetObjectType() == "FontString" then
                SE:StyleFont(region)
            end
        end
    end

    -- Always update quality border (elements get recycled by ScrollBox)
    UpdateElementBorder(element, bdFrame)
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
