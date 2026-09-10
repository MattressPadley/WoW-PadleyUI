local _, ns = ...

local C = ns.C

-- ===========================================================================
-- Restored regions: exempt-and-reskin registry
--
-- Our party/raid and unit-frame skins run blanket "hide everything decorative"
-- sweeps. Some of the regions those sweeps catch are not decoration — they are
-- game data (incoming heals, absorb shields, threat, target selection). This
-- module is the single list of which regions the sweeps must SKIP, plus the
-- flat restyle applied to the ones we keep.
--
-- We do NOT rebuild any of these. Blizzard renders, positions, shows and hides
-- them with the real (untainted) values; we only decide what survives the sweep
-- and write texture/colour/alpha on it.
--
-- Hard rules, all of them taint rules:
--   * Never read a game value behind one of these regions. UnitGetIncomingHeals,
--     UnitGetTotalAbsorbs, UnitThreatSituation, UnitDetailedThreatSituation and
--     friends return secret values in combat / encounters / keys / arena, and
--     any arithmetic or comparison on a secret throws. Shown-state is Blizzard's.
--   * Never SetPoint / SetSize / SetWidth / SetHeight on these regions.
--   * Never read back GetTexture() on them either — it can return a secret
--     number, and comparing that throws. We always just write.
--   * Texture, vertex-colour and alpha writes on Blizzard textures are safe, so
--     that is the entire extent of what we do here.
-- ===========================================================================

local RestoredRegions = {}
ns.RestoredRegions = RestoredRegions

-- Back-compat alias. The registry started life as the heal-prediction module
-- and is still referenced as `HP` in the skins and the /puipredict probe.
ns.HealPrediction = RestoredRegions

-- Role -> restyle spec, or `false` meaning "pure chrome, leave it suppressed".
--
--   texture = true       replace the art with C.BAR_TEXTURE (flat white)
--   color   = {r,g,b,a}  SetVertexColor / SetStatusBarColor. Omit to let
--                        Blizzard own the tint (threat colour, dispel school).
--   alpha   = n          SetAlpha. Separate channel from the vertex alpha, so
--                        a Blizzard SetVertexColor(r,g,b) cannot blow it back
--                        up to opaque.
--
-- The glow/shadow art stays hidden, both because it carries no information and
-- because the glows deliberately overhang the bar edge (they rely on Blizzard's
-- mask, which our flat-bar mask stripping removes).
local ROLE_SPEC = {
    -- Heal prediction / absorbs. Blizzard never re-tints these, so the colour
    -- lives in the vertex alpha.
    myHeal         = { texture = true, color = { 0.15, 0.80, 0.35, 0.45 } },  -- your incoming heal
    otherHeal      = { texture = true, color = { 0.20, 0.60, 0.55, 0.35 } },  -- everyone else's incoming heal
    absorb         = { texture = true, color = { 0.70, 0.80, 1.00, 0.40 } },  -- damage absorb shield
    healAbsorb     = { texture = true, color = { 0.65, 0.12, 0.12, 0.50 } },  -- heal absorb (necrotic etc.)
    absorbOverlay  = false,                                                    -- striped art over the absorb
    overAbsorb     = false,                                                    -- glow, overhangs the bar
    overHealAbsorb = false,                                                    -- glow, overhangs the bar
    healAbsorbEdge = false,                                                    -- gradient shadow art

    -- Threat / aggro on a group member (CompactUnitFrame.aggroHighlight).
    --
    -- NO texture swap and NO colour override, deliberately:
    --   * The region is `setAllPoints="true"` over the whole unit button and the
    --     RaidFrame-AgroFrame atlas is a border glow with a transparent centre.
    --     SetTexture(WHITE8x8) would paint an opaque rectangle across the entire
    --     frame and bury the health bar. The atlas is already flat-ish line art,
    --     so keeping it is both the correct visual and the safe one.
    --   * CompactUnitFrame_UpdateAggroHighlight calls SetVertexColor with the
    --     threat-status colour. That colour IS the information (tanking vs
    --     high-threat vs losing aggro) and we must not read the status to
    --     reproduce it — UnitThreatSituation is secret. So Blizzard keeps the pen.
    -- All we do is stop hiding it.
    aggro          = { alpha = 1 },

    -- Your current target (CompactUnitFrame.selectionHighlight).
    --
    -- Flat white wash instead of the RaidFrame-TargetFrame border art, held at a
    -- low alpha via SetAlpha. CompactUnitFrame_UpdateHealthColor calls
    -- SetVertexColor on this region (white, or the health colour when the
    -- extended-colours option is on), which would reset a vertex alpha to 1 and
    -- give us an opaque block — hence SetAlpha, which Blizzard never touches
    -- here, and no colour of our own.
    selection      = { texture = true, alpha = 0.12 },
}

