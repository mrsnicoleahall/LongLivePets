--[[ Long Live Pets ----------------------------------------------------------
  Main.lua — the single window. Three panels in one frame:

      COLLECTION (left)  │  LOADED TEAM (center)  │  TEAMS (right)

  Replaces the old separate team window and pet-browser window. The pet card,
  import/export, and share all live inline here — no extra popups. Original UI;
  the Blizzard pet journal is never touched.

  ns.UI is the public surface (Toggle/Show/Refresh). ns.PetBrowser aliases it so
  "/llp pets" just opens this window.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local UI = {}
ns.UI = UI
ns.PetBrowser = UI

local COL_ROWS, TEAM_ROWS = 16, 16
local ROW_H = 22

local frame
local colRows, teamRows = {}, {}
local colPets = {}            -- current filtered collection list
local state = {
    activeSlot = 1, search = "", typeIndex = nil, maxOnly = false, colOffset = 0,
    mode = "name", markedOnly = false, rightMode = "teams",
    selectedTeam = nil, selectedPet = nil,
}

-- ---- slotting -------------------------------------------------------------
-- Click-to-slot is the reliable path. Drag uses WoW's NATIVE pet cursor
-- (C_PetJournal.PickupPet) so the loadout slots receive it correctly.
local function placePet(pet, slot)
    if not pet then return end
    ns.Roster:SlotPet(pet.petID, slot)
    UI:RefreshLoadout()
end

-- If a battle pet is sitting on the game cursor, drop it into `slot`.
local function dropCursorPet(slot)
    local kind, a1 = GetCursorInfo()
    if kind == "battlepet" and a1 then
        if not (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then
            C_PetJournal.SetPetLoadOutInfo(slot, a1)
        end
        ClearCursor()
        UI:RefreshLoadout()
        return true
    end
    return false
end

-- ---- small builders -------------------------------------------------------
local function panelTitle(parent, text, x)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, -40)
    fs:SetText(text)
    return fs
end
local function btn(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 20); b:SetText(label)
    return b
end

-- A small self-contained dropdown (no dependency on Blizzard dropdown
-- templates). options = { { text=, value= }, ... }. onSelect(value) fires on
-- pick. Returns the button; call dd:SelectText(text) to set the shown label.
local openMenu
local function makeDropdown(parent, w, options, onSelect, initialText)
    local dd = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    dd:SetSize(w, 20); dd:SetText(initialText or "")
    function dd:SelectText(t) self:SetText(t) end

    local menu = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG"); menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        menu:SetBackdropColor(0.05, 0.05, 0.07, 1)
        menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
    menu:Hide()

    local y = 4
    for _, opt in ipairs(options) do
        local ob = CreateFrame("Button", nil, menu)
        ob:SetSize(w - 8, 18); ob:SetPoint("TOPLEFT", 4, -y)
        ob:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local t = ob:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("LEFT", 4, 0); t:SetJustifyH("LEFT"); t:SetText(opt.text)
        ob:SetScript("OnClick", function()
            dd:SetText(opt.text); menu:Hide(); openMenu = nil
            onSelect(opt.value)
        end)
        y = y + 18
    end
    menu:SetSize(w, y + 4)

    dd:SetScript("OnClick", function()
        if openMenu and openMenu ~= menu then openMenu:Hide() end
        if menu:IsShown() then menu:Hide(); openMenu = nil
        else menu:Show(); openMenu = menu end
    end)
    return dd
end

-- ===========================================================================
-- BUILD
-- ===========================================================================
local function build()
    frame = CreateFrame("Frame", "LongLivePetsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(780, 560)
    frame:SetPoint("CENTER")
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
    -- opaque backing so the world doesn't show through the window
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 6, -6); bg:SetPoint("BOTTOMRIGHT", -6, 6)
    bg:SetColorTexture(0.04, 0.04, 0.06, 1)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26); icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\AddOns\\LongLivePets\\Textures\\icon.png")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0); title:SetText("Long Live Pets")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- framing around each column for readability
    local function columnFrame(x1, x2)
        local c = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        c:SetPoint("TOPLEFT", x1, -34)
        c:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", x2, 12)
        if c.SetBackdrop then
            c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            c:SetBackdropColor(0.03, 0.04, 0.06, 0.92)
            c:SetBackdropBorderColor(0.55, 0.5, 0.35, 0.9)
        end
        -- a gold divider under the column title for structure
        local div = c:CreateTexture(nil, "ARTWORK")
        div:SetPoint("TOPLEFT", 6, -23); div:SetPoint("TOPRIGHT", -6, -23); div:SetHeight(1)
        div:SetColorTexture(0.55, 0.45, 0.2, 0.7)
        return c
    end
    columnFrame(10, 248)    -- Collection
    columnFrame(252, 484)   -- Loaded Team
    columnFrame(488, 772)   -- Teams / Queue

    UI:BuildCollection()
    UI:BuildLoadout()
    UI:BuildMoves()
    UI:BuildTeams()
    UI:BuildImportExport()
    UI:BuildRenameDialog()
    UI:BuildMenu()
end

-- ---- rename popup (groups + teams) ----------------------------------------
function UI:BuildRenameDialog()
    local p = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    p:SetSize(280, 96); p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG")
    if p.SetBackdrop then
        p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        p:SetBackdropColor(0.05, 0.05, 0.07, 1); p:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", 0, -12); p.title:SetText("Rename")
    p.edit = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    p.edit:SetSize(230, 22); p.edit:SetPoint("TOP", 0, -36); p.edit:SetAutoFocus(true); p.edit:SetMaxLetters(40)
    p.accept = btn(p, "OK", 80, 22); p.accept:SetPoint("BOTTOMRIGHT", -16, 12)
    p.accept:SetScript("OnClick", function()
        local v = p.edit:GetText(); p:Hide()
        if p.cb and v and v ~= "" then p.cb(v) end
    end)
    local cancel = btn(p, "Cancel", 80, 22); cancel:SetPoint("RIGHT", p.accept, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() p:Hide() end)
    p.edit:SetScript("OnEnterPressed", function() p.accept:Click() end)
    p.edit:SetScript("OnEscapePressed", function() p:Hide() end)
    p:Hide()
    frame.renameDialog = p
end

function UI:PromptText(title, current, onAccept)
    if not frame then build() end
    local p = frame.renameDialog
    p.title:SetText(title or "Edit")
    p.cb = onAccept
    p.edit:SetText(current or ""); p.edit:SetFocus(); p.edit:HighlightText()
    p:Show()
end

-- ---- reusable right-click context menu ------------------------------------
function UI:BuildMenu()
    local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetWidth(150)
    if m.SetBackdrop then
        m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        m:SetBackdropColor(0.05, 0.05, 0.07, 1); m:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    end
    m.buttons = {}
    for i = 1, 7 do
        local b = CreateFrame("Button", nil, m)
        b:SetSize(142, 18); b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 6, 0); b.text:SetJustifyH("LEFT")
        b:Hide(); m.buttons[i] = b
    end
    m:SetScript("OnHide", function() m:Hide() end)
    m:Hide()
    frame.ctxMenu = m
