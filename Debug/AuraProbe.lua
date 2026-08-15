-- ============================================================================
-- TEMPORARY / THROWAWAY DIAGNOSTIC FILE — DELETE BEFORE SHIPPING
--
-- Purpose: answer the open question in the nameplate-aura-container spec —
-- in WoW 12.1, what/where is the nameplate aura display object, and does it
-- expose an attachable AuraContainer (AddAuraGroup) and/or an initializeFrame
-- hook we can register a skinning callback on?
--
-- Slash command: /puiprobe  (page 2+: /puiprobe 2)
--   /puiprobe cast  — cast bar identity dump for nameplate-castbar-reskin
--                     (which object is Blizzard's nameplate cast bar?)
--
-- READ-ONLY. This file must never call SetAlpha/SetPoint/Show/Hide, never hook
-- anything, never reparent, and never write a key onto a Blizzard frame.
-- It only reads fields, walks the frame tree, and prints.
--
-- To revert: delete this file and its line in PadleyUI.toc.
-- ============================================================================

local _ = ...

local MAX_DEPTH     = 4
local PAGE_SIZE     = 55
local MAX_CHILDREN  = 14   -- per node, so a big container can't flood us
local MAX_REGIONS   = 10
local LINE_CAP      = 230  -- chat cuts off at 255

-- Method-name keywords we care about on a node's metatable __index chain.
local KEYWORDS = { "aura", "group", "slot", "container", "init" }

-- Field names to probe directly (hierarchy children aren't enough — the real
-- container may only exist as a named field). Includes every nameplate field
-- Skins/Nameplates.lua already references.
local FIELD_NAMES = {
    "UnitFrame", "AurasFrame", "BuffFrame", "AuraContainer", "BuffContainer",
    "DebuffFrame", "DebuffContainer", "AuraFrame", "Auras", "AuraGroup",
    "AuraGroups", "auras", "aurasFrame", "buffFrame", "auraContainer",
    "Container", "Content", "driverFrame",
    -- referenced by our own Nameplates.lua:
    "healthBar", "castBar", "ClassificationFrame", "LevelFrame",
    "selectionHighlight", "aggroHighlight", "name", "statusText",
}

-- ---------------------------------------------------------------------------
-- Safe accessors (never let a secret value or a protected index blow us up)
-- ---------------------------------------------------------------------------

local function SafeGet(obj, key)
    local ok, v = pcall(function() return obj[key] end)
    if not ok then return nil, "ERR" end
    if issecretvalue and issecretvalue(v) then return nil, "SECRET" end
    return v
end

local function SafeCall(obj, method)
    local fn = SafeGet(obj, method)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function IsWidget(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return false end
    if issecrettable and type(v) == "table" and issecrettable(v) then return false end
    return type(SafeGet(v, "GetObjectType")) == "function"
end

-- ---------------------------------------------------------------------------
-- Metatable __index method surface
-- ---------------------------------------------------------------------------

local function CollectMethods(obj)
    local names, seen = {}, {}
    local ok, mt = pcall(getmetatable, obj)
    if not ok then return names end
    local level = 0
    while type(mt) == "table" and level < 6 do
        local idx = rawget(mt, "__index")
        if type(idx) ~= "table" then break end
        local okIter = pcall(function()
            for k, v in pairs(idx) do
                if type(k) == "string" and type(v) == "function" and not seen[k] then
                    seen[k] = true
                    names[#names + 1] = k
                end
            end
        end)
        if not okIter then break end
        local okMT, nextMT = pcall(getmetatable, idx)
        if not okMT then break end
        mt = nextMT
        level = level + 1
    end
    table.sort(names)
    return names
end

local function InterestingMethods(methodNames)
    local hits = {}
    for _, n in ipairs(methodNames) do
        local low = n:lower()
        for _, kw in ipairs(KEYWORDS) do
            if low:find(kw, 1, true) then
                hits[#hits + 1] = n
                break
            end
        end
    end
    return hits
end

-- ---------------------------------------------------------------------------
-- Output buffer
-- ---------------------------------------------------------------------------

local out = {}
local function Emit(s)
    if #s > LINE_CAP then s = s:sub(1, LINE_CAP - 3) .. "..." end
    out[#out + 1] = s
end

local function Chunk(prefix, list, perLine)
    local i = 1
    while i <= #list do
        local slice = {}
        for j = i, math.min(i + perLine - 1, #list) do
            slice[#slice + 1] = list[j]
        end
        Emit(prefix .. table.concat(slice, " "))
        i = i + perLine
    end
end

-- ---------------------------------------------------------------------------
-- Node description
-- ---------------------------------------------------------------------------

local INIT_KEYS = {
    "initializeFrame", "InitializeFrame", "SetInitializeFrame",
    "initializerFunction", "initFunction", "OnInitializeFrame",
    "SetInitializeFrameCallback", "RegisterInitializeFrame",
}

local function Describe(node, label, depth)
    local indent = string.rep("  ", depth)
    local objType = SafeCall(node, "GetObjectType") or "?"
    local frameName = SafeCall(node, "GetName") or "?"

    local flags = {}
    local hasAG = type(SafeGet(node, "AddAuraGroup")) == "function"
    if hasAG then flags[#flags + 1] = "AG" end

    for _, k in ipairs(INIT_KEYS) do
        local v = SafeGet(node, k)
        if v ~= nil then
            flags[#flags + 1] = "INIT:" .. k
            break
        end
    end

    local methods = CollectMethods(node)
    local hits = InterestingMethods(methods)

    local flagStr = (#flags > 0) and (" FLAGS:" .. table.concat(flags, ",")) or ""
    Emit(string.format("%s[%d] %s <%s> %s%s", indent, depth, label, objType, frameName, flagStr))

    if #hits > 0 then
        Chunk(indent .. "   m: ", hits, 6)
    end

    -- Full method surface for anything that looks like the real container.
    if hasAG then
        Emit(indent .. "   *** FULL METHOD SURFACE (" .. #methods .. ") ***")
        Chunk(indent .. "   > ", methods, 5)
    end

    return hasAG
end

-- ---------------------------------------------------------------------------
-- Recursive walk
-- ---------------------------------------------------------------------------

local visited

local function Walk(node, label, depth)
    if depth > MAX_DEPTH or not IsWidget(node) then return end
    if visited[node] then
        Emit(string.rep("  ", depth) .. "[" .. depth .. "] " .. label .. " (already seen)")
        return
    end
    visited[node] = true

    Describe(node, label, depth)
    if depth == MAX_DEPTH then return end

    local kids = {}
    local getKids = SafeGet(node, "GetChildren")
    if type(getKids) == "function" then
        local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(getKids, node)
        if ok then
            kids = { a, b, c, d, e, f, g, h, i, j, k, l, m, n }
        end
    end

    local shown = 0
    for idx = 1, MAX_CHILDREN do
        local child = kids[idx]
        if IsWidget(child) then
            shown = shown + 1
            Walk(child, "child#" .. idx, depth + 1)
        end
    end
    if shown == 0 then
        Emit(string.rep("  ", depth + 1) .. "(no children)")
    end

    -- Regions (textures/fontstrings) — shallow, just to see naming.
    local getRegions = SafeGet(node, "GetRegions")
    if type(getRegions) == "function" and depth < MAX_DEPTH - 1 then
        local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = pcall(getRegions, node)
        if ok then
            local regs = { r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 }
            for idx = 1, MAX_REGIONS do
                local r = regs[idx]
                if IsWidget(r) then
                    local rt = SafeCall(r, "GetObjectType") or "?"
                    local rn = SafeCall(r, "GetName") or "?"
                    Emit(string.format("%s[%d] region#%d <%s> %s",
                        string.rep("  ", depth + 1), depth + 1, idx, rt, rn))
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Field probe (named fields, not hierarchy)
-- ---------------------------------------------------------------------------

local function ProbeFields(obj, objLabel)
    Emit("== FIELD PROBE on " .. objLabel .. " ==")
    local found = 0
    for _, key in ipairs(FIELD_NAMES) do
        local v, err = SafeGet(obj, key)
        if err then
            Emit("  ." .. key .. " -> <" .. err .. ">")
            found = found + 1
        elseif v ~= nil then
            found = found + 1
            if IsWidget(v) then
                local t = SafeCall(v, "GetObjectType") or "?"
                local n = SafeCall(v, "GetName") or "?"
                local ag = (type(SafeGet(v, "AddAuraGroup")) == "function") and " **AG**" or ""
                Emit(string.format("  .%s -> <%s> %s%s", key, t, n, ag))
            else
                Emit("  ." .. key .. " -> " .. type(v))
            end
        end
    end
    if found == 0 then Emit("  (no fields matched)") end
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

local function BuildReport()
    out = {}
    visited = {}

    Emit("=== PadleyUI aura probe (12.1) ===")
    Emit("restrictions active: " .. tostring(
        C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() or "n/a"))

    local base
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        base = C_NamePlate.GetNamePlateForUnit("target")
    end
    if not base and C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates and plates[1] then
            base = plates[1]
            Emit("(no target nameplate — using first visible nameplate)")
        end
    end
    if not base then
        Emit("NO NAMEPLATE FOUND. Target an enemy mob with a visible nameplate and retry.")
        return
    end

    Emit("base: " .. (SafeCall(base, "GetName") or "?") ..
         " <" .. (SafeCall(base, "GetObjectType") or "?") .. ">")

    -- 1. Named-field probe on the base and on its UnitFrame.
    ProbeFields(base, "base nameplate")

    local uf = SafeGet(base, "UnitFrame")
    if IsWidget(uf) then
        ProbeFields(uf, "base.UnitFrame")
    end

    -- 2. Globals worth a look.
    Emit("== GLOBALS ==")
    for _, g in ipairs({ "NamePlateDriverFrame", "NamePlateBaseMixin", "NameplateBuffContainerMixin" }) do
        local v = _G[g]
        if v ~= nil then
            local extra = IsWidget(v) and (" <" .. (SafeCall(v, "GetObjectType") or "?") .. ">") or (" " .. type(v))
            Emit("  " .. g .. extra)
        end
    end

    -- 3. Recursive tree walk.
    Emit("== TREE WALK (depth " .. MAX_DEPTH .. ") ==")
    Walk(base, "base", 0)

    -- 4. Also walk any named aura-ish field that the tree walk may not reach
    --    (a container parented elsewhere still shows up as a field).
    for _, key in ipairs({ "AurasFrame", "BuffFrame", "AuraContainer", "BuffContainer" }) do
        for _, owner in ipairs({ base, uf }) do
            if IsWidget(owner) then
                local v = SafeGet(owner, key)
                if IsWidget(v) and not visited[v] then
                    Emit("== EXTRA WALK: ." .. key .. " ==")
                    Walk(v, "." .. key, 0)
                end
            end
        end
    end

    Emit("=== end (" .. #out .. " lines) ===")
end

-- ---------------------------------------------------------------------------
-- Cast bar identity probe (/puiprobe cast)
--
-- Answers the nameplate-castbar-reskin open question: which object is
-- Blizzard's nameplate cast bar, and what does it own? Still READ-ONLY.
-- ---------------------------------------------------------------------------

local function DescribeCastRegions(node, indent)
    local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(node.GetRegions, node)
    if not ok then return end
    local regs = { a, b, c, d, e, f, g, h, i, j, k, l }
    for idx = 1, 12 do
        local r = regs[idx]
        if IsWidget(r) then
            local rt = SafeCall(r, "GetObjectType") or "?"
            local atlas = SafeCall(r, "GetAtlas")
            local tex = SafeCall(r, "GetTexture")
            local kind = atlas and ("atlas:" .. tostring(atlas))
                or (tex ~= nil and ("tex:" .. type(tex)) or "tex:none/secret")
            Emit(string.format("%sregion#%d <%s> %s", indent, idx, rt,
                (rt == "FontString") and "(fontstring)" or kind))
        end
    end
end

local function BuildCastReport()
    out = {}
    visited = {}

    Emit("=== PadleyUI cast bar probe (12.1) ===")
    Emit("restrictions active: " .. tostring(
        C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() or "n/a"))

    local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit("target")
    if not base and C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates and plates[1] then
            base = plates[1]
            Emit("(no target nameplate — using first visible nameplate)")
        end
    end
    if not base then
        Emit("NO NAMEPLATE FOUND. Target a caster mob mid-cast and retry.")
        return
    end

    local uf = SafeGet(base, "UnitFrame")
    if not IsWidget(uf) then
        Emit("base has no .UnitFrame")
        return
    end

    local cb = SafeGet(uf, "castBar")
    if not IsWidget(cb) then
        Emit(".castBar -> " .. tostring(cb) .. "  <-- NOT a widget; reskin will report this")
    else
        Emit(".castBar <" .. (SafeCall(cb, "GetObjectType") or "?") .. "> " ..
             (SafeCall(cb, "GetName") or "?"))
        local parent = SafeCall(cb, "GetParent")
        Emit("  parent: " .. (IsWidget(parent)
            and ((SafeCall(parent, "GetName") or "?") .. " <" ..
                 (SafeCall(parent, "GetObjectType") or "?") .. ">")
            or "?") .. "   (same as UnitFrame: " .. tostring(parent == uf) .. ")")
        Emit("  shown: " .. tostring(SafeCall(cb, "IsShown")) ..
             "  visible: " .. tostring(SafeCall(cb, "IsVisible")) ..
             "  level: " .. tostring(SafeCall(cb, "GetFrameLevel")))
        Emit("  fill: " .. tostring(SafeCall(cb, "GetStatusBarTexture") ~= nil) ..
             "  .Icon: " .. tostring(IsWidget(SafeGet(cb, "Icon"))) ..
             "  .Text: " .. tostring(IsWidget(SafeGet(cb, "Text"))) ..
             "  .BorderShield: " .. tostring(IsWidget(SafeGet(cb, "BorderShield"))))
        Emit("  regions:")
        DescribeCastRegions(cb, "    ")
        Emit("  children:")
        Walk(cb, ".castBar", 1)
    end

    -- Cross-check: every StatusBar under the plate, so a wrapper shape shows up.
    Emit("== TREE WALK (StatusBar cross-check) ==")
    visited = {}
    Walk(base, "base", 0)

    Emit("=== end (" .. #out .. " lines) ===")
end

local function Run(page, mode)
    if mode == "cast" then
        BuildCastReport()
    else
        BuildReport()
    end

    local total = #out
    local pages = math.max(1, math.ceil(total / PAGE_SIZE))
    page = math.min(math.max(page or 1, 1), pages)

    local first = (page - 1) * PAGE_SIZE + 1
    local last  = math.min(first + PAGE_SIZE - 1, total)

    print("|cff66ccffPUIPROBE|r page " .. page .. "/" .. pages ..
          " (lines " .. first .. "-" .. last .. " of " .. total .. ")")
    for i = first, last do
        print(out[i])
    end
    if page < pages then
        print("|cff66ccffPUIPROBE|r more: /puiprobe " ..
              ((mode == "cast") and "cast " or "") .. (page + 1))
    end
end

SLASH_PUIPROBE1 = "/puiprobe"
SlashCmdList["PUIPROBE"] = function(msg)
    msg = msg or ""
    local page = tonumber(msg:match("%d+"))
    local mode = msg:lower():find("cast", 1, true) and "cast" or nil
    local ok, err = pcall(Run, page, mode)
    if not ok then
        print("|cffff5555PUIPROBE error:|r " .. tostring(err))
    end
end
