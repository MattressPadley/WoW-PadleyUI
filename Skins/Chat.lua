local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine

local ChatSkin = {}
ns.ChatSkin = ChatSkin

-- External tracking tables
local skinnedTabs = {}
local skinnedEditBoxes = {}
local skinnedFrames = {}

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------

local function SkinChatTab(tab)
    if not tab or skinnedTabs[tab] then return end
    skinnedTabs[tab] = true

    -- Alpha-zero all texture regions
    for i = 1, tab:GetNumRegions() do
        local region = select(i, tab:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end

    -- Alpha-zero special button textures (not returned by GetRegions)
    if tab:GetHighlightTexture() then tab:GetHighlightTexture():SetAlpha(0) end

    -- Style the tab text
    local text = tab.Text or tab:GetFontString()
    if text then
        SE:StyleFont(text)
    end
end

---------------------------------------------------------------------------
-- Edit box
---------------------------------------------------------------------------

local function SkinEditBox(editBox)
    if not editBox or skinnedEditBoxes[editBox] then return end
    skinnedEditBoxes[editBox] = true

    -- Alpha-zero all texture regions (border pieces)
    for i = 1, editBox:GetNumRegions() do
        local region = select(i, editBox:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end

    -- Shrink the edit box and push it down for a gap below the chat panel
    editBox:SetHeight(18)
    local yOffset = -6
    for i = 1, editBox:GetNumPoints() do
        local point, rel, relPoint, x, y = editBox:GetPoint(i)
        editBox:SetPoint(point, rel, relPoint, x, y + yOffset)
    end

    -- Child backdrop frame matching chat panel bg
    local bdFrame = CreateFrame("Frame", nil, editBox, "BackdropTemplate")
    bdFrame:SetAllPoints()
    bdFrame:SetFrameLevel(editBox:GetFrameLevel())
    bdFrame:EnableMouse(false)
    bdFrame:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    bdFrame:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])

    -- Style the header font (channel prefix e.g. "[Guild]")
    local header = editBox.header or _G[editBox:GetName() .. "Header"]
    if header then
        SE:StyleFont(header)
    end
end

---------------------------------------------------------------------------
-- Button frame (scroll buttons area)
---------------------------------------------------------------------------

local function SkinButtonFrame(bf)
    if not bf then return end

    -- Alpha-zero background textures
    for i = 1, bf:GetNumRegions() do
        local region = select(i, bf:GetRegions())
        if region and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- Single chat frame
---------------------------------------------------------------------------

local function SkinChatFrame(chatFrame)
    if not chatFrame or skinnedFrames[chatFrame] then return end
    skinnedFrames[chatFrame] = true

    local name = chatFrame:GetName()

    -- Kill Blizzard background via their API
    FCF_SetWindowAlpha(chatFrame, 0, true)

    -- Nuke textures on the chat frame, its children, AND its parent
    local function StripAllTextures(frame)
        if not frame then return end
        for i = 1, frame:GetNumRegions() do
            local region = select(i, frame:GetRegions())
            if region and region:GetObjectType() == "Texture" then
                region:SetAlpha(0)
            end
        end
    end

    StripAllTextures(chatFrame)
    StripAllTextures(chatFrame:GetParent())

    for i = 1, select("#", chatFrame:GetChildren()) do
        local child = select(i, chatFrame:GetChildren())
        if child and child.GetRegions then
            StripAllTextures(child)
        end
    end

    -- Also clear any backdrop set directly on parent
    local parent = chatFrame:GetParent()
    if parent and parent.SetBackdrop then
        parent:SetBackdrop(nil)
    end

    -- Prevent Blizzard from re-showing the background on hover
    hooksecurefunc("FCF_SetWindowAlpha", function(cf)
        if cf == chatFrame then
            StripAllTextures(chatFrame)
            StripAllTextures(chatFrame:GetParent())
        end
    end)

    -- Flat backdrop panel — use editBox width as reference for right edge
    local editBox = _G[name .. "EditBox"]
    local panel = CreateFrame("Frame", nil, chatFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", -4, 4)
    if editBox then
        panel:SetPoint("RIGHT", editBox, "RIGHT", 0, 0)
        panel:SetPoint("BOTTOM", chatFrame, "BOTTOM", 0, -4)
    else
        panel:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 4, -4)
    end
    panel:SetFrameLevel(math.max(0, chatFrame:GetFrameLevel() - 1))
    panel:EnableMouse(false)
    panel:SetBackdrop({
        bgFile   = C.FLAT_BACKDROP.bgFile,
    })
    panel:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    panel:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2], C.BORDER_COLOR[3], C.BORDER_COLOR[4])

    -- Skin sub-elements
    SkinChatTab(_G[name .. "Tab"])
    SkinEditBox(_G[name .. "EditBox"])
    SkinButtonFrame(_G[name .. "ButtonFrame"])
end

---------------------------------------------------------------------------
-- Scan for unskinned frames (used by hooks)
---------------------------------------------------------------------------

local function SkinNewFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf and not skinnedFrames[cf] then
            SkinChatFrame(cf)
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

function ChatSkin:Apply()
    -- Skin all existing chat frames
    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame" .. i]
        if cf then
            SkinChatFrame(cf)
        end
    end

    -- Hook for newly created windows
    if FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", SkinNewFrames)
    end
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", SkinNewFrames)
    end

    -- Strip GeneralDockManager background textures
    if GeneralDockManager then
        SE:StripTextures(GeneralDockManager)
    end
end
