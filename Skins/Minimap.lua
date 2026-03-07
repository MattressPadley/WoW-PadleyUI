local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local MinimapSkin = {}
ns.MinimapSkin = MinimapSkin

local skinApplied = false

-- Track skinned addon buttons externally
local skinnedButtons = {}

-- Blizzard frames we should NOT treat as addon buttons
local blizzardChildren = {}

---------------------------------------------------------------------------
-- Strip border/decoration textures from a frame's regions
---------------------------------------------------------------------------

local function StripRegionTextures(frame)
    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Skin a single addon minimap button (LibDBIcon style)
-- Strips the border overlay but keeps the icon, making a borderless circle.
---------------------------------------------------------------------------

local function SkinMinimapButton(button)
    if not button or skinnedButtons[button] then return end
    if blizzardChildren[button] then return end

    -- Must be a Button-type frame with an icon texture
    if not button.GetObjectType or button:GetObjectType() ~= "Button" then return end
    if not button.icon and not button.Icon then return end

    skinnedButtons[button] = true

    local icon = button.icon or button.Icon

    -- Hide the border overlay only (LibDBIcon stores it as .border)
    if button.border then button.border:SetTexture(nil) end
    if button.Border and button.Border ~= icon then button.Border:SetTexture(nil) end

    -- Hide the background behind the icon
    if button.background then button.background:SetAlpha(0) end

    -- Crop the icon edges slightly for a cleaner look
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
end

---------------------------------------------------------------------------
-- Scan and skin all addon minimap buttons
---------------------------------------------------------------------------

local function SkinAllMinimapButtons()
    for _, child in pairs({ Minimap:GetChildren() }) do
        SkinMinimapButton(child)
    end
end

---------------------------------------------------------------------------
-- Register known Blizzard children so we don't skin them as addon buttons
---------------------------------------------------------------------------

local function RegisterBlizzardChildren()
    local minimap = Minimap
    -- Tag known Blizzard child frames
    if minimap.ZoomIn then blizzardChildren[minimap.ZoomIn] = true end
    if minimap.ZoomOut then blizzardChildren[minimap.ZoomOut] = true end
    if GameTimeFrame then blizzardChildren[GameTimeFrame] = true end
    if TimeManagerClockButton then blizzardChildren[TimeManagerClockButton] = true end
    if QueueStatusMinimapButton then blizzardChildren[QueueStatusMinimapButton] = true end
    if AddonCompartmentFrame then blizzardChildren[AddonCompartmentFrame] = true end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function MinimapSkin:Apply()
    if skinApplied then return end
    skinApplied = true

    local cluster = MinimapCluster
    local minimap = Minimap

    if not cluster or not minimap then return end

    RegisterBlizzardChildren()

    -- 1. Strip cluster-level border/ring textures (direct regions only)
    StripRegionTextures(cluster)

    -- 2. Strip BorderTop textures (don't alpha-zero the frame — it parents functional buttons)
    if cluster.BorderTop then
        StripRegionTextures(cluster.BorderTop)
    end

    -- 3. Hide MinimapBackdrop
    if MinimapBackdrop then
        MinimapBackdrop:SetAlpha(0)
        StripRegionTextures(MinimapBackdrop)
    end

    -- 4. Strip Minimap's own border/overlay textures
    StripRegionTextures(minimap)

    -- 5. Hide compass texture (common source of border blur/glow)
    if MinimapCompassTexture then
        MinimapCompassTexture:SetAlpha(0)
    end

    -- 6. Hide north tag
    if MinimapNorthTag then
        MinimapNorthTag:SetAlpha(0)
    end

    -- 7. Hide zoom buttons (mousewheel zoom is sufficient)
    if minimap.ZoomIn then minimap.ZoomIn:Hide() end
    if minimap.ZoomOut then minimap.ZoomOut:Hide() end

    -- 8. Hide zone text
    if MinimapZoneTextButton then MinimapZoneTextButton:Hide() end
    if cluster.ZoneTextButton then cluster.ZoneTextButton:Hide() end

    -- 9. Clean up blob ring artifacts
    if minimap.SetArchBlobRingScalar then
        minimap:SetArchBlobRingScalar(0)
    end
    if minimap.SetQuestBlobRingScalar then
        minimap:SetQuestBlobRingScalar(0)
    end

    -- 10. Scale up the minimap
    minimap:SetScale(1.4)

    -- 11. Ensure mousewheel zoom works after hiding buttons
    minimap:EnableMouseWheel(true)
    minimap:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            Minimap_ZoomIn()
        else
            Minimap_ZoomOut()
        end
    end)

    -- 12. Ensure AddonCompartmentFrame stays clickable above the scaled minimap
    if AddonCompartmentFrame then
        AddonCompartmentFrame:SetFrameStrata("HIGH")
    end

    -- 13. Skin addon minimap buttons (borderless circles)
    SkinAllMinimapButtons()

    -- 14. Re-strip on show (loading screens / Blizzard resets)
    cluster:HookScript("OnShow", function()
        StripRegionTextures(cluster)
    end)

    -- 15. Catch late-loading addon buttons (addons that load after us)
    C_Timer.After(2, SkinAllMinimapButtons)
    C_Timer.After(5, SkinAllMinimapButtons)
end

---------------------------------------------------------------------------
-- TODO: AddonCompartmentFrame skinning
--
-- The button (16x16, child of MinimapCluster) needs flat backdrop + icon.
-- Approaches tried that didn't work:
--   - StripRegionTextures + child strip + Normal/Highlight/Pushed alpha-zero:
--     Blizzard textures persist through our backdrop.
--   - Needs /fstack on the button itself to identify the exact persisting texture.
--
-- TODO: Compartment dropdown menu skinning
--
-- The dropdown is an anonymous frame at FULLSCREEN_DIALOG strata using
-- the "common-dropdown-bg" atlas (confirmed via /fstack).
-- Source: Interface/AddOns/Blizzard_Menu/Menu.lua:2049
--
-- Approaches tried that didn't work:
--   1. Searching UIParent children for NineSlice frames — menu doesn't
--      use NineSlice, uses "common-dropdown-bg" atlas instead.
--   2. Searching for legacy DropDownList1/2 — modern Menu system doesn't
--      use these frames.
--   3. Searching for anonymous FULLSCREEN_DIALOG frames + StripRegionTextures
--      + ApplyBackdrop — finds frames but no visible change. The bg atlas
--      may be deeply nested or reapplied after our strip.
--
-- Next steps:
--   - Hook Blizzard_Menu internals (Menu.GetManager) to get direct frame ref
--   - Or use EventRegistry callbacks for menu open events
--   - May need to walk the full child hierarchy of the menu frame with /fstack
--     to find exactly where common-dropdown-bg is applied
---------------------------------------------------------------------------
