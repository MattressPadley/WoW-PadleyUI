-- ============================================================================
-- TEMPORARY / THROWAWAY DIAGNOSTIC FILE — DELETE BEFORE SHIPPING
--
-- Purpose (STEP 0 of heal-prediction-restore): enumerate the ACTUAL
-- heal-prediction / absorb parentKeys present at runtime in 12.1, so the skin
-- exempts the real keys rather than guessed ones.
--
-- Slash command: /puipredict            — player + target + first CUF
--                /puipredict 2          — page 2
--                /puipredict cuf        — CompactUnitFrames only
--                /puipredict uf         — PlayerFrame/TargetFrame/FocusFrame only
--
-- READ-ONLY. Never calls SetAlpha/SetPoint/Show/Hide, never hooks anything,
-- never writes a key onto a Blizzard frame. Reads fields, walks regions/
-- children, and prints — plus it reports the role our inference assigns to
-- each region so we can see the exemption logic agree (or not) with reality.
--
-- To revert: delete this file and its line in PadleyUI.toc.
-- ============================================================================

local _, ns = ...

local PAGE_SIZE = 55
local LINE_CAP  = 230

local out = {}
local function Emit(s)
    if #s > LINE_CAP then s = s:sub(1, LINE_CAP - 3) .. "..." end
    out[#out + 1] = s
end

-- ---------------------------------------------------------------------------
-- Safe accessors (a secret value or protected index must never blow us up)
-- ---------------------------------------------------------------------------

local function SafeGet(obj, key)
    local ok, v = pcall(function() return obj[key] end)
    if not ok then return nil, "ERR" end
    if issecretvalue and issecretvalue(v) then return nil, "SECRET" end
    return v
end

local function SafeCall(obj, method, ...)
    local fn = SafeGet(obj, method)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj, ...)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function IsWidget(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return false end
    if issecrettable and type(v) == "table" and issecrettable(v) then return false end
    return type(SafeGet(v, "GetObjectType")) == "function"
end

local function DebugNameOf(obj)
    local n = SafeCall(obj, "GetDebugName")
    if type(n) == "string" and n ~= "" then return n end
    return SafeCall(obj, "GetName") or "<unnamed>"
end

-- ---------------------------------------------------------------------------
-- Candidate parentKeys. Two naming families are known from the Blizzard source
-- history: CompactUnitFrame uses lowerCamel textures on the frame itself, the
-- modern PlayerFrame/TargetFrame use UpperCamel bars on HealthBarsContainer.
-- Probe both on every owner — whichever family 12.1 actually uses will light up.
-- ---------------------------------------------------------------------------

local CANDIDATE_KEYS = {
    -- CompactUnitFrame family
    "myHealPrediction", "otherHealPrediction",
    "totalAbsorb", "totalAbsorbOverlay",
    "myHealAbsorb", "myHealAbsorbLeftShadow", "myHealAbsorbRightShadow",
    "overAbsorbGlow", "overHealAbsorbGlow",
    -- Modern unit frame family
    "MyHealPredictionBar", "OtherHealPredictionBar",
    "TotalAbsorbBar", "TotalAbsorbBarOverlay",
    "OverAbsorbGlow", "HealAbsorbBar", "OverHealAbsorbGlow",
    -- Things that live alongside them and must NOT be exempted by accident
    "HealthBar", "healthBar", "AnimatedLossBar", "HealthBarMask",
    "TiledFillOverlay", "HealthBarsContainer",
}

local function DescribeRegion(obj, label, indent)
    local ot    = SafeCall(obj, "GetObjectType") or "?"
    local shown = SafeCall(obj, "IsShown")
    local alpha = SafeCall(obj, "GetAlpha")
    local role  = ns.HealPrediction and ns.HealPrediction:Role(obj) or nil
    local exempt = ns.HealPrediction and ns.HealPrediction:IsExempt(obj)
    local masks = SafeCall(obj, "GetMaskTextures")

    Emit(string.format("%s%s <%s> shown=%s alpha=%s role=%s exempt=%s",
        indent, label, ot, tostring(shown), tostring(alpha),
        tostring(role or "-"), tostring(exempt and true or false)))
    Emit(string.format("%s    debugName=%s%s", indent, DebugNameOf(obj),
        (masks ~= nil) and "  hasMask=yes" or ""))
end

-- ---------------------------------------------------------------------------
-- Owner dump: named-field probe + full region/child enumeration
-- ---------------------------------------------------------------------------

local function DumpOwner(owner, label)
    if not IsWidget(owner) then
        Emit("-- " .. label .. ": MISSING")
        return
    end

    Emit("")
    Emit("== " .. label .. " == <" .. (SafeCall(owner, "GetObjectType") or "?") ..
         "> " .. DebugNameOf(owner))

    -- 1. Named fields.
    local hits = 0
    for _, key in ipairs(CANDIDATE_KEYS) do
        local v, err = SafeGet(owner, key)
        if err then
            Emit("  ." .. key .. " -> <" .. err .. ">")
            hits = hits + 1
        elseif v ~= nil then
            hits = hits + 1
            if IsWidget(v) then
                DescribeRegion(v, "  ." .. key, "")
            else
                Emit("  ." .. key .. " -> " .. type(v))
            end
        end
    end
    if hits == 0 then Emit("  (no candidate keys on this owner)") end

    -- 2. Every texture region, so a key we never guessed still shows up.
    Emit("  -- regions --")
    local n = SafeCall(owner, "GetNumRegions") or 0
    local regs = { pcall(owner.GetRegions, owner) }
    local okRegs = table.remove(regs, 1)
    if okRegs then
        for i = 1, math.min(n, 24) do
            local r = regs[i]
            if IsWidget(r) then
                DescribeRegion(r, "  region#" .. i, "")
            end
        end
    else
        Emit("  (GetRegions failed)")
    end

    -- 3. Every child frame (absorb bars are StatusBars in some layouts).
    Emit("  -- children --")
    local kids = { pcall(owner.GetChildren, owner) }
    local okKids = table.remove(kids, 1)
    if okKids then
        local shown = 0
        for i = 1, math.min(#kids, 20) do
            local c = kids[i]
            if IsWidget(c) then
                shown = shown + 1
                DescribeRegion(c, "  child#" .. i, "")
            end
        end
        if shown == 0 then Emit("  (no children)") end
    else
        Emit("  (GetChildren failed)")
    end
end

-- ---------------------------------------------------------------------------
-- Hook-target surface: which global update function exists to re-apply on
-- ---------------------------------------------------------------------------

local function DumpGlobals()
    Emit("== UPDATE-FUNCTION SURFACE (hook targets) ==")
    for _, g in ipairs({
        "CompactUnitFrame_UpdateHealPrediction",
        "CompactUnitFrame_UtilSetHealPrediction",
        "UnitFrameHealPredictionBars_Update",
        "UnitFrameHealPredictionBars_UpdateMax",
        "UnitFrameUtil_UpdateFillBar",
        "UnitFrameHealPredictionBarsMixin",
        "CompactUnitFrame_UpdateAll",
    }) do
        Emit("  " .. g .. ": " .. type(_G[g]))
    end
    Emit("  restrictions active: " .. tostring(
        C_Secrets and C_Secrets.HasSecretRestrictions
        and C_Secrets.HasSecretRestrictions() or "n/a"))
end

-- ---------------------------------------------------------------------------
-- Owner resolution
-- ---------------------------------------------------------------------------

local function HealthBarsContainerOf(frame)
    if not IsWidget(frame) then return nil end
    local content = SafeGet(frame, "PlayerFrameContent") or SafeGet(frame, "TargetFrameContent")
    local main = IsWidget(content)
        and (SafeGet(content, "PlayerFrameContentMain") or SafeGet(content, "TargetFrameContentMain"))
        or nil
    local hbc = IsWidget(main) and SafeGet(main, "HealthBarsContainer") or nil
    return hbc, main
end

local function FirstCompactFrame()
    for _, name in ipairs({
        "CompactPartyFrameMember1", "CompactRaidFrame1",
        "CompactPartyFrameMember2", "CompactRaidGroup1Member1",
    }) do
        local f = _G[name]
        if IsWidget(f) then return f, name end
    end
    -- Fall back to walking CompactPartyFrame's children.
    local parent = _G.CompactPartyFrame or _G.CompactRaidFrameContainer
    if IsWidget(parent) then
        local kids = { pcall(parent.GetChildren, parent) }
        if table.remove(kids, 1) then
            for _, c in ipairs(kids) do
                if IsWidget(c) and SafeGet(c, "healthBar") ~= nil then
                    return c, DebugNameOf(c)
                end
            end
        end
    end
    return nil
end

local function BuildReport(mode)
    out = {}
    Emit("=== PadleyUI heal-prediction / absorb probe (12.1) ===")
    DumpGlobals()

    if mode ~= "cuf" then
        for _, spec in ipairs({
            { _G.PlayerFrame, "PlayerFrame" },
            { _G.TargetFrame, "TargetFrame" },
            { _G.FocusFrame,  "FocusFrame"  },
        }) do
            local frame, label = spec[1], spec[2]
            if IsWidget(frame) then
                local hbc, main = HealthBarsContainerOf(frame)
                DumpOwner(hbc, label .. ".HealthBarsContainer")
                local hb = IsWidget(hbc) and SafeGet(hbc, "HealthBar") or nil
                DumpOwner(hb, label .. ".HealthBarsContainer.HealthBar")
                if mode == "uf" then DumpOwner(main, label .. " ContentMain") end
            else
                Emit("-- " .. label .. ": not loaded")
            end
        end
    end

    if mode ~= "uf" then
        local cuf, cufName = FirstCompactFrame()
        if IsWidget(cuf) then
            DumpOwner(cuf, "CUF " .. tostring(cufName))
            DumpOwner(SafeGet(cuf, "healthBar"), "CUF " .. tostring(cufName) .. ".healthBar")
        else
            Emit("")
            Emit("-- No CompactUnitFrame found. Join a party/raid (or enable raid-style")
            Emit("   party frames) and re-run /puipredict cuf.")
        end
    end

    Emit("=== end (" .. #out .. " lines) ===")
end

local function Run(page, mode)
    BuildReport(mode)

    local total = #out
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    page = math.min(math.max(page or 1, 1), pages)
    local first = (page - 1) * PAGE_SIZE + 1
    local last  = math.min(first + PAGE_SIZE - 1, total)

    print("|cff66ccffPUIPREDICT|r page " .. page .. "/" .. pages ..
          " (lines " .. first .. "-" .. last .. " of " .. total .. ")")
    for i = first, last do print(out[i]) end
    if page < pages then
        print("|cff66ccffPUIPREDICT|r more: /puipredict " ..
              ((mode and mode ~= "") and (mode .. " ") or "") .. (page + 1))
    end
end

SLASH_PUIPREDICT1 = "/puipredict"
SlashCmdList["PUIPREDICT"] = function(msg)
    msg = (msg or ""):lower()
    local page = tonumber(msg:match("%d+"))
    local mode = msg:find("cuf", 1, true) and "cuf"
        or (msg:find("uf", 1, true) and "uf" or nil)
    local ok, err = pcall(Run, page, mode)
    if not ok then
        print("|cffff5555PUIPREDICT error:|r " .. tostring(err))
    end
end
