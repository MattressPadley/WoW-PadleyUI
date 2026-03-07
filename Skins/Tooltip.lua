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
    skinnedTooltips[tooltip] = true

    -- Hide the NineSlice border via alpha-zero (preserves layout)
    if tooltip.NineSlice then
        tooltip.NineSlice:SetAlpha(0)
    end

    -- Apply flat backdrop directly (tooltips are NOT secure frames)
    SE:ApplyBackdrop(tooltip)

    -- Re-apply on every show cycle (Blizzard can reset colors)
    tooltip:HookScript("OnShow", function(self)
        if self.NineSlice then
            self.NineSlice:SetAlpha(0)
        end
        local bg = C.BACKDROP_COLOR
        self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        local border = C.BORDER_COLOR
        self:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
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

    SE:ApplyBackdrop(statusBar, {
        bgColor = { 0, 0, 0, 0.8 },
    })
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

    -- Hook GameTooltip:Show to catch lazy tooltips on first appearance
    if GameTooltip and GameTooltip.Show then
        hooksecurefunc(GameTooltip, "Show", SkinLazyTooltips)
    end
end
