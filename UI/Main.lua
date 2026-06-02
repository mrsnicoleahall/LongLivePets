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
local state = {
    activeSlot = 1, search = "", typeIndex = nil, maxOnly = false,
    mode = "name", markedOnly = false,
    selectedTeam = nil, selectedPet = nil,
}

-- ---- drag support ---------------------------------------------------------
local pendingDrag, dragFrame
local function startDrag(pet)
    pendingDrag = pet
    if not dragFrame then
        dragFrame = CreateFrame("Frame", nil, UIParent)
        dragFrame:SetSize(28, 28); dragFrame:SetFrameStrata("TOOLTIP")
        dragFrame.tex = dragFrame:CreateTexture(nil, "OVERLAY")
        dragFrame.tex:SetAllPoints()
        dragFrame:Hide()
    end
    dragFrame.tex:SetTexture(pet.icon)
    dragFrame:Show()
    dragFrame:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        dragFrame:ClearAllPoints()
        dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
end
local function stopDrag()
    pendingDrag = nil
    if dragFrame then dragFrame:Hide(); dragFrame:SetScript("OnUpdate", nil) end
end
local function placePet(pet, slot)
    if not pet then return end
    ns.Roster:SlotPet(pet.petID, slot)
    ns:Print(("Put %s into slot %d."):format(pet.name, slot))
    UI:RefreshLoadout()
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

-- ===========================================================================
-- BUILD
-- ===========================================================================
local function build()
    frame = CreateFrame("Frame", "LongLivePetsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(720, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    -- a global mouse-up ends a drag that was dropped on nothing
    frame:SetScript("OnMouseUp", function() if pendingDrag then stopDrag() end end)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26); icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\AddOns\\LongLivePets\\Textures\\icon.png")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0); title:SetText("Long Live Pets")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    UI:BuildCollection()
    UI:BuildLoadout()
    UI:BuildTeams()
    UI:BuildImportExport()
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

    local typeBtn = btn(frame, "Type: All", 110, 20); typeBtn:SetPoint("TOPLEFT", 16, -84)
    typeBtn:SetScript("OnClick", function()
        local i = (state.typeIndex or 0) + 1; if i > 10 then i = nil end
        state.typeIndex = i; typeBtn:SetText("Type: " .. (i and ns.Types.NAME[i] or "All")); UI:RefreshCollection()
    end)
    local maxBtn = btn(frame, "Lv25", 50, 20); maxBtn:SetPoint("LEFT", typeBtn, "RIGHT", 6, 0)
    maxBtn:SetScript("OnClick", function() state.maxOnly = not state.maxOnly; maxBtn:SetText(state.maxOnly and "Lv25*" or "Lv25"); UI:RefreshCollection() end)
    local markBtn = btn(frame, "★", 28, 20); markBtn:SetPoint("LEFT", maxBtn, "RIGHT", 6, 0)
    markBtn:SetScript("OnClick", function() state.markedOnly = not state.markedOnly; UI:RefreshCollection() end)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 16, -110); list:SetSize(218, ROW_H * COL_ROWS)
    for i = 1, COL_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:RegisterForDrag("LeftButton")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(18, 18); ico:SetPoint("LEFT", 0, 0); row.ico = ico
        local mk = row:CreateTexture(nil, "OVERLAY"); mk:SetSize(14, 14); mk:SetPoint("LEFT", ico, "RIGHT", 2, 0); row.mk = mk
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nm:SetPoint("LEFT", mk, "RIGHT", 3, 0); nm:SetPoint("RIGHT", 0, 0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false); row.nm = nm

        row:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then
                ns.Markers:Cycle(self.pet.speciesID)
            else
                state.selectedPet = self.pet; placePet(self.pet, state.activeSlot); UI:ShowCard(self.pet)
            end
        end)
        row:SetScript("OnDragStart", function(self) if self.pet then startDrag(self.pet) end end)
        row:SetScript("OnEnter", function(self) if self.pet then UI:ShowCard(self.pet) end end)
        row:Hide(); colRows[i] = row
    end
    frame.colEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.colEmpty:SetPoint("TOP", 0, -8); frame.colEmpty:SetText("No pets match.")
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
        b:SetScript("OnClick", function() state.activeSlot = s; UI:RefreshLoadout() end)
        b:SetScript("OnReceiveDrag", function() if pendingDrag then placePet(pendingDrag, s); stopDrag() end end)
        b:SetScript("OnMouseUp", function() if pendingDrag then placePet(pendingDrag, s); stopDrag() end end)
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
    local build = btn(frame, "\226\154\148 Build Counter", 130, 20); build:SetPoint("LEFT", reload, "RIGHT", 6, 0)
    build:SetScript("OnClick", function() UI:BuildCounter() end)

    -- counter / card area
    local strip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    strip:SetPoint("TOPLEFT", 250, -168); strip:SetWidth(210); strip:SetJustifyH("LEFT"); strip:SetSpacing(2)
    strip:SetText("Hover a pet for its card.\nClick a pet to slot it.")
    frame.strip = strip

    frame.counterLoad = btn(frame, "Load these picks", 130, 20)
    frame.counterLoad:SetPoint("BOTTOMLEFT", 250, 16); frame.counterLoad:Hide()
end

