local _, ns = ...

local C = ns.C

local ItemSkin = {}
ns.ItemSkin = ItemSkin

-- External tracking tables (avoids writing keys to Blizzard frames)
local skinnedButtons = {}  -- button -> bdFrame

---------------------------------------------------------------------------
-- Core: SkinItemButton
---------------------------------------------------------------------------

local function SkinItemButton(button)
    if not button or skinnedButtons[button] then return end

    local icon = button.icon or button.Icon

    -- 1) Strip art — alpha-zero NormalTexture, PushedTexture; hide IconBorder
    local normalTex = button.GetNormalTexture and button:GetNormalTexture()
    if normalTex then normalTex:SetAlpha(0) end

    local pushedTex = button.GetPushedTexture and button:GetPushedTexture()
    if pushedTex then pushedTex:SetAlpha(0) end

    if button.IconBorder then button.IconBorder:Hide() end

    -- 2) Remove icon mask and crop icon
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "MaskTexture" then
            if icon then icon:RemoveMaskTexture(region) end
            region:Hide()
        end
    end
    if icon then
        icon:SetTexCoord(unpack(C.ICON_CROP))
    end

    -- Also handle named IconMask
    if button.IconMask then
        if icon then icon:RemoveMaskTexture(button.IconMask) end
        button.IconMask:Hide()
    end

    -- 3) Child backdrop frame (never Mixin on Blizzard frames)
    local bdFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    bdFrame:EnableMouse(false)

    -- 4) Restyle highlight — flat white overlay anchored to icon
    local highlightTex = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlightTex then
        highlightTex:SetTexture(C.BAR_TEXTURE)
        highlightTex:SetVertexColor(unpack(C.HIGHLIGHT_OVERLAY))
        if icon then
            highlightTex:SetAllPoints(icon)
        end
    end

    skinnedButtons[button] = bdFrame
    return bdFrame
end

---------------------------------------------------------------------------
-- Core: UpdateItemBorder
---------------------------------------------------------------------------

local function SetBorderForQuality(bdFrame, quality)
    if quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        bdFrame:SetBackdrop({
            bgFile   = C.FLAT_BACKDROP.bgFile,
            edgeFile = C.FLAT_BACKDROP.edgeFile,
            edgeSize = C.BORDER_SIZE,
        })
        bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
        bdFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
    else
        bdFrame:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
        bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    end
end

local function UpdateItemBorder(button, bdFrame)
    if not bdFrame then bdFrame = skinnedButtons[button] end
    if not bdFrame then return end

    -- Hide Blizzard's IconBorder each update
    if button.IconBorder then button.IconBorder:Hide() end

    local quality

    -- Try GetItemQualityFromButton (available on bag/bank item buttons)
    if button.GetItemQualityFromButton then
        local ok, q = pcall(button.GetItemQualityFromButton, button)
        if ok then quality = q end
    end

    -- Fallback: read IconBorder vertex color if it was visible
    if not quality and button.IconBorder and button.IconBorder:IsShown() then
        local r, g, b = button.IconBorder:GetVertexColor()
        if ITEM_QUALITY_COLORS then
            for q = 7, 0, -1 do
                local c = ITEM_QUALITY_COLORS[q]
                if c and math.abs(c.r - r) < 0.05 and math.abs(c.g - g) < 0.05 and math.abs(c.b - b) < 0.05 then
                    quality = q
                    break
                end
            end
        end
    end

    SetBorderForQuality(bdFrame, quality)
end

---------------------------------------------------------------------------
-- Character Panel: UpdateEquipSlotBorder
---------------------------------------------------------------------------

-- Equipment slot frame name -> API slot name mapping
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

-- External table mapping button -> slotID (avoids writing to Blizzard frames)
local slotIDs = {}

local function QualityFromVertexColor(r, g, b)
    if not ITEM_QUALITY_COLORS then return nil end
    for q = 7, 0, -1 do
        local c = ITEM_QUALITY_COLORS[q]
        if c and math.abs(c.r - r) < 0.05 and math.abs(c.g - g) < 0.05 and math.abs(c.b - b) < 0.05 then
            return q
        end
    end
    return nil
