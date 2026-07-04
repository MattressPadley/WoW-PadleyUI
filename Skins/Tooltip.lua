local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local TooltipSkin = {}
ns.TooltipSkin = TooltipSkin

-- External tracking table (avoids writing keys to Blizzard frames)
local skinnedTooltips = {}

---------------------------------------------------------------------------
-- Tooltip lists
---------------------------------------------------------------------------

-- Tooltips that exist at load time
local TOOLTIPS = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "EmbeddedItemTooltip",
}

-- Tooltips created on demand (skinned lazily)
local LAZY_TOOLTIPS = {
    "ShoppingTooltip1",
    "ShoppingTooltip2",
}

---------------------------------------------------------------------------
-- Core skinning function
---------------------------------------------------------------------------

local function SkinTooltip(tooltip)
    if not tooltip or skinnedTooltips[tooltip] then return end

    -- Hide the NineSlice border via alpha-zero (preserves layout)
    if tooltip.NineSlice then
        tooltip.NineSlice:SetAlpha(0)
    end

    -- Use a plain frame + texture instead of BackdropTemplate to avoid taint.
    -- BackdropTemplate's SetupTextureCoordinates calls GetWidth() in Lua, which
    -- returns a secret value when the tooltip is shown via securecallfunction
    -- (e.g. loot). A plain texture anchors at the C level without Lua width calls.
    local bdFrame = CreateFrame("Frame", nil, tooltip)
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(tooltip:GetFrameLevel())
    local bgTex = bdFrame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    skinnedTooltips[tooltip] = bdFrame

    -- Re-apply on every show cycle (Blizzard can reset colors)
    tooltip:HookScript("OnShow", function(self)
        if self.NineSlice then
            self.NineSlice:SetAlpha(0)
        end
        local bg = C.BACKDROP_COLOR
        bgTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    end)
end

---------------------------------------------------------------------------
-- Health bar skinning
---------------------------------------------------------------------------

local function SkinHealthBar(tooltip)
    local statusBar = tooltip.StatusBar or GameTooltipStatusBar
    if not statusBar then return end

    SE:SkinStatusBar(statusBar, {
        color = { 0, 0.8, 0, 1 },
    })

    -- Plain texture backdrop (avoids BackdropTemplate taint in secure context)
    local bgFrame = CreateFrame("Frame", nil, statusBar)
    bgFrame:SetAllPoints()
    bgFrame:SetFrameLevel(statusBar:GetFrameLevel())
    local bgTex = bgFrame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 0.8)
end

---------------------------------------------------------------------------
-- Lazy tooltip skinning (for on-demand tooltips)
---------------------------------------------------------------------------

local function SkinLazyTooltips()
    for _, name in ipairs(LAZY_TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip then
            SkinTooltip(tooltip)
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function TooltipSkin:Apply()
    -- Skin all tooltips that exist at load time
    for _, name in ipairs(TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip then
            SkinTooltip(tooltip)
        end
    end

    -- Skin the GameTooltip health bar
    if GameTooltip then
        SkinHealthBar(GameTooltip)
    end

    -- Catch lazy tooltips (ShoppingTooltip1/2) on first appearance via the
    -- C-dispatched OnShow handler. HookScript is isolated per taint rules;
    -- hooksecurefunc(GameTooltip, "Show", ...) leaks the addon's insecure
    -- taint into the tooltip-build execution and breaks secret-number
    -- arithmetic in GameTooltip_AddWidgetSet (AreaPOI item-display widgets).
    if GameTooltip then
        GameTooltip:HookScript("OnShow", SkinLazyTooltips)
    end
end
