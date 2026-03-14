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
    auraBlacklist = {},  -- { [spellId] = { name = "...", icon = textureId } }
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

function Config:IsAuraBlacklisted(spellId)
    return self.db.auraBlacklist[spellId] ~= nil
end

function Config:AddToAuraBlacklist(spellId, name, icon, auraType)
    self.db.auraBlacklist[spellId] = { name = name, icon = icon, type = auraType or "debuff" }
    if self.RefreshBlacklistTab then self:RefreshBlacklistTab() end
    if self.onBlacklistChanged then self.onBlacklistChanged() end
end

function Config:RemoveFromAuraBlacklist(spellId)
    self.db.auraBlacklist[spellId] = nil
    if self.RefreshBlacklistTab then self:RefreshBlacklistTab() end
    if self.onBlacklistChanged then self.onBlacklistChanged() end
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
    panel:SetSize(320, 220)
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
    -- Tab system
    --------------------------------------------------------------------------
    local TAB_HEIGHT = 22
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    tabBar:SetHeight(TAB_HEIGHT)

    local tabBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints()
    tabBg:SetColorTexture(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                           C.HEADER_COLOR[3], C.HEADER_COLOR[4])

    local tabs = {}
    local tabContents = {}

    local function SelectTab(id)
        for i, tab in ipairs(tabs) do
            if i == id then
                tab.bg:SetColorTexture(C.BACKDROP_COLOR[1], C.BACKDROP_COLOR[2],
                                        C.BACKDROP_COLOR[3], 0.95)
                tab.label:SetTextColor(0, 0.8, 1)
                tabContents[i]:Show()
            else
                tab.bg:SetColorTexture(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                                        C.HEADER_COLOR[3], C.HEADER_COLOR[4])
                tab.label:SetTextColor(0.6, 0.6, 0.6)
                tabContents[i]:Hide()
            end
        end
    end

    local function CreateTab(name, index)
        local tab = CreateFrame("Button", nil, tabBar)
        tab:SetHeight(TAB_HEIGHT)
        tab:SetWidth(80)
        if index == 1 then
            tab:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 1, 0)
        else
            tab:SetPoint("TOPLEFT", tabs[index - 1], "TOPRIGHT", 1, 0)
        end

        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        tab.bg = bg

        local label = tab:CreateFontString(nil, "OVERLAY")
        label:SetFont(C.FONT, C.FONT_SIZE, "")
        label:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
        label:SetShadowColor(unpack(C.SHADOW_COLOR))
        label:SetPoint("CENTER", 0, 0)
        label:SetText(name)
        tab.label = label

        tab:SetScript("OnClick", function() SelectTab(index) end)

        local content = CreateFrame("Frame", nil, panel)
        content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
        content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        content:Hide()

        tabs[index] = tab
        tabContents[index] = content
        return content
    end

    --------------------------------------------------------------------------
    -- Tab 1: General
    --------------------------------------------------------------------------
    local generalContent = CreateTab("General", 1)

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
    -- Tab 2: Blacklist
    --------------------------------------------------------------------------
    local blacklistContent = CreateTab("Blacklist", 2)

    -- Add-spell input row
    local inputRow = CreateFrame("Frame", nil, blacklistContent)
    inputRow:SetPoint("TOPLEFT", 12, -10)
    inputRow:SetPoint("RIGHT", blacklistContent, "RIGHT", -12, 0)
    inputRow:SetHeight(24)

    local inputBox = CreateFrame("EditBox", nil, inputRow, "BackdropTemplate")
    inputBox:SetPoint("TOPLEFT", 0, 0)
    inputBox:SetPoint("RIGHT", inputRow, "RIGHT", -50, 0)
    inputBox:SetHeight(22)
    inputBox:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    inputBox:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    inputBox:SetFont(C.FONT, C.FONT_SIZE, "")
    inputBox:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    inputBox:SetShadowColor(unpack(C.SHADOW_COLOR))
    inputBox:SetTextColor(1, 1, 1)
    inputBox:SetTextInsets(6, 6, 0, 0)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(64)

    -- Placeholder text
    local placeholder = inputBox:CreateFontString(nil, "ARTWORK")
    placeholder:SetFont(C.FONT, C.FONT_SIZE, "")
    placeholder:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    placeholder:SetShadowColor(unpack(C.SHADOW_COLOR))
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    placeholder:SetText("Spell ID or name...")
    inputBox:HookScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    local addBtn = CreateFrame("Button", nil, inputRow, "BackdropTemplate")
    addBtn:SetSize(44, 22)
    addBtn:SetPoint("LEFT", inputBox, "RIGHT", 4, 0)
    addBtn:SetBackdrop({ bgFile = C.FLAT_BACKDROP.bgFile })
    addBtn:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                             C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    local addLabel = addBtn:CreateFontString(nil, "OVERLAY")
    addLabel:SetFont(C.FONT, C.FONT_SIZE, "")
    addLabel:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    addLabel:SetShadowColor(unpack(C.SHADOW_COLOR))
    addLabel:SetPoint("CENTER", 0, 0)
    addLabel:SetText("Add")
    addLabel:SetTextColor(0.9, 0.9, 0.9)
    addBtn:HookScript("OnEnter", function()
        addBtn:SetBackdropColor(C.HIGHLIGHT_COLOR[1], C.HIGHLIGHT_COLOR[2],
                                 C.HIGHLIGHT_COLOR[3], C.HIGHLIGHT_COLOR[4])
    end)
    addBtn:HookScript("OnLeave", function()
        addBtn:SetBackdropColor(C.HEADER_COLOR[1], C.HEADER_COLOR[2],
                                 C.HEADER_COLOR[3], C.HEADER_COLOR[4])
    end)

    local function TryAddSpell()
        local text = inputBox:GetText():trim()
        if text == "" then return end

        local spellId = tonumber(text)
        if spellId then
            -- Numeric input — look up by spell ID
            local info = C_Spell.GetSpellInfo(spellId)
            if not info then
                print("|cff00ccffPadleyUI:|r Unknown spell ID: " .. text)
                return
            end
            local icon = C_Spell.GetSpellTexture(spellId)
            self:AddToAuraBlacklist(spellId, info.name, icon, "debuff")
            print("|cff00ccffPadleyUI:|r Blacklisted " .. info.name .. " (" .. spellId .. ")")
        else
            -- Text input — search by name
            local info = C_Spell.GetSpellInfo(text)
            if not info then
                print("|cff00ccffPadleyUI:|r Unknown spell: " .. text)
                return
            end
            local icon = C_Spell.GetSpellTexture(info.spellID)
            self:AddToAuraBlacklist(info.spellID, info.name, icon, "debuff")
            print("|cff00ccffPadleyUI:|r Blacklisted " .. info.name .. " (" .. info.spellID .. ")")
        end
        inputBox:SetText("")
        inputBox:ClearFocus()
    end

    addBtn:SetScript("OnClick", TryAddSpell)
    inputBox:SetScript("OnEnterPressed", TryAddSpell)
    inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local blHeader = blacklistContent:CreateFontString(nil, "OVERLAY")
    blHeader:SetFont(C.FONT, C.FONT_SIZE_SMALL, "")
    blHeader:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
    blHeader:SetShadowColor(unpack(C.SHADOW_COLOR))
    blHeader:SetPoint("TOPLEFT", inputRow, "BOTTOMLEFT", 0, -6)
    blHeader:SetPoint("RIGHT", blacklistContent, "RIGHT", -12, 0)
    blHeader:SetTextColor(0.4, 0.4, 0.4)
    blHeader:SetWordWrap(true)
    blHeader:SetText("Right-click to remove.")

    -- List layout
    local ROW_HEIGHT = 20
    local ICON_SIZE = 16
    local ROW_GAP = 2

    local scrollParent = CreateFrame("Frame", nil, blacklistContent)
    scrollParent:SetPoint("TOPLEFT", blHeader, "BOTTOMLEFT", 0, -8)
    scrollParent:SetPoint("BOTTOMRIGHT", blacklistContent, "BOTTOMRIGHT", -8, 8)
    scrollParent:SetClipsChildren(true)

    local scrollChild = CreateFrame("Frame", nil, scrollParent)
    scrollChild:SetPoint("TOPLEFT")
    scrollChild:SetPoint("TOPRIGHT")

    local blacklistRows = {}

    local function CreateBlacklistRow(parent, yOffset, spellId, data, configRef)
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", 0, yOffset)
        row:RegisterForClicks("RightButtonUp")

        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ICON_SIZE, ICON_SIZE)
        iconTex:SetPoint("LEFT", 0, 0)
        iconTex:SetTexCoord(unpack(C.ICON_CROP))
        iconTex:SetTexture(data.icon)

        local name = row:CreateFontString(nil, "OVERLAY")
        name:SetFont(C.FONT, C.FONT_SIZE, "")
        name:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
        name:SetShadowColor(unpack(C.SHADOW_COLOR))
        name:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(data.name)
        name:SetTextColor(0.9, 0.9, 0.9)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0, 0, 0.15)

        local sid = spellId
        row:SetScript("OnClick", function()
            configRef:RemoveFromAuraBlacklist(sid)
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetSpellByID(sid)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-click to remove", 1, 0.2, 0.2)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return row
    end

    local SECTION_HEADER_HEIGHT = 18

    local function CreateListSectionHeader(parent, text, yOffset)
        local header = parent:CreateFontString(nil, "OVERLAY")
        header:SetFont(C.FONT, C.FONT_SIZE, "")
        header:SetShadowOffset(C.SHADOW_OFFSET[1], C.SHADOW_OFFSET[2])
        header:SetShadowColor(unpack(C.SHADOW_COLOR))
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        header:SetText(text)
        header:SetTextColor(0, 0.8, 1)
        return header
    end

    function Config:RefreshBlacklistTab()
        for _, row in ipairs(blacklistRows) do
            row:Hide()
        end
        wipe(blacklistRows)

        -- Also hide old section headers
        for _, child in pairs({ scrollChild:GetRegions() }) do
            if child and child.Hide then child:Hide() end
        end

        -- Split entries by type
        local buffEntries = {}
        local debuffEntries = {}
        for spellId, data in pairs(self.db.auraBlacklist) do
            if data.type == "buff" then
                buffEntries[#buffEntries + 1] = { id = spellId, data = data }
            else
                debuffEntries[#debuffEntries + 1] = { id = spellId, data = data }
            end
        end

        local y = 0

        -- Buffs section
        if #buffEntries > 0 then
            CreateListSectionHeader(scrollChild, "Buffs", y)
            y = y - SECTION_HEADER_HEIGHT
            for _, entry in ipairs(buffEntries) do
                local row = CreateBlacklistRow(scrollChild, y, entry.id, entry.data, self)
                blacklistRows[#blacklistRows + 1] = row
                y = y - (ROW_HEIGHT + ROW_GAP)
            end
            y = y - 4  -- extra gap between sections
        end

        -- Debuffs section
        if #debuffEntries > 0 then
            CreateListSectionHeader(scrollChild, "Debuffs", y)
            y = y - SECTION_HEADER_HEIGHT
            for _, entry in ipairs(debuffEntries) do
                local row = CreateBlacklistRow(scrollChild, y, entry.id, entry.data, self)
                blacklistRows[#blacklistRows + 1] = row
                y = y - (ROW_HEIGHT + ROW_GAP)
            end
        end

        scrollChild:SetHeight(math.max(1, math.abs(y)))
    end

    -- Populate on show
    panel:HookScript("OnShow", function() self:RefreshBlacklistTab() end)

    --------------------------------------------------------------------------

    -- Select first tab by default
    SelectTab(1)

    -- Make panel taller to accommodate tabs
    panel:SetSize(320, 300)

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