-- Known parentKeys, both naming families. CompactUnitFrame uses lowerCamel
-- textures on the frame itself; the modern PlayerFrame/TargetFrame use
-- UpperCamel bars on HealthBarsContainer. Probing both on every owner is
-- harmless and means either family is picked up. /puipredict dumps what the
-- live client actually has.
--
-- Verified against the 12.1 client source
-- (Blizzard_UnitFrame/Shared/CompactUnitFrame.xml) for the CompactUnitFrame
-- family, including aggroHighlight (ARTWORK/3, atlas RaidFrame-AgroFrame) and
-- selectionHighlight (OVERLAY, atlas RaidFrame-TargetFrame).
local KEY_ROLE = {
    -- CompactUnitFrame (party / raid)
    myHealPrediction        = "myHeal",
    otherHealPrediction     = "otherHeal",
    totalAbsorb             = "absorb",
    totalAbsorbOverlay      = "absorbOverlay",
    myHealAbsorb            = "healAbsorb",
    myHealAbsorbLeftShadow  = "healAbsorbEdge",
    myHealAbsorbRightShadow = "healAbsorbEdge",
    overAbsorbGlow          = "overAbsorb",
    overHealAbsorbGlow      = "overHealAbsorb",
    aggroHighlight          = "aggro",
    selectionHighlight      = "selection",
    -- Player / Target / Focus (HealthBarsContainer)
    MyHealPredictionBar     = "myHeal",
    OtherHealPredictionBar  = "otherHeal",
    TotalAbsorbBar          = "absorb",
    TotalAbsorbBarOverlay   = "absorbOverlay",
    HealAbsorbBar           = "healAbsorb",
    OverAbsorbGlow          = "overAbsorb",
    OverHealAbsorbGlow      = "overHealAbsorb",
}

-- role cache: region -> role string, or false for "definitely not ours".
-- Weak-keyed so a recycled frame pool entry cannot be pinned by this table.
local roleCache = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Role inference
---------------------------------------------------------------------------

-- Fallback for regions we reach through a blanket sweep without having seen
-- their parentKey. GetDebugName() renders the parentKey path, so a key we
-- never enumerated still resolves. If this misses, the region simply gets
-- hidden as before — the failure mode is the current behaviour, not a break.
local function RoleFromName(name)
    name = name:lower()

    -- Tested before the absorb/heal families: these names share no substrings
    -- with them, but keeping them first documents that aggroFlash and
    -- classificationIndicator are deliberately NOT matched — they stay chrome.
    if name:find("aggrohighlight", 1, true) then return "aggro" end
    if name:find("selectionhighlight", 1, true) then return "selection" end

    if name:find("healabsorb", 1, true) then
        if name:find("shadow", 1, true) then return "healAbsorbEdge" end
        if name:find("over", 1, true) then return "overHealAbsorb" end
        return "healAbsorb"
    end

    if name:find("absorb", 1, true) then
        -- "overlay" contains "over", so it has to be tested first.
        if name:find("overlay", 1, true) then return "absorbOverlay" end
        if name:find("over", 1, true) then return "overAbsorb" end
        return "absorb"
    end

    if name:find("healpred", 1, true) then
        if name:find("other", 1, true) then return "otherHeal" end
        return "myHeal"
    end

    return nil
end

-- Returns the restored-region role of a region, or nil.
function RestoredRegions:Role(region)
    if not region then return nil end

    local cached = roleCache[region]
    if cached ~= nil then
        return cached or nil
    end

    local role
    local ok, name = pcall(region.GetDebugName, region)
    if ok and type(name) == "string" and name ~= "" then
        role = RoleFromName(name)
    end

    roleCache[region] = role or false
    return role
end

