local _, ns = ...

local C = ns.C

local CooldownTrackerSkin = {}
ns.CooldownTrackerSkin = CooldownTrackerSkin

-- External tracking tables (avoids writing keys to Blizzard frames)
local skinnedIcons = {}
local skinnedBars = {}

local VIEWER_FRAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

---------------------------------------------------------------------------
-- Find the StatusBar child of a bar item frame
---------------------------------------------------------------------------

local function FindStatusBar(frame)
    for i = 1, select("#", frame:GetChildren()) do
        local child = select(i, frame:GetChildren())
        if child and child:GetObjectType() == "StatusBar" then
            return child
        end
    end
end

---------------------------------------------------------------------------
-- Skin a cooldown icon (Essential, Utility, BuffIcon viewers)
---------------------------------------------------------------------------

local function SkinCooldownIcon(icon)
    if not icon or skinnedIcons[icon] then return end
    skinnedIcons[icon] = true

    local iconTex = icon.Icon or icon.icon

    -- Alpha-zero all texture regions except the spell icon
    for i = 1, icon:GetNumRegions() do
        local region = select(i, icon:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= iconTex then
            region:SetAlpha(0)
        end
    end

    -- Remove all mask textures for square corners and crop edges
    if iconTex then
        -- Remove any mask found by known key names
        if icon.IconMask then
            iconTex:RemoveMaskTexture(icon.IconMask)
            icon.IconMask:Hide()
        end
        -- Brute-force: iterate all regions and remove any MaskTexture
        for i = 1, icon:GetNumRegions() do
            local region = select(i, icon:GetRegions())
            if region and region:GetObjectType() == "MaskTexture" then
                iconTex:RemoveMaskTexture(region)
                region:Hide()
            end
        end
        -- Also check children for masks
        for i = 1, select("#", icon:GetChildren()) do
            local child = select(i, icon:GetChildren())
            if child and child.GetNumRegions then
                for j = 1, child:GetNumRegions() do
                    local region = select(j, child:GetRegions())
                    if region and region:GetObjectType() == "MaskTexture" then
                        iconTex:RemoveMaskTexture(region)
                        region:Hide()
                    end
                end
            end
        end
        iconTex:SetTexCoord(unpack(C.ICON_CROP))
    end

    -- Hide named art elements
    if icon.Border then icon.Border:SetAlpha(0) end
    if icon.SlotArt then icon.SlotArt:SetAlpha(0) end
    if icon.SlotBackground then icon.SlotBackground:SetAlpha(0) end

    -- Strip textures on child frames (decorative art children)
    local existingChildren = { icon:GetChildren() }
    for _, child in ipairs(existingChildren) do
        if child and child.GetNumRegions then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "Texture" and region ~= iconTex then
                    region:SetAlpha(0)
                end
            end
        end
    end

end

---------------------------------------------------------------------------
-- Skin a cooldown bar item (BuffBarCooldownViewer)
---------------------------------------------------------------------------

local function SkinCooldownBar(item)
    if not item or skinnedBars[item] then return end
    skinnedBars[item] = true

    local statusBar = FindStatusBar(item)
    -- item.Icon is a Frame containing a child .Icon Texture
    local iconFrame = item.Icon or item.icon
    local iconTex = iconFrame and (iconFrame.Icon or iconFrame.icon) or nil

    -- Alpha-zero decorative textures on the item frame (keep the icon)
    for i = 1, item:GetNumRegions() do
        local region = select(i, item:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= iconTex then
            region:SetAlpha(0)
        end
    end

    -- Remove masks from bar icon for square corners
    if iconTex then
        for i = 1, item:GetNumRegions() do
            local region = select(i, item:GetRegions())
            if region and region:GetObjectType() == "MaskTexture" then
                iconTex:RemoveMaskTexture(region)
                region:Hide()
            end
        end
        iconTex:SetTexCoord(unpack(C.ICON_CROP))
        iconTex:SetAlpha(1)
    end

    -- Alpha-zero textures on child frames (skip iconFrame and statusBar)
    for i = 1, select("#", item:GetChildren()) do
        local child = select(i, item:GetChildren())
        if child and child ~= iconFrame and child ~= statusBar and child.GetNumRegions then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region:GetObjectType() == "Texture" then
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- Strip masks from the icon frame itself
    if iconFrame and iconFrame.GetNumRegions then
        for j = 1, iconFrame:GetNumRegions() do
            local region = select(j, iconFrame:GetRegions())
            if region and region:GetObjectType() == "MaskTexture" and iconTex then
                iconTex:RemoveMaskTexture(region)
                region:Hide()
            elseif region and region:GetObjectType() == "Texture" and region ~= iconTex then
                region:SetAlpha(0)
            end
        end
    end

    -- Ensure the icon frame and texture are visible
    if iconFrame then iconFrame:SetAlpha(1) end
    if iconTex then iconTex:SetAlpha(1) end

    if statusBar then
        -- Alpha-zero StatusBar background/overlay textures (not the fill)
        for i = 1, statusBar:GetNumRegions() do
            local region = select(i, statusBar:GetRegions())
            if region and region:GetObjectType() == "Texture" then
                if region ~= statusBar:GetStatusBarTexture() then
                    region:SetAlpha(0)
                end
            end
        end

        -- Flatten to flat texture
        local fillTexture = statusBar:GetStatusBarTexture()
        if fillTexture then
            fillTexture:SetAtlas("")
            fillTexture:SetTexture(C.BAR_TEXTURE)
        end
        statusBar:SetStatusBarTexture(C.BAR_TEXTURE)

        -- Backdrop sized to the status bar
        local bdFrame = CreateFrame("Frame", nil, item, "BackdropTemplate")
        bdFrame:SetAllPoints(statusBar)
        bdFrame:SetFrameLevel(math.max(statusBar:GetFrameLevel() - 1, 0))
        bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
        bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        bdFrame:EnableMouse(false)
    end
end

---------------------------------------------------------------------------
-- Skin all items on a viewer
---------------------------------------------------------------------------

local function SkinViewer(viewerName)
    local frame = _G[viewerName]
    if not frame or not frame.GetItemFrames then return end

    local items = frame:GetItemFrames()
    if not items then return end

    local isBarViewer = (viewerName == "BuffBarCooldownViewer")

    for _, item in ipairs(items) do
        if isBarViewer then
            SkinCooldownBar(item)
        else
            SkinCooldownIcon(item)
        end
    end
end

local function SkinAllViewers()
    for _, name in ipairs(VIEWER_FRAMES) do
        SkinViewer(name)
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function CooldownTrackerSkin:Apply()
    SkinAllViewers()

    -- Hook Layout on each viewer instance to skin new items
    for _, name in ipairs(VIEWER_FRAMES) do
        local frame = _G[name]
        if frame and frame.Layout then
            hooksecurefunc(frame, "Layout", function()
                SkinViewer(name)
            end)
        end
    end

    -- Deferred pass for late-initialized items
    C_Timer.After(0, SkinAllViewers)
end
