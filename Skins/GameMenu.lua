local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local GameMenuSkin = {}
ns.GameMenuSkin = GameMenuSkin

-- External tracking table
local skinnedButtons = {}

---------------------------------------------------------------------------
-- Button skinning
---------------------------------------------------------------------------

local function SkinMenuButton(button)
    if not button or skinnedButtons[button] then return end
    skinnedButtons[button] = true

    -- Alpha-zero all texture regions
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end

    -- Also clear the special Button texture slots
    if button:GetNormalTexture() then button:GetNormalTexture():SetAlpha(0) end
    if button:GetHighlightTexture() then button:GetHighlightTexture():SetAlpha(0) end
    if button:GetPushedTexture() then button:GetPushedTexture():SetAlpha(0) end

    -- Child backdrop at same frame level (renders behind button's own regions)
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(button:GetFrameLevel())
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
        edgeFile = C.FLAT_BACKDROP.edgeFile,
        edgeSize = C.BORDER_SIZE,
    })
    bdFrame:SetBackdropColor(0.15, 0.15, 0.15, 1)
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    bdFrame:EnableMouse(false)

    -- Hover highlight
    button:HookScript("OnEnter", function()
        bdFrame:SetBackdropBorderColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2], C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    button:HookScript("OnLeave", function()
        bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    end)
end

---------------------------------------------------------------------------
-- Skin all children helper
---------------------------------------------------------------------------

local function SkinAllChildren(gmf)
    for i = 1, select("#", gmf:GetChildren()) do
        local child = select(i, gmf:GetChildren())
        if child:GetObjectType() == "Button" then
            SkinMenuButton(child)
        elseif child:GetObjectType() == "Frame" and child ~= gmf.Border then
            -- Hide decorative/separator frames
            child:SetAlpha(0)
        end
    end
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

    -- Apply flat backdrop
    SE:ApplyBackdrop(gmf)

    -- Skin children now (in case they exist already)
    SkinAllChildren(gmf)

    -- Buttons may not exist yet — hook OnShow to skin when menu first opens
    gmf:HookScript("OnShow", function(self)
        SkinAllChildren(self)
    end)
end
