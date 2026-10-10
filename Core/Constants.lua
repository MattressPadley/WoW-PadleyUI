local _, ns = ...

-- Running client flavour: "retail" | "forever". Keyed off the interface number,
-- not WOW_PROJECT_ID — Forever beta builds have reported both 1 (Mainline) and
-- 18 for the project ID, while its interface is 1.60.x => 16xxx.
ns.INTERFACE = select(4, GetBuildInfo())
ns.FLAVOR = (ns.INTERFACE >= 16000 and ns.INTERFACE < 20000) and "forever" or "retail"

-- PadleyUI shared constants
ns.C = {
    -- Backdrop
    BACKDROP_COLOR = { 0, 0, 0, 0.6 },
    BORDER_COLOR = { 0, 0, 0, 1 },
    BORDER_SIZE = 1,

    -- Bars
    BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8",

    -- Header
    HEADER_COLOR = { 0.15, 0.15, 0.15, 0.9 },

    -- Hover highlight
    HIGHLIGHT_COLOR = { 0.4, 0.4, 0.4, 1 },

    -- Icon texcoord crop (removes default border artifacts)
    ICON_CROP = { 0.08, 0.92, 0.08, 0.92 },

    -- Highlight overlay for hover effects on buttons/items
    HIGHLIGHT_OVERLAY = { 1, 1, 1, 0.25 },

    -- Text shadow
    SHADOW_OFFSET = { 2, -1 },
    SHADOW_COLOR  = { 0, 0, 0, 1 },

    -- Fonts
    FONT = "Interface\\AddOns\\PadleyUI\\Fonts\\Expressway.ttf",
    FONT_SIZE = 11,
    FONT_SIZE_SMALL = 10,
    FONT_FLAGS = "OUTLINE",

    -- Frame spacing (extra vertical gap between party/raid frames)
    FRAME_SPACING = 2,

    -- Flat backdrop table (reused everywhere)
    FLAT_BACKDROP = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    },
}
