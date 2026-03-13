local _, ns = ...

local C = ns.C

local ItemSkin = {}
ns.ItemSkin = ItemSkin

-- External tracking tables (avoids writing keys to Blizzard frames)
local skinnedButtons = {}   -- button -> bdFrame
local hookedBorders = {}    -- IconBorder -> true

---------------------------------------------------------------------------
-- Atlas-to-quality lookup (ElvUI pattern)
---------------------------------------------------------------------------

local QUALITY_ATLAS = {
    ["auctionhouse-itemicon-border-gray"]     = 0,
    ["auctionhouse-itemicon-border-white"]    = 1,
    ["auctionhouse-itemicon-border-green"]    = 2,
    ["auctionhouse-itemicon-border-blue"]     = 3,
    ["auctionhouse-itemicon-border-purple"]   = 4,
    ["auctionhouse-itemicon-border-orange"]   = 5,
    ["auctionhouse-itemicon-border-artifact"] = 6,
    ["auctionhouse-itemicon-border-account"]  = 7,
    ["Professions-Slot-Frame"]                = 1,
    ["Professions-Slot-Frame-Green"]          = 2,
    ["Professions-Slot-Frame-Blue"]           = 3,
    ["Professions-Slot-Frame-Epic"]           = 4,
    ["Professions-Slot-Frame-Legendary"]      = 5,
}

---------------------------------------------------------------------------
-- Core: SkinItemButton
---------------------------------------------------------------------------

local function SkinItemButton(button)
    if not button or skinnedButtons[button] then return skinnedButtons[button] end

    local icon = button.icon or button.Icon
    local iconTex = icon and icon.GetTexture and icon:GetTexture()

    -- 1) Strip ALL texture regions (kills NormalTexture, borders, backgrounds)
    --    and remove all MaskTextures (kills CircleMask making icons round)
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region then
            local objType = region:GetObjectType()
            if objType == "Texture" and region ~= icon then
                region:SetTexture(0)
                region:SetAtlas("")
                region:SetAlpha(0)
            elseif objType == "MaskTexture" then
                if icon then icon:RemoveMaskTexture(region) end
                region:Hide()
            end
        end
    end

    -- Handle named masks (may not appear in GetRegions on all frames)
    if button.CircleMask then
        if icon then icon:RemoveMaskTexture(button.CircleMask) end
        button.CircleMask:Hide()
    end
    if button.IconMask then
        if icon then icon:RemoveMaskTexture(button.IconMask) end
        button.IconMask:Hide()
    end

    -- Crop icon and restore texture if stripping cleared it
    if icon then
        icon:SetTexCoord(unpack(C.ICON_CROP))
        if iconTex and not icon:GetTexture() then
            icon:SetTexture(iconTex)
        end
    end

    -- 2) Child backdrop with permanent flat border
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop(C.FLAT_BACKDROP)
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    bdFrame:EnableMouse(false)

    -- 3) Anchor icon inside the border
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", bdFrame, "TOPLEFT", C.BORDER_SIZE, -C.BORDER_SIZE)
        icon:SetPoint("BOTTOMRIGHT", bdFrame, "BOTTOMRIGHT", -C.BORDER_SIZE, C.BORDER_SIZE)
    end

    -- 4) Flat highlight overlay
    local highlightTex = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlightTex then
        highlightTex:SetColorTexture(C.HIGHLIGHT_OVERLAY[1], C.HIGHLIGHT_OVERLAY[2], C.HIGHLIGHT_OVERLAY[3], C.HIGHLIGHT_OVERLAY[4])
        if icon then highlightTex:SetAllPoints(icon) end
    end

    skinnedButtons[button] = bdFrame
    return bdFrame
end

---------------------------------------------------------------------------
-- Core: HandleIconBorder (ElvUI-style reactive quality colors)
--
-- Hooks Blizzard's IconBorder so that whenever Blizzard sets its atlas,
-- vertex color, or show/hide state, we mirror the quality color onto our
-- flat backdrop border.  The Blizzard border itself stays hidden.
---------------------------------------------------------------------------

local function HandleIconBorder(border, bdFrame)
    if not border or hookedBorders[border] then return end
    hookedBorders[border] = true

    -- Capture initial quality color before hiding
    if border:IsShown() then
        local atlas = border.GetAtlas and border:GetAtlas()
        local quality = atlas and QUALITY_ATLAS[atlas]
        if quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        else
            local r, g, b = border:GetVertexColor()
            if r then
                bdFrame:SetBackdropBorderColor(r, g, b, 1)
            end
        end
    end

    border:Hide()

    -- Atlas update → translate to quality color
    hooksecurefunc(border, "SetAtlas", function(self, atlas)
        local quality = QUALITY_ATLAS[atlas]
        if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        end
    end)

    -- Vertex color update → forward directly
    hooksecurefunc(border, "SetVertexColor", function(self, r, g, b)
        if r then
            bdFrame:SetBackdropBorderColor(r, g, b, 1)
        end
    end)

    -- Keep Blizzard border hidden; pass 0 so Hide hook ignores our own call
    hooksecurefunc(border, "Show", function(self)
        self:Hide(0)
    end)

    -- When Blizzard hides border (empty slot / common quality) → reset color
    hooksecurefunc(border, "Hide", function(self, value)
        if value == 0 then return end
        bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    end)

    -- SetShown variant
    hooksecurefunc(border, "SetShown", function(self, show)
        if show then
            self:Hide(0)
        else
            bdFrame:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])
        end
    end)
end

