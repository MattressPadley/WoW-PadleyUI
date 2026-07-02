local _, ns = ...
local C = ns.C

local BetterBagsSkin = {}
ns.BetterBagsSkin = BetterBagsSkin

local decoratorFrames = {}  -- frame name -> decoration
local itemButtons = {}      -- button name -> { decoration, bdFrame }
local decorationBorders = {}  -- decoration frame AND item button -> bdFrame
local mirroredBorders = {}  -- IconBorder -> true (avoid double-hooking)

---------------------------------------------------------------------------
-- Helper: rarity border colouring
---------------------------------------------------------------------------

local function ResetBorderColor(bdFrame)
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
end

-- Keep an ItemButton's rounded IconBorder invisible and mirror its rarity
-- colour onto our flat bdFrame. Safe to call for both the decoration's and the
-- underlying button's IconBorder (deduped by object) — BetterBags drives the
-- quality colour on the real item button, not our blank decoration.
local function MirrorIconBorder(iconBorder, bdFrame)
    if not iconBorder then return end
    iconBorder:SetAlpha(0)
    if mirroredBorders[iconBorder] then return end
    mirroredBorders[iconBorder] = true

    hooksecurefunc(iconBorder, "Show", function(self)
        self:SetAlpha(0)
    end)
    hooksecurefunc(iconBorder, "SetVertexColor", function(_, r, g, b)
        if r and g and b and not (r == 1 and g == 1 and b == 1) then
            bdFrame:SetBackdropBorderColor(r, g, b, 1)
        else
            ResetBorderColor(bdFrame)
        end
    end)
    hooksecurefunc(iconBorder, "Hide", function()
        ResetBorderColor(bdFrame)
    end)
end

---------------------------------------------------------------------------
-- Helper: shared decoration with flat backdrop
---------------------------------------------------------------------------

local function CreateDecoration(frame)
    local name = frame:GetName()
    local decoration = decoratorFrames[name]
    if decoration then
        decoration:Show()
        return decoration, false
    end

    decoration = CreateFrame("Frame", name .. "PadleyUI", frame)
    decoration:SetAllPoints()
    decoration:SetFrameLevel(frame:GetFrameLevel() - 1)

    decoration.bg = CreateFrame("Frame", nil, decoration, "BackdropTemplate")
    decoration.bg:SetAllPoints()
    decoration.bg:SetFrameLevel(frame:GetFrameLevel() - 1)
    decoration.bg:SetBackdrop(C.FLAT_BACKDROP)
    decoration.bg:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    decoration.bg:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

    decoratorFrames[name] = decoration
    return decoration, true
end

---------------------------------------------------------------------------
-- Helper: add title to decoration
---------------------------------------------------------------------------

local function AddTitle(decoration, themes, frameName)
    local title = decoration:CreateFontString(nil, "OVERLAY")
    title:SetFont(C.FONT, C.FONT_SIZE, C.FONT_FLAGS)
    title:SetPoint("TOP", decoration, "TOP", 0, 0)
    title:SetHeight(30)
    decoration.title = title

    if themes.titles[frameName] then
        title:SetText(themes.titles[frameName])
    end
end

---------------------------------------------------------------------------
-- Helper: add flat close button
---------------------------------------------------------------------------

