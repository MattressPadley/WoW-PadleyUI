local _, ns = ...

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

    -- Fonts
    FONT = "Interface\\AddOns\\PadleyUI\\Fonts\\Expressway.ttf",
    FONT_SIZE = 11,
    FONT_SIZE_SMALL = 10,
    FONT_FLAGS = "OUTLINE",

    -- Flat backdrop table (reused everywhere)
    FLAT_BACKDROP = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    },
}
