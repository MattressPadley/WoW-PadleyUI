local addonName, ns = ...

local C = ns.C

local Config = {}
ns.Config = Config

-- Defaults
local defaults = {
    minimap = { angle = 220 },
    nameplates = {
        width = 110,
        height = 11,
    },
    unitframes = {
        width = 123,
        healthHeight = 19,
        powerHeight = 8,
    },
}

----------------------------------------------------------------------------
-- SavedVariables
----------------------------------------------------------------------------

function Config:Init()
    PadleyUI_DB = PadleyUI_DB or {}
    for section, vals in pairs(defaults) do
        if not PadleyUI_DB[section] then
            PadleyUI_DB[section] = {}
        end
        for k, v in pairs(vals) do
            if PadleyUI_DB[section][k] == nil then
                PadleyUI_DB[section][k] = v
            end
        end
    end
    self.db = PadleyUI_DB

    self:CreateMinimapButton()
    self:CreateConfigPanel()
end

function Config:Get(section, key)
    return self.db[section][key]
end

function Config:Set(section, key, value)
    self.db[section][key] = value
end

----------------------------------------------------------------------------
-- Minimap Button
----------------------------------------------------------------------------

function Config:CreateMinimapButton()
    local btn = CreateFrame("Button", "PadleyUIMinimapButton", Minimap)
    btn:SetSize(18, 18)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- Background circle
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    bg:SetDrawLayer("BACKGROUND")

    -- "P" label
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(C.FONT, 10, "")
    label:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    label:SetShadowColor(unpack(C.SHADOW_COLOR))
    label:SetPoint("CENTER", 0, 0)
    label:SetText("P")
    label:SetTextColor(0, 0.8, 1)

    -- Highlight
    btn:HookScript("OnEnter", function(self)
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("PadleyUI")
        GameTooltip:AddLine("Click to open settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        bg:SetColorTexture(0, 0, 0, 0.8)
        GameTooltip:Hide()
    end)

    -- Position on minimap edge
    local function UpdatePosition()
        local angle = math.rad(self.db.minimap.angle)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Drag to reposition around minimap
    btn:SetScript("OnDragStart", function()
        btn:StartMoving()
        btn:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            self.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function()
        btn:StopMovingOrSizing()
        btn:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function()
        if self.panel:IsShown() then
            self.panel:Hide()
        else
            self.panel:Show()
        end
    end)

    UpdatePosition()
    self.minimapButton = btn
end

----------------------------------------------------------------------------
-- Config Panel
----------------------------------------------------------------------------

local function CreateSlider(parent, label, min, max, step, x, y, width)
    width = width or 200

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 40)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    -- Label
    local text = container:CreateFontString(nil, "OVERLAY")
    text:SetFont(C.FONT, C.FONT_SIZE, "")
    text:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    text:SetShadowColor(unpack(C.SHADOW_COLOR))
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(0.8, 0.8, 0.8)

    -- Slider
    local slider = CreateFrame("Slider", nil, container, "MinimalSliderTemplate")
    slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
    slider:SetSize(width - 50, 14)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Flat track
    local track = slider:GetThumbTexture()
    if track then
        track:SetColorTexture(0, 0.8, 1, 1)
        track:SetSize(10, 14)
    end

    -- Value text
    local valText = container:CreateFontString(nil, "OVERLAY")
    valText:SetFont(C.FONT, C.FONT_SIZE, "")
    valText:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    valText:SetShadowColor(unpack(C.SHADOW_COLOR))
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valText:SetTextColor(1, 1, 1)

    slider.valText = valText
    slider.container = container
    return slider
end

local function CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY")
    header:SetFont(C.FONT, C.FONT_SIZE + 2, "")
    header:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    header:SetShadowColor(unpack(C.SHADOW_COLOR))
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText(text)
    header:SetTextColor(0, 0.8, 1)
    return header
end

