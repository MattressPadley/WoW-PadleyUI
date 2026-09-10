local _, ns = ...

local C = ns.C
local SE = ns.SkinEngine
local HP = ns.HealPrediction

local PartyFrameSkin = {}
ns.PartyFrameSkin = PartyFrameSkin

-- External tracking tables (never write keys to Blizzard frames)
local skinnedFrames = {}
local hookedBars = {}
local barBackdrops = {}
local skinnedAuras = {}

-- Guard against recursive hook calls
local settingTexture = {}
local settingColor = {}

-- Spacing re-anchor state. CompactRaidFrame*/CompactPartyFrameMember* are
-- PROTECTED frames — re-anchoring them in combat raises ADDON_ACTION_BLOCKED,
-- so we queue the re-anchor and flush it on PLAYER_REGEN_ENABLED.
-- appliedOffsets records both the offset we wrote and the Blizzard offset we
-- derived it from, so a repeat pass can tell its own output apart from a fresh
-- Blizzard layout and stay idempotent.
local appliedOffsets = {}
local spacingPending = false
local spacingScheduled = false

---------------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------------

local function GetClassColor(unit)
    if not unit or not UnitExists(unit) then return 0.5, 0.5, 0.5 end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                return color.r, color.g, color.b
            end
        end
    end
    -- Fallback: reaction color for NPCs (pets, etc.)
    local r, g, b = UnitSelectionColor(unit)
    if r then return r, g, b end
    return 0.5, 0.5, 0.5
end

local function GetPowerColor(unit)
    if not unit or not UnitExists(unit) then return 0.0, 0.0, 1.0 end
    local _, powerToken = UnitPowerType(unit)
    local color = PowerBarColor[powerToken]
    if color then
        return color.r, color.g, color.b
    end
    return 0.0, 0.0, 1.0
end

local function CreateBarBackdrop(bar)
    -- Plain frame + SetColorTexture instead of BackdropTemplate to avoid
    -- secret-value taint (BackdropTemplate's SetupTextureCoordinates calls
    -- GetWidth() which returns a secret number on secure-parented frames).
    local bd = CreateFrame("Frame", nil, bar)
    bd:SetAllPoints()
    bd:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    local tex = bd:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
    return bd
end

-- Blizzard's own setup (DefaultCompactUnitFrameSetup / DefaultCompactMiniFrameSetup)
-- ends with `healthBar:GetStatusBarTexture():SetDrawLayer("BORDER")` — the fill is
-- deliberately BELOW the frame's ARTWORK regions (roleIcon) and below the
-- BORDER/5 heal-prediction + absorb textures.
--
-- SetStatusBarTexture(path) allocates a BRAND NEW texture object, and a fresh
-- statusbar texture defaults to the StatusBar's drawLayer, i.e. ARTWORK/0. So
-- every time we (or Blizzard) re-skin the bar, the fill silently jumps above the
-- role icon and the absorb art and covers them until health drops. Blizzard only
-- re-pins the layer in the one-shot setup call, never in UpdateAll, so it never
-- recovers on its own. Re-pin it ourselves after every texture swap.
local function RestoreFillDrawLayer(bar)
    if not bar or not bar.GetStatusBarTexture then return end
    local tex = bar:GetStatusBarTexture()
    if tex and tex.SetDrawLayer then
        tex:SetDrawLayer("BORDER")
    end
end

local function EnforceFlatTexture(bar)
    if settingTexture[bar] then return end
    local tex = bar:GetStatusBarTexture()
    if tex and tex:GetTexture() ~= C.BAR_TEXTURE then
        settingTexture[bar] = true
        bar:SetStatusBarTexture(C.BAR_TEXTURE)
        settingTexture[bar] = nil
    end
    RestoreFillDrawLayer(bar)
end