---------------------------------------------------------------------------
-- Character Panel: SkinCharacterSlots
---------------------------------------------------------------------------

local EQUIP_SLOTS = {
    { frame = "CharacterHeadSlot",          slot = "HeadSlot" },
    { frame = "CharacterNeckSlot",          slot = "NeckSlot" },
    { frame = "CharacterShoulderSlot",      slot = "ShoulderSlot" },
    { frame = "CharacterBackSlot",          slot = "BackSlot" },
    { frame = "CharacterChestSlot",         slot = "ChestSlot" },
    { frame = "CharacterShirtSlot",         slot = "ShirtSlot" },
    { frame = "CharacterTabardSlot",        slot = "TabardSlot" },
    { frame = "CharacterWristSlot",         slot = "WristSlot" },
    { frame = "CharacterHandsSlot",        slot = "HandsSlot" },
    { frame = "CharacterWaistSlot",         slot = "WaistSlot" },
    { frame = "CharacterLegsSlot",          slot = "LegsSlot" },
    { frame = "CharacterFeetSlot",          slot = "FeetSlot" },
    { frame = "CharacterFinger0Slot",       slot = "Finger0Slot" },
    { frame = "CharacterFinger1Slot",       slot = "Finger1Slot" },
    { frame = "CharacterTrinket0Slot",      slot = "Trinket0Slot" },
    { frame = "CharacterTrinket1Slot",      slot = "Trinket1Slot" },
    { frame = "CharacterMainHandSlot",      slot = "MainHandSlot" },
    { frame = "CharacterSecondaryHandSlot", slot = "SecondaryHandSlot" },
}

local characterSkinned = false

local function SkinCharacterSlots()
    if characterSkinned then return end

    for _, entry in ipairs(EQUIP_SLOTS) do
        local button = _G[entry.frame]
        if button then
            local bdFrame = SkinItemButton(button)
            if bdFrame then
                HandleIconBorder(button.IconBorder, bdFrame)

                -- Set initial quality for already-equipped items
                local slotID = GetInventorySlotInfo(entry.slot)
                if slotID then
                    local quality = GetInventoryItemQuality("player", slotID)
                    if quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
                        local c = ITEM_QUALITY_COLORS[quality]
                        bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
                    end
                end
            end
        end
    end

    characterSkinned = true
end

---------------------------------------------------------------------------
-- Bank: SkinBank
---------------------------------------------------------------------------

local bankSkinned = false

local function SkinBank()
    if bankSkinned then return end

    -- Bank item slots (BankFrameItem1 through BankFrameItem28)
    for i = 1, 28 do
        local button = _G["BankFrameItem" .. i]
        if button then
            local bdFrame = SkinItemButton(button)
            if bdFrame then
                HandleIconBorder(button.IconBorder, bdFrame)
            end
        end
    end

    -- Bank bag slots
    if BankSlotsFrame then
        for i = 1, 7 do
            local button = BankSlotsFrame["Bag" .. i]
            if button then
                local bdFrame = SkinItemButton(button)
                if bdFrame then
                    HandleIconBorder(button.IconBorder, bdFrame)
                end
            end
        end
    end

    -- Account bank / reagent bank if available via BankFrame children
    if BankFrame then
        for i = 1, select("#", BankFrame:GetChildren()) do
            local child = select(i, BankFrame:GetChildren())
            if child and child.Items then
                for _, button in ipairs(child.Items) do
                    local bdFrame = SkinItemButton(button)
                    if bdFrame then
                        HandleIconBorder(button.IconBorder, bdFrame)
                    end
                end
            end
        end
    end

    bankSkinned = true
end

---------------------------------------------------------------------------
-- Merchant: SkinMerchant
---------------------------------------------------------------------------

local merchantSkinned = false

local function SkinMerchant()
    if merchantSkinned then return end

    for i = 1, 12 do
        local merchantItem = _G["MerchantItem" .. i]
        if merchantItem then
            local itemButton = merchantItem.ItemButton or _G["MerchantItem" .. i .. "ItemButton"]
            if itemButton then
                local bdFrame = SkinItemButton(itemButton)
                if bdFrame then
                    HandleIconBorder(itemButton.IconBorder, bdFrame)
                end
            end
        end
    end

    merchantSkinned = true
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function ItemSkin:Apply()
    -- Character panel: skin when it loads
    if PaperDollFrame then
        SkinCharacterSlots()
    end
    EventUtil.ContinueOnAddOnLoaded("Blizzard_CharacterFrame", function()
        C_Timer.After(0, SkinCharacterSlots)
    end)

    -- Bank: deferred — hook OnShow
    EventUtil.ContinueOnAddOnLoaded("Blizzard_AccountBank", function()
        if BankFrame then
            BankFrame:HookScript("OnShow", function()
                C_Timer.After(0, function()
                    bankSkinned = false
                    SkinBank()
                end)
            end)
        end
    end)
    if BankFrame then
        BankFrame:HookScript("OnShow", function()
            C_Timer.After(0, function()
                bankSkinned = false
                SkinBank()
            end)
        end)
    end

    -- Merchant: deferred — hook OnShow
    if MerchantFrame then
        MerchantFrame:HookScript("OnShow", function()
            if not merchantSkinned then
                C_Timer.After(0, SkinMerchant)
            end
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("Blizzard_MerchantFrame", function()
        if MerchantFrame then
            MerchantFrame:HookScript("OnShow", function()
                if not merchantSkinned then
                    C_Timer.After(0, SkinMerchant)
                end
            end)
        end
    end)
end