local function AddCloseButton(decoration, frame, addon, isPortrait)
    local close = CreateFrame("Button", nil, decoration)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", decoration, "TOPRIGHT", -4, -4)
    close:SetFrameLevel(1001)

    local closeBd = CreateFrame("Frame", nil, close, "BackdropTemplate")
    closeBd:SetPoint("TOPLEFT", 1, -1)
    closeBd:SetPoint("BOTTOMRIGHT", -1, 1)
    closeBd:SetFrameLevel(close:GetFrameLevel())
    closeBd:SetBackdrop(C.FLAT_BACKDROP)
    closeBd:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    closeBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

    local xText = closeBd:CreateFontString(nil, "OVERLAY")
    xText:SetFont(C.FONT, C.FONT_SIZE_SMALL, C.FONT_FLAGS)
    xText:SetPoint("CENTER", 0, 0)
    xText:SetText("x")

    close:HookScript("OnEnter", function()
        closeBd:SetBackdropBorderColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    close:HookScript("OnLeave", function()
        closeBd:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    end)

    if isPortrait then
        addon.SetScript(close, "OnClick", function(ctx)
            frame.Owner:Hide(ctx)
        end)
    else
        close:SetScript("OnClick", function()
            frame:Hide()
        end)
    end
end

---------------------------------------------------------------------------
-- Apply: register theme with BetterBags
---------------------------------------------------------------------------

function BetterBagsSkin:Apply()
    local bb = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
    local themes = bb:GetModule('Themes')
    local searchBox = bb:GetModule('SearchBox')

    ---@type Theme
    local padleyTheme = {
        Name = 'PadleyUI',
        Description = 'Flat dark theme matching PadleyUI.',
        Available = true,
        DisableMasque = true,

        Portrait = function(frame)
            local decoration, isNew = CreateDecoration(frame)
            if not isNew then return end

            AddTitle(decoration, themes, frame:GetName())
            AddCloseButton(decoration, frame, bb, true)

            local box = searchBox:CreateBox(frame.Owner.kind, decoration)
            box.frame:SetPoint("TOPLEFT", decoration, "TOPLEFT", 20, -40)
            box.frame:SetPoint("BOTTOMRIGHT", decoration, "TOPRIGHT", -10, -60)
            decoration.search = box

            local bagButton = themes.SetupBagButton(frame.Owner, decoration)
            bagButton:SetPoint("TOPLEFT", decoration, "TOPLEFT", 4, -6)
            local w, h = bagButton.portrait:GetSize()
            bagButton.portrait:SetSize((w / 10) * 8.5, (h / 10) * 8.5)
            bagButton.highlightTex:SetSize((w / 10) * 8.5, (h / 10) * 8.5)
        end,

        Simple = function(frame)
            local decoration, isNew = CreateDecoration(frame)
            if not isNew then return end

            AddTitle(decoration, themes, frame:GetName())
            AddCloseButton(decoration, frame, bb, false)
        end,

        Flat = function(frame)
            local decoration, isNew = CreateDecoration(frame)
            if not isNew then return end

            AddTitle(decoration, themes, frame:GetName())
        end,

        Opacity = function(frame, alpha)
            local decoration = decoratorFrames[frame:GetName()]
            if decoration then
                decoration.bg:SetAlpha(alpha / 100)
            end
        end,

        SectionFont = function(font)
            font:SetFont(C.FONT, C.FONT_SIZE, C.FONT_FLAGS)
        end,

        SetTitle = function(frame, title)
            local decoration = decoratorFrames[frame:GetName()]
            if decoration then
                decoration.title:SetText(title)
            end
        end,

        ToggleSearch = function(frame, shown)
            local decoration = decoratorFrames[frame:GetName()]
            if decoration and decoration.search then
                decoration.search:SetShown(shown)
            end
        end,

        Reset = function()
            for _, frame in pairs(decoratorFrames) do
                frame:Hide()
            end
            for _, entry in pairs(itemButtons) do
                entry.decoration:Hide()
            end
        end,

        ItemButton = function(item)
            local buttonName = item.button:GetName()
            local entry = itemButtons[buttonName]
            if entry then
                entry.decoration:Show()
                return entry.decoration
            end

            local decoration = themes.CreateBlankItemButtonDecoration(item.frame, "PadleyUI", buttonName)

            -- Kill the rounded NormalTexture (slot border)
            if decoration.NormalTexture then
                decoration.NormalTexture:SetTexture("")
                decoration.NormalTexture:SetAlpha(0)
            end
            local normalTex = decoration.GetNormalTexture and decoration:GetNormalTexture()
            if normalTex and normalTex ~= decoration.NormalTexture then
                normalTex:SetTexture("")
                normalTex:SetAlpha(0)
            end

            -- Kill pushed texture
            local pushedTex = decoration.GetPushedTexture and decoration:GetPushedTexture()
            if pushedTex then pushedTex:SetAlpha(0) end

            -- Hide the rounded IconBorder — we keep it alive but invisible
            -- so BetterBags can still call methods on it without error
            if decoration.IconBorder then
                decoration.IconBorder:SetAlpha(0)
            end

            -- Remove masks for square icons
            if decoration.IconMask then
                if decoration.IconTexture then
                    decoration.IconTexture:RemoveMaskTexture(decoration.IconMask)
                end
                decoration.IconMask:Hide()
            end

            -- Crop icon
            if decoration.IconTexture then
                decoration.IconTexture:SetTexCoord(unpack(C.ICON_CROP))
            end

            -- Flat highlight
            local ht = decoration.GetHighlightTexture and decoration:GetHighlightTexture()
            if ht then
                ht:SetTexture(C.BAR_TEXTURE)
                ht:SetVertexColor(unpack(C.HIGHLIGHT_OVERLAY))
                if decoration.IconTexture then ht:SetAllPoints(decoration.IconTexture) end
            end

            -- Child backdrop behind icon for our flat border
            local bdFrame = CreateFrame("Frame", nil, decoration, "BackdropTemplate")
            bdFrame:SetAllPoints()
            bdFrame:SetFrameLevel(math.max(decoration:GetFrameLevel() - 1, 0))
            bdFrame:SetBackdrop(C.FLAT_BACKDROP)
            bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
            bdFrame:EnableMouse(false)

            -- Mirror the rarity colour onto our flat border. BetterBags renders
            -- item icon/quality on the underlying item button, not on our blank
            -- decoration, so the real colour arrives on the BUTTON's IconBorder
            -- (and via SetItemButtonQuality(button, ...)). Mirror both IconBorders
            -- and key the lookup by both objects so quality resolves regardless of
            -- which one BetterBags drives.
            local button = item.button
            MirrorIconBorder(decoration.IconBorder, bdFrame)
            MirrorIconBorder(button and button.IconBorder, bdFrame)

            decorationBorders[decoration] = bdFrame
            if button then decorationBorders[button] = bdFrame end

            itemButtons[buttonName] = { decoration = decoration, bdFrame = bdFrame }
            return decoration
        end,
    }

    themes:RegisterTheme('PadleyUI', padleyTheme)

    hooksecurefunc("SetItemButtonQuality", function(button, quality)
        local bdFrame = decorationBorders[button]
        if not bdFrame then return end
        if quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        else
            ResetBorderColor(bdFrame)
        end
    end)
end
