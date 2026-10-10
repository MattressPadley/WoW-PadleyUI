-- ============================================================================
-- TEMPORARY / THROWAWAY DIAGNOSTIC FILE — DELETE ONCE THE FOREVER PORT IS SHAPED
--
-- Purpose: step 1 of porting PadleyUI to the WoW Forever client. Answers, per
-- skin module, "could this skin even run here?" — by checking every Blizzard
-- global, child key, hook target and API that skin depends on — plus the
-- handful of questions that decide the port's shape (Edit Mode? DamageMeter?
-- unit-frame lineage? nameplate structure? ObjectiveTracker kind? Secret
-- Values era?).
--
-- Loaded ONLY by PadleyUI_Forever.toc. Never by PadleyUI.toc (retail).
--
-- PRIMARY OUTPUT: PadleyUI_DB.foreverProbe (SavedVariables). The probe runs
-- automatically at PLAYER_LOGIN; /reload or logout flushes it to
--   WTF\Account\<ACCOUNT>\SavedVariables\PadleyUI.lua
-- Read that file directly. Chat output is a secondary, paginated summary.
--
-- Slash command: /puiforever          — summary page 1 (/puiforever 2 ...)
--                /puiforever run      — re-probe now (e.g. after targeting a mob)
--                /puiforever full     — LoadAddOn every on-demand Blizzard addon
--                                       the retail skins depend on, then re-probe
--                /puiforever plate    — capture target nameplate structure
--
-- READ-ONLY toward Blizzard frames: never calls SetAlpha/SetPoint/Show/Hide on
-- them, never hooks them, never reparents, never writes a key onto them. It
-- reads fields via pcall, creates throwaway frames of its own to test widget
-- methods, and writes only to PadleyUI_DB.foreverProbe.
--
-- The SKINS table below was derived by reading every file in Skins/ and Core/
-- at the commit that introduced this probe. If a skin changes, this list does
-- not follow it — it is a snapshot for the port's first decision.
--
-- To revert: delete this file, PadleyUI_Forever.toc, and ns.FLAVOR/ns.INTERFACE
-- in Core/Constants.lua if the port is abandoned.
-- ============================================================================

local addonName, ns = ...

local SCHEMA    = 1
local PAGE_SIZE = 55
local LINE_CAP  = 230  -- chat cuts off at 255

-- Bindings.xml is loaded from the addon folder regardless of which TOC is
-- active, and references these. Stub them so a keypress can't throw here.
PadleyUI_ToggleActionBarMouseover = PadleyUI_ToggleActionBarMouseover or function() end
PadleyUI_ToggleQuestTracker = PadleyUI_ToggleQuestTracker or function() end

-- ---------------------------------------------------------------------------
-- Safe accessors (a secret value or protected index must never blow us up,
-- and nothing secret may ever reach SavedVariables)
-- ---------------------------------------------------------------------------

local function IsSecret(v)
    if issecretvalue then
        local ok, s = pcall(issecretvalue, v)
        if ok and s then return true end
    end
    return false
end

local function SafeGet(obj, key)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[key] end)
    if not ok then return nil, "ERR" end
    if IsSecret(v) then return nil, "SECRET" end
    return v
end

local function SafeCall(obj, method, ...)
    local fn = SafeGet(obj, method)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj, ...)
    if not ok then return nil end
    if IsSecret(v) then return nil end
    return v
end