-- ---- TEAMS (right) --------------------------------------------------------
function UI:BuildTeams()
    panelTitle(frame, "Teams", 478)
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 478, -60); list:SetSize(226, ROW_H * TEAM_ROWS)
    for i = 1, TEAM_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nm:SetPoint("LEFT", 2, 0); nm:SetPoint("RIGHT", -78, 0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false); row.nm = nm
        local up = btn(row, "\225\131\157", 18, 18); up:SetPoint("RIGHT", -60, 0); row.up = up
        local dn = btn(row, "\225\131\158", 18, 18); dn:SetPoint("RIGHT", -42, 0); row.dn = dn
        local del = btn(row, "\195\151", 18, 18); del:SetPoint("RIGHT", -2, 0); row.del = del
        local sh = btn(row, "\226\135\132", 18, 18); sh:SetPoint("RIGHT", -22, 0); row.sh = sh
        row:Hide(); teamRows[i] = row
    end
    frame.teamsEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.teamsEmpty:SetPoint("TOP", 0, -8); frame.teamsEmpty:SetText("No teams yet.\nSlot pets, name it, Save.")

    local newG = btn(frame, "+ Group", 80, 20); newG:SetPoint("BOTTOMLEFT", 478, 40)
    newG:SetScript("OnClick", function() ns.Groups:Create("New Group") end)
    local ie = btn(frame, "Import/Export", 110, 20); ie:SetPoint("LEFT", newG, "RIGHT", 6, 0)
    ie:SetScript("OnClick", function() UI:ShowText("Backup — copy, or paste to import", "both", ns.Serialize:BackupAll()) end)

    -- share row
    local sendBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    sendBox:SetSize(120, 20); sendBox:SetPoint("BOTTOMLEFT", 478, 16); sendBox:SetAutoFocus(false)
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

function UI:RefreshCollection()
    if not frame then return end
    local opts = { maxOnly = state.maxOnly, typeIndex = state.typeIndex, markedOnly = state.markedOnly }
    if state.mode == "ability" then opts.ability = state.search else opts.search = state.search end
    local pets = ns.Roster:Filter(opts)
    frame.colEmpty:SetShown(#pets == 0)
    for i, row in ipairs(colRows) do
        local p = pets[i]
        if p then
            row.pet = p
            if p.icon then row.ico:SetTexture(p.icon) end
            row.mk:SetTexture(p.marker and ns.Markers:Texture(p.marker) or nil)
            row.nm:SetText(("%s |cffaaaaaaL%d %s|r"):format(p.name, p.level, ns.Types.NAME[p.petType] or "?"))
            row:Show()
        else row.pet = nil; row:Hide() end
    end
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
end

function UI:RefreshTeams()
    if not frame then return end
    -- flat display list (group headers + teams), reused from team list
    local groups, teams = ns.Groups:List(), ns.Teams:List()
    local byGroup, ungrouped = {}, {}
    for _, t in ipairs(teams) do
        if t.group then byGroup[t.group] = byGroup[t.group] or {}; table.insert(byGroup[t.group], t)
        else table.insert(ungrouped, t) end
    end
    local disp = {}
    for _, g in ipairs(groups) do
        if byGroup[g.id] then
            disp[#disp + 1] = { header = true, name = g.name }
            for _, t in ipairs(byGroup[g.id]) do disp[#disp + 1] = { team = t } end
        end
    end
    if #ungrouped > 0 then
        if next(byGroup) then disp[#disp + 1] = { header = true, name = "Ungrouped" } end
        for _, t in ipairs(ungrouped) do disp[#disp + 1] = { team = t } end
    end

    frame.teamsEmpty:SetShown(#teams == 0)
    for i, row in ipairs(teamRows) do
        local d = disp[i]
        if not d then row:Hide()
        elseif d.header then
            row.nm:SetText("|cffffd100" .. d.name .. "|r")
            row.up:Hide(); row.dn:Hide(); row.del:Hide(); row.sh:Hide(); row:Show()
        else
            local t = d.team
            local label = t.name
            if t.loaded then label = "|cff44ff44>|r " .. label end
            if (t.wins + t.losses) > 0 then label = label .. (" |cffaaaaaa%d-%d|r"):format(t.wins, t.losses) end
            if state.selectedTeam == t.id then label = "|cffffffff[" .. label .. "]|r" end
            row.nm:SetText(label)
            row:SetScript("OnClick", function() state.selectedTeam = t.id; ns.Teams:Load(t.id) end)
            row.up:SetScript("OnClick", function() UI:MoveTeam(t, -1) end)
            row.dn:SetScript("OnClick", function() UI:MoveTeam(t, 1) end)
            row.del:SetScript("OnClick", function() ns.Teams:Delete(t.id) end)
            row.sh:SetScript("OnClick", function() state.selectedTeam = t.id; ns:Print('Selected "' .. t.name .. '" — type a name and click Send.') end)
            row.up:Show(); row.dn:Show(); row.del:Show(); row.sh:Show(); row:Show()
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
    self:RefreshCollection(); self:RefreshTeams(); self:RefreshLoadout()
end

function UI:Toggle()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); self:Refresh() end
end
function UI:Show()
    if not frame then build() end
    frame:Show(); self:Refresh()
end
