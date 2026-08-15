local _, ns = ...

local Movers = {}
ns.Movers = Movers

-- External tracking tables (never write custom keys onto Blizzard frames)
local registered = {}   -- [frame] = entry
local applying = {}     -- [frame] = true while we are re-anchoring (re-entrancy guard)

---------------------------------------------------------------------------
-- Managed Blizzard panels
--
-- These are the UIPanel-managed windows Edit Mode never adopted. Each entry:
--   id           key in PadleyUI_DB.panels
--   global       _G name of the panel frame
--   addon        owning addon (nil = always loaded)
--   titlePath    path from the panel down to its title bar (default TitleContainer)
--   alreadyMovable  Blizzard already declares movable="true" in XML
--   skip         predicate: return true to leave the frame alone right now
---------------------------------------------------------------------------

local panels = {
    {
        id = "CharacterFrame",
        global = "CharacterFrame",
        addon = "Blizzard_UIPanels_Game",
        alreadyMovable = true,
    },
    {
        id = "CollectionsJournal",
        global = "CollectionsJournal",
        addon = "Blizzard_Collections",
    },
    {
        id = "EncounterJournal",
        global = "EncounterJournal",
        addon = "Blizzard_EncounterJournal",
    },
    {
        id = "ProfessionsFrame",
        global = "ProfessionsFrame",
        addon = "Blizzard_Professions",
    },
    {
        id = "ProfessionsBookFrame",
        global = "ProfessionsBookFrame",
        addon = "Blizzard_ProfessionsBook",
        alreadyMovable = true,
    },
    {
        id = "PVEFrame",
        global = "PVEFrame",
        addon = "Blizzard_GroupFinder",
    },
    {
        id = "WorldMapFrame",
        global = "WorldMapFrame",
        addon = "Blizzard_WorldMap",
        -- World map keeps its title bar one level deeper
        titlePath = { "BorderFrame", "TitleContainer" },
        -- Maximized map owns the whole screen — leave it to Blizzard
        skip = function(frame)
            return frame.IsMaximized and frame:IsMaximized()
        end,
    },
}

---------------------------------------------------------------------------
-- Storage
--
-- Positions live in PadleyUI_DB.panels (initialised in Config:Init). Coords are
-- UIParent-space offsets from UIParent's TOPLEFT; they are divided by the
-- frame's scale when applied, so checkFit's resolution-driven SetScale() can't
-- make saved positions drift.
---------------------------------------------------------------------------

local function GetStore()
    PadleyUI_DB = PadleyUI_DB or {}
    PadleyUI_DB.panels = PadleyUI_DB.panels or {}
    return PadleyUI_DB.panels
end

function Movers:GetPosition(id)
    return GetStore()[id]
end

function Movers:ClearPosition(id)
    GetStore()[id] = nil
end

-- Record the frame's current on-screen position in UIParent space.
function Movers:SavePosition(id, frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end

    local scale = frame:GetScale()
    if not scale or scale == 0 then scale = 1 end

    GetStore()[id] = {
        point = "TOPLEFT",
        relPoint = "TOPLEFT",
        x = left * scale - UIParent:GetLeft(),
        y = top * scale - UIParent:GetTop(),
    }
end

---------------------------------------------------------------------------
-- Anchoring
---------------------------------------------------------------------------

local function ApplyPosition(frame, pos)
    local scale = frame:GetScale()
    if not scale or scale == 0 then scale = 1 end

    applying[frame] = true
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x / scale, pos.y / scale)
    applying[frame] = false
end

-- Re-anchor to the saved position, if there is one and the frame wants it.
local function Restore(entry, frame)
    local pos = Movers:GetPosition(entry.id)
    if not pos then return end
    if entry.skip and entry.skip(frame) then return end
    ApplyPosition(frame, pos)
end

---------------------------------------------------------------------------
-- Dragging
---------------------------------------------------------------------------

local function AttachDrag(entry, frame, dragRegion)
    if not entry.alreadyMovable then
        frame:SetMovable(true)
    end

    -- TitleContainer is neither mouse-enabled nor drag-registered by Blizzard
    dragRegion:EnableMouse(true)
    dragRegion:RegisterForDrag("LeftButton")

    dragRegion:SetScript("OnDragStart", function()
        if entry.skip and entry.skip(frame) then return end
        if not frame:IsMovable() then return end
        frame:StartMoving()
    end)

    dragRegion:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if entry.skip and entry.skip(frame) then return end
        Movers:SavePosition(entry.id, frame)
        -- Normalise the anchor StartMoving left behind to our UIParent TOPLEFT one
        Restore(entry, frame)
    end)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- Make a frame draggable by dragRegion and persist its position under `id`.
-- opts.titleRegion  region to drag by (defaults to the frame itself)
-- opts.hookSetPoint hook the frame's SetPoint to beat the UIPanel re-snap
-- opts.alreadyMovable / opts.skip  as per the panel table above
function Movers:Register(id, frame, opts)
    if not frame or registered[frame] then return end
    opts = opts or {}

    local entry = {
        id = id,
        alreadyMovable = opts.alreadyMovable,
        skip = opts.skip,
    }
    registered[frame] = entry

    AttachDrag(entry, frame, opts.titleRegion or frame)

    if opts.hookSetPoint then
        -- The panel manager ClearAllPoints + SetPoints its windows on every
        -- show and on every layout pass. FramePositionDelegate is local and
        -- SetForbidden, so we can't hook it — hook this instance's SetPoint
        -- instead and re-anchor synchronously (deferring would flicker).
        hooksecurefunc(frame, "SetPoint", function(self)
            if applying[self] then return end
            Restore(entry, self)
        end)
    end

    frame:HookScript("OnShow", function(self)
        Restore(entry, self)
    end)

    Restore(entry, frame)
    return entry
end

local function ResolveTitle(entry, frame)
    local region = frame
    if entry.titlePath then
        for _, key in ipairs(entry.titlePath) do
            region = region and region[key]
        end
    else
        region = frame.TitleContainer
    end
    return region
end

local function RegisterPanel(entry)
    local frame = _G[entry.global]
    if not frame or registered[frame] then return end

    local title = ResolveTitle(entry, frame)
    if not title then return end

    Movers:Register(entry.id, frame, {
        titleRegion = title,
        hookSetPoint = true,
        alreadyMovable = entry.alreadyMovable,
        skip = entry.skip,
    })
end

-- Register every managed panel whose owning addon is already loaded.
function Movers:Init()
    for _, entry in ipairs(panels) do
        RegisterPanel(entry)
    end
end

-- Called from PadleyUI.lua's ADDON_LOADED branches for the load-on-demand panels.
function Movers:OnAddonLoaded(loadedAddon)
    for _, entry in ipairs(panels) do
        if entry.addon == loadedAddon then
            RegisterPanel(entry)
        end
    end
end
