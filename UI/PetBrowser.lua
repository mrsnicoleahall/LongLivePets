--[[ Long Live Pets ----------------------------------------------------------
  PetBrowser.lua — our own pet-collection window. Search and filter your owned
  pets, hover for a pet card, then drop one into a battle slot. This is an
  original interface; it does not modify or reskin the Blizzard pet journal.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Browser = {}
ns.PetBrowser = Browser

local ROW_H, MAX_ROWS = 22, 16

local frame, rows
local state = { activeSlot = 1, maxOnly = false, typeIndex = nil, mode = "name" }

local function build()
    frame = CreateFrame("Frame", "LongLivePetsBrowser", UIParent, "BackdropTemplate")
    frame:SetSize(390, 520)
    frame:SetPoint("CENTER", 220, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Pets")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- row 1: search + search-mode toggle
    local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetSize(210, 22)
    search:SetPoint("TOPLEFT", 16, -42)
    search:SetScript("OnTextChanged", function() Browser:Refresh() end)
    frame.search = search

    local modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    modeBtn:SetSize(120, 22)
    modeBtn:SetPoint("LEFT", search, "RIGHT", 10, 0)
    modeBtn:SetText("Find: name")
    modeBtn:SetScript("OnClick", function()
        state.mode = (state.mode == "name") and "ability" or "name"
        modeBtn:SetText(state.mode == "ability" and "Find: ability" or "Find: name")
        Browser:Refresh()
    end)

    -- row 2: type filter + Lv25 + active-slot selector
    local typeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    typeBtn:SetSize(130, 22)
    typeBtn:SetPoint("TOPLEFT", 16, -70)
    typeBtn:SetText("Type: All")
    typeBtn:SetScript("OnClick", function()
        local i = (state.typeIndex or 0) + 1
        if i > 10 then i = nil end
        state.typeIndex = i
        typeBtn:SetText("Type: " .. (i and ns.Types.NAME[i] or "All"))
        Browser:Refresh()
    end)

    local maxBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    maxBtn:SetSize(74, 22)
    maxBtn:SetPoint("LEFT", typeBtn, "RIGHT", 8, 0)
    maxBtn:SetText("Lv25: off")
    maxBtn:SetScript("OnClick", function()
        state.maxOnly = not state.maxOnly
        maxBtn:SetText(state.maxOnly and "Lv25: on" or "Lv25: off")
        Browser:Refresh()
    end)

    local slotLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotLabel:SetPoint("LEFT", maxBtn, "RIGHT", 12, 0)
    slotLabel:SetText("Slot:")
    frame.slotButtons = {}
    for s = 1, 3 do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(22, 22)
        b:SetPoint("LEFT", slotLabel, "RIGHT", 2 + (s - 1) * 24, 0)
        b:SetText(tostring(s))
        b:SetScript("OnClick", function()
            state.activeSlot = s
            Browser:UpdateSlotButtons()
        end)
        frame.slotButtons[s] = b
    end

    -- list
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 16, -100)
    list:SetPoint("BOTTOMRIGHT", -16, 16)
    rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if self.pet then ns.PetCard:Show(self, self.pet) end
        end)
        row:SetScript("OnLeave", function() ns.PetCard:Hide() end)

        local tex = row:CreateTexture(nil, "ARTWORK")
        tex:SetSize(18, 18); tex:SetPoint("LEFT", 0, 0)
        row.icon = tex

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", 24, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -64, 0)
        name:SetJustifyH("LEFT"); name:SetWordWrap(false)
        row.name = name

        local slot = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        slot:SetSize(56, 18); slot:SetPoint("RIGHT", 0, 0); slot:SetText("Slot")
        row.slot = slot

        row:Hide()
        rows[i] = row
    end

    local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOP", 0, -10)
    empty:SetText("No pets match.")
    frame.empty = empty
end

function Browser:UpdateSlotButtons()
    if not frame then return end
    for s, b in ipairs(frame.slotButtons) do
        if s == state.activeSlot then b:LockHighlight() else b:UnlockHighlight() end
    end
end

function Browser:Refresh()
    if not frame then return end
    local text = frame.search and frame.search:GetText() or ""
    local opts = { maxOnly = state.maxOnly, typeIndex = state.typeIndex }
    if state.mode == "ability" then opts.ability = text else opts.search = text end

    local pets = ns.Roster:Filter(opts)
    frame.empty:SetShown(#pets == 0)
    for i, row in ipairs(rows) do
        local p = pets[i]
        if p then
            row.pet = p
            if p.icon then row.icon:SetTexture(p.icon) end
            local typeName = p.petType and ns.Types.NAME[p.petType] or "?"
            row.name:SetText(("%s  |cffaaaaaaL%d %s|r"):format(p.name, p.level, typeName))
            row.slot:SetScript("OnClick", function()
                ns.Roster:SlotPet(p.petID, state.activeSlot)
                ns:Print(("Put %s into slot %d."):format(p.name, state.activeSlot))
            end)
            row:Show()
        else
            row.pet = nil
            row:Hide()
        end
    end
    if #pets > MAX_ROWS then
        ns:Print(("Showing %d of %d matches — narrow the search."):format(MAX_ROWS, #pets))
    end
    self:UpdateSlotButtons()
end

function Browser:Toggle()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); self:Refresh() end
end

function Browser:Show()
    if not frame then build() end
    frame:Show(); self:Refresh()
end
