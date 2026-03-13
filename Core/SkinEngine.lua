local _, ns = ...

local C = ns.C
local SkinEngine = {}
ns.SkinEngine = SkinEngine

--- Strip all textures from a frame's regions.
--- @param frame table The frame to strip
--- @param kill boolean If true, permanently hide textures (prevent re-show)
function SkinEngine:StripTextures(frame, kill)
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            if kill then
                region:Hide()
                region.Show = region.Hide
            else
                region:SetTexture(nil)
                region:SetAtlas("")
            end
        end
    end
end

--- Apply a flat backdrop with pixel border to a frame.
--- @param frame table The target frame
--- @param opts table|nil Optional overrides { bgColor, borderColor, borderSize }
function SkinEngine:ApplyBackdrop(frame, opts)
    opts = opts or {}

    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end

    local backdrop = {
        bgFile = C.FLAT_BACKDROP.bgFile,
    }

    frame:SetBackdrop(backdrop)

    local bg = opts.bgColor or C.BACKDROP_COLOR
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
end

--- Skin a StatusBar with a flat texture.
--- @param bar table The StatusBar frame
--- @param opts table|nil Optional { texture, color }
function SkinEngine:SkinStatusBar(bar, opts)
    opts = opts or {}
    bar:SetStatusBarTexture(opts.texture or C.BAR_TEXTURE)

    if opts.color then
        bar:SetStatusBarColor(opts.color[1], opts.color[2], opts.color[3], opts.color[4] or 1)
    end
end

--- Hook a texture region's SetTexture to keep it cleared.
--- Uses hooksecurefunc to avoid taint.
--- @param region table The texture region to keep cleared
function SkinEngine:HookTextureRemoval(region)
    if region._padleyHooked then return end
    region._padleyHooked = true

    hooksecurefunc(region, "SetTexture", function(self)
        if self:GetTexture() then
            self:SetTexture(nil)
        end
    end)
end

--- Hook a texture region's SetAtlas to keep it cleared.
--- @param region table The texture region to keep cleared
function SkinEngine:HookAtlasRemoval(region)
    if region._padleyAtlasHooked then return end
    region._padleyAtlasHooked = true

    hooksecurefunc(region, "SetAtlas", function(self)
        self:SetAtlas("")
    end)
end

--- Style a FontString with the addon's default font settings.
--- @param fontString table The FontString to style
--- @param size number|nil Optional font size override
--- @param flags string|nil Optional font flags override
function SkinEngine:StyleFont(fontString, size, flags)
    if not fontString or not fontString.SetFont then return end
    fontString:SetFont(C.FONT, size or C.FONT_SIZE, flags or C.FONT_FLAGS)
end

-- Track skinned frames externally (avoids writing keys to Blizzard frames)
local skinnedButtons = {}
local skinnedCloseButtons = {}
local skinnedTabs = {}
local windowBackdrops = {}

--- Skin a dropdown/button that uses ButtonStateBehaviorMixin.
--- Uses alpha-zero pattern: hides Blizzard textures via SetAlpha(0) so they
--- stay invisible even when OnButtonStateChanged() re-applies atlases.
--- Uses a separate child frame for backdrop to avoid Mixin on Blizzard frames.
--- @param button table The button frame
--- @param opts table|nil Optional { bgColor, borderColor }
function SkinEngine:SkinDropdownButton(button, opts)
    if not button or skinnedButtons[button] then return end
    skinnedButtons[button] = true
    opts = opts or {}

    -- A) Alpha-zero all known Blizzard child textures.
    --    OnButtonStateChanged() will keep calling SetAtlas on these,
    --    but alpha=0 persists so they remain invisible.
    if button.Arrow then button.Arrow:SetAlpha(0) end
    if button.Background then button.Background:SetAlpha(0) end
    if button.Icon then button.Icon:SetAlpha(0) end

    -- Clear standard button textures
    if button.SetNormalTexture then button:SetNormalTexture("") end
    if button.SetHighlightTexture then button:SetHighlightTexture("") end
    if button.SetPushedTexture then button:SetPushedTexture("") end
    if button.SetDisabledTexture then button:SetDisabledTexture("") end

    -- B) Separate child frame for backdrop (avoids Mixin(blizzardFrame, BackdropTemplateMixin))
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(button:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    local bg = opts.bgColor or C.HEADER_COLOR
    bdFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])

    -- C) Hook OnEnter/OnLeave for hover bg highlight
    button:HookScript("OnEnter", function()
        bdFrame:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    button:HookScript("OnLeave", function()
        bdFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    end)

    -- D) Style any text on the button
    local text = button.Text or (button.GetFontString and button:GetFontString())
    if text then
        self:StyleFont(text)
    end
end

