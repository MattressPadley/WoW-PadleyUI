local _, ns = ...

local C = ns.C

-- ===========================================================================
-- Heal prediction / absorb exemption + reskin
--
-- We do NOT rebuild these bars. Blizzard renders and positions them with the
-- real (untainted) numbers; this module only decides which of its regions our
-- blanket "hide everything decorative" sweeps must skip, and flattens the
-- texture + colour of the ones we keep.
--
-- Hard rules, all of them taint rules:
--   * Never read a heal/absorb amount. UnitGetIncomingHeals,
--     UnitGetTotalAbsorbs, UnitGetTotalHealAbsorbs and
--     UnitGetDetailedHealPrediction all return secret values in combat /
--     encounters / keys / arena, and any arithmetic or comparison on a secret
--     throws. Geometry stays Blizzard's.
--   * Never SetPoint / SetSize / SetWidth / SetHeight on these regions.
--   * Never read back GetTexture() on them either — it can return a secret
--     number, and comparing that throws. We always just write.
--   * Texture and colour writes on Blizzard textures are safe, so that is the
--     entire extent of what we do here.
-- ===========================================================================

local HealPrediction = {}
ns.HealPrediction = HealPrediction

-- Role -> flat colour, or false meaning "pure chrome, leave it suppressed".
-- The four data-bearing bars are restored; the glow/shadow art stays hidden,
-- both because it carries no information and because the glows deliberately
-- overhang the bar edge (they rely on Blizzard's mask, which our flat-bar
-- mask stripping removes).
local ROLE_COLOR = {
    myHeal         = { 0.15, 0.80, 0.35, 0.45 },  -- your incoming heal
    otherHeal      = { 0.20, 0.60, 0.55, 0.35 },  -- everyone else's incoming heal
    absorb         = { 0.70, 0.80, 1.00, 0.40 },  -- damage absorb shield
    healAbsorb     = { 0.65, 0.12, 0.12, 0.50 },  -- heal absorb (necrotic etc.)
    absorbOverlay  = false,                        -- striped art over the absorb
    overAbsorb     = false,                        -- glow, overhangs the bar
    overHealAbsorb = false,                        -- glow, overhangs the bar
    healAbsorbEdge = false,                        -- gradient shadow art
}

-- Known parentKeys, both naming families. CompactUnitFrame uses lowerCamel
-- textures on the frame itself; the modern PlayerFrame/TargetFrame use
-- UpperCamel bars on HealthBarsContainer. Probing both on every owner is
-- harmless and means either family is picked up. /puipredict dumps what the
-- live client actually has.
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

-- Returns the prediction/absorb role of a region, or nil.
function HealPrediction:Role(region)
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
function HealPrediction:IsExempt(region)
    local role = self:Role(region)
    return role ~= nil and ROLE_COLOR[role] ~= false and ROLE_COLOR[role] ~= nil
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
    if not ROLE_COLOR[role] then return end

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
                local role = HealPrediction:Role(region)
                if role then Note(owner, region, role) end
            end
        end
    end

    if type(owner.GetRegions) == "function" then scan(owner.GetRegions) end
    if type(owner.GetChildren) == "function" then scan(owner.GetChildren) end
end

function HealPrediction:Register(...)
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

local function ApplyColor(region, role)
    local col = ROLE_COLOR[role]
    if not col then return end

    local ok, objType = pcall(region.GetObjectType, region)
    if not ok then return end

    if objType == "StatusBar" then
        pcall(region.SetStatusBarTexture, region, C.BAR_TEXTURE)
        pcall(region.SetStatusBarColor, region, col[1], col[2], col[3], col[4])
    elseif region.SetTexture then
        -- Write only. Reading GetTexture() here could hand us a secret number.
        pcall(region.SetTexture, region, C.BAR_TEXTURE)
        if region.SetVertexColor then
            pcall(region.SetVertexColor, region, col[1], col[2], col[3], col[4])
        end
    end
end

-- Flatten + colour a single region. No-op unless it is one of the roles we keep.
function HealPrediction:Reskin(region)
    if not region then return end
    local role = self:Role(region)
    if role and ROLE_COLOR[role] then
        ApplyColor(region, role)
    end
end

-- Reskin every kept prediction/absorb region belonging to these owners. Called
-- after skinning and from the Blizzard update hooks, so Blizzard swapping a
-- texture back never outlasts one update cycle. Registers first, so an owner
-- that was not skinned through our normal path still resolves.
function HealPrediction:Apply(...)
    for i = 1, select("#", ...) do
        local owner = select(i, ...)
        if IsRegionLike(owner) then
            if not registered[owner] then RegisterOwner(owner) end
            local keep = ownerKeep[owner]
            if keep then
                for j = 1, #keep do
                    local region = keep[j]
                    ApplyColor(region, roleCache[region])
                end
            end
        end
    end
end