-- Raise the icons Blizzard draws on the frame itself above the health bar fill.
-- roleIcon lives on the frame's ARTWORK/0 layer, the same layer a freshly
-- allocated fill texture lands on, and loses the tie because it was created
-- first. OVERLAY/7 puts it unambiguously on top regardless of what the bar does.
-- readyCheckIcon (frameLevel 120) and centerStatusIcon (frameLevel 110) are real
-- child Frames, already above the bar.
--
-- Confirmed against the 12.1 client source: CompactUnitFrameTemplate has NO raid
-- target marker region and NO leader / assistant / master-looter icon of its own,
-- on party OR raid layouts. The only regions on the template are background, the
-- heal-prediction/absorb set, name, statusText, roleIcon, aggroHighlight and
-- selectionHighlight; the only child frames are healthBar, TempMaxHealthLoss,
-- powerBar, centerStatusIcon, readyCheckIcon and pingIconFrame. Main tank /
-- main assist ride on roleIcon (atlases RaidFrame-Icon-MainTank /
-- RaidFrame-Icon-MainAssist), which is already preserved; raid target markers
-- ride on nameplates and the target frame. So there is nothing for the sweep to
-- have hidden and nothing to add to the preserve set.
--
-- Layer-only writes: no geometry, no anchors, no reads — taint-safe.
local function RaiseFrameIcons(frame)
    if frame.roleIcon and frame.roleIcon.SetDrawLayer then
        frame.roleIcon:SetDrawLayer("OVERLAY", 7)
    end
end

local function RemoveMasksFromTexture(tex)
    if not tex or not tex.RemoveMaskTexture or not tex.GetMaskTextures then return end
    local masks = { tex:GetMaskTextures() }
    for _, mask in ipairs(masks) do
        tex:RemoveMaskTexture(mask)
        mask:Hide()
    end
end

local function RemoveBarMasks(bar)
    if not bar then return end
    if bar.GetStatusBarTexture then
        RemoveMasksFromTexture(bar:GetStatusBarTexture())
    end
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and (region:GetObjectType() == "Texture" or region:GetObjectType() == "MaskTexture") then
            RemoveMasksFromTexture(region)
        end
    end
end

---------------------------------------------------------------------------
-- Skin Health Bar
---------------------------------------------------------------------------

local function SkinHealthBar(frame)
    local bar = frame.healthBar
    if not bar then return end

    SE:SkinStatusBar(bar)
    RestoreFillDrawLayer(bar)
    RemoveBarMasks(bar)

    -- Blizzard owns the geometry of the heal-prediction/absorb regions; we only
    -- need their identities here so the sweep below leaves them alone.
    HP:Register(frame, bar)

    -- Alpha-zero all non-fill texture regions
    local fillTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex
            and not HP:IsExempt(region) then
            region:SetAlpha(0)
        end
    end

    -- Backdrop behind bar
    if not barBackdrops[bar] then
        barBackdrops[bar] = CreateBarBackdrop(bar)
    end

    -- Apply class color
    local unit = frame.unit
    if unit and UnitExists(unit) then
        local r, g, b = GetClassColor(unit)
        settingColor[bar] = true
        bar:SetStatusBarColor(r, g, b)
        settingColor[bar] = nil
    end

    -- Hook for enforcement
    if not hookedBars[bar] then
        hookedBars[bar] = true

        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            -- Runs on OUR swap too (EnforceFlatTexture early-returns under the
            -- recursion guard), which is exactly when the new texture needs
            -- re-pinning to BORDER.
            EnforceFlatTexture(self)
            RestoreFillDrawLayer(self)
        end)

        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            local u = frame.unit
            if u and UnitExists(u) then
                local r, g, b = GetClassColor(u)
                settingColor[self] = true
                self:SetStatusBarColor(r, g, b)
                settingColor[self] = nil
            end
        end)

        hooksecurefunc(bar, "SetValue", function(self)
            EnforceFlatTexture(self)
        end)
    end
end

---------------------------------------------------------------------------
-- Skin Power Bar
---------------------------------------------------------------------------

local function SkinPowerBar(frame)
    local bar = frame.powerBar
    if not bar then return end

    SE:SkinStatusBar(bar)
    RestoreFillDrawLayer(bar)
    RemoveBarMasks(bar)

    -- Alpha-zero all non-fill texture regions
    local fillTex = bar:GetStatusBarTexture()
    for i = 1, bar:GetNumRegions() do
        local region = select(i, bar:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= fillTex then
            region:SetAlpha(0)
        end
    end

    -- Backdrop behind bar
    if not barBackdrops[bar] then
        barBackdrops[bar] = CreateBarBackdrop(bar)
    end

    -- Apply power color
    local unit = frame.unit
    if unit and UnitExists(unit) then
        local r, g, b = GetPowerColor(unit)
        settingColor[bar] = true
        bar:SetStatusBarColor(r, g, b)
        settingColor[bar] = nil
    end

    -- Hook for enforcement
    if not hookedBars[bar] then
        hookedBars[bar] = true

        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            EnforceFlatTexture(self)
            RestoreFillDrawLayer(self)
        end)

        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if settingColor[self] then return end
            local u = frame.unit
            if u and UnitExists(u) then
                local r, g, b = GetPowerColor(u)
                settingColor[self] = true
                self:SetStatusBarColor(r, g, b)
                settingColor[self] = nil
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Strip Chrome / Decorative Elements
---------------------------------------------------------------------------

