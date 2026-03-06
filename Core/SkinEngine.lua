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
        edgeFile = C.FLAT_BACKDROP.edgeFile,
        edgeSize = opts.borderSize or C.BORDER_SIZE,
    }

    frame:SetBackdrop(backdrop)

    local bg = opts.bgColor or C.BACKDROP_COLOR
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])

    local border = opts.borderColor or C.BORDER_COLOR
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
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

--- Skin a dropdown/button that uses ButtonStateBehaviorMixin.
--- Uses alpha-zero pattern: hides Blizzard textures via SetAlpha(0) so they
--- stay invisible even when OnButtonStateChanged() re-applies atlases.
--- @param button table The button frame
--- @param opts table|nil Optional { bgColor, borderColor }
function SkinEngine:SkinDropdownButton(button, opts)
    if not button or button._padleySkinned then return end
    button._padleySkinned = true
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

    -- B) Apply flat backdrop as our replacement visual
    self:ApplyBackdrop(button, {
        bgColor = opts.bgColor or C.HEADER_COLOR,
        borderColor = opts.borderColor or C.BORDER_COLOR,
    })

    -- C) Hook OnEnter/OnLeave for hover border highlight
    button:HookScript("OnEnter", function(btn)
        if btn.SetBackdropBorderColor then
            btn:SetBackdropBorderColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
        end
    end)
    button:HookScript("OnLeave", function(btn)
        if btn.SetBackdropBorderColor then
            btn:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end
    end)

    -- D) Style any text on the button
    local text = button.Text or (button.GetFontString and button:GetFontString())
    if text then
        self:StyleFont(text)
    end
end
