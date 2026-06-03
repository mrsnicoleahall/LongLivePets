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

local COL_ROWS, TEAM_ROWS = 10, 10
local ROW_H = 38
local ICON_CROP = { 0.07, 0.93, 0.07, 0.93 }  -- trims the baked black border off icons

local frame
local colRows, teamRows = {}, {}
local colPets = {}            -- current filtered collection list
local rightDisp = {}          -- current right-panel display list (headers/teams/queue)
local state = {
    activeSlot = 1, search = "", typeIndex = nil, maxOnly = false, colOffset = 0,
    mode = "name", markedOnly = false, rightMode = "teams", rightOffset = 0,
    selectedTeam = nil, selectedPet = nil, collapsed = {},
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
    -- keep the button label clipped to the button so it never overflows
    local fs = dd.GetFontString and dd:GetFontString()
    if fs and fs.SetWidth then fs:SetWidth(w - 10); fs:SetWordWrap(false) end

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

    local y, maxW = 4, 0
    for _, opt in ipairs(options) do
        local ob = CreateFrame("Button", nil, menu)
        ob:SetHeight(18)
        ob:SetPoint("TOPLEFT", 4, -y); ob:SetPoint("RIGHT", menu, "RIGHT", -4, 0)  -- width follows menu
        ob:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local t = ob:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("LEFT", 6, 0); t:SetJustifyH("LEFT"); t:SetText(opt.text)
        local sw = t.GetStringWidth and t:GetStringWidth()
        if type(sw) == "number" and sw > maxW then maxW = sw end
        ob:SetScript("OnClick", function()
            dd:SetText(opt.short or opt.text); menu:Hide(); openMenu = nil
            onSelect(opt.value)
        end)
        y = y + 18
    end
    -- size the menu to its widest option so text never overflows the border
    menu:SetWidth(math.max(w, maxW + 24))
    menu:SetHeight(y + 4)

    dd:SetScript("OnClick", function()
        if openMenu and openMenu ~= menu then openMenu:Hide() end
        if menu:IsShown() then menu:Hide(); openMenu = nil
        else menu:Show(); openMenu = menu end
    end)
    return dd
end

-- rarity colors (1 poor .. 5 epic)
local RARITY_COLOR = {
    [1] = { .62, .62, .62 }, [2] = { 1, 1, 1 }, [3] = { .12, 1, 0 },
    [4] = { 0, .44, .87 }, [5] = { .64, .21, .93 },
}

-- Add rich decorations (rarity border, level badge, type icon, breed) to a row
-- that already has row.ico (texture) and row.nm (fontstring).
local function decoratePetRow(row)
    -- rarity ring around the portrait
    row.border = row:CreateTexture(nil, "BACKGROUND")
    row.border:SetPoint("TOPLEFT", row.ico, "TOPLEFT", -1, 1)
    row.border:SetPoint("BOTTOMRIGHT", row.ico, "BOTTOMRIGHT", 1, -1)
    row.border:Hide()
    -- level badge, bottom-right of the portrait
    row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.lvl:SetPoint("BOTTOMRIGHT", row.ico, "BOTTOMRIGHT", 3, -1)
    -- TYPE badge: a small color-coded pill (always crisp; readable on dark bg).
    row.typeBg = row:CreateTexture(nil, "ARTWORK")
    row.typeBg:SetColorTexture(0, 0, 0, 0.55)
    row.typeBg:SetSize(40, 16); row.typeBg:SetPoint("RIGHT", row, "RIGHT", -42, 0); row.typeBg:Hide()
    row.typeBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.typeBadge:SetPoint("CENTER", row.typeBg, "CENTER", 0, 0)
    row.typeBadge:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    -- breed (B/B, P/S …) on the far right
    row.breed = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.breed:SetPoint("RIGHT", row, "RIGHT", -6, 0); row.breed:SetWidth(32); row.breed:SetJustifyH("RIGHT")
end

-- render a pet into a decorated row.
local function renderPetRow(row, pet)
    local rc = RARITY_COLOR[pet.rarity or 2] or RARITY_COLOR[2]
    if pet.icon then row.ico:SetTexture(pet.icon) end
    row.ico:SetTexCoord(unpack(ICON_CROP)); row.ico:Show()
    row.border:SetColorTexture(rc[1], rc[2], rc[3], 1); row.border:Show()
    row.lvl:SetText(pet.level and tostring(pet.level) or ""); row.lvl:Show()
    row.nm:SetTextColor(rc[1], rc[2], rc[3])
    if pet.petType and ns.Types.ABBR[pet.petType] then
        local tc = ns.Types:Color(pet.petType)
        row.typeBadge:SetText(ns.Types:Abbr(pet.petType))
        row.typeBadge:SetTextColor(tc[1], tc[2], tc[3])
        row.typeBg:Show()
    else row.typeBg:Hide(); row.typeBadge:SetText("") end
    local breed = pet.breed or (ns.Breed and ns.Breed:Get(pet.petID))
    row.breed:SetText(breed or "")
end

-- hide the rich decorations (for header/team rows).
local function clearPetRow(row)
    if row.border then row.border:Hide() end
    if row.lvl then row.lvl:SetText("") end
    if row.typeBg then row.typeBg:Hide() end
    if row.typeBadge then row.typeBadge:SetText("") end
    if row.breed then row.breed:SetText("") end
    row.nm:SetTextColor(1, 1, 1)
end

-- ===========================================================================
-- BUILD
-- ===========================================================================
local function build()
    frame = CreateFrame("Frame", "LongLivePetsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(780, 600)
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
            -- transparent fill: the window already has an opaque dark bg; a
            -- tinted fill here renders OVER (and dims) the labels/stat text.
            c:SetBackdropColor(0, 0, 0, 0)
            c:SetBackdropBorderColor(0.55, 0.5, 0.35, 0.9)
        end
        -- gold divider under the (frame-level) header bar; thin line, won't
        -- cover the title text
        local div = c:CreateTexture(nil, "ARTWORK")
        div:SetPoint("TOPLEFT", 6, -24); div:SetPoint("TOPRIGHT", -6, -24); div:SetHeight(1)
        div:SetColorTexture(0.65, 0.52, 0.25, 0.9)
        return c
    end
    columnFrame(10, 248)    -- Collection
    columnFrame(252, 484)   -- Loaded Team
    columnFrame(488, 772)   -- Teams / Queue

    -- header bars live on the MAIN frame (BACKGROUND) so the titles, which are
    -- also on the main frame (OVERLAY), draw on top of them. (The columns have
    -- a transparent fill, so these show through.)
    local function headerBar(x1, x2)
        local hb = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        hb:SetPoint("TOPLEFT", frame, "TOPLEFT", x1 + 4, -38)
        hb:SetPoint("TOPRIGHT", frame, "TOPLEFT", x2 - 4, -38)
        hb:SetHeight(20); hb:SetColorTexture(0.16, 0.14, 0.09, 0.95)
    end
    headerBar(10, 248); headerBar(252, 484); headerBar(488, 772)

    UI:BuildCollection()
    UI:BuildLoadout()
    UI:BuildMoves()
    UI:BuildTeams()
    UI:BuildPetCare()
    UI:BuildImportExport()
    UI:BuildRenameDialog()
    UI:BuildMenu()
end

-- ---- Heal Pets + Pet Bandage (secure buttons in the title bar) ------------
-- Revive Battle Pets = spell 125439 (8-min cd). Battle Pet Bandage = item 86143.
local REVIVE_SPELL, BANDAGE_ITEM = 125439, 86143
function UI:BuildPetCare()
    local function spellInfo(id)
        if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(id); if i then return i.name, i.iconID end end
        if GetSpellInfo then local n, _, ic = GetSpellInfo(id); return n, ic end
    end
    local function spellCooldown(id)
        if C_Spell and C_Spell.GetSpellCooldown then
            local c = C_Spell.GetSpellCooldown(id); if c then return c.startTime, c.duration, c.isEnabled end
        elseif GetSpellCooldown then return GetSpellCooldown(id) end
    end
    local function itemCount(id) return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0 end
    local function itemIcon(id) return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) end

    -- Heal Pets
    local healName, healIcon = spellInfo(REVIVE_SPELL)
    local heal = CreateFrame("Button", "LongLivePetsHealBtn", frame, "SecureActionButtonTemplate")
    heal:SetSize(28, 28); heal:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -10)
    heal:SetAttribute("type", "spell"); heal:SetAttribute("spell", healName or "Revive Battle Pets")
    heal:RegisterForClicks("AnyUp", "AnyDown")
    local hi = heal:CreateTexture(nil, "ARTWORK"); hi:SetAllPoints(); hi:SetTexture(healIcon or 134376); hi:SetTexCoord(unpack(ICON_CROP))
    heal:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local hb = heal:CreateTexture(nil, "BACKGROUND"); hb:SetPoint("TOPLEFT", -1, 1); hb:SetPoint("BOTTOMRIGHT", 1, -1); hb:SetColorTexture(0.5, 0.4, 0.1, 1)
    heal.cd = CreateFrame("Cooldown", nil, heal, "CooldownFrameTemplate"); heal.cd:SetAllPoints()
    heal:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(healName or "Revive Battle Pets")
        GameTooltip:AddLine("Heal & revive all your battle pets (8-min cooldown).", .9, .9, .9, true)
        GameTooltip:Show()
    end)
    heal:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.healBtn = heal

    -- Pet Bandage
    local band = CreateFrame("Button", "LongLivePetsBandageBtn", frame, "SecureActionButtonTemplate")
    band:SetSize(28, 28); band:SetPoint("RIGHT", heal, "LEFT", -6, 0)
    band:SetAttribute("type", "item"); band:SetAttribute("item", "item:" .. BANDAGE_ITEM)
    band:RegisterForClicks("AnyUp", "AnyDown")
    local bi = band:CreateTexture(nil, "ARTWORK"); bi:SetAllPoints(); bi:SetTexture(itemIcon(BANDAGE_ITEM) or 133681); bi:SetTexCoord(unpack(ICON_CROP))
    band:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local bb = band:CreateTexture(nil, "BACKGROUND"); bb:SetPoint("TOPLEFT", -1, 1); bb:SetPoint("BOTTOMRIGHT", 1, -1); bb:SetColorTexture(0.5, 0.4, 0.1, 1)
    band.count = band:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    band.count:SetPoint("BOTTOMRIGHT", 1, 1)
    band.iconTex = bi
    band:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Battle Pet Bandage")
        GameTooltip:AddLine("Heal one battle pet. You have " .. itemCount(BANDAGE_ITEM) .. ".", .9, .9, .9, true)
        GameTooltip:Show()
    end)
    band:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.bandageBtn = band

    function UI:RefreshPetCare()
        if not frame or not frame.healBtn then return end
        local s, d = spellCooldown(REVIVE_SPELL)
        if s and d and frame.healBtn.cd then frame.healBtn.cd:SetCooldown(s, d) end
        local n = itemCount(BANDAGE_ITEM)
        frame.bandageBtn.count:SetText(n > 0 and tostring(n) or "")
        frame.bandageBtn.iconTex:SetDesaturated(n == 0)
        if not InCombatLockdown() then frame.bandageBtn:SetEnabled(n > 0) end
    end

    ns:On("SPELL_UPDATE_COOLDOWN", function() if frame and frame:IsShown() then UI:RefreshPetCare() end end)
    ns:On("BAG_UPDATE_DELAYED", function() if frame and frame:IsShown() then UI:RefreshPetCare() end end)
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

    -- one search box: matches pet name OR ability text (no mode toggle)
    local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    search:SetSize(218, 20); search:SetPoint("TOPLEFT", 16, -60)
    if search.Instructions then search.Instructions:SetText("Search name or move…") end
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        state.search = self:GetText() or ""; UI:RefreshCollection()
    end)
    frame.search = search

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
    local counterOpts = { { text = "Counter: off", short = "Counter: off", value = nil } }
    for i = 1, 10 do counterOpts[#counterOpts + 1] = { text = "Strong vs " .. ns.Types.NAME[i], short = "Str: " .. ns.Types.NAME[i], value = { mode = "strong", t = i } } end
    for i = 1, 10 do counterOpts[#counterOpts + 1] = { text = "Tough vs " .. ns.Types.NAME[i], short = "Tgh: " .. ns.Types.NAME[i], value = { mode = "tough", t = i } } end
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
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            if self.pet and C_PetJournal.PickupPet then C_PetJournal.PickupPet(self.pet.petID) end
        end)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(34, 34); ico:SetPoint("LEFT", 2, 0); row.ico = ico
        local mk = row:CreateTexture(nil, "OVERLAY"); mk:SetSize(14, 14); mk:SetPoint("TOPLEFT", ico, "TOPLEFT", -2, 2); row.mk = mk
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nm:SetPoint("LEFT", ico, "RIGHT", 8, 0); nm:SetPoint("RIGHT", row, "RIGHT", -86, 0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false)
        nm:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, ""); row.nm = nm
        decoratePetRow(row)

        row:SetScript("OnClick", function(self, mouse)
            if not self.pet then return end
            local p = self.pet
            if mouse == "RightButton" then
                UI:ShowMenu({
                    { text = "Slot into active slot", fn = function() placePet(p, state.activeSlot); UI:ShowCard(p) end },
                    { text = "Add to leveling queue", fn = function() ns.Queue:Add(p.petID) end },
                    { text = "Cycle marker", fn = function() ns.Markers:Cycle(p.speciesID) end },
                    { text = "Clear marker", fn = function() ns.Markers:Clear(p.speciesID) end },
                })
            else
                -- fill the active slot and show that pet's card + moves
                state.selectedPet = p
                placePet(p, state.activeSlot)
                UI:ShowCard(p)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.pet then UI:ShowCard(self.pet); ns.PetCard:Show(self, self.pet) end
        end)
        row:SetScript("OnLeave", function() ns.PetCard:Hide() end)
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