function Config:CreateConfigPanel()
    local panel = CreateFrame("Frame", "PadleyUIConfigPanel", UIParent, "BackdropTemplate")
    panel:SetSize(320, 350)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop(C.FLAT_BACKDROP)
    panel:SetBackdropColor(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                           C.BACKDROP_COLOR[3], 0.95)
    panel:SetBackdropBorderColor(C.BORDER_COLOR[1], C.BORDER_COLOR[2],
                                  C.BORDER_COLOR[3], C.BORDER_COLOR[4])
    panel:Hide()

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    titleBar:SetHeight(24)
    titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    titleBar:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    titleBar:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                               C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    title:SetFont(C.FONT, C.FONT_SIZE + 1, "")
    title:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    title:SetShadowColor(unpack(C.SHADOW_COLOR))
    title:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    title:SetText("PadleyUI Settings")
    title:SetTextColor(1, 1, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -1, 0)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    local closeBg = CreateFrame("Frame", nil, closeBtn, "BackdropTemplate")
    closeBg:SetAllPoints()
    closeBg:SetFrameLevel(closeBtn:GetFrameLevel())
    closeBg:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    closeBg:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                              C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    local closeX = closeBg:CreateFontString(nil, "OVERLAY")
    closeX:SetFont(C.FONT, C.FONT_SIZE_SMALL, "")
    closeX:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    closeX:SetShadowColor(unpack(C.SHADOW_COLOR))
    closeX:SetPoint("CENTER", 0, 0)
    closeX:SetText("x")

    closeBtn:HookScript("OnEnter", function()
        closeBg:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2],
                                  C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    closeBtn:HookScript("OnLeave", function()
        closeBg:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                                  C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    end)

    -- Close with Escape
    tinsert(UISpecialFrames, "PadleyUIConfigPanel")

    --------------------------------------------------------------------------
    -- Content
    --------------------------------------------------------------------------
    local generalContent = CreateFrame("Frame", nil, panel)
    generalContent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -4)
    generalContent:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    CreateSectionHeader(generalContent, "Nameplates", 12, -10)

    -- Width slider
    local widthSlider = CreateSlider(generalContent, "Width", 60, 200, 1, 12, -34, 280)
    widthSlider:SetValue(self.db.nameplates.width)
    widthSlider.valText:SetText(tostring(self.db.nameplates.width))

    widthSlider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val + 0.5)
        widthSlider.valText:SetText(tostring(val))
        self:Set("nameplates", "width", val)
        self:ApplyNameplateDimensions()
    end)

    -- Height slider
    local heightSlider = CreateSlider(generalContent, "Height", 4, 40, 1, 12, -84, 280)
    heightSlider:SetValue(self.db.nameplates.height)
    heightSlider.valText:SetText(tostring(self.db.nameplates.height))

    heightSlider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val + 0.5)
        heightSlider.valText:SetText(tostring(val))
        self:Set("nameplates", "height", val)
        self:ApplyNameplateDimensions()
    end)

    --------------------------------------------------------------------------
    -- Unit Frames section
    --------------------------------------------------------------------------
    CreateSectionHeader(generalContent, "Unit Frames", 12, -140)

    local ufWidthSlider = CreateSlider(generalContent, "Width", 60, 200, 1, 12, -164, 280)
    ufWidthSlider:SetValue(self.db.unitframes.width)
    ufWidthSlider.valText:SetText(tostring(self.db.unitframes.width))
    ufWidthSlider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val + 0.5)
        ufWidthSlider.valText:SetText(tostring(val))
        self:Set("unitframes", "width", val)
        self:ApplyUnitFrameDimensions()
    end)

    local ufHealthSlider = CreateSlider(generalContent, "Health Height", 4, 40, 1, 12, -214, 280)
    ufHealthSlider:SetValue(self.db.unitframes.healthHeight)
    ufHealthSlider.valText:SetText(tostring(self.db.unitframes.healthHeight))
    ufHealthSlider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val + 0.5)
        ufHealthSlider.valText:SetText(tostring(val))
        self:Set("unitframes", "healthHeight", val)
        self:ApplyUnitFrameDimensions()
    end)

    local ufPowerSlider = CreateSlider(generalContent, "Power Height", 2, 20, 1, 12, -264, 280)
    ufPowerSlider:SetValue(self.db.unitframes.powerHeight)
    ufPowerSlider.valText:SetText(tostring(self.db.unitframes.powerHeight))
    ufPowerSlider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val + 0.5)
        ufPowerSlider.valText:SetText(tostring(val))
        self:Set("unitframes", "powerHeight", val)
        self:ApplyUnitFrameDimensions()
    end)

    self.panel = panel
end

----------------------------------------------------------------------------
-- Apply nameplate dimensions
----------------------------------------------------------------------------

function Config:ApplyNameplateDimensions()
    if ns.NameplateSkin then
        ns.NameplateSkin:ResizeAll()
    end
end

function Config:ApplyUnitFrameDimensions()
    if ns.UnitFrameSkin then
        ns.UnitFrameSkin:ResizeAllBars()
    end
end