end

local function UpdateEquipSlotBorder(button)
    local bdFrame = skinnedButtons[button]
    if not bdFrame then return end

    if button.IconBorder then button.IconBorder:Hide() end

    local slotID = slotIDs[button]
    if not slotID then return end

    local quality = GetInventoryItemQuality("player", slotID)
    SetBorderForQuality(bdFrame, quality)
end

---------------------------------------------------------------------------
-- Character Panel: SkinCharacterSlots
---------------------------------------------------------------------------

local characterSkinned = false

local function SkinCharacterSlots()
    if characterSkinned then return end

    for _, entry in ipairs(EQUIP_SLOTS) do
        local button = _G[entry.frame]
        if button then
            -- Get reliable slotID via API instead of button:GetID()
            local slotID = GetInventorySlotInfo(entry.slot)
            if slotID and slotID > 0 then
                slotIDs[button] = slotID
            end

            local bdFrame = SkinItemButton(button)
            if bdFrame then
                -- Hook IconBorder:Show on the instance to reactively catch updates
                if button.IconBorder then
                    hooksecurefunc(button.IconBorder, "Show", function(iconBorder)
                        local r, g, b = iconBorder:GetVertexColor()
                        iconBorder:Hide()
                        local quality = QualityFromVertexColor(r, g, b)
                        SetBorderForQuality(bdFrame, quality)
                    end)
                end

                -- Set initial border for already-equipped items
                UpdateEquipSlotBorder(button)
            end
        end
    end

    -- Listen for inventory events as backup re-check
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        for button, _ in pairs(slotIDs) do
            if skinnedButtons[button] then
                UpdateEquipSlotBorder(button)
            end
        end
    end)

    characterSkinned = true
end

---------------------------------------------------------------------------
-- Bank: SkinBank
---------------------------------------------------------------------------

local bankSkinned = false

local function SkinBagButton(button)
    local bdFrame = SkinItemButton(button)
    if bdFrame then
        UpdateItemBorder(button, bdFrame)
        if button.SetItemButtonQuality then
            hooksecurefunc(button, "SetItemButtonQuality", function(btn)
                UpdateItemBorder(btn)
            end)
        end
    end
end

local function SkinBank()
    if bankSkinned then return end

    -- Bank item slots (BankFrameItem1 through BankFrameItem28)
    for i = 1, 28 do
        local button = _G["BankFrameItem" .. i]
        if button then
            SkinBagButton(button)
        end
    end

    -- Bank bag slots
    if BankSlotsFrame then
        for i = 1, 7 do
            local button = BankSlotsFrame["Bag" .. i]
            if button then
                SkinBagButton(button)
            end
        end
    end

    -- Account bank / reagent bank if available via BankFrame children
    if BankFrame then
        for i = 1, select("#", BankFrame:GetChildren()) do
            local child = select(i, BankFrame:GetChildren())
            if child and child.Items then
                for _, button in ipairs(child.Items) do
                    SkinBagButton(button)
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
                    UpdateItemBorder(itemButton, bdFrame)
                end
            end
        end
    end

    merchantSkinned = true
end

local function UpdateMerchantBorders()
    for i = 1, 12 do
        local merchantItem = _G["MerchantItem" .. i]
        if merchantItem then
            local itemButton = merchantItem.ItemButton or _G["MerchantItem" .. i .. "ItemButton"]
            if itemButton and skinnedButtons[itemButton] then
                UpdateItemBorder(itemButton)
            end
        end
    end
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
            C_Timer.After(0, UpdateMerchantBorders)
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("Blizzard_MerchantFrame", function()
        if MerchantFrame then
            MerchantFrame:HookScript("OnShow", function()
                if not merchantSkinned then
                    C_Timer.After(0, SkinMerchant)
                end
                C_Timer.After(0, UpdateMerchantBorders)
            end)
        end
    end)
end