-- a short gold divider centered under a center sub-section label
local function centerDivider(y)
    local d = frame:CreateTexture(nil, "OVERLAY")
    d:SetSize(220, 1); d:SetPoint("TOP", frame, "TOPLEFT", 368, y)
    d:SetColorTexture(0.5, 0.42, 0.2, 0.7)
end

-- ---- CENTER: Selected Pet → Team → Team facts -----------------------------
function UI:BuildLoadout()
    -- SELECTED PET: 3D model + stats
    local selLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selLabel:SetPoint("TOP", frame, "TOPLEFT", 368, -38); selLabel:SetText("Selected Pet")

    local model = CreateFrame("PlayerModel", nil, frame)
    model:SetSize(138, 150); model:SetPoint("TOP", frame, "TOPLEFT", 368, -56)
    frame.petModel = model

    local selInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selInfo:SetPoint("TOP", frame, "TOPLEFT", 368, -208); selInfo:SetWidth(226)
    selInfo:SetJustifyH("CENTER"); selInfo:SetSpacing(2)
    selInfo:SetText("Hover or click a pet to inspect it.")
    frame.selInfo = selInfo

    -- TEAM: label + 3 slots + name/save
    local teamLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    teamLabel:SetPoint("TOP", frame, "TOPLEFT", 368, -246); teamLabel:SetText("Team")
    centerDivider(-262)

    frame.slots = {}
    for s = 1, 3 do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(44, 44); b:SetPoint("TOP", frame, "TOPLEFT", 368 + (s - 2) * 52, -268)
        b:RegisterForClicks("LeftButtonUp")
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        b.ico = b:CreateTexture(nil, "ARTWORK"); b.ico:SetSize(38, 38); b.ico:SetPoint("CENTER"); b.ico:SetTexCoord(unpack(ICON_CROP))
        b:SetScript("OnClick", function()
            if dropCursorPet(s) then return end
            state.activeSlot = s
            local petID = C_PetJournal.GetPetLoadOutInfo(s)
            if petID then
                local speciesID, customName, level, _, _, _, _, name, _, petType = C_PetJournal.GetPetInfoByPetID(petID)
                local rarity = select(5, C_PetJournal.GetPetStats(petID))
                UI:ShowCard({ petID = petID, speciesID = speciesID, name = customName or name,
                              level = level, petType = petType, rarity = rarity })
            end
            UI:RefreshLoadout()
        end)
        b:SetScript("OnReceiveDrag", function() dropCursorPet(s) end)
        b:SetScript("OnEnter", function(self)
            local petID = C_PetJournal.GetPetLoadOutInfo(s)
            if not petID then return end
            local speciesID, customName, level, _, _, _, _, name, _, petType = C_PetJournal.GetPetInfoByPetID(petID)
            local rarity = select(5, C_PetJournal.GetPetStats(petID))
            ns.PetCard:Show(self, {
                petID = petID, speciesID = speciesID, name = customName or name,
                level = level, petType = petType, rarity = rarity,
            })
        end)
        b:SetScript("OnLeave", function() ns.PetCard:Hide() end)
        frame.slots[s] = b
    end

    local nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameBox:SetSize(146, 20); nameBox:SetPoint("TOPLEFT", 261, -322); nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(40)
    frame.nameBox = nameBox
    local save = btn(frame, "Save", 60, 20); save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    save:SetScript("OnClick", function()
        local n = nameBox:GetText(); if n and n ~= "" then ns.Teams:SaveCurrent(n); nameBox:SetText("") end
    end)

    -- TEAM FACTS (bottom)
    local factsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    factsLabel:SetPoint("TOP", frame, "TOPLEFT", 368, -426); factsLabel:SetText("Team facts")
    centerDivider(-442)
    local facts = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    facts:SetPoint("TOP", frame, "TOPLEFT", 368, -450); facts:SetWidth(226)
    facts:SetJustifyH("CENTER"); facts:SetSpacing(2)
    frame.facts = facts
