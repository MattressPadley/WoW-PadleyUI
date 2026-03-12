local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local LootSkin = {}
ns.LootSkin = LootSkin

-- External tracking tables (avoids writing keys to Blizzard frames)
local skinnedElements = {}   -- element -> bdFrame
local skinnedIcons = {}      -- itemButton -> iconBdFrame
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
-- Loot icon skinning
---------------------------------------------------------------------------

local function RemoveAllMasks(texture, frame)
    -- Remove masks from direct regions
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "MaskTexture" then
            texture:RemoveMaskTexture(region)
            region:Hide()
        end
    end
    -- Remove masks from child frames
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "MaskTexture" then
                    texture:RemoveMaskTexture(region)
                    region:Hide()
                end
            end
        end
    end
end

local function SkinLootIcon(button)
    if not button or skinnedIcons[button] then return end

    local icon = button.icon or button.Icon
    if not icon then return end

    -- Strip normal/pushed textures
    local normalTex = button.GetNormalTexture and button:GetNormalTexture()
    if normalTex then normalTex:SetAlpha(0) end
    local pushedTex = button.GetPushedTexture and button:GetPushedTexture()
    if pushedTex then pushedTex:SetAlpha(0) end

    -- Hide Blizzard icon border
    if button.IconBorder then button.IconBorder:Hide() end

    -- Remove ALL masks from icon (regions, children, named)
    RemoveAllMasks(icon, button)
    if button.IconMask then
        icon:RemoveMaskTexture(button.IconMask)
        button.IconMask:Hide()
    end
    if button.CircleMask then
        icon:RemoveMaskTexture(button.CircleMask)
        button.CircleMask:Hide()
    end
    icon:SetTexCoord(unpack(C.ICON_CROP))

    -- Also remove masks from IconBorder so it can't clip rounded
    if button.IconBorder then
        RemoveAllMasks(button.IconBorder, button)
        if button.IconMask then button.IconBorder:RemoveMaskTexture(button.IconMask) end
        if button.CircleMask then button.IconBorder:RemoveMaskTexture(button.CircleMask) end
    end

    -- Remove masks from highlight and replace with flat texture
    local highlightTex = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlightTex then
        RemoveAllMasks(highlightTex, button)
        if button.IconMask then highlightTex:RemoveMaskTexture(button.IconMask) end
        if button.CircleMask then highlightTex:RemoveMaskTexture(button.CircleMask) end
        highlightTex:SetTexture(C.BAR_TEXTURE)
        highlightTex:SetVertexColor(unpack(C.HIGHLIGHT_OVERLAY))
        highlightTex:SetAllPoints(icon)
    end

    -- Child backdrop behind the icon
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
        edgeFile = C.FLAT_BACKDROP.edgeFile,
        edgeSize = C.BORDER_SIZE,
    })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    bdFrame:EnableMouse(false)

    -- Hook IconBorder:Show to reactively apply quality color
    if button.IconBorder then
        hooksecurefunc(button.IconBorder, "Show", function(iconBorder)
            local r, g, b = iconBorder:GetVertexColor()
            iconBorder:Hide()
            if ITEM_QUALITY_COLORS then
                for q = 7, 0, -1 do
                    local qc = ITEM_QUALITY_COLORS[q]
                    if qc and math.abs(qc.r - r) < 0.05 and math.abs(qc.g - g) < 0.05 and math.abs(qc.b - b) < 0.05 then
                        if q >= 2 then
                            bdFrame:SetBackdropBorderColor(qc.r, qc.g, qc.b, 1)
                        else
                            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
                        end
                        return
                    end
                end
            end
            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end)
    end

    skinnedIcons[button] = bdFrame
end

---------------------------------------------------------------------------
-- Loot element skinning
---------------------------------------------------------------------------

local function SkinLootElement(element)
    if not element then return end

    local bdFrame = skinnedElements[element]

    if not bdFrame then
        -- Hide HighlightNameFrame and PushedNameFrame (rounded hover/push overlays)
        if element.HighlightNameFrame then
            element.HighlightNameFrame:Hide()
            hooksecurefunc(element.HighlightNameFrame, "Show", function(self) self:Hide() end)
        end
        if element.PushedNameFrame then
            element.PushedNameFrame:Hide()
            hooksecurefunc(element.PushedNameFrame, "Show", function(self) self:Hide() end)
        end

        -- Strip textures on the element frame only (not children — icons handled by SkinLootIcon)
        for i = 1, element:GetNumRegions() do
            local region = select(i, element:GetRegions())
            if region and region:GetObjectType() == "Texture" then
                local layer = region:GetDrawLayer()
                if layer == "BACKGROUND" or layer == "BORDER" or layer == "HIGHLIGHT" then
                    region:SetTexture(nil)
                    region:SetAtlas("")
                    region:SetAlpha(0)
                end
                if region:GetAtlas() and region:GetAtlas():find("raritytag") then
                    region:SetAlpha(0)
                end
            end
        end

        -- Skin item buttons
        for i = 1, select("#", element:GetChildren()) do
            local child = select(i, element:GetChildren())
            local ctype = child:GetObjectType()
            if ctype == "Button" or ctype == "ItemButton" then
                if child:GetPushedTexture() then child:GetPushedTexture():SetTexture("") end
                SkinLootIcon(child)
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
        xText:SetFont(C.FONT, C.FONT_SIZE_SMALL, C.FONT_FLAGS)
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
