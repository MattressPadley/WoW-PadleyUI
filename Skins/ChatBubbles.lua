local _, ns = ...
local C = ns.C
local SE = ns.SkinEngine

local ChatBubbleSkin = {}
ns.ChatBubbleSkin = ChatBubbleSkin

local skinnedBubbles = {}

local function SkinBubble(chatBubble)
    if skinnedBubbles[chatBubble] then return end

    local holder = select(1, chatBubble:GetChildren())
    if not holder or holder:IsForbidden() then return end

    -- Hide the tail (arrow)
    if holder.Tail then
        holder.Tail:Hide()
        holder.Tail.Show = function() end
    end

    -- Hide border/background textures (skip String so Blizzard's fade animation works)
    for i = 1, holder:GetNumRegions() do
        local region = select(i, holder:GetRegions())
        if region and region ~= holder.String then
            region:SetAlpha(0)
        end
    end

    -- Apply flat backdrop via child frame (holder lacks BackdropTemplateMixin)
    local bd = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(holder:GetFrameLevel())
    SE:ApplyBackdrop(bd)

    -- Style font
    if holder.String then
        SE:StyleFont(holder.String, C.FONT_SIZE)
    end

    -- Re-apply on reuse (skip String so Blizzard's fade animation works)
    chatBubble:HookScript("OnShow", function()
        for i = 1, holder:GetNumRegions() do
            local region = select(i, holder:GetRegions())
            if region and region ~= holder.String then
                region:SetAlpha(0)
            end
        end
    end)

    skinnedBubbles[chatBubble] = true
end

function ChatBubbleSkin:Apply()
    local elapsed = 0
    local poller = CreateFrame("Frame")
    poller:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles()) do
            SkinBubble(bubble)
        end
    end)
end
