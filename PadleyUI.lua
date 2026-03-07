local addonName, ns = ...

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        print("|cff00ccffPadleyUI|r loaded!")

        -- Always-available skins (core UI, no optional dep)
        ns.TooltipSkin:Apply()
        ns.GameMenuSkin:Apply()
        ns.ChatSkin:Apply()
        ns.StatusBarSkin:Apply()
        ns.MinimapSkin:Apply()
        ns.ActionBarSkin:Apply()

        -- Blizzard_DamageMeter is in OptionalDeps so it loads BEFORE us.
        -- By the time this fires, we already missed its ADDON_LOADED event.
        if C_AddOns.IsAddOnLoaded("Blizzard_DamageMeter") then
            ns.DamageMeterSkin:Apply()
        end
        if C_AddOns.IsAddOnLoaded("Blizzard_UIPanels_Game") then
            ns.LootSkin:Apply()
        end
    elseif loadedAddon == "Blizzard_DamageMeter" then
        -- Fallback: if it loads on-demand after us
        ns.DamageMeterSkin:Apply()
    elseif loadedAddon == "Blizzard_UIPanels_Game" then
        ns.LootSkin:Apply()
    end
end)