end

function UI:ShowMenu(items)
    if not frame then build() end
    local m = frame.ctxMenu
    for i, b in ipairs(m.buttons) do
        local it = items[i]
        if it then
            b.text:SetText(it.text)
            b:SetScript("OnClick", function() m:Hide(); it.fn() end)
            b:Show()
        else b:Hide() end
    end
    m:SetHeight(#items * 18 + 8)
    local x, y = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    m:Show()
end

-- ---- COLLECTION (left) ----------------------------------------------------
function UI:BuildCollection()
    panelTitle(frame, "Collection", 16)

    local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetSize(150, 20); search:SetPoint("TOPLEFT", 16, -60)
    search:SetScript("OnTextChanged", function(self) state.search = self:GetText() or ""; UI:RefreshCollection() end)
    frame.search = search

    local modeBtn = btn(frame, "name", 60, 20)
    modeBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    modeBtn:SetScript("OnClick", function()
        state.mode = state.mode == "name" and "ability" or "name"
        modeBtn:SetText(state.mode); UI:RefreshCollection()
    end)

    -- Type dropdown (All + the 10 families)
    local typeOpts = { { text = "Type: All", value = nil } }
    for i = 1, 10 do typeOpts[#typeOpts + 1] = { text = ns.Types.NAME[i], value = i } end
    local typeDD = makeDropdown(frame, 110, typeOpts, function(v)
        state.typeIndex = v; UI:RefreshCollection()
    end, "Type: All")
    typeDD:SetPoint("TOPLEFT", 16, -84)

    -- Level dropdown
    local levelDD = makeDropdown(frame, 108, {
        { text = "All levels", value = "all" },
        { text = "Level 25", value = "max" },
        { text = "Leveling (1-24)", value = "low" },
    }, function(v)
        state.maxOnly = (v == "max"); state.maxLevel = (v == "low") and 24 or nil
        UI:RefreshCollection()
    end, "All levels")
    levelDD:SetPoint("LEFT", typeDD, "RIGHT", 6, 0)

    -- More filters dropdown (its own row, so the filter bar stays in-column)
    local moreDD = makeDropdown(frame, 110, {
        { text = "All pets", value = "all" },
        { text = "Marked only", value = "marked" },
        { text = "Rare+ only", value = "rare" },
    }, function(v)
        state.markedOnly = (v == "marked"); state.rarity = (v == "rare") and 4 or nil
        UI:RefreshCollection()
    end, "Filter: all")
    moreDD:SetPoint("TOPLEFT", 16, -108)

    -- Counter dropdown: Strong Vs / Tough Vs a chosen enemy type
    local counterOpts = { { text = "Counter: off", value = nil } }
    for i = 1, 10 do counterOpts[#counterOpts + 1] = { text = "Strong vs " .. ns.Types.NAME[i], value = { mode = "strong", t = i } } end
    for i = 1, 10 do counterOpts[#counterOpts + 1] = { text = "Tough vs " .. ns.Types.NAME[i], value = { mode = "tough", t = i } } end
    local counterDD = makeDropdown(frame, 110, counterOpts, function(v)
        if not v then state.strongVs = nil; state.toughVs = nil
        elseif v.mode == "strong" then state.strongVs = v.t; state.toughVs = nil
        else state.toughVs = v.t; state.strongVs = nil end
        UI:RefreshCollection()
    end, "Counter: off")
    counterDD:SetPoint("LEFT", moreDD, "RIGHT", 6, 0)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 16, -134); list:SetSize(210, ROW_H * COL_ROWS)
    list:EnableMouseWheel(true)
    for i = 1, COL_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(18, 18); ico:SetPoint("LEFT", 0, 0); row.ico = ico
        local mk = row:CreateTexture(nil, "OVERLAY"); mk:SetSize(14, 14); mk:SetPoint("LEFT", ico, "RIGHT", 2, 0); row.mk = mk
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nm:SetPoint("LEFT", mk, "RIGHT", 3, 0); nm:SetPoint("RIGHT", 0, 0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false); row.nm = nm

        row:SetScript("OnClick", function(self, mouse)
            if not self.pet then return end
            if mouse == "RightButton" then
                ns.Markers:Cycle(self.pet.speciesID)
            else
                -- fill the active slot and show that pet's card + moves
                state.selectedPet = self.pet
                placePet(self.pet, state.activeSlot)
                UI:ShowCard(self.pet)
            end
        end)
        row:SetScript("OnEnter", function(self) if self.pet then UI:ShowCard(self.pet) end end)
        row:Hide(); colRows[i] = row
    end
    frame.colEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.colEmpty:SetPoint("TOP", 0, -8); frame.colEmpty:SetText("No pets match.")

    -- scrollbar + mouse wheel
    local sb = CreateFrame("Slider", nil, frame)
    sb:SetOrientation("VERTICAL"); sb:SetWidth(14)
    sb:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, 0)
    sb:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 2, 0)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(1); sb:SetObeyStepOnDrag(true)
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = sb:GetThumbTexture(); if thumb and thumb.SetSize then thumb:SetSize(14, 26) end
    sb:SetScript("OnValueChanged", function(_, value)
        state.colOffset = math.floor((value or 0) + 0.5); UI:RenderCollection()
    end)
    frame.colSlider = sb

    local function wheel(_, delta) sb:SetValue((sb:GetValue() or 0) - delta) end
    list:SetScript("OnMouseWheel", wheel)
    for _, row in ipairs(colRows) do
        row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", wheel)
    end
end

-- ---- LOADED TEAM (center) -------------------------------------------------
function UI:BuildLoadout()
    panelTitle(frame, "Loaded Team", 250)
    frame.slots = {}
    for s = 1, 3 do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(44, 44); b:SetPoint("TOPLEFT", 250 + (s - 1) * 52, -60)
        b:RegisterForClicks("LeftButtonUp")
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        b.ico = b:CreateTexture(nil, "ARTWORK"); b.ico:SetSize(38, 38); b.ico:SetPoint("CENTER")
        b:SetScript("OnClick", function()
            -- if a pet is on the cursor, drop it here; otherwise make this the active slot
            if not dropCursorPet(s) then state.activeSlot = s; UI:RefreshLoadout() end
        end)
        b:SetScript("OnReceiveDrag", function() dropCursorPet(s) end)
        frame.slots[s] = b
    end

    local nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameBox:SetSize(150, 20); nameBox:SetPoint("TOPLEFT", 250, -116); nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(40)
    frame.nameBox = nameBox
    local save = btn(frame, "Save", 60, 20); save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    save:SetScript("OnClick", function()
        local n = nameBox:GetText(); if n and n ~= "" then ns.Teams:SaveCurrent(n); nameBox:SetText("") end
    end)
    local reload = btn(frame, "Reload", 70, 20); reload:SetPoint("TOPLEFT", 250, -140)
    reload:SetScript("OnClick", function() ns.Teams:Reload() end)
    -- Build Counter lives at the bottom of the center column
    local build = btn(frame, "Build Counter", 150, 22); build:SetPoint("BOTTOMLEFT", 250, 40)
    build:SetScript("OnClick", function() UI:BuildCounter() end)

    -- counter / card area (below the moves picker)
    local strip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    strip:SetPoint("TOPLEFT", 250, -290); strip:SetWidth(212); strip:SetJustifyH("LEFT"); strip:SetSpacing(2)
    strip:SetText("Hover a pet for its card.\nClick a pet to slot it.")
    frame.strip = strip

    frame.counterLoad = btn(frame, "Load these picks", 130, 20)
    frame.counterLoad:SetPoint("BOTTOMLEFT", 250, 16); frame.counterLoad:Hide()
end

-- ---- MOVES picker (center, below the buttons) -----------------------------
function UI:BuildMoves()
    frame.movesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.movesLabel:SetPoint("TOPLEFT", 250, -166); frame.movesLabel:SetText("Moves")

    frame.moveBtns = {}
    for i = 1, 3 do
        frame.moveBtns[i] = {}
        for j = 1, 2 do
            local b = CreateFrame("Button", nil, frame)
            b:SetSize(30, 30)
            -- 3 ability slots across (i), the two options stacked below (j) —
            -- matches the in-battle ability bar.
            b:SetPoint("TOPLEFT", 250 + (i - 1) * 40, -184 - (j - 1) * 34)
            b.ico = b:CreateTexture(nil, "ARTWORK"); b.ico:SetAllPoints()
            b.sel = b:CreateTexture(nil, "OVERLAY")
            b.sel:SetPoint("TOPLEFT", -2, 2); b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
            b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight"); b.sel:SetBlendMode("ADD"); b.sel:Hide()
            b:SetScript("OnClick", function(self)
                if self.abilityID and not self.locked then
                    ns.Abilities:Set(state.activeSlot, i, self.abilityID)
                    UI:RefreshMoves()
                end
            end)
            b:SetScript("OnEnter", function(self)
                if self.ability then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.ability.name)
                    if self.locked then GameTooltip:AddLine("Unlocks at level " .. (self.ability.reqLevel or "?"), 1, .3, .3) end
                    if self.ability.desc then GameTooltip:AddLine(self.ability.desc, .9, .9, .9, true) end
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            frame.moveBtns[i][j] = b
        end
    end
end

function UI:RefreshMoves()
    if not frame or not frame.moveBtns then return end
    local slots = ns.Abilities:GetLayout(state.activeSlot)
    frame.movesLabel:SetText(slots and ("Moves — slot " .. state.activeSlot .. " (click to choose)") or "Moves — slot is empty")
    for i = 1, 3 do
        for j = 1, 2 do
            local b = frame.moveBtns[i][j]
            local opt = slots and slots[i] and slots[i][j]
            if opt then
                b.abilityID = opt.id; b.ability = opt; b.locked = opt.locked
                b.ico:SetTexture(opt.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                b.ico:SetDesaturated(opt.locked and true or false)
                b:SetAlpha(opt.locked and 0.4 or 1)
                b.sel:SetShown(opt.selected and true or false)
                b:Show()
            else
                b.abilityID = nil; b.ability = nil; b:Hide()
            end
        end
    end
end

-- ---- TEAMS / QUEUE (right) ------------------------------------------------
function UI:BuildTeams()
    panelTitle(frame, "Teams", 500)

    -- Teams / Queue toggle + New Group (top of the panel)
    local teamsTab = btn(frame, "Teams", 60, 18); teamsTab:SetPoint("TOPLEFT", 500, -58); frame.teamsTab = teamsTab
    local queueTab = btn(frame, "Queue", 60, 18); queueTab:SetPoint("LEFT", teamsTab, "RIGHT", 4, 0); frame.queueTab = queueTab
    local newG = btn(frame, "+ New Group", 100, 18); newG:SetPoint("LEFT", queueTab, "RIGHT", 6, 0)
    teamsTab:SetScript("OnClick", function() state.rightMode = "teams"; UI:RefreshRight() end)
    queueTab:SetScript("OnClick", function() state.rightMode = "queue"; UI:RefreshRight() end)
    newG:SetScript("OnClick", function()
        UI:PromptText("New group name", "", function(n) if n and n ~= "" then ns.Groups:Create(n) end end)
    end)

    frame.teamsHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.teamsHint:SetPoint("TOPLEFT", 500, -80)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 500, -96); list:SetSize(262, ROW_H * TEAM_ROWS)
    for i = 1, TEAM_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(16, 16); ico:SetPoint("LEFT", 0, 0); row.ico = ico
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nm:SetPoint("LEFT", 20, 0); nm:SetPoint("RIGHT", -62, 0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false); row.nm = nm
        local up  = btn(row, "^", 18, 18); up:SetPoint("RIGHT", -40, 0); row.up = up
        local dn  = btn(row, "v", 18, 18); dn:SetPoint("RIGHT", -20, 0); row.dn = dn
        local del = btn(row, "X", 18, 18); del:SetPoint("RIGHT", 0, 0); row.del = del
        row:Hide(); teamRows[i] = row
    end
    frame.teamsEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.teamsEmpty:SetPoint("TOP", 0, -8)

    local ie = btn(frame, "Import/Export", 110, 20); ie:SetPoint("BOTTOMLEFT", 500, 40)
    ie:SetScript("OnClick", function() UI:ShowText("Backup — copy, or paste to import", "both", ns.Serialize:BackupAll()) end)

    -- share row
    local sendBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    sendBox:SetSize(120, 20); sendBox:SetPoint("BOTTOMLEFT", 500, 16); sendBox:SetAutoFocus(false)
    frame.sendBox = sendBox
    local send = btn(frame, "Send selected", 100, 20); send:SetPoint("LEFT", sendBox, "RIGHT", 6, 0)
    send:SetScript("OnClick", function()
        if not state.selectedTeam then ns:Print("Select a team first (click its name)."); return end
        local who = sendBox:GetText()
        ns.Comm:Send(state.selectedTeam, who); sendBox:SetText("")
    end)
end

-- ---- inline import/export panel ------------------------------------------
function UI:BuildImportExport()
    local p = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    p:SetPoint("CENTER"); p:SetSize(420, 220); p:SetFrameStrata("DIALOG")
    if p.SetBackdrop then
        p:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.title:SetPoint("TOP", 0, -12)
    local scroll = CreateFrame("ScrollFrame", nil, p, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -34); scroll:SetPoint("BOTTOMRIGHT", -30, 40)
    p.edit = scroll.EditBox or scroll:GetScrollChild()
    if p.edit then p.edit:SetWidth(360) end
    p.imp = btn(p, "Import", 90, 22); p.imp:SetPoint("BOTTOMLEFT", 14, 12)
    p.imp:SetScript("OnClick", function()
        local v = p.edit and p.edit:GetText() or ""
        local n, err = ns.Serialize:Import(v)
        ns:Print(n and ("Imported " .. n .. " team(s).") or err); p:Hide()
    end)
    local cls = CreateFrame("Button", nil, p, "UIPanelCloseButton"); cls:SetPoint("TOPRIGHT", -4, -4)
    p:Hide()
    frame.iePanel = p
end

function UI:ShowText(titleText, mode, text)
    if not frame then build() end
    local p = frame.iePanel
    p.title:SetText(titleText)
    if p.edit then p.edit:SetText(text or ""); p.edit:SetFocus(); if mode == "export" then p.edit:HighlightText() end end
    p.imp:SetShown(mode ~= "export")
    p:Show()
end

-- ===========================================================================
-- REFRESH
-- ===========================================================================
function UI:ShowCard(pet)
    if not frame or not pet then return end
    local out = {}
    for _, l in ipairs(ns.PetCard:BuildLines(pet)) do
        if l.kind == "double" then out[#out + 1] = l.left .. ": " .. l.right
        elseif l.kind ~= "gap" then out[#out + 1] = l.text end
    end
    frame.strip:SetText(table.concat(out, "\n"))
end

-- Render the visible window of colPets starting at state.colOffset.
function UI:RenderCollection()
    if not frame then return end
    local off = state.colOffset or 0
    for i, row in ipairs(colRows) do
        local p = colPets[i + off]
        if p then
            row.pet = p
            if p.icon then row.ico:SetTexture(p.icon) end
            row.mk:SetTexture(p.marker and ns.Markers:Texture(p.marker) or nil)
            row.nm:SetText(("%s |cffaaaaaaL%d %s|r"):format(p.name, p.level, ns.Types.NAME[p.petType] or "?"))
            row:Show()
        else row.pet = nil; row:Hide() end
    end
end

function UI:RefreshCollection()
    if not frame then return end
    local opts = {
        maxOnly = state.maxOnly, maxLevel = state.maxLevel, typeIndex = state.typeIndex,
        markedOnly = state.markedOnly, rarity = state.rarity,
        strongVs = state.strongVs, toughVs = state.toughVs,
    }
    if state.mode == "ability" then opts.ability = state.search else opts.search = state.search end
    colPets = ns.Roster:Filter(opts)
    frame.colEmpty:SetShown(#colPets == 0)

    local maxOff = math.max(0, #colPets - COL_ROWS)
    if (state.colOffset or 0) > maxOff then state.colOffset = maxOff end
    if frame.colSlider then
        frame.colSlider:SetMinMaxValues(0, maxOff)
        frame.colSlider:SetValue(state.colOffset or 0)
    end
    self:RenderCollection()
end

function UI:RefreshLoadout()
    if not frame then return end
    for s, b in ipairs(frame.slots) do
        local petID = C_PetJournal.GetPetLoadOutInfo(s)
        local icon = petID and select(9, C_PetJournal.GetPetInfoByPetID(petID))
        b.ico:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if s == state.activeSlot then b:LockHighlight() else b:UnlockHighlight() end
    end
    local id = ns.db and ns.db.loaded
    frame.nameBox:SetText(id and ns.db.teams[id] and ns.db.teams[id].name or "")
    self:RefreshMoves()
end

-- Right column dispatches to Teams or Queue.
function UI:RefreshRight()
    if not frame then return end
    if frame.teamsTab then
        if state.rightMode == "queue" then frame.teamsTab:UnlockHighlight(); frame.queueTab:LockHighlight()
        else frame.teamsTab:LockHighlight(); frame.queueTab:UnlockHighlight() end
    end
    if state.rightMode == "queue" then self:RefreshQueue() else self:RefreshTeams() end
end

function UI:RefreshQueue()
    if not frame then return end
    frame.teamsHint:SetText("Your leveling queue. X removes a pet.")
    local q = ns.Queue:Pending()
    frame.teamsEmpty:SetShown(#q == 0)
    if #q == 0 then frame.teamsEmpty:SetText("Queue is empty.\n/llp queue add <slot 1-3>") end
    for i, row in ipairs(teamRows) do
        local petID = q[i]
        if petID then
            local _, _, level, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(petID)
            row.ico:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark"); row.ico:Show()
            row.nm:SetText(("%d. %s |cffaaaaaaL%s|r"):format(i, name or "pet", tostring(level or "?")))
            row.up:Hide(); row.dn:Hide()
            row.del:SetScript("OnClick", function() ns.Queue:Remove(petID) end)
            row.del:Show()
            row:SetScript("OnClick", nil)
            row:Show()
        else
            row:Hide()
        end
    end
end

function UI:RefreshTeams()
    if not frame then return end
    frame.teamsHint:SetText("Click to select. Right-click for options. Click a group to move there.")
    -- flat display list (group headers + teams), reused from team list
    local groups, teams = ns.Groups:List(), ns.Teams:List()
    local byGroup, ungrouped = {}, {}
    for _, t in ipairs(teams) do
        if t.group then byGroup[t.group] = byGroup[t.group] or {}; table.insert(byGroup[t.group], t)
        else table.insert(ungrouped, t) end
    end
    -- Show EVERY group as a header (even empty), then the Ungrouped bucket.
    -- Clicking a header moves the currently-selected team into that group.
    local disp = {}
    for _, g in ipairs(groups) do
        disp[#disp + 1] = { header = true, name = g.name, groupID = g.id }
        for _, t in ipairs(byGroup[g.id] or {}) do disp[#disp + 1] = { team = t } end
    end
    -- Ungrouped header always present (so you can move teams back out), unless
    -- there are no groups at all (then ungrouped teams just list plainly).
    if #groups > 0 then disp[#disp + 1] = { header = true, name = "Ungrouped", groupID = nil } end
    for _, t in ipairs(ungrouped) do disp[#disp + 1] = { team = t } end

    frame.teamsEmpty:SetShown(#teams == 0 and #groups == 0)
    for i, row in ipairs(teamRows) do
        local d = disp[i]
        if not d then
            row:Hide()
        elseif d.header then
            row.ico:Hide()
            local hint = state.selectedTeam and "  |cff44ff44← move here|r" or ""
            row.nm:SetText("|cffffd100" .. d.name .. "|r" .. hint)
            row.up:Hide(); row.dn:Hide()
            if d.groupID then           -- real group: offer a delete button
                row.del:SetScript("OnClick", function() ns.Groups:Delete(d.groupID) end)
                row.del:Show()
            else                        -- "Ungrouped" can't be deleted
                row.del:Hide()
            end
            row:SetScript("OnClick", function(_, mouse)
                if mouse == "RightButton" then
                    if d.groupID then
                        UI:ShowMenu({
                            { text = "Rename group", fn = function() UI:PromptText("Rename group", d.name, function(n) ns.Groups:Rename(d.groupID, n) end) end },
                            { text = "Delete group", fn = function() ns.Groups:Delete(d.groupID) end },
                        })
                    end
                elseif state.selectedTeam then
                    ns.Groups:Assign(state.selectedTeam, d.groupID)
                else
                    ns:Print("Click a team first to select it, then click a group to move it.")
                end
            end)
            row:Show()
        else
            local t = d.team
            row.ico:Hide()
            local label = t.name
            if t.loaded then label = "|cff44ff44>|r " .. label end
            if (t.wins + t.losses) > 0 then label = label .. (" |cffaaaaaa%d-%d|r"):format(t.wins, t.losses) end
            if t.script then label = label .. " |cff8ec5ff(s)|r" end
            if t.notes then label = label .. " |cffd0a0ff(n)|r" end
            if state.selectedTeam == t.id then label = "|cffffffff[" .. label .. "]|r" end
            row.nm:SetText(label)
            row:SetScript("OnClick", function(_, mouse)
                if mouse == "RightButton" then
                    local team = ns.db.teams[t.id]
                    UI:ShowMenu({
                        { text = "Load", fn = function() ns.Teams:Load(t.id) end },
                        { text = "Rename", fn = function() UI:PromptText("Rename team", t.name, function(n) ns.Teams:Rename(t.id, n) end) end },
                        { text = "Edit note", fn = function() UI:PromptText("Note for " .. t.name, team and team.notes or "", function(v) ns.Teams:SetNotes(t.id, v) end) end },
                        { text = "Set / edit script", fn = function() UI:PromptText("Script name for " .. t.name, team and team.script or "", function(v) ns.Integration:SetScript(t.id, v) end) end },
                        { text = "Test script", fn = function() ns.Integration:Test(t.id) end },
                        { text = "Delete", fn = function() ns.Teams:Delete(t.id) end },
                    })
                else
                    state.selectedTeam = t.id; ns.Teams:Load(t.id); UI:RefreshRight()
                end
            end)
            row.up:SetScript("OnClick", function() UI:MoveTeam(t, -1) end)
            row.dn:SetScript("OnClick", function() UI:MoveTeam(t, 1) end)
            row.del:SetScript("OnClick", function() ns.Teams:Delete(t.id) end)
            row.up:Show(); row.dn:Show(); row.del:Show(); row:Show()
        end
    end
end

-- move a team up/down within its bucket
function UI:MoveTeam(t, delta)
    local bucket = {}
    for _, x in ipairs(ns.Teams:List()) do if x.group == t.group then bucket[#bucket + 1] = x.id end end
    local idx
    for i, id in ipairs(bucket) do if id == t.id then idx = i end end
    if idx then ns.Teams:Reorder(t.id, t.group, idx + delta) end
end

function UI:BuildCounter()
    local intel, npcID = ns.EnemyIntel:GetForCurrentTarget()
    if not intel and state.selectedTeam then
        local team = ns.db.teams[state.selectedTeam]
        if team and team.targets then for n in pairs(team.targets) do intel = ns.EnemyIntel:Get(n); if intel then break end end end
    end
    if not intel then
        frame.strip:SetText("No enemy intel yet.\nFight a tamer once and I'll learn\ntheir team, then Build Counter.")
        frame.counterLoad:Hide(); return
    end
    local res = ns.CounterBuilder:Build(intel, ns.Roster:GetOwnedPets())
    local lines = { ("Counter for %s (covers %d/%d):"):format(intel.name or "target", res.covered, res.total) }
    for _, p in ipairs(res.picks) do
        lines[#lines + 1] = "• " .. p.pet.name .. (p.reasons[1] and (" — " .. p.reasons[1]) or "")
    end
    frame.strip:SetText(table.concat(lines, "\n"))
    frame.counterLoad:Show()
    frame.counterLoad:SetScript("OnClick", function()
        for s, p in ipairs(res.picks) do if s <= 3 then ns.Roster:SlotPet(p.pet.petID, s) end end
        ns:Print("Loaded the counter picks."); UI:RefreshLoadout()
    end)
end

function UI:Refresh()
    if not frame then return end
    self:RefreshCollection(); self:RefreshRight(); self:RefreshLoadout()
end

function UI:Toggle()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); self:Refresh() end
end
function UI:Show()
    if not frame then build() end
    frame:Show(); self:Refresh()
end