--- Skin a close button with a flat "x" style.
--- Does NOT call SetSize on the Blizzard button (avoids taint).
--- @param button table The close button frame
function SkinEngine:SkinCloseButton(button)
    if not button or skinnedCloseButtons[button] then return end
    skinnedCloseButtons[button] = true

    self:StripTextures(button)
    if button.SetNormalTexture then button:SetNormalTexture("") end
    if button.SetHighlightTexture then button:SetHighlightTexture("") end
    if button.SetPushedTexture then button:SetPushedTexture("") end
    if button.SetDisabledTexture then button:SetDisabledTexture("") end

    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetPoint("TOPLEFT", 1, -1)
    bdFrame:SetPoint("BOTTOMRIGHT", -1, 1)
    bdFrame:SetFrameLevel(button:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    local xText = bdFrame:CreateFontString(nil, "OVERLAY")
    xText:SetFont(C.FONT, C.FONT_SIZE_SMALL, C.FONT_FLAGS)
    xText:SetPoint("CENTER", 0, 0)
    xText:SetText("x")

    button:HookScript("OnEnter", function()
        bdFrame:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    button:HookScript("OnLeave", function()
        bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    end)

    return bdFrame
end

--- Skin a PanelTabButtonTemplate tab with flat style.
--- @param tab table The tab button frame
function SkinEngine:SkinTab(tab)
    if not tab or skinnedTabs[tab] then return end
    skinnedTabs[tab] = true

    self:StripTextures(tab)
    if tab.SetNormalTexture then tab:SetNormalTexture("") end
    if tab.SetHighlightTexture then tab:SetHighlightTexture("") end
    if tab.SetPushedTexture then tab:SetPushedTexture("") end
    if tab.SetDisabledTexture then tab:SetDisabledTexture("") end

    local bdFrame = CreateFrame("Frame", nil, tab, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(tab:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    local text = tab.Text or (tab.GetFontString and tab:GetFontString())
    if text then
        self:StyleFont(text)
        text:SetParent(bdFrame)
    end

    tab:HookScript("OnEnter", function()
        bdFrame:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    tab:HookScript("OnLeave", function()
        bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    end)

    return bdFrame
end

--- Skin a PortraitFrame / ButtonFrameTemplate window with flat style.
--- Creates a child BackdropTemplate frame (never Mixin on Blizzard frame).
--- Idempotent via windowBackdrops tracking table.
--- @param frame table The window frame
--- @param opts table|nil Optional flags: noCloseButton, noTitle, noPortrait, noBg, noNineSlice
--- @return table The backdrop frame
function SkinEngine:SkinWindow(frame, opts)
    if not frame then return end
    if windowBackdrops[frame] then return windowBackdrops[frame] end
    opts = opts or {}

    -- Hide NineSlice border
    if not opts.noNineSlice and frame.NineSlice then
        frame.NineSlice:SetAlpha(0)
    end

    -- Hide background
    if not opts.noBg and frame.Bg then
        if frame.Bg.SetAlpha then
            -- Some Bg frames have sub-regions (TopSection, BottomLeft, etc.)
            if frame.Bg.TopSection then frame.Bg.TopSection:SetAlpha(0) end
            if frame.Bg.BottomLeft then frame.Bg.BottomLeft:SetAlpha(0) end
            if frame.Bg.BottomRight then frame.Bg.BottomRight:SetAlpha(0) end
            if frame.Bg.BottomEdge then frame.Bg.BottomEdge:SetAlpha(0) end
            -- Flat texture variant
            if frame.Bg.GetObjectType and frame.Bg:GetObjectType() == "Texture" then
                frame.Bg:SetAlpha(0)
            end
            -- Frame variant — hide all child textures
            if frame.Bg.GetNumRegions then
                for i = 1, frame.Bg:GetNumRegions() do
                    local region = select(i, frame.Bg:GetRegions())
                    if region and region:GetObjectType() == "Texture" then
                        region:SetAlpha(0)
                    end
                end
            end
        end
    end

    -- Hide portrait
    if not opts.noPortrait and frame.PortraitContainer then
        frame.PortraitContainer:SetAlpha(0)
    end

    -- Hide top tile streaks
    if frame.TopTileStreaks then
        frame.TopTileStreaks:SetAlpha(0)
    end

    -- Create flat backdrop as child frame
    local bdFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(frame:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Style title text
    if not opts.noTitle and frame.TitleContainer and frame.TitleContainer.TitleText then
        self:StyleFont(frame.TitleContainer.TitleText)
    end

    -- Skin close button
    if not opts.noCloseButton then
        local closeBtn = frame.ClosePanelButton or frame.CloseButton
        if closeBtn then
            self:SkinCloseButton(closeBtn)
        end
    end

    windowBackdrops[frame] = bdFrame
    return bdFrame
end