end

-- ---- MOVES picker (center, below the buttons) -----------------------------
function UI:BuildMoves()
    frame.movesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.movesLabel:SetPoint("TOP", frame, "TOPLEFT", 368, -348); frame.movesLabel:SetText("Moves")

    frame.moveBtns = {}
    for i = 1, 3 do
        frame.moveBtns[i] = {}
        for j = 1, 2 do
            local b = CreateFrame("Button", nil, frame)
            b:SetSize(30, 30)
            -- 3 ability slots across (i), the two options stacked below (j) —
            -- matches the in-battle ability bar.
            b:SetPoint("TOP", frame, "TOPLEFT", 368 + (i - 2) * 40, -362 - (j - 1) * 32)
            b.ico = b:CreateTexture(nil, "ARTWORK"); b.ico:SetAllPoints(); b.ico:SetTexCoord(unpack(ICON_CROP))
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
    list:SetPoint("TOPLEFT", 500, -96); list:SetSize(244, ROW_H * TEAM_ROWS)
    list:EnableMouseWheel(true)
    for i = 1, TEAM_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(20, 20); ico:SetPoint("LEFT", 0, 0); row.ico = ico
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nm:SetPoint("LEFT", 24, 0); nm:SetPoint("RIGHT", -62, 0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false); row.nm = nm
        local up  = btn(row, "^", 18, 18); up:SetPoint("RIGHT", -40, 0); row.up = up
        local dn  = btn(row, "v", 18, 18); dn:SetPoint("RIGHT", -20, 0); row.dn = dn
        local del = btn(row, "X", 18, 18); del:SetPoint("RIGHT", 0, 0); row.del = del
        decoratePetRow(row)
        row:Hide(); teamRows[i] = row
    end
    frame.teamsEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.teamsEmpty:SetPoint("TOP", 0, -8)

    -- scrollbar + mouse wheel for the (often long) team/queue list
    local sb = CreateFrame("Slider", nil, frame)
    sb:SetOrientation("VERTICAL"); sb:SetWidth(14)
    sb:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, 0)
    sb:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 2, 0)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(1); sb:SetObeyStepOnDrag(true)
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = sb:GetThumbTexture(); if thumb and thumb.SetSize then thumb:SetSize(14, 26) end
    sb:SetScript("OnValueChanged", function(_, v) state.rightOffset = math.floor((v or 0) + 0.5); UI:RenderRight() end)
    frame.teamsSlider = sb
    local function wheel(_, delta) sb:SetValue((sb:GetValue() or 0) - delta) end
    list:SetScript("OnMouseWheel", wheel)
    for _, row in ipairs(teamRows) do row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", wheel) end

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
-- Update the center "Selected Pet" model + stats text.
function UI:ShowCard(pet)
    if not frame or not pet then return end
    -- 3D model
    if frame.petModel then
        local displayID = pet.petID and select(6, C_PetJournal.GetPetInfoByPetID(pet.petID))
        if frame.petModel.ClearModel then frame.petModel:ClearModel() end
        if displayID and frame.petModel.SetDisplayInfo then
            pcall(function()
                frame.petModel:SetDisplayInfo(displayID)
                if frame.petModel.SetCamDistanceScale then frame.petModel:SetCamDistanceScale(0.85) end
                if frame.petModel.SetPortraitZoom then frame.petModel:SetPortraitZoom(0) end
                if frame.petModel.SetPosition then frame.petModel:SetPosition(0, 0, 0) end
            end)
        end
    end
    -- compact, centered stats for the Selected Pet panel
    if not frame.selInfo then return end
    local RAR = { [1] = "Poor", [2] = "Common", [3] = "Uncommon", [4] = "Rare", [5] = "Epic" }
    local typeName = pet.petType and ns.Types.NAME[pet.petType] or "?"
    local breed = pet.breed or (ns.Breed and ns.Breed:Get(pet.petID))
    local line1 = "|cffffd100" .. (pet.name or "Pet") .. "|r"
    local line2 = ("Lvl %d   %s%s%s"):format(pet.level or 1, typeName,
        RAR[pet.rarity or 0] and ("   " .. RAR[pet.rarity or 0]) or "",
        breed and ("   |cff8ec5ff" .. breed .. "|r") or "")
    local line3
    if C_PetJournal.GetPetStats and pet.petID then
        local hh, _, pp, ss = C_PetJournal.GetPetStats(pet.petID)
        if hh then line3 = ("%d HP    %d Pow    %d Spd"):format(hh, pp, ss) end
    end
    frame.selInfo:SetText(line1 .. "\n" .. line2 .. (line3 and ("\n" .. line3) or ""))