-- True only for the regions we actually want on screen. Everything our sweeps
-- should still hide — including the chrome roles — returns false, so those keep
-- their existing KillRegion/SetAlpha(0) treatment.
function RestoredRegions:IsExempt(region)
    local role = self:Role(region)
    if not role then return false end
    return ROLE_SPEC[role] and true or false
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- Per-owner list of the regions we keep, so Apply() is a short fixed walk
-- rather than a re-scan on every Blizzard update.
local ownerKeep = setmetatable({}, { __mode = "k" })
local registered = setmetatable({}, { __mode = "k" })

local function IsRegionLike(v)
    return type(v) == "table" and type(v.GetObjectType) == "function"
end

local function Note(owner, region, role)
    roleCache[region] = role
    if not ROLE_SPEC[role] then return end

    local keep = ownerKeep[owner]
    if not keep then
        keep = {}
        ownerKeep[owner] = keep
    end
    for i = 1, #keep do
        if keep[i] == region then return end
    end
    keep[#keep + 1] = region
end

-- Seed the role cache for one owner, two ways:
--   1. the known parentKeys, and
--   2. a walk of the owner's regions and children resolving roles from
--      GetDebugName, so a parentKey renamed in 12.1 is still picked up.
-- Safe to call repeatedly; cheap enough for the CheckClassification path.
local function RegisterOwner(owner)
    registered[owner] = true

    for key, role in pairs(KEY_ROLE) do
        local ok, region = pcall(function() return owner[key] end)
        if ok and IsRegionLike(region) then
            Note(owner, region, role)
        end
    end

    local function scan(getter)
        local ok, list = pcall(function() return { getter(owner) } end)
        if not ok then return end
        for i = 1, #list do
            local region = list[i]
            if IsRegionLike(region) then
                local role = RestoredRegions:Role(region)
                if role then Note(owner, region, role) end
            end
        end
    end

    if type(owner.GetRegions) == "function" then scan(owner.GetRegions) end
    if type(owner.GetChildren) == "function" then scan(owner.GetChildren) end
end

function RestoredRegions:Register(...)
    for i = 1, select("#", ...) do
        local owner = select(i, ...)
        if IsRegionLike(owner) then
            RegisterOwner(owner)
        end
    end
end

---------------------------------------------------------------------------
-- Reskin
---------------------------------------------------------------------------

local function ApplySpec(region, role)
    local spec = ROLE_SPEC[role]
    if not spec then return end

    local ok, objType = pcall(region.GetObjectType, region)
    if not ok then return end

    if objType == "StatusBar" then
        if spec.texture then
            pcall(region.SetStatusBarTexture, region, C.BAR_TEXTURE)
        end
        local col = spec.color
        if col then
            pcall(region.SetStatusBarColor, region, col[1], col[2], col[3], col[4])
        end
    elseif region.SetTexture then
        -- Write only. Reading GetTexture() here could hand us a secret number.
        if spec.texture then
            pcall(region.SetTexture, region, C.BAR_TEXTURE)
        end
        local col = spec.color
        if col and region.SetVertexColor then
            pcall(region.SetVertexColor, region, col[1], col[2], col[3], col[4])
        end
    end

    -- Alpha last: this is what un-does a previous sweep's SetAlpha(0), and for
    -- `selection` it is also the only thing holding the wash translucent.
    if spec.alpha and region.SetAlpha then
        pcall(region.SetAlpha, region, spec.alpha)
    end
end

-- Flatten + colour a single region. No-op unless it is one of the roles we keep.
function RestoredRegions:Reskin(region)
    if not region then return end
    local role = self:Role(region)
    if role and ROLE_SPEC[role] then
        ApplySpec(region, role)
    end
end

-- Reskin every kept region belonging to these owners. Called after skinning and
-- from the Blizzard update hooks, so Blizzard swapping a texture back never
-- outlasts one update cycle. Registers first, so an owner that was not skinned
-- through our normal path still resolves.
function RestoredRegions:Apply(...)
    for i = 1, select("#", ...) do
        local owner = select(i, ...)
        if IsRegionLike(owner) then
            if not registered[owner] then RegisterOwner(owner) end
            local keep = ownerKeep[owner]
            if keep then
                for j = 1, #keep do
                    local region = keep[j]
                    ApplySpec(region, roleCache[region])
                end
            end
        end
    end
end