local function IsWidget(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return false end
    if issecrettable and type(v) == "table" then
        local ok, s = pcall(issecrettable, v)
        if ok and s then return false end
    end
    return type(SafeGet(v, "GetObjectType")) == "function"
end

-- Plain, serialisable description of any value.
local function Describe(v, err)
    if err then return { present = false, type = err } end
    if v == nil then return { present = false, type = "nil" } end
    local d = { present = true, type = type(v) }
    if IsWidget(v) then
        d.objType = SafeCall(v, "GetObjectType")
        d.name = SafeCall(v, "GetName")
        d.forbidden = SafeCall(v, "IsForbidden") or nil
    end
    return d
end

-- Resolve "A.b.c" / "A:Method" from _G. Each segment is a plain field read.
-- Also returns the deepest segment that resolved, so a broken chain says where.
local function Resolve(path)
    local cur, err = _G, nil
    local walked = {}
    for seg in path:gmatch("[^%.:]+") do
        local idx = tonumber(seg) or seg
        cur, err = SafeGet(cur, idx)
        if cur == nil then
            return nil, err, table.concat(walked, ".")
        end
        walked[#walked + 1] = seg
    end
    return cur, nil, table.concat(walked, ".")
end

-- "@StatusBar:SetTimerDuration" — does a widget of that type (built by us)
-- carry this method? Throwaway objects, parented to nothing we care about.
local scratch = {}
local function ScratchWidget(kind)
    if scratch[kind] ~= nil then return scratch[kind] end
    local ok, w = pcall(function()
        if kind == "Texture" or kind == "FontString" or kind == "MaskTexture" then
            local host = ScratchWidget("Frame")
            if not host then return nil end
            if kind == "Texture" then return host:CreateTexture() end
            if kind == "MaskTexture" then return host:CreateMaskTexture() end
            return host:CreateFontString()
        end
        local f = CreateFrame(kind)
        f:Hide()
        return f
    end)
    scratch[kind] = (ok and w) or false
    return scratch[kind]
end

-- "#Slider:MinimalSliderTemplate" — does this XML template exist? Building one
-- of our own is the only way to ask; CreateFrame errors on an unknown template.
local function ProbeTemplate(kind, template)
    local ok, f = pcall(CreateFrame, kind, nil, nil, template)
    if ok and f then pcall(f.Hide, f) end
    return { present = ok and true or false, type = ok and "template" or "no-template" }
end

local function ProbeTarget(path)
    local tKind, template = path:match("^#(%w+):([%w_]+)$")
    if tKind then return ProbeTemplate(tKind, template) end
    local kind, method = path:match("^@(%w+):(%w+)$")
    if kind then
        local w = ScratchWidget(kind)
        if not w then return { present = false, type = "no-" .. kind } end
        return Describe(SafeGet(w, method))
    end
    local v, err, reached = Resolve(path)
    local d = Describe(v, err)
    if not d.present and reached ~= "" then d.reached = reached end
    return d
end

-- ---------------------------------------------------------------------------
-- Per-skin dependency inventory (derived from Skins/ and Core/ — see header)
--
--   requires = Blizzard addon whose load gates Apply() in PadleyUI.lua
--   crit     = paths whose absence makes Apply() error or do nothing
--   deps     = everything else the skin dereferences or hooks
-- Path syntax: "Global.child.child", "Global:Method" (field read),
-- "@WidgetType:Method" (method on a throwaway widget we create), and
-- "#WidgetType:TemplateName" (does CreateFrame accept that template).
-- ---------------------------------------------------------------------------

local SKINS = {
    { name = "Core", file = "Core/Config.lua+Movers.lua+SkinEngine.lua+Fonts.lua",
      crit = { "Minimap", "UIParent", "UISpecialFrames", "GetCursorPosition",
               "C_AddOns.IsAddOnLoaded", "hooksecurefunc", "@Frame:HookScript",
               "#Slider:MinimalSliderTemplate", "#Frame:BackdropTemplate" },
      deps = { "GameTooltip", "@Slider:SetObeyStepOnDrag", "STANDARD_TEXT_FONT",
               "UNIT_NAME_FONT", "DAMAGE_TEXT_FONT", "@Frame:SetIgnoreParentAlpha",
               "CollectionsJournal", "EncounterJournal", "PVEFrame", "ProfessionsBookFrame",
               "WorldMapFrame.BorderFrame.TitleContainer", "CharacterFrame.TitleContainer",
               "@Texture:GetDebugName", "@Texture:RemoveMaskTexture",
               "@Texture:GetMaskTextures" } },
    { name = "Tooltip", file = "Skins/Tooltip.lua",
      crit = { "GameTooltip", "GameTooltip.NineSlice" },
      deps = { "ItemRefTooltip", "ItemRefTooltip.NineSlice", "ItemRefShoppingTooltip1",
               "ItemRefShoppingTooltip2", "EmbeddedItemTooltip", "ShoppingTooltip1",
               "ShoppingTooltip2", "GameTooltip.StatusBar", "GameTooltipStatusBar" } },
    { name = "GameMenu", file = "Skins/GameMenu.lua",
      crit = { "GameMenuFrame", "GameMenuFrame:InitButtons", "GameMenuFrame.buttonPool",
               "GameMenuFrame.Border" },
      deps = { "GameMenuFrame.Header" } },
    { name = "Chat", file = "Skins/Chat.lua",
      crit = { "NUM_CHAT_WINDOWS", "ChatFrame1", "ChatFrame1Tab", "ChatFrame1EditBox",
               "FCF_SetWindowAlpha" },
      deps = { "ChatFrame1ButtonFrame", "ChatFrame1EditBoxHeader", "ChatFrame1Tab.Text",
               "GeneralDockManager", "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow" } },
    { name = "StatusBar", file = "Skins/StatusBar.lua",
      crit = { "MainStatusTrackingBarContainer", "StatusTrackingBarManager:UpdateBarsShown",
               "UnitXP", "UnitXPMax", "GetXPExhaustion" },
      deps = { "@StatusBar:SetStatusBarAtlas", "MainMenuExpBar", "ReputationWatchBar" } },
    { name = "Minimap", file = "Skins/Minimap.lua",
      crit = { "MinimapCluster", "Minimap", "Minimap_ZoomIn", "Minimap_ZoomOut" },
      deps = { "Minimap.ZoomIn", "Minimap.ZoomOut", "MinimapCluster.BorderTop",
               "MinimapCluster.ZoneTextButton", "GameTimeFrame", "TimeManagerClockButton",
               "QueueStatusMinimapButton", "AddonCompartmentFrame", "MinimapBackdrop",
               "MinimapCompassTexture", "MinimapNorthTag", "MinimapZoneTextButton",
               "Minimap:SetArchBlobRingScalar", "Minimap:SetQuestBlobRingScalar",
               "MinimapBorder", "MiniMapTracking", "MiniMapWorldMapButton" } },
    { name = "ActionBars", file = "Skins/ActionBars.lua",
      crit = { "MainActionBar", "ActionButton1", "UIFrameFadeIn", "UIFrameFadeOut" },
      deps = { "ActionButton1.icon", "ActionButton1.IconMask", "ActionButton1.SlotArt",
               "ActionButton1.SlotBackground", "ActionButton1:UpdateButtonArt",
               "MainActionBar:UpdateButtonArt", "MainActionBar:RefreshButtonArt",
               "MultiBarBottomLeft", "MultiBarBottomLeftButton1", "MultiBarBottomRight",
               "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
               "StanceBar", "StanceButton1", "PetActionBar", "PetActionButton1",
               "UIFrameFadeRemoveFrame", "ObjectiveTrackerFrame.Header.MinimizeButton",
               "MainMenuBar", "MainMenuBarArtFrame", "PetActionBarFrame", "StanceBarFrame" } },
    { name = "CooldownTracker", file = "Skins/CooldownTracker.lua",
      crit = { "EssentialCooldownViewer", "EssentialCooldownViewer:GetItemFrames",
               "EssentialCooldownViewer:Layout" },
      deps = { "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
               "C_CooldownViewer" } },
    { name = "Nameplates", file = "Skins/Nameplates.lua",
      crit = { "C_NamePlate.GetNamePlates", "C_NamePlate.GetNamePlateForUnit",
               "C_Secrets.ShouldUnitIdentityBeSecret", "C_TooltipInfo.GetUnit",
               "WorldFrame", "SetCVar", "#GameTooltip:GameTooltipTemplate" },
      deps = { "C_CurveUtil.EvaluateColorValueFromBoolean", "C_DurationUtil.CreateDuration",
               "UnitCastingDuration", "UnitChannelDuration", "UnitCastingInfo",
               "UnitChannelInfo", "CreateUnitHealPredictionCalculator",
               "UnitGetDetailedHealPrediction", "CompactUnitFrame_UnregisterEvents",
               "C_Spell.GetSpellInfo", "C_Spell.GetSpellTexture", "UnitThreatSituation",
               "GetSpecialization", "GetSpecializationRole", "UnitNameFromGUID",
               "@StatusBar:SetTimerDuration", "@Texture:SetAlphaFromBoolean",
               "@Texture:GetDebugName", "@Frame:SetClipsChildren",
               "Enum.UnitMaximumHealthMode.WithAbsorbs",
               "Enum.UnitDamageAbsorbClampMode.MaximumHealth",
               "Enum.TooltipDataLineType.QuestObjective",
               "Enum.StatusBarTimerDirection.RemainingTime",
               "Enum.StatusBarInterpolation.Immediate", "SHIELD_TEXTURE" } },
    { name = "CastBar", file = "Skins/CastBar.lua",
      crit = { "PlayerCastingBarFrame", "PlayerCastingBarFrame.Text", "RAID_CLASS_COLORS" },
      deps = { "PetCastingBarFrame", "PlayerCastingBarFrame.Icon",
               "PlayerCastingBarFrame.BorderShield", "PlayerCastingBarFrame.TextBorder",
               "PlayerCastingBarFrame.Spark", "PlayerCastingBarFrame.StandardGlow",
               "PlayerCastingBarFrame.ChargeTier1", "CastingBarFrame" } },
    { name = "GCDBar", file = "Skins/GCDBar.lua",
      crit = { "C_Spell.GetSpellCooldown", "PlayerCastingBarFrame" },
      deps = {} },
    { name = "Items", file = "Skins/Items.lua",
      crit = { "EventUtil.ContinueOnAddOnLoaded", "GetInventorySlotInfo",
               "GetInventoryItemQuality", "ITEM_QUALITY_COLORS", "CharacterHeadSlot",
               "CharacterHeadSlot.IconBorder" },
      deps = { "BankFrame", "BankSlotsFrame", "BankFrameItem1", "MerchantFrame",
               "MerchantItem1", "MerchantItem1ItemButton", "MerchantItem1.ItemButton",
               "PaperDollFrame" } },
    { name = "CharacterFrame", file = "Skins/CharacterFrame.lua",
      requires = "Blizzard_UIPanels_Game",
      crit = { "CharacterFrame", "CharacterStatsPane", "PaperDollFrame_UpdateStats",
               "PaperDollFrame_UpdateSidebarTabs", "CharacterFrameTab1" },
      deps = { "CharacterFrame.Inset.NineSlice", "CharacterStatsPane.ItemLevelFrame.Value",
               "CharacterStatsPane.statsFramePool", "PaperDollSidebarTab1",
               "PaperDollFrame.EquipmentManagerPane.ScrollBox",
               "PaperDollFrame.EquipmentManagerPane.ScrollBox:ForEachFrame",
               "PaperDollFrame.TitleManagerPane.ScrollBox", "ReputationFrame",
               "ReputationFrame.ScrollBox", "ReputationFrame.ReputationDetailFrame",
               "CharacterModelScene", "CharacterModelFrameBackgroundOverlay",
               "CharacterLevelText", "CharacterFrameInsetRight", "PaperDollFrameEquipSet",
               "PaperDollFrameSaveSet", "CharacterFrame.TitleContainer" } },
    { name = "CharacterTokens", file = "Skins/CharacterFrame.lua (ApplyTokenFrame)",
      requires = "Blizzard_TokenUI",
      crit = { "TokenFrame", "TokenFrame.ScrollBox" },
      deps = { "TokenFramePopup", "TokenFramePopup.CloseButton" } },
    { name = "Loot", file = "Skins/Loot.lua", requires = "Blizzard_UIPanels_Game",
      crit = { "LootFrame", "LootFrame.ScrollBox", "LootFrame.ScrollBox:Update",
               "ITEM_QUALITY_COLORS" },
      deps = { "LootFrame.ScrollBox:ForEachFrame", "LootButton1" } },
    { name = "UnitFrames", file = "Skins/UnitFrames.lua",
      crit = { "PlayerFrame", "TargetFrame", "FocusFrame",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
               "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
               "TargetFrame:CheckClassification", "FocusFrame:CheckClassification",
               "UnitFrameHealthBar_Update" },
      deps = { "PlayerFrame.PlayerFrameContainer",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.StatusTexture",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator",
               "PlayerFrame.threatIndicator", "PlayerFrame.name",
               "TargetFrame.TargetFrameContainer",
               "TargetFrame.TargetFrameContainer.FrameTexture",
               "TargetFrame.TargetFrameContainer.Portrait",
               "TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBarArea.ManaBar",
               "TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText",
               "TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor",
               "TargetFrame.TargetFrameContent.TargetFrameContentContextual.HighLevelTexture",
               "TargetFrame.spellbar", "TargetFrameSpellBar", "TargetFrame.auraPools",
               "TargetFrame:UpdateAuras", "FocusFrame:UpdateAuras",
               "UnitFrameHealPredictionBars_Update", "GetCreatureDifficultyColor",
               "PowerBarColor", "RAID_CLASS_COLORS",
               -- classic-lineage names, for contrast
               "PlayerFrameHealthBar", "PlayerFrameManaBar", "TargetFrameHealthBar",
               "PlayerFrame.healthbar", "TargetFrame.healthbar" } },
    { name = "ClassPower", file = "Skins/ClassPower.lua",
      crit = { "Enum.PowerType.HolyPower", "Enum.PowerType.Chi",
               "Enum.PowerType.ComboPoints", "Enum.PowerType.SoulShards",
               "Enum.PowerType.ArcaneCharges", "Enum.PowerType.Runes",
               "Enum.PowerType.Essence", "UnitPower", "UnitPowerMax" },
      deps = { "PersonalResourceDisplayFrame", "PaladinPowerBarFrame",
               "MonkHarmonyBarFrame", "WarlockPowerFrame", "MageArcaneChargesFrame",
               "RuneFrame", "EssencePlayerFrame", "DruidComboPointBarFrame",
               "RogueComboPointBarFrame", "GetRuneCooldown", "GetShapeshiftFormID",
               "CAT_FORM", "GetSpecialization", "ComboFrame" } },
    { name = "PartyFrames", file = "Skins/PartyFrames.lua + Core/RestoredRegions.lua",
      crit = { "CompactUnitFrame_SetUnit", "CompactPartyFrame",
               "CompactPartyFrame.memberUnitFrames", "CompactRaidFrameContainer" },
      deps = { "CompactPartyFrameMember1", "CompactPartyFrameMember1.healthBar",
               "CompactPartyFrameMember1.powerBar", "CompactPartyFrameMember1:UpdateAll",
               "CompactPartyFrameMember1.myHealPrediction",
               "CompactPartyFrameMember1.aggroHighlight",
               "CompactPartyFrameMember1.selectionHighlight",
               "CompactPartyFrameMember1.buffFrames", "CompactRaidFrame1",
               "CompactRaidGroup1", "CompactPartyFrameTitle",
               "CompactRaidFrameContainerBorderFrame", "CompactPartyFrame:UpdateLayout",
               "CompactRaidFrameContainer:LayoutFrames", "CompactUnitFrame_UpdateHealPrediction",
               "CompactRaidGroup_UpdateLayout", "FlowContainer_DoLayout", "MAX_RAID_GROUPS",
               "hasanysecretvalues", "UnitSelectionColor", "PowerBarColor" } },
    { name = "MirrorTimer", file = "Skins/MirrorTimer.lua",
      crit = { "MirrorTimerContainer", "MirrorTimerContainer.mirrorTimers",
               "MirrorTimerContainer:SetupTimer", "MirrorTimerContainer:GetAvailableTimer" },
      deps = { "MirrorTimer1" } },
    { name = "TimerTracker", file = "Skins/TimerTracker.lua",
      crit = { "TimerTracker" },
      deps = { "TimerTracker.timerList" } },
    { name = "EncounterBar", file = "Skins/EncounterBar.lua",
      crit = { "UIWidgetPowerBarContainerFrame", "UIWidgetPowerBarContainerFrame.widgetFrames" },
      deps = { "UIWidgetPowerBarContainerFrame:ProcessWidget" } },
    { name = "ChatBubbles", file = "Skins/ChatBubbles.lua",
      crit = { "C_ChatBubbles.GetAllChatBubbles" },
      deps = {} },
    { name = "DamageMeter", file = "Skins/DamageMeter.lua", requires = "Blizzard_DamageMeter",
      crit = { "DamageMeter", "DamageMeter:SetupSessionWindow" },
      deps = { "DamageMeter.windowDataList", "C_DamageMeter" } },
    { name = "ObjectiveTracker", file = "Skins/ObjectiveTracker.lua",
      requires = "Blizzard_ObjectiveTracker",
      crit = { "ObjectiveTrackerFrame", "ObjectiveTrackerFrame.modules",
               "ObjectiveTrackerFrame:Update", "ObjectiveTrackerFrame.Header.MinimizeButton" },
      deps = { "ObjectiveTrackerFrame.Header", "ObjectiveTrackerFrame.Header.Text",
               "ObjectiveTrackerFrame.Header.Background" } },
    { name = "Professions", file = "Skins/Professions.lua", requires = "Blizzard_Professions",
      crit = { "ProfessionsFrame", "ProfessionsFrame.CraftingPage",
               "ProfessionsFrame.CraftingPage.RecipeList.ScrollBox",
               "ProfessionsFrame.CraftingPage.SchematicForm:Init", "ProfessionsFrame.TabSystem" },
      deps = { "ProfessionsFrame.SpecPage", "ProfessionsFrame.SpecPage:UpdateTabs",
               "ProfessionsFrame.OrdersPage", "ProfessionsFrame.CraftingPage.CraftingOutputLog",
               "ProfessionsFrame.CraftingPage.RankBar", "TradeSkillFrame" } },
    { name = "WorldMap", file = "Skins/WorldMap.lua", requires = "Blizzard_WorldMap",
      crit = { "WorldMapFrame", "WorldMapFrame:Maximize", "WorldMapFrame:Minimize",
               "WorldMapFrame.BorderFrame", "QuestInfo_Display", "QuestLogQuests_Update" },
      deps = { "WorldMapFrame.NavBar", "NavBar_AddButton", "WorldMapFrame.ScrollContainer",
               "WorldMapFrame.BlackoutFrame.Blackout", "WorldMapFrame.SidePanelToggle",
               "QuestMapFrame", "QuestMapFrame.DetailsFrame", "QuestMapFrame.QuestsFrame",
               "QuestMapFrame.MapLegend", "QuestMapFrame.QuestsTab", "QuestScrollFrame",
               "QuestScrollFrame.headerFramePool", "QuestScrollFrame.titleFramePool",
               "QuestInfoFrame", "QuestInfoRewardsFrame", "MapQuestInfoRewardsFrame",
               "QuestLogFrame" } },
    { name = "BetterBags", file = "Skins/BetterBags.lua", requires = "BetterBags",
      crit = { "LibStub" },
      deps = { "C_Item.GetItemQualityColor" } },
}

-- Blizzard addons the retail skins/movers are gated on (PadleyUI.lua + Movers).
local BLIZZARD_ADDONS = {
    "Blizzard_DamageMeter", "Blizzard_UIPanels_Game", "Blizzard_ObjectiveTracker",
    "Blizzard_TokenUI", "Blizzard_Professions", "Blizzard_ProfessionsBook",
    "Blizzard_Collections", "Blizzard_GroupFinder", "Blizzard_EncounterJournal",
    "Blizzard_WorldMap", "Blizzard_EditMode", "Blizzard_CooldownViewer",
    "Blizzard_NamePlates", "Blizzard_UnitFrame", "Blizzard_CompactRaidFrames",
    "Blizzard_ActionBar", "Blizzard_ActionBarController", "Blizzard_MapCanvas",
    "Blizzard_QuestLog", "Blizzard_WatchFrame", "Blizzard_QuestTimer",
    "Blizzard_TimeManager", "Blizzard_PlayerSpells", "Blizzard_SpellBook",
    "Blizzard_ClassTalentUI", "Blizzard_TalentUI", "Blizzard_ChatFrameBase",
    "Blizzard_MirrorTimer", "Blizzard_UIWidgets", "Blizzard_Minimap",
    "Blizzard_PersonalResourceDisplay", "BetterBags",
}

-- ---------------------------------------------------------------------------
-- Decisive questions
-- ---------------------------------------------------------------------------

local function Exists(path) return ProbeTarget(path).present end

local function ProbeList(list)
    local t = {}
    for _, p in ipairs(list) do t[p] = ProbeTarget(p) end
    return t
end

local function ProbeBuild()
    local version, build, date, interface = GetBuildInfo()
    local b = {
        version = version, build = build, date = date, interface = interface,
        flavor = ns.FLAVOR, nsInterface = ns.INTERFACE,
        projectId = WOW_PROJECT_ID,
        tocVariant = C_AddOns and C_AddOns.GetAddOnMetadata
            and C_AddOns.GetAddOnMetadata(addonName, "X-PadleyUI-TOC") or nil,
        tocInterface = C_AddOns and C_AddOns.GetAddOnMetadata
            and C_AddOns.GetAddOnMetadata(addonName, "Interface") or nil,
        locale = GetLocale and GetLocale() or nil,
        expansionLevel = GetExpansionLevel and GetExpansionLevel() or nil,
        serverExpansionLevel = GetServerExpansionLevel and GetServerExpansionLevel() or nil,
        maxLevelForExpansion = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or nil,
        isTestBuild = IsTestBuild and IsTestBuild() or nil,
        isPublicBuild = IsPublicBuild and IsPublicBuild() or nil,
    }
    -- Every WOW_PROJECT_* constant, and which ones equal WOW_PROJECT_ID.
    b.projectConstants, b.projectMatches = {}, {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^WOW_PROJECT_") and type(v) == "number" then
            b.projectConstants[k] = v
            if v == WOW_PROJECT_ID and k ~= "WOW_PROJECT_ID" then
                b.projectMatches[#b.projectMatches + 1] = k
            end
        end
    end
    table.sort(b.projectMatches)
    -- Game-rules surface (Classic-on-modern clients expose ruleset queries).
    b.gameRules = {}
    if type(C_GameRules) == "table" then
        for k, v in pairs(C_GameRules) do b.gameRules[k] = type(v) end
        if C_GameRules.GetActiveGameMode then
            local ok, m = pcall(C_GameRules.GetActiveGameMode)
            if ok and not IsSecret(m) then b.activeGameMode = m end
        end
        if Enum and type(Enum.GameMode) == "table" then
            b.gameModeEnum = {}
            for k, v in pairs(Enum.GameMode) do b.gameModeEnum[k] = v end
        end
    end
    for _, fn in ipairs({ "ClassicExpansionAtLeast", "ClassicExpansionAtMost",
                          "GetClassicExpansionLevel", "IsOnGlueScreen" }) do
        b[fn] = type(_G[fn])
    end
    return b
end

local function ProbeSecrets()
    local s = {
        globals = {}, cSecrets = {}, cSecretsState = {}, widgetMethods = {},
        enums = {}, cvars = {},
    }
    for _, g in ipairs({
        "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
        "canaccessallvalues", "secretwrap", "scrubsecretvalues",
        "hasanysecretvalues", "dropsecretaccess",
        "C_Secrets", "C_RestrictedActions", "C_DurationUtil", "C_CurveUtil",
        "C_StringUtil", "C_DamageMeter", "C_CombatLog",
        "UnitCastingDuration", "UnitChannelDuration",
        "UnitHealthPercent", "UnitHealthMissing",
        "CreateUnitHealPredictionCalculator", "UnitGetDetailedHealPrediction",
        "CombatLogGetCurrentEventInfo", "GetSpellInfo", "GetItemInfo",
        "AbbreviateNumbers",
    }) do
        s.globals[g] = type(_G[g])
    end
    if type(C_Secrets) == "table" then
        for k, v in pairs(C_Secrets) do
            s.cSecrets[k] = type(v)
            if type(v) == "function" and (k:find("^Should") or k:find("^Has")) then
                local ok, r = pcall(v)
                if ok then
                    s.cSecretsState[k] = IsSecret(r) and "SECRET" or r
                else
                    s.cSecretsState[k] = "ERR"
                end
            end
        end
    end
    s.curveUtil = {}
    if type(C_CurveUtil) == "table" then
        for k, v in pairs(C_CurveUtil) do s.curveUtil[k] = type(v) end
    end
    s.durationUtil = {}
    if type(C_DurationUtil) == "table" then
        for k, v in pairs(C_DurationUtil) do s.durationUtil[k] = type(v) end
    end
    for _, m in ipairs({
        "@Texture:SetAlphaFromBoolean", "@Texture:SetVertexColorFromBoolean",
        "@FontString:SetAlphaFromBoolean", "@FontString:SetVertexColorFromBoolean",
        "@Frame:SetAlphaFromBoolean", "@Frame:HasSecretValues",
        "@Frame:HasSecretAspect", "@Frame:SetPreventSecretValues",
        "@Frame:IsAnchoringSecret", "@Frame:SetToDefaults",
        "@StatusBar:SetTimerDuration", "@StatusBar:SetToTargetValue",
        "@StatusBar:SetValue", "@Cooldown:SetCooldownFromExpirationTime",
        "@Cooldown:SetCooldownFromDurationObject",
    }) do
        s.widgetMethods[m] = ProbeTarget(m).present
    end
    for _, e in ipairs({ "StatusBarInterpolation", "StatusBarTimerDirection",
                         "AddOnRestrictionType", "LuaCurveType" }) do
        s.enums[e] = Enum and type(Enum[e]) == "table"
    end
    for _, cv in ipairs({ "secretAurasForced", "secretCooldownsForced",
                          "secretUnitIdentityForced", "secretUnitPowerForced",
                          "secretUnitComparisonForced", "addonChatRestrictionsForced" }) do
        local ok, v = pcall(C_CVar and C_CVar.GetCVar or GetCVar, cv)
        s.cvars[cv] = (ok and v ~= nil) and tostring(v) or false
    end
    -- Behaviour, not just presence: does a secret actually refuse arithmetic
    -- in our (tainted) context? This is the taint-era vs pre-taint verdict.
    if type(secretwrap) == "function" then
        local okWrap, sv = pcall(secretwrap, 5)
        s.secretwrapOk = okWrap
        if okWrap then
            s.wrappedIsSecret = issecretvalue and issecretvalue(sv) or false
            local okMath = pcall(function() return sv + 1 end)
            s.arithmeticOnSecretAllowed = okMath
            local okCmp = pcall(function() return sv == 5 end)
            s.compareOnSecretAllowed = okCmp
        end
    end
    -- Live sample: is the player's own health secret right now? (Out of
    -- combat this is expected false even on a taint-era client.)
    local okH, h = pcall(UnitHealth, "player")
    if okH then s.playerHealthSecretNow = IsSecret(h) else s.playerHealthSecretNow = "ERR" end
    local okHM, hm = pcall(UnitHealthMax, "player")
    if okHM then s.playerHealthMaxSecretNow = IsSecret(hm) else s.playerHealthMaxSecretNow = "ERR" end
    if C_Secrets and C_Secrets.HasSecretRestrictions then
        local ok, r = pcall(C_Secrets.HasSecretRestrictions)
        if not ok then
            s.restrictionsActiveNow = "ERR"
        elseif IsSecret(r) then
            s.restrictionsActiveNow = "SECRET"
        else
            s.restrictionsActiveNow = r and true or false
        end
    end

    local era
    if s.globals.issecretvalue == "function" and s.globals.C_Secrets == "table" then
        era = "taint-era"
    elseif s.globals.issecretvalue == "nil" and s.globals.C_Secrets == "nil" then
        era = "pre-taint"
    else
        era = "mixed"
    end
    s.verdict = era
    return s
end

local function ProbeEditMode()
    local e = ProbeList({
        "EditModeManagerFrame", "EditModeManagerFrame.registeredSystemFrames",
        "EditModeManagerFrame:UpdateRaidContainerFlow",
        "EditModeSystemMixin", "C_EditMode", "C_EditMode.GetLayouts",
        "Enum.EditModeSystem", "Enum.EditModeUnitFrameSystemIndices",
        "PlayerFrame.systemInfo", "MainActionBar.systemInfo",
        "MainMenuBar.systemInfo", "ObjectiveTrackerFrame.systemInfo",
        "MinimapCluster.systemInfo", "EssentialCooldownViewer.systemInfo",
        "DamageMeter.systemInfo",
    })
    local systems = {}
    if Enum and type(Enum.EditModeSystem) == "table" then
        for k, v in pairs(Enum.EditModeSystem) do systems[k] = v end
    end
    return { targets = e, systems = systems,
             verdict = e["EditModeManagerFrame"].present and "present" or "absent" }
end

local function ProbeUnitFrameLineage()
    local t = ProbeList({
        -- retail (Dragonflight+) structure
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar",
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual",
        "PlayerFrame.PlayerFrameContainer",
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
        "TargetFrame.TargetFrameContainer",
        "PartyFrame", "PartyFrame.MemberFrame1",
        -- classic structure
        "PlayerFrameHealthBar", "PlayerFrameManaBar", "PlayerFrameTexture",
        "TargetFrameHealthBar", "TargetFrameTextureFrame", "PartyMemberFrame1",
        -- compact (raid-style) frames
        "CompactPartyFrame", "CompactRaidFrameContainer", "CompactUnitFrame_SetUnit",
        "CompactUnitFrame_UpdateHealPrediction",
        -- heal-prediction family (Core/RestoredRegions.lua)
        "UnitFrameHealPredictionBars_Update", "UnitFrameHealPredictionBarsMixin",
    })
    local retail = t["PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar"].present
    local classic = t["PlayerFrameHealthBar"].present
    local verdict = (retail and classic and "both?") or (retail and "retail")
        or (classic and "classic") or "unknown"
    return { targets = t, verdict = verdict }
end

local function ProbeObjectiveTracker()
    local t = ProbeList({
        "ObjectiveTrackerFrame", "ObjectiveTrackerFrame.Header",
        "ObjectiveTrackerFrame.Header.MinimizeButton", "ObjectiveTrackerFrame.modules",
        "ObjectiveTrackerFrame:Update", "ObjectiveTrackerManager",
        "QuestObjectiveTracker", "WatchFrame", "QuestWatchFrame",
        "QuestTimerFrame", "AchievementWatchFrame",
    })
    local verdict = (t["ObjectiveTrackerFrame.modules"].present and "retail-modular")
        or (t["ObjectiveTrackerFrame"].present and "retail-legacy")
        or (t["WatchFrame"].present and "wrath-watchframe")
        or (t["QuestWatchFrame"].present and "vanilla-questwatch") or "none"
    return { targets = t, verdict = verdict }
end

local function ProbeDamageMeter()
    local loadable
    if C_AddOns and C_AddOns.GetAddOnInfo then
        local ok, name, _, _, canLoad, reason = pcall(C_AddOns.GetAddOnInfo, "Blizzard_DamageMeter")
        loadable = { ok = ok, name = ok and name or nil, loadable = ok and canLoad or nil,
                     reason = ok and reason or nil }
    end
    local t = ProbeList({
        "DamageMeter", "DamageMeter:SetupSessionWindow", "DamageMeter.windowDataList",
        "C_DamageMeter", "C_DamageMeter.GetAvailableCombatSessions",
        "C_DamageMeter.GetCombatSessionFromID",
    })
    return {
        addonInfo = loadable,
        loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_DamageMeter") or false,
        targets = t,
        verdict = t["DamageMeter"].present and "present" or "absent",
    }
end

-- Nameplate structure needs a live plate. Captured on the first
-- NAME_PLATE_UNIT_ADDED, and again by /puiforever plate (prefers target).
local PLATE_FIELDS = {
    "UnitFrame", "driverFrame",
    "UnitFrame.healthBar", "UnitFrame.HealthBarsContainer",
    "UnitFrame.HealthBarsContainer.healthBar", "UnitFrame.castBar",
    "UnitFrame.CastBar", "UnitFrame.AurasFrame", "UnitFrame.BuffFrame",
    "UnitFrame.AurasFrame.BuffListFrame", "UnitFrame.AurasFrame.DebuffListFrame",
    "UnitFrame.ClassificationFrame", "UnitFrame.LevelFrame",
    "UnitFrame.selectionHighlight", "UnitFrame.aggroHighlight",
    "UnitFrame.name", "UnitFrame.statusText", "UnitFrame.RaidTargetFrame",
    "UnitFrame.WidgetContainer", "UnitFrame.SoftTargetFrame",
}

local function CapturePlate(plate, unit, source)
    local p = { source = source, unit = unit, fields = {} }
    p.plate = Describe(plate)
    for _, path in ipairs(PLATE_FIELDS) do
        local cur, err = plate, nil
        for seg in path:gmatch("[^%.]+") do
            cur, err = SafeGet(cur, seg)
            if cur == nil then break end
        end
        p.fields[path] = Describe(cur, err)
    end
    -- Count of StatusBars / Cooldowns (aura buttons) under UnitFrame, shallow.
    local uf = SafeGet(plate, "UnitFrame")
    if IsWidget(uf) then
        local bars, cds, kids = 0, 0, 0
        local function sweep(node, depth)
            if depth > 4 or not IsWidget(node) then return end
            local ot = SafeCall(node, "GetObjectType")
            if ot == "StatusBar" then bars = bars + 1 end
            if ot == "Cooldown" then cds = cds + 1 end
            local getKids = SafeGet(node, "GetChildren")
            if type(getKids) ~= "function" then return end
            local packed = { pcall(getKids, node) }
            if table.remove(packed, 1) then
                for _, c in ipairs(packed) do
                    kids = kids + 1
                    sweep(c, depth + 1)
                end
            end
        end
        sweep(uf, 0)
        p.statusBars, p.cooldowns, p.descendants = bars, cds, kids
    end
    return p
end

local function ProbeNameplates()
    local t = ProbeList({
        "NamePlateDriverFrame", "C_NamePlate", "C_NamePlate.GetNamePlateForUnit",
        "C_NamePlate.GetNamePlates", "C_NamePlate.SetNamePlateEnemySize",
        "NamePlateBaseMixin", "NameplateBuffContainerMixin",
        "CompactUnitFrame_UnregisterEvents", "C_NamePlateManager",
    })
    return { targets = t }
end

local function ProbeAddons()
    local a = {}
    for _, name in ipairs(BLIZZARD_ADDONS) do
        local row = {}
        if C_AddOns and C_AddOns.GetAddOnInfo then
            local ok, n, _, _, canLoad, reason = pcall(C_AddOns.GetAddOnInfo, name)
            row.exists = ok and n ~= nil and reason ~= "MISSING"
            row.loadable = ok and canLoad or false
            row.reason = ok and reason or "ERR"
        end
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
            row.loaded = ok and loaded and true or false
        end
        if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
            local ok, lod = pcall(C_AddOns.IsAddOnLoadOnDemand, name)
            row.loadOnDemand = ok and lod or nil
        end
        a[name] = row
    end
    return a
end

local function ProbeSkins(addons)
    local out = {}
    for _, skin in ipairs(SKINS) do
        local r = { file = skin.file, requires = skin.requires, targets = {},
                    missingCrit = {}, missing = {} }
        for _, p in ipairs(skin.crit or {}) do
            local d = ProbeTarget(p)
            d.crit = true
            r.targets[p] = d
            if not d.present then r.missingCrit[#r.missingCrit + 1] = p end
        end
        for _, p in ipairs(skin.deps or {}) do
            local d = ProbeTarget(p)
            r.targets[p] = d
            if not d.present then r.missing[#r.missing + 1] = p end
        end
        local gated = skin.requires and addons[skin.requires]
            and not addons[skin.requires].loaded
        if #r.missingCrit > 0 then
            r.verdict = gated and "addon-not-loaded" or "blocked"
        elseif #r.missing > 0 then
            r.verdict = "partial"
        else
            r.verdict = "ok"
        end
        out[skin.name] = r
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Run + persist
-- ---------------------------------------------------------------------------

local livePlate  -- survives re-runs within a session

local function RunProbe(mode)
    local result = { schema = SCHEMA, mode = mode, time = time(), errors = {} }
    local function step(key, fn, ...)
        local ok, v = pcall(fn, ...)
        if ok then
            result[key] = v
        else
            result.errors[#result.errors + 1] = key .. ": " .. tostring(v)
        end
    end
    step("build", ProbeBuild)
    step("addons", ProbeAddons)
    step("secrets", ProbeSecrets)
    step("editMode", ProbeEditMode)
    step("unitFrames", ProbeUnitFrameLineage)
    step("objectiveTracker", ProbeObjectiveTracker)
    step("damageMeter", ProbeDamageMeter)
    step("nameplates", ProbeNameplates)
    if result.nameplates then result.nameplates.live = livePlate end
    step("skins", ProbeSkins, result.addons or {})

    PadleyUI_DB = PadleyUI_DB or {}
    PadleyUI_DB.foreverProbe = result
    return result
end

local function CaptureLivePlate(unit, source)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not IsWidget(plate) then return false end
    local okCap, p = pcall(CapturePlate, plate, unit, source)
    if not okCap then return false end
    livePlate = p
    local db = PadleyUI_DB and PadleyUI_DB.foreverProbe
    if db and db.nameplates then db.nameplates.live = p end
    return true
end

-- ---------------------------------------------------------------------------
-- Human summary (secondary channel — the SV file is the primary one)
-- ---------------------------------------------------------------------------

local out = {}
local function Emit(s)
    if #s > LINE_CAP then s = s:sub(1, LINE_CAP - 3) .. "..." end
    out[#out + 1] = s
end

local function BuildSummary(r)
    out = {}
    local b = r.build or {}
    Emit(string.format("=== PadleyUI Forever probe (schema %d, mode %s) ===",
        r.schema or 0, tostring(r.mode)))
    Emit(string.format("build %s (%s) iface=%s flavor=%s toc=%s projectId=%s [%s]",
        tostring(b.version), tostring(b.build), tostring(b.interface),
        tostring(b.flavor), tostring(b.tocVariant), tostring(b.projectId),
        table.concat(b.projectMatches or {}, ",")))
    Emit("secrets: " .. tostring(r.secrets and r.secrets.verdict) ..
        "  editMode: " .. tostring(r.editMode and r.editMode.verdict) ..
        "  unitFrames: " .. tostring(r.unitFrames and r.unitFrames.verdict))
    Emit("objectiveTracker: " .. tostring(r.objectiveTracker and r.objectiveTracker.verdict) ..
        "  damageMeter: " .. tostring(r.damageMeter and r.damageMeter.verdict))
    local live = r.nameplates and r.nameplates.live
    if live then
        local f = live.fields
        Emit(string.format("nameplate(%s): castBar=%s CastBar=%s AurasFrame=%s healthBar=%s bars=%s cds=%s",
            tostring(live.unit), tostring(f["UnitFrame.castBar"].present),
            tostring(f["UnitFrame.CastBar"].present), tostring(f["UnitFrame.AurasFrame"].present),
            tostring(f["UnitFrame.healthBar"].present), tostring(live.statusBars),
            tostring(live.cooldowns)))
    else
        Emit("nameplate: no live plate captured yet — target a mob, /puiforever plate")
    end
    Emit("== skins ==")
    local names = {}
    for name in pairs(r.skins or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local s = r.skins[name]
        local line = string.format("%-16s %-16s", name, s.verdict)
        if #s.missingCrit > 0 then
            line = line .. " crit-missing: " .. table.concat(s.missingCrit, ", ")
        elseif #s.missing > 0 then
            line = line .. " missing: " .. table.concat(s.missing, ", ")
        end
        Emit(line)
    end
    if #(r.errors or {}) > 0 then
        Emit("== probe errors ==")
        for _, e in ipairs(r.errors) do Emit("  " .. e) end
    end
    Emit("Full data: PadleyUI_DB.foreverProbe — /reload to flush to SavedVariables.")
end

local function PrintPage(page)
    local total = #out
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    page = math.min(math.max(page or 1, 1), pages)
    local first = (page - 1) * PAGE_SIZE + 1
    local last  = math.min(first + PAGE_SIZE - 1, total)
    print("|cff66ccffPUIFOREVER|r page " .. page .. "/" .. pages ..
          " (lines " .. first .. "-" .. last .. " of " .. total .. ")")
    for i = first, last do print(out[i]) end
    if page < pages then
        print("|cff66ccffPUIFOREVER|r more: /puiforever " .. (page + 1))
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local ON_DEMAND = {
    "Blizzard_DamageMeter", "Blizzard_UIPanels_Game", "Blizzard_ObjectiveTracker",
    "Blizzard_TokenUI", "Blizzard_Professions", "Blizzard_WorldMap",
    "Blizzard_CooldownViewer", "Blizzard_EditMode",
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(RunProbe, "login")
        if ok then
            print("|cff66ccffPadleyUI|r Forever probe written to PadleyUI_DB.foreverProbe " ..
                  "(flavor=" .. tostring(ns.FLAVOR) .. "). /puiforever for a summary.")
        else
            print("|cffff5555PadleyUI Forever probe error:|r " .. tostring(err))
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if CaptureLivePlate(unit, "auto") then
            self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        end
    end
end)

SLASH_PUIFOREVER1 = "/puiforever"
SlashCmdList["PUIFOREVER"] = function(msg)
    msg = (msg or ""):lower()
    local ok, err = pcall(function()
        local r = PadleyUI_DB and PadleyUI_DB.foreverProbe
        if msg:find("full", 1, true) then
            local loaded = {}
            for _, name in ipairs(ON_DEMAND) do
                if C_AddOns and C_AddOns.LoadAddOn
                    and not C_AddOns.IsAddOnLoaded(name) then
                    local okL, did = pcall(C_AddOns.LoadAddOn, name)
                    loaded[#loaded + 1] = name .. "=" .. tostring(okL and did)
                end
            end
            r = RunProbe("full")
            r.loadAttempts = loaded
        elseif msg:find("plate", 1, true) then
            local got = CaptureLivePlate("target", "manual")
            if not got and C_NamePlate and C_NamePlate.GetNamePlates then
                local plates = C_NamePlate.GetNamePlates()
                local first = plates and plates[1]
                local u = first and SafeGet(first, "namePlateUnitToken")
                if u then got = CaptureLivePlate(u, "manual-first") end
            end
            print("|cff66ccffPUIFOREVER|r nameplate capture: " .. tostring(got))
            r = PadleyUI_DB and PadleyUI_DB.foreverProbe
        elseif msg:find("run", 1, true) or not r then
            r = RunProbe("manual")
        end
        BuildSummary(r)
        PrintPage(tonumber(msg:match("%d+")))
    end)
    if not ok then
        print("|cffff5555PUIFOREVER error:|r " .. tostring(err))
    end
end
