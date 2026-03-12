local _, ns = ...

local FONT = ns.C.FONT

-- Override global font path variables so newly created UI elements use Expressway
STANDARD_TEXT_FONT = FONT
UNIT_NAME_FONT = FONT
DAMAGE_TEXT_FONT = FONT

-- Replace the font face on all existing Font objects while preserving size and flags
for name, obj in pairs(_G) do
    if type(obj) == "table" then
        local ok, isFont = pcall(function()
            if obj.IsObjectType and obj:IsObjectType("Font") then
                local _, size, flags = obj:GetFont()
                if size and size > 0 then
                    obj:SetFont(FONT, size, flags)
                end
            end
        end)
    end
end
