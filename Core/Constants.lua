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

    -- Fonts
    FONT = "Fonts\\FRIZQT__.TTF",
    FONT_SIZE = 11,
    FONT_FLAGS = "OUTLINE",

    -- Flat backdrop table (reused everywhere)
    FLAT_BACKDROP = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    },
}