local function StripChrome(frame)
    -- Alpha-zero the frame background. Pure chrome, no information on it.
    if frame.background then frame.background:SetAlpha(0) end

    -- Game-data regions are deliberately NOT hidden any more. Blizzard draws,
    -- sizes, shows/hides and (for threat) colours these with the real values,
    -- which are secret to us in combat; we only flatten texture/colour/alpha.
    -- The registry covers heal prediction, absorbs, aggroHighlight (threat) and
    -- selectionHighlight (your current target). See Core/RestoredRegions.lua.
    --
    -- Registration MUST happen before the sweep below: it is what seeds the role
    -- cache that IsExempt() consults, and StripChrome re-runs on every
    -- CompactUnitFrame_UpdateAll.
    HP:Register(frame, frame.healthBar)

    -- Strip all decorative texture regions, but preserve icons Blizzard manages
    local preserve = {}
    if frame.roleIcon then preserve[frame.roleIcon] = true end
    if frame.readyCheckIcon then preserve[frame.readyCheckIcon] = true end
    if frame.centerStatusIcon then preserve[frame.centerStatusIcon] = true end

    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:GetObjectType() == "Texture" and not preserve[region]
            and not HP:IsExempt(region) then
            region:SetAlpha(0)
        end
    end

    HP:Apply(frame, frame.healthBar)

    -- Re-applied on every UpdateAll, so a Blizzard re-layout that re-allocates
    -- the fill texture can never bury the role icon again.
    RaiseFrameIcons(frame)

    -- Ensure the PartyMemberOverlay (leader crown, role, PvP icons) stays visible.
    -- This only exists on the classic-art PartyMemberFrame; CompactUnitFrame has
    -- no equivalent in 12.1 (see the raid-marker/leader note on RaiseFrameIcons).
    local overlay = frame.PartyMemberOverlay
    if overlay then
        overlay:SetAlpha(1)
        if overlay.LeaderIcon then overlay.LeaderIcon:SetAlpha(1) end
    end

    -- Dispel cue: nothing to do here, and nothing we are allowed to do. In 12.1
    -- the dispel highlight is no longer a region on the CompactUnitFrame. It is
    -- `frame.DispelOverlay`, a Frame acquired from a pool inside
    -- Blizzard_PrivateAurasUI's `<ScopedModifier forbidden="true"
    -- hideFromGlobalEnv="true">` block and re-parented onto the unit button at
    -- runtime. Its Background/Gradient/Border textures and its three
    -- dispelDebuffFrames belong to THAT frame, so frame:GetRegions() above never
    -- reaches them and the sweep cannot hide them. They are also forbidden
    -- objects: any method call on them from addon code raises. So the dispel
    -- school colour is Blizzard's, intact, and untouchable — by design.
end

---------------------------------------------------------------------------
-- Skin Aura Icons (Buffs/Debuffs)
---------------------------------------------------------------------------

local function SkinAuraIcon(button)
    if not button or skinnedAuras[button] then return end
    skinnedAuras[button] = true

    local icon = button.Icon or button.icon
    if not icon then return end

    -- Alpha-zero decorative textures (keep only the icon)
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "Texture" and region ~= icon then
            region:SetAlpha(0)
        end
    end

    -- Remove masks for square corners
    for i = 1, button:GetNumRegions() do
        local region = select(i, button:GetRegions())
        if region and region:GetObjectType() == "MaskTexture" then
            icon:RemoveMaskTexture(region)
            region:Hide()
        end
    end

    icon:SetTexCoord(unpack(C.ICON_CROP))

    -- Hide named border elements
    if button.Border then button.Border:SetAlpha(0) end
    if button.border then button.border:SetAlpha(0) end

    -- Plain frame + texture instead of BackdropTemplate to avoid secret-value taint
    local bd = CreateFrame("Frame", nil, button)
    bd:SetAllPoints(button)
    bd:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    local bgTex = bd:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2], C.BACKDROP_COLOR[3], C.BACKDROP_COLOR[4])
end

local function SkinAuraFrames(frame)
    if frame.buffFrames then
        for _, buff in ipairs(frame.buffFrames) do
            SkinAuraIcon(buff)
        end
    end
    if frame.debuffFrames then
        for _, debuff in ipairs(frame.debuffFrames) do
            SkinAuraIcon(debuff)
        end
    end
end

---------------------------------------------------------------------------
-- Style Name
---------------------------------------------------------------------------

local function StyleFontString(fs)
    if not fs or not fs.SetFont then return end
    SE:StyleFont(fs, nil, "")
    fs:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    fs:SetShadowColor(unpack(C.SHADOW_COLOR))
end

local function StyleName(frame)
    if frame.name then
        StyleFontString(frame.name)
    end
end

---------------------------------------------------------------------------
-- Per-Frame Skinning
---------------------------------------------------------------------------

local function SkinMemberFrame(frame)
    if not frame or skinnedFrames[frame] then return end
    skinnedFrames[frame] = true

    SkinHealthBar(frame)
    SkinPowerBar(frame)
    StripChrome(frame)
    StyleName(frame)
    SkinAuraFrames(frame)

    -- Hook CompactUnitFrame_UpdateAll on instance to re-apply visuals
    if frame.UpdateAll then
        hooksecurefunc(frame, "UpdateAll", function(self)
            -- Re-enforce flat textures
            if self.healthBar then
                EnforceFlatTexture(self.healthBar)
                RestoreFillDrawLayer(self.healthBar)
                RemoveBarMasks(self.healthBar)
            end
            if self.powerBar then
                EnforceFlatTexture(self.powerBar)
                RestoreFillDrawLayer(self.powerBar)
                RemoveBarMasks(self.powerBar)
            end
            StripChrome(self)
            SkinAuraFrames(self)
        end)
    end
end

---------------------------------------------------------------------------
-- Refresh colors (called on unit change)
---------------------------------------------------------------------------

local function RefreshColors(frame)
    if not frame or not frame.unit or not UnitExists(frame.unit) then return end

    if frame.healthBar then
        local r, g, b = GetClassColor(frame.unit)
        settingColor[frame.healthBar] = true
        frame.healthBar:SetStatusBarColor(r, g, b)
        settingColor[frame.healthBar] = nil
    end

    if frame.powerBar then
        local r, g, b = GetPowerColor(frame.unit)
        settingColor[frame.powerBar] = true
        frame.powerBar:SetStatusBarColor(r, g, b)
        settingColor[frame.powerBar] = nil
    end
end

---------------------------------------------------------------------------
-- Spacing
---------------------------------------------------------------------------
-- Blizzard lays compact frames out two different ways (verified against the
-- 12.1.0.69299 UI source):
--
--   * Group frames (CompactPartyFrame, CompactRaidGroup1-8) CHAIN each member
--     to the previous one. CompactRaidGroup_UpdateLayout() does
--     Member(i):SetPoint("TOP", Member(i-1), "BOTTOM", 0, yOffset) for vertical
--     groups and ("LEFT", prev, "RIGHT", 0, 0) for horizontal ones, and
--     CompactPartyFrameMixin:UpdateLayout() chains the pet frames on the end.
--
--   * The raid container is a FlowContainer. FlowContainer_DoLayout() anchors
--     every object ABSOLUTELY as ("TOPLEFT", container, "TOPLEFT", x, -y) with
--     x/y accumulated from object sizes — there is no parent-to-child chain to
--     nudge, and a wrapped grid puts frames at non-zero x AND y at once.
--
-- Both cases compute the target offset outright and write it; nothing is ever
-- added to whatever GetPoint() happens to return. Running a pass twice is a
-- no-op, and a frame we can't safely read is skipped rather than aborting the
-- loop (raid slots go in and out of use constantly).

local SPACING_EPSILON = 0.01

local function AnySecret(...)
    if hasanysecretvalues then
        return hasanysecretvalues(...)
    end
    if issecretvalue then
        for i = 1, select("#", ...) do
            if issecretvalue((select(i, ...))) then return true end
        end
    end
    return false
end

-- Read anchor 1. Returns nil if the frame has no point, or if anything about
-- the anchor is a secret value (we must never compare or do maths on those).
local function ReadPoint(frame)
    if not frame or not frame.GetPoint then return nil end
    local ok, point, rel, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok or not point then return nil end
    if AnySecret(point, rel, relPoint, x, y) then return nil end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return point, rel, relPoint, x, y
end

local function SameOffset(a, b)
    return math.abs(a - b) < SPACING_EPSILON
end

-- If we already wrote this exact anchor, recover the Blizzard offset it came
-- from; otherwise the current offset IS the Blizzard offset.
local function GetBaseOffset(frame, point, rel, relPoint, x, y)
    local applied = appliedOffsets[frame]
    if applied and applied.point == point and applied.rel == rel
        and applied.relPoint == relPoint
        and SameOffset(applied.x, x) and SameOffset(applied.y, y) then
        return applied.baseX, applied.baseY
    end
    return x, y
end

local function StoreOffset(frame, point, rel, relPoint, x, y, baseX, baseY)
    appliedOffsets[frame] = {
        point = point, rel = rel, relPoint = relPoint,
        x = x, y = y, baseX = baseX, baseY = baseY,
    }
end

-- Which way does this anchor push the frame away from its neighbour? Both axes
-- are resolved together, so a diagonal anchor (e.g. TOPLEFT -> BOTTOMRIGHT)
-- gets both offsets rather than being skipped.
local function AxisDelta(point, relPoint, spacing)
    local dx, dy = 0, 0
    if point:find("TOP") and relPoint:find("BOTTOM") then
        dy = -spacing
    elseif point:find("BOTTOM") and relPoint:find("TOP") then
        dy = spacing
    end
    if point:find("LEFT") and relPoint:find("RIGHT") then
        dx = spacing
    elseif point:find("RIGHT") and relPoint:find("LEFT") then
        dx = -spacing
    end
    return dx, dy
end

-- Chained layouts: each frame keeps its own anchor, we just widen the link.
-- The first member anchors to its group's own TOP/TOPLEFT, so AxisDelta returns
-- zero for it and it stays put — the group keeps its position.
local function SpaceChainedFrames(frames)
    if type(frames) ~= "table" then return end

    for i = 1, #frames do
        local frame = frames[i]
        local point, rel, relPoint, x, y = ReadPoint(frame)
        if point and rel then
            local baseX, baseY = GetBaseOffset(frame, point, rel, relPoint, x, y)
            local dx, dy = AxisDelta(point, relPoint, C.FRAME_SPACING)
            local nx, ny = baseX + dx, baseY + dy

            if not (SameOffset(nx, x) and SameOffset(ny, y)) then
                frame:ClearAllPoints()
                frame:SetPoint(point, rel, relPoint, nx, ny)
            end
            StoreOffset(frame, point, rel, relPoint, nx, ny, baseX, baseY)
        end
    end
end

-- Rank a set of coordinates into 0-based grid indices. Blizzard's flow offsets
-- are exact multiples of the object sizes, so equal coordinates share an index;
-- the 1px tolerance just absorbs fractional frame widths.
local function RankKey(value)
    return string.format("%.1f", value)
end

local function BuildRankLookup(values, descending)
    table.sort(values, function(a, b)
        if descending then return a > b end
        return a < b
    end)

    local lookup, rank, prev = {}, 0, nil
    for _, v in ipairs(values) do
        if prev and math.abs(v - prev) > 1 then
            rank = rank + 1
        end
        lookup[RankKey(v)] = rank
        prev = v
    end
    return lookup
end

local function IsFlowChild(frame)
    if not frame or not frame.GetName then return false end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or not name then return false end
    if not (name:find("^CompactRaidFrame%d+$") or name:find("^CompactRaidGroup%d+$")) then
        return false
    end
    -- Hidden frames keep stale anchors; including them would invent grid rows.
    local shown
    ok, shown = pcall(frame.IsShown, frame)
    if not ok or AnySecret(shown) then return false end
    return shown and true or false
end

-- FlowContainer layout: derive each frame's column/row from its position in the
-- grid and set the absolute offset for that cell. Empty/unused slots are simply
-- absent from the list instead of terminating the scan.
local function SpaceFlowContainer(container)
    if not container or not container.GetChildren then return end

    local entries, xs, ys = {}, {}, {}
    for _, child in ipairs({ container:GetChildren() }) do
        if IsFlowChild(child) then
            local point, rel, relPoint, x, y = ReadPoint(child)
            if point == "TOPLEFT" and rel == container and relPoint == "TOPLEFT" then
                local baseX, baseY = GetBaseOffset(child, point, rel, relPoint, x, y)
                entries[#entries + 1] = {
                    frame = child, point = point, rel = rel, relPoint = relPoint,
                    x = x, y = y, baseX = baseX, baseY = baseY,
                }
                xs[#xs + 1] = baseX
                ys[#ys + 1] = baseY
            end
        end
    end
    if #entries == 0 then return end

    -- Columns run left to right (x ascending); rows run top to bottom, and the
    -- flow's y offsets are negative going down, so rank y descending.
    local colRank = BuildRankLookup(xs, false)
    local rowRank = BuildRankLookup(ys, true)

    for _, e in ipairs(entries) do
        local col = colRank[RankKey(e.baseX)] or 0
        local row = rowRank[RankKey(e.baseY)] or 0
        local nx = e.baseX + col * C.FRAME_SPACING
        local ny = e.baseY - row * C.FRAME_SPACING

        if not (SameOffset(nx, e.x) and SameOffset(ny, e.y)) then
            e.frame:ClearAllPoints()
            e.frame:SetPoint(e.point, e.rel, e.relPoint, nx, ny)
        end
        StoreOffset(e.frame, e.point, e.rel, e.relPoint, nx, ny, e.baseX, e.baseY)
    end
end

local function ApplySpacing()
    -- Never re-anchor protected raid/party frames during combat — every
    -- ClearAllPoints/SetPoint is blocked (ADDON_ACTION_BLOCKED). Queue it and
    -- flush once combat ends (PLAYER_REGEN_ENABLED).
    if InCombatLockdown() then
        spacingPending = true
        return
    end
    spacingPending = false

    if CompactPartyFrame then
        SpaceChainedFrames(CompactPartyFrame.memberUnitFrames)
        SpaceChainedFrames(CompactPartyFrame.petUnitFrames)
    end

    -- "Keep Groups Together" (discrete mode) builds CompactRaidGroup1-8, each
    -- its own chained group inside the flow container.
    for i = 1, (MAX_RAID_GROUPS or 8) do
        local group = _G["CompactRaidGroup" .. i]
        if group then
            SpaceChainedFrames(group.memberUnitFrames)
        end
    end

    SpaceFlowContainer(CompactRaidFrameContainer)
end

-- Coalesce the layout hooks: Blizzard fires several layout passes per update,
-- and the hooks run inside secure execution, so defer the re-anchor to the next
-- frame rather than moving frames mid-Refresh.
local function QueueSpacing()
    if spacingScheduled then return end
    spacingScheduled = true
    C_Timer.After(0, function()
        spacingScheduled = false
        ApplySpacing()
    end)
end

-- Blizzard relayouts on far more triggers than the roster/combat events we
-- listen to (Edit Mode toggles, sort changes, Keep Groups Together, border
-- toggles), which is why the spacing used to drift and then heal itself. Hook
-- the layout functions so we re-apply after every Blizzard pass.
--
-- CompactRaidGroup_UpdateLayout is a GLOBAL (safe to hook by name) and covers
-- CompactPartyFrame plus every CompactRaidGroupN. LayoutFrames/UpdateLayout are
-- hooked on the INSTANCE — never on CompactRaidFrameContainerMixin or
-- CompactPartyFrameMixin, since Mixin() would copy the hooked function as a
-- plain Lua value and taint every secure call through it.
local layoutHooked = {}

local function InstallLayoutHooks()
    if not layoutHooked.group and type(_G.CompactRaidGroup_UpdateLayout) == "function" then
        layoutHooked.group = true
        hooksecurefunc("CompactRaidGroup_UpdateLayout", QueueSpacing)
    end
    if not layoutHooked.party and CompactPartyFrame and CompactPartyFrame.UpdateLayout then
        layoutHooked.party = true
        hooksecurefunc(CompactPartyFrame, "UpdateLayout", QueueSpacing)
    end
    if not layoutHooked.container and CompactRaidFrameContainer and CompactRaidFrameContainer.LayoutFrames then
        layoutHooked.container = true
        hooksecurefunc(CompactRaidFrameContainer, "LayoutFrames", QueueSpacing)
    end
    -- EditModeManagerFrame:UpdateRaidContainerFlow() reaches FlowContainer_DoLayout
    -- without going through LayoutFrames, so cover the global too. It fires once
    -- per added object, but QueueSpacing collapses a burst into one pass.
    if not layoutHooked.flow and type(_G.FlowContainer_DoLayout) == "function" then
        layoutHooked.flow = true
        hooksecurefunc("FlowContainer_DoLayout", QueueSpacing)
    end
end

---------------------------------------------------------------------------
-- Frame Discovery
---------------------------------------------------------------------------

local function ScanPartyFrames()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            SkinMemberFrame(frame)
            RefreshColors(frame)
        end
    end
end

local function ScanRaidFrames()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            SkinMemberFrame(frame)
            RefreshColors(frame)
        end
    end
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

local function HideTitles()
    -- Party title
    if CompactPartyFrameTitle then
        CompactPartyFrameTitle:SetAlpha(0)
    end
    if CompactPartyFrame and CompactPartyFrame.title then
        CompactPartyFrame.title:SetAlpha(0)
    end
    -- Raid container chrome
    if CompactRaidFrameContainer and CompactRaidFrameContainer.title then
        CompactRaidFrameContainer.title:SetAlpha(0)
    end
    if CompactRaidFrameContainerBorderFrame then
        CompactRaidFrameContainerBorderFrame:SetAlpha(0)
    end
end

function PartyFrameSkin:Apply()
    HideTitles()

    -- Re-flatten the heal-prediction/absorb textures after Blizzard's own update
    -- pass. Hooking the GLOBAL is safe; hooking CompactUnitFrameMixin would copy
    -- the hooked function as a plain Lua value and taint every secure call
    -- through it, so never do that. This hook only writes texture + colour — it
    -- never reads a heal or absorb amount, so nothing here can touch a secret.
    if type(_G.CompactUnitFrame_UpdateHealPrediction) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
            if not frame or not skinnedFrames[frame] then return end
            HP:Apply(frame, frame.healthBar)
        end)
    end

    -- Hook CompactUnitFrame_SetUnit to catch newly assigned party/raid frames
    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
        if not frame or not frame.GetName then return end
        local ok, name = pcall(frame.GetName, frame)
        if not ok or not name then return end
        if not name:find("^CompactPartyFrameMember") and not name:find("^CompactRaidFrame%d") then return end

        if not skinnedFrames[frame] then
            SkinMemberFrame(frame)
        end
        RefreshColors(frame)
    end)

    -- Event-driven discovery
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            -- Defer to next frame so Blizzard has time to create/assign frames
            C_Timer.After(0, function()
                InstallLayoutHooks()
                ScanPartyFrames()
                ScanRaidFrames()
                HideTitles()
                ApplySpacing()
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Combat ended: flush any spacing re-anchor that was blocked in combat.
            if spacingPending then
                spacingPending = false
                QueueSpacing()
            end
        elseif event == "UNIT_DISPLAYPOWER" then
            -- Refresh power color when power type changes
            for i = 1, 5 do
                local frame = _G["CompactPartyFrameMember" .. i]
                if frame and frame.unit and frame.unit == arg1 then
                    if frame.powerBar then
                        local r, g, b = GetPowerColor(frame.unit)
                        settingColor[frame.powerBar] = true
                        frame.powerBar:SetStatusBarColor(r, g, b)
                        settingColor[frame.powerBar] = nil
                    end
                end
            end
            for i = 1, 40 do
                local frame = _G["CompactRaidFrame" .. i]
                if frame and frame.unit and frame.unit == arg1 then
                    if frame.powerBar then
                        local r, g, b = GetPowerColor(frame.unit)
                        settingColor[frame.powerBar] = true
                        frame.powerBar:SetStatusBarColor(r, g, b)
                        settingColor[frame.powerBar] = nil
                    end
                end
            end
        end
    end)

    -- Skin any frames already visible
    InstallLayoutHooks()
    ScanPartyFrames()
    ScanRaidFrames()
    ApplySpacing()
end