end

-- Summarize the currently loaded team (totals + type coverage).
function UI:RefreshFacts()
    if not frame or not frame.facts then return end
    local h, p, s, n, types = 0, 0, 0, 0, {}
    for slot = 1, 3 do
        local petID = C_PetJournal.GetPetLoadOutInfo(slot)
        if petID then
            local health, _, power, speed = C_PetJournal.GetPetStats(petID)
            h = h + (health or 0); p = p + (power or 0); s = s + (speed or 0); n = n + 1
            local pt = select(10, C_PetJournal.GetPetInfoByPetID(petID))
            if pt and ns.Types.NAME[pt] then types[#types + 1] = ns.Types.NAME[pt] end
        end
    end
    if n == 0 then frame.facts:SetText("No pets slotted.") return end
    frame.facts:SetText(("|cffffffff%d|r HP   |cffffffff%d|r Power   |cffffffff%d|r Speed\nTypes: %s")
        :format(h, p, s, table.concat(types, ", ")))
end

-- Render the visible window of colPets starting at state.colOffset.
function UI:RenderCollection()
    if not frame then return end
    local off = state.colOffset or 0
    for i, row in ipairs(colRows) do
        local p = colPets[i + off]
        if p then
            row.pet = p
            renderPetRow(row, p)
            row.mk:SetTexture(p.marker and ns.Markers:Texture(p.marker) or nil)
            row.nm:SetText(p.name)
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
    opts.text = state.search
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
    self:RefreshFacts()
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
    rightDisp = {}
    for i, petID in ipairs(q) do rightDisp[#rightDisp + 1] = { queue = petID, index = i } end
    self:RenderRight()
end

local function gkey(id) return id or "__ungrouped" end

function UI:RefreshTeams()
    if not frame then return end
    frame.teamsHint:SetText("Click a group to expand/collapse. Right-click a group for options.")
    local groups, teams = ns.Groups:List(), ns.Teams:List()
    local byGroup, ungrouped = {}, {}
    for _, t in ipairs(teams) do
        if t.group then byGroup[t.group] = byGroup[t.group] or {}; table.insert(byGroup[t.group], t)
        else table.insert(ungrouped, t) end
    end
    rightDisp = {}
    for _, g in ipairs(groups) do
        local teamsIn = byGroup[g.id] or {}
        local collapsed = state.collapsed[gkey(g.id)] and true or false
        rightDisp[#rightDisp + 1] = { header = true, name = g.name, groupID = g.id, count = #teamsIn, collapsed = collapsed }
        if not collapsed then for _, t in ipairs(teamsIn) do rightDisp[#rightDisp + 1] = { team = t } end end
    end
    if #groups > 0 then
        local collapsed = state.collapsed["__ungrouped"] and true or false
        rightDisp[#rightDisp + 1] = { header = true, name = "Ungrouped", groupID = nil, count = #ungrouped, collapsed = collapsed }
        if not collapsed then for _, t in ipairs(ungrouped) do rightDisp[#rightDisp + 1] = { team = t } end end
    else
        for _, t in ipairs(ungrouped) do rightDisp[#rightDisp + 1] = { team = t } end
    end
    frame.teamsEmpty:SetShown(#teams == 0 and #groups == 0)
    self:RenderRight()
end

-- render the visible window of rightDisp at state.rightOffset, sized by the scrollbar
function UI:RenderRight()
    if not frame then return end
    local off = state.rightOffset or 0
    for i, row in ipairs(teamRows) do
        local d = rightDisp[i + off]
        if not d then
            row:Hide()
        elseif d.header then
            row.ico:Hide(); clearPetRow(row)
            local arrow = d.collapsed and "|cffaaaaaa▶|r " or "|cffaaaaaa▼|r "
            local cnt = (d.count and d.count > 0) and ("  |cff888888(" .. d.count .. ")|r") or ""
            row.nm:SetText(arrow .. "|cffffd100" .. d.name .. "|r" .. cnt)
            row.up:Hide(); row.dn:Hide()
            if d.groupID then
                row.del:SetScript("OnClick", function() ns.Groups:Delete(d.groupID) end); row.del:Show()
            else row.del:Hide() end
            row:SetScript("OnClick", function(_, mouse)
                local key = d.groupID or "__ungrouped"
                if mouse == "RightButton" then
                    local items = {}
                    if state.selectedTeam then
                        items[#items + 1] = { text = "Move selected team here", fn = function() ns.Groups:Assign(state.selectedTeam, d.groupID) end }
                    end
                    if d.groupID then
                        items[#items + 1] = { text = "Rename group", fn = function() UI:PromptText("Rename group", d.name, function(n) ns.Groups:Rename(d.groupID, n) end) end }
                        items[#items + 1] = { text = "Delete group", fn = function() ns.Groups:Delete(d.groupID) end }
                    end
                    items[#items + 1] = { text = d.collapsed and "Expand" or "Collapse",
                        fn = function() state.collapsed[key] = not state.collapsed[key]; UI:RefreshRight() end }
                    UI:ShowMenu(items)
                else
                    -- left-click toggles expand/collapse
                    state.collapsed[key] = not state.collapsed[key]; UI:RefreshRight()
                end
            end)
            row:Show()
        elseif d.team then
            local t = d.team
            row.ico:Hide(); clearPetRow(row)
            local label = t.name
            if t.loaded then label = "|cff44ff44>|r " .. label end
            if (t.wins + t.losses) > 0 then label = label .. (" |cffaaaaaa%d-%d|r"):format(t.wins, t.losses) end
            -- icon flags: scroll = script, note = notes
            if t.script then label = label .. "  |TInterface\\Icons\\INV_Scroll_03:12:12|t" end
            if t.notes then label = label .. " |TInterface\\Icons\\INV_Misc_Note_01:12:12|t" end
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
                    state.selectedTeam = t.id; ns.Teams:Load(t.id)
                end
            end)
            row.up:SetScript("OnClick", function() UI:MoveTeam(t, -1) end)
            row.dn:SetScript("OnClick", function() UI:MoveTeam(t, 1) end)
            row.del:SetScript("OnClick", function() ns.Teams:Delete(t.id) end)
            row.up:Show(); row.dn:Show(); row.del:Show(); row:Show()
        elseif d.queue then
            local petID = d.queue
            local speciesID, customName, level, _, _, _, _, name, icon, petType = C_PetJournal.GetPetInfoByPetID(petID)
            local rarity = select(5, C_PetJournal.GetPetStats(petID))
            local pet = { petID = petID, speciesID = speciesID, name = customName or name or "pet",
                          level = level, petType = petType, icon = icon, rarity = rarity }
            renderPetRow(row, pet)
            row.nm:SetText(pet.name)
            row.up:Hide(); row.dn:Hide(); row.del:Hide()
            row:SetScript("OnClick", function(_, mouse)
                if mouse == "RightButton" then
                    UI:ShowMenu({ { text = "Remove from queue", fn = function() ns.Queue:Remove(petID) end } })
                end
            end)
            row:Show()
        end
    end
    local maxOff = math.max(0, #rightDisp - TEAM_ROWS)
    if (state.rightOffset or 0) > maxOff then state.rightOffset = maxOff end
    if frame.teamsSlider then
        frame.teamsSlider:SetMinMaxValues(0, maxOff)
        frame.teamsSlider:SetValue(state.rightOffset or 0)
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

-- Build Counter is suppressed in the UI for now; the engine still works via
-- /llp build and prints to chat (we'll re-surface it in the UI later).
function UI:BuildCounter()
    local intel = ns.EnemyIntel:GetForCurrentTarget()
    if not intel and state.selectedTeam then
        local team = ns.db.teams[state.selectedTeam]
        if team and team.targets then for n in pairs(team.targets) do intel = ns.EnemyIntel:Get(n); if intel then break end end end
    end
    if not intel then
        ns:Print("No enemy intel yet — fight a tamer once, then try /llp build."); return
    end
    local res = ns.CounterBuilder:Build(intel, ns.Roster:GetOwnedPets())
    ns:Print(("Counter for %s (covers %d/%d):"):format(intel.name or "target", res.covered, res.total))
    for _, p in ipairs(res.picks) do
        ns:Print("  • " .. p.pet.name .. (p.reasons[1] and (" — " .. p.reasons[1]) or ""))
    end
end

function UI:Refresh()
    if not frame then return end
    self:RefreshCollection(); self:RefreshRight(); self:RefreshLoadout()
    if self.RefreshPetCare then self:RefreshPetCare() end
end

function UI:Toggle()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); self:Refresh() end
end
function UI:Show()
    if not frame then build() end
    frame:Show(); self:Refresh()
end

-- keep the loaded-team slots in sync when the journal changes (e.g. after a load)
ns:On("PET_JOURNAL_LIST_UPDATE", function()
    if frame and frame:IsShown() then UI:RefreshLoadout() end
end)
