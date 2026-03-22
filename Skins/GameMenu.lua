local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local GameMenuSkin = {}
ns.GameMenuSkin = GameMenuSkin

-- External tracking tables
local skinnedButtons = {}
local hookedRegions = {}

---------------------------------------------------------------------------
-- Button skinning
---------------------------------------------------------------------------

-- Zero a texture's alpha and hook SetAlpha so Blizzard can never restore it.
local function HookZeroAlpha(region)
    if not region or hookedRegions[region] then return end
    hookedRegions[region] = true
    region:SetAlpha(0)
    hooksecurefunc(region, "SetAlpha", function(self)
        if self:GetAlpha() > 0 then self:SetAlpha(0) end
    end)
end

local function SkinMenuButton(button)
    if not button or skinnedButtons[button] then return end
    skinnedButtons[button] = true

    -- Permanently zero all button textures via hooks
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            HookZeroAlpha(region)
        end
    end
    HookZeroAlpha(button:GetNormalTexture())
    HookZeroAlpha(button:GetHighlightTexture())
    HookZeroAlpha(button:GetPushedTexture())

    -- Child backdrop at SAME level as button (not +1, which covers text)
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(button:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile = C.FLAT_BACKDROP.bgFile,
    })
    bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    bdFrame:EnableMouse(false)

    -- Hover highlight (bg color change)
    button:HookScript("OnEnter", function()
        bdFrame:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    button:HookScript("OnLeave", function()
        bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    end)

    -- Re-add hover hooks when Blizzard resets scripts during pool recycling
    hooksecurefunc(button, "SetScript", function(self, script)
        if script == "OnEnter" then
            self:HookScript("OnEnter", function()
                bdFrame:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
            end)
        elseif script == "OnLeave" then
            self:HookScript("OnLeave", function()
                bdFrame:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2], C.HEADER_COLOR[3], C.HEADER_COLOR[4])
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function GameMenuSkin:Apply()
    local gmf = GameMenuFrame

    -- Hide the dialog border and background
    if gmf.Border then
        gmf.Border:SetAlpha(0)
    end

    -- Strip all textures from the main frame and header
    SE:StripTextures(gmf)
    if gmf.Header then
        SE:StripTextures(gmf.Header)
    end

    -- Apply flat backdrop (child frame — avoids Mixin taint)
    SE:ApplyBackdrop(gmf)

    -- Hook InitButtons to skin pool buttons each time the menu opens
    hooksecurefunc(gmf, "InitButtons", function(menu)
        if not menu.buttonPool then return end
        for button in menu.buttonPool:EnumerateActive() do
            SkinMenuButton(button)
        end
    end)
end
