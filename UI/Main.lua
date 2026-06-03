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

local COL_ROWS, TEAM_ROWS = 12, 13
local ROW_H = 42
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
    frame:SetSize(880, 700)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")   -- above the AddOns list / achievements etc.
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
    frame.closeBtn = close

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
    columnFrame(252, 484)   -- Current Team
    columnFrame(488, 872)   -- Teams / Queue

    -- header bars live on the MAIN frame (BACKGROUND) so the titles, which are
    -- also on the main frame (OVERLAY), draw on top of them. (The columns have
    -- a transparent fill, so these show through.)
    local function headerBar(x1, x2)
        local hb = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        hb:SetPoint("TOPLEFT", frame, "TOPLEFT", x1 + 4, -38)
        hb:SetPoint("TOPRIGHT", frame, "TOPLEFT", x2 - 4, -38)
        hb:SetHeight(20); hb:SetColorTexture(0.16, 0.14, 0.09, 0.95)
    end
    headerBar(10, 248); headerBar(252, 484); headerBar(488, 872)

    UI:BuildCollection()
    UI:BuildLoadout()
    UI:BuildTeams()
    UI:BuildPetCare()
    UI:BuildImportExport()
    UI:BuildRenameDialog()
    UI:BuildMenu()
    UI:ApplyScale()
end

-- Scale the whole window up to fill most of the screen height (keeps the layout
-- intact — everything just gets bigger, which fixes the "squished" feel).
function UI:ApplyScale()
    if not frame then return end
    local sh = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(sh) ~= "number" or sh <= 0 then return end
    -- a gentle bump for legibility — NOT screen-filling (that overlapped other
    -- windows and was unusable). ~80% of screen height, capped at 1.25x.
    local scale = (sh * 0.80) / 700
    if scale < 1 then scale = 1 elseif scale > 1.25 then scale = 1.25 end
    frame:SetScale(scale)
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
    heal:SetSize(24, 24)
    -- sit in the bottom button row, just right of Import
    if frame.importBtn then heal:SetPoint("LEFT", frame.importBtn, "RIGHT", 14, 0)
    else heal:SetPoint("RIGHT", frame.closeBtn, "LEFT", -2, 0) end
    heal:SetAttribute("type", "spell"); heal:SetAttribute("spell", healName or "Revive Battle Pets")
    heal:RegisterForClicks("AnyUp", "AnyDown")
    local hi = heal:CreateTexture(nil, "ARTWORK"); hi:SetAllPoints(); hi:SetTexture(healIcon or 134376); hi:SetTexCoord(unpack(ICON_CROP))
    heal:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local hb = heal:CreateTexture(nil, "BACKGROUND"); hb:SetPoint("TOPLEFT", -1, 1); hb:SetPoint("BOTTOMRIGHT", 1, -1); hb:SetColorTexture(0.5, 0.4, 0.1, 1)
    heal.cd = CreateFrame("Cooldown", nil, heal, "CooldownFrameTemplate"); heal.cd:SetAllPoints()
    heal:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(healName or "Revive Battle Pets")
        GameTooltip:AddLine("Heal & revive all your battle pets (8-min cooldown).", .9, .9, .9, true)
        GameTooltip:Show()
    end)
    heal:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.healBtn = heal

    -- Pet Bandage
    local band = CreateFrame("Button", "LongLivePetsBandageBtn", frame, "SecureActionButtonTemplate")
    band:SetSize(24, 24); band:SetPoint("LEFT", heal, "RIGHT", 6, 0)
    band:SetAttribute("type", "item"); band:SetAttribute("item", "item:" .. BANDAGE_ITEM)
    band:RegisterForClicks("AnyUp", "AnyDown")
    local bi = band:CreateTexture(nil, "ARTWORK"); bi:SetAllPoints(); bi:SetTexture(itemIcon(BANDAGE_ITEM) or 133681); bi:SetTexCoord(unpack(ICON_CROP))
    band:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local bb = band:CreateTexture(nil, "BACKGROUND"); bb:SetPoint("TOPLEFT", -1, 1); bb:SetPoint("BOTTOMRIGHT", 1, -1); bb:SetColorTexture(0.5, 0.4, 0.1, 1)
    band.count = band:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    band.count:SetPoint("BOTTOMRIGHT", 1, 1)
    band.iconTex = bi
    band:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
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

    -- TYPE BAR: All + 10 color-coded type squares (matches the row badges and
    -- renders on every client — no reliance on the type textures).
    local typeBtns = {}
    local function setTypeActive(v)
        state.typeIndex = v
        for _, b in ipairs(typeBtns) do b.selBg:SetShown(b.value == v) end
        UI:RefreshCollection()
    end
    local function typeButton(w, x, label, color, value, tip)
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(w, 18); b:SetPoint("TOPLEFT", x, -84)
        b.selBg = b:CreateTexture(nil, "BACKGROUND", nil, 0)
        b.selBg:SetPoint("TOPLEFT", -2, 2); b.selBg:SetPoint("BOTTOMRIGHT", 2, -2)
        b.selBg:SetColorTexture(1, 0.85, 0.25, 1); b.selBg:Hide()
        b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1); b.bg:SetAllPoints()
        b.bg:SetColorTexture(color[1] * 0.55, color[2] * 0.55, color[3] * 0.55, 0.95)
        b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.txt:SetPoint("CENTER"); b.txt:SetText(label); b.txt:SetTextColor(1, 1, 1)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        b.value = value
        b:SetScript("OnClick", function() setTypeActive(value) end)
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        typeBtns[#typeBtns + 1] = b
        return b
    end
    typeButton(26, 16, "All", { 0.5, 0.5, 0.5 }, nil, "All types")
    for i = 1, 10 do
        typeButton(16, 46 + (i - 1) * 18, ns.Types:Abbr(i):sub(1, 2), ns.Types:Color(i), i, ns.Types.NAME[i])
    end
    typeBtns[1].selBg:Show()   -- "All" active by default

    -- Level + Filter dropdowns
    local levelDD = makeDropdown(frame, 104, {
        { text = "All levels", value = "all" },
        { text = "Level 25", value = "max" },
        { text = "Leveling (1-24)", value = "low" },
    }, function(v)
        state.maxOnly = (v == "max"); state.maxLevel = (v == "low") and 24 or nil
        UI:RefreshCollection()
    end, "All levels")
    levelDD:SetPoint("TOPLEFT", 16, -110)

    local moreDD = makeDropdown(frame, 104, {
        { text = "All pets", value = "all" },
        { text = "Marked only", value = "marked" },
        { text = "Rare+ only", value = "rare" },
    }, function(v)
        state.markedOnly = (v == "marked"); state.rarity = (v == "rare") and 4 or nil
        UI:RefreshCollection()
    end, "Filter: all")
    moreDD:SetPoint("LEFT", levelDD, "RIGHT", 6, 0)

    -- Counter dropdown: Strong Vs / Tough Vs a chosen enemy type
    local counterOpts = { { text = "Counter: off", short = "Counter: off", value = nil } }
    for i = 1, 10 do counterOpts[#counterOpts + 1] = { text = "Strong vs " .. ns.Types.NAME[i], short = "Str: " .. ns.Types.NAME[i], value = { mode = "strong", t = i } } end
    for i = 1, 10 do counterOpts[#counterOpts + 1] = { text = "Tough vs " .. ns.Types.NAME[i], short = "Tgh: " .. ns.Types.NAME[i], value = { mode = "tough", t = i } } end
    local counterDD = makeDropdown(frame, 214, counterOpts, function(v)
        if not v then state.strongVs = nil; state.toughVs = nil
        elseif v.mode == "strong" then state.strongVs = v.t; state.toughVs = nil
        else state.toughVs = v.t; state.strongVs = nil end
        UI:RefreshCollection()
    end, "Counter: off")
    counterDD:SetPoint("TOPLEFT", 16, -134)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 16, -160); list:SetSize(210, ROW_H * COL_ROWS)
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

        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(36, 36); ico:SetPoint("LEFT", 3, 0); row.ico = ico
        local mk = row:CreateTexture(nil, "OVERLAY"); mk:SetSize(14, 14); mk:SetPoint("TOPLEFT", ico, "TOPLEFT", -2, 2); row.mk = mk
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nm:SetPoint("LEFT", ico, "RIGHT", 8, 0); nm:SetPoint("RIGHT", row, "RIGHT", -86, 0)
        nm:SetJustifyH("LEFT"); nm:SetJustifyV("MIDDLE"); nm:SetWordWrap(true)
        if nm.SetMaxLines then nm:SetMaxLines(2) end
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

-- ---- CENTER: loaded-team name → 3 pet cards → team facts ------------------
-- (Inspired by Rematch's at-a-glance team view; all original code.)
local CARD_W, CARD_H, CARD_TOP, CARD_GAP = 226, 126, -92, 8
local function cardY(s) return CARD_TOP - (s - 1) * (CARD_H + CARD_GAP) end

local function colorCode(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- A shared icon flyout: click an ability on a card to pick its alternate.
local function buildAbilityFlyout()
    local fo = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    fo:SetFrameStrata("DIALOG"); fo:SetSize(80, 44)
    if fo.SetBackdrop then
        fo:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        fo:SetBackdropColor(0.05, 0.05, 0.07, 1); fo:SetBackdropBorderColor(0.55, 0.45, 0.3, 1)
    end
    fo.opts = {}
    for k = 1, 2 do
        local o = CreateFrame("Button", nil, fo)
        o:SetSize(32, 32); o:SetPoint("LEFT", 6 + (k - 1) * 36, 0)
        o.ico = o:CreateTexture(nil, "ARTWORK"); o.ico:SetAllPoints(); o.ico:SetTexCoord(unpack(ICON_CROP))
        o:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        o.sel = o:CreateTexture(nil, "OVERLAY"); o.sel:SetPoint("TOPLEFT", -2, 2); o.sel:SetPoint("BOTTOMRIGHT", 2, -2)
        o.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight"); o.sel:SetBlendMode("ADD"); o.sel:Hide()
        o:SetScript("OnEnter", function(self)
            if self.ability then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.ability.name or "?")
                if self.locked then GameTooltip:AddLine("Unlocks at level " .. (self.ability.reqLevel or "?"), 1, .3, .3) end
                if self.ability.desc then GameTooltip:AddLine(self.ability.desc, .9, .9, .9, true) end
                GameTooltip:Show()
            end
        end)
        o:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fo.opts[k] = o
    end
    fo:Hide()
    frame.abilFlyout = fo
end

local function openAbilityFlyout(anchor, loadoutSlot, abilitySlot)
    local fo = frame.abilFlyout
    local layout = ns.Abilities:GetLayout(loadoutSlot)
    local pair = layout and layout[abilitySlot]
    if not pair then return end
    if fo:IsShown() and fo._anchor == anchor then fo:Hide(); return end
    fo._anchor = anchor
    for k = 1, 2 do
        local o, opt = fo.opts[k], pair[k]
        if opt then
            o.ability, o.locked = opt, opt.locked
            o.ico:SetTexture(opt.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            o.ico:SetDesaturated(opt.locked and true or false)
            o.sel:SetShown(opt.selected and true or false)
            o:SetAlpha(opt.locked and 0.4 or 1)
            o:SetScript("OnClick", function()
                if not opt.locked then ns.Abilities:Set(loadoutSlot, abilitySlot, opt.id); fo:Hide(); UI:RefreshLoadout() end
            end)
            o:Show()
        else o:Hide() end
    end
    fo:ClearAllPoints(); fo:SetPoint("TOP", anchor, "BOTTOM", 0, -2); fo:Show()
end

function UI:BuildLoadout()
    -- center column header label
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOPLEFT", 368, -40); title:SetText("Current Team")

    -- loaded-team name + Save
    local nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameBox:SetSize(150, 20); nameBox:SetPoint("TOPLEFT", 259, -64); nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(40)
    frame.nameBox = nameBox
    local save = btn(frame, "Save", 56, 20); save:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    save:SetScript("OnClick", function()
        local n = nameBox:GetText(); if n and n ~= "" then ns.Teams:SaveCurrent(n); nameBox:SetText("") end
    end)

    buildAbilityFlyout()

    -- three team pet cards
    frame.cards = {}
    for s = 1, 3 do
        local card = CreateFrame("Button", nil, frame, "BackdropTemplate")
        card:SetSize(CARD_W, CARD_H); card:SetPoint("TOP", frame, "TOPLEFT", 368, cardY(s))
        card:RegisterForClicks("LeftButtonUp")
        if card.SetBackdrop then
            card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            card:SetBackdropColor(0.09, 0.09, 0.13, 0.85); card:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.9)
        end
        card.stripe = card:CreateTexture(nil, "ARTWORK")
        card.stripe:SetPoint("TOPLEFT", 4, -4); card.stripe:SetPoint("BOTTOMLEFT", 4, 4); card.stripe:SetWidth(3)
        card.pBorder = card:CreateTexture(nil, "BACKGROUND")
        card.ico = card:CreateTexture(nil, "ARTWORK"); card.ico:SetSize(48, 48); card.ico:SetPoint("TOPLEFT", 12, -12); card.ico:SetTexCoord(unpack(ICON_CROP))
        card.pBorder:SetPoint("TOPLEFT", card.ico, "TOPLEFT", -1, 1); card.pBorder:SetPoint("BOTTOMRIGHT", card.ico, "BOTTOMRIGHT", 1, -1)
        card.lvl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); card.lvl:SetPoint("BOTTOMRIGHT", card.ico, "BOTTOMRIGHT", 2, -1)
        card.nm = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        card.nm:SetPoint("TOPLEFT", 66, -12); card.nm:SetWidth(86)
        card.nm:SetJustifyH("LEFT"); card.nm:SetJustifyV("TOP"); card.nm:SetWordWrap(true)
        if card.nm.SetMaxLines then card.nm:SetMaxLines(2) end
        card.breed = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); card.breed:SetPoint("TOPLEFT", 66, -48)
        card.hpBarBg = card:CreateTexture(nil, "ARTWORK"); card.hpBarBg:SetColorTexture(0, 0, 0, 0.6)
        card.hpBarBg:SetPoint("TOPLEFT", 66, -68); card.hpBarBg:SetSize(96, 13)
        card.hpBar = card:CreateTexture(nil, "ARTWORK", nil, 1); card.hpBar:SetColorTexture(0.2, 0.7, 0.2, 0.95)
        card.hpBar:SetPoint("TOPLEFT", card.hpBarBg, "TOPLEFT", 1, -1); card.hpBar:SetSize(94, 11)
        card.hp = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); card.hp:SetPoint("CENTER", card.hpBarBg, "CENTER", 0, 0)
        card.abil = {}
        for i = 1, 3 do
            local ab = CreateFrame("Button", nil, card)
            ab:SetSize(32, 32); ab:SetPoint("TOPLEFT", 66 + (i - 1) * 36, -88)
            ab.ico = ab:CreateTexture(nil, "ARTWORK"); ab.ico:SetAllPoints(); ab.ico:SetTexCoord(unpack(ICON_CROP))
            ab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
            ab:SetScript("OnClick", function(self) openAbilityFlyout(self, s, i) end)
            ab:SetScript("OnEnter", function(self)
                if self.ability then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.ability.name or "?")
                    if self.ability.desc then GameTooltip:AddLine(self.ability.desc, .9, .9, .9, true) end
                    GameTooltip:AddLine("Click to swap", .6, .8, 1); GameTooltip:Show()
                end
            end)
            ab:SetScript("OnLeave", function() GameTooltip:Hide() end)
            card.abil[i] = ab
        end
        local model = CreateFrame("PlayerModel", nil, card)
        model:SetSize(62, 104); model:SetPoint("TOPRIGHT", -8, -12); card.model = model
        card.empty = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        card.empty:SetPoint("CENTER"); card.empty:SetText("Empty — click a pet to slot it")

        card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        card:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then
                if not card.curPetID then return end
                local p = card.curPet
                UI:ShowMenu({
                    { text = "Add to leveling queue", fn = function() ns.Queue:Add(p.petID) end },
                    { text = "Cycle marker", fn = function() ns.Markers:Cycle(p.speciesID) end },
                    { text = "Clear marker", fn = function() ns.Markers:Clear(p.speciesID) end },
                    { text = "Remove from slot", fn = function() C_PetJournal.SetPetLoadOutInfo(s, nil); UI:RefreshLoadout() end },
                })
                return
            end
            if dropCursorPet(s) then return end
            state.activeSlot = s; UI:RefreshLoadout()
        end)
        card:SetScript("OnReceiveDrag", function() dropCursorPet(s) end)
        card:SetScript("OnEnter", function(self)
            if not self.curPetID then return end
            local sp, cn, lv, _, _, _, _, nmv, _, pt = C_PetJournal.GetPetInfoByPetID(self.curPetID)
            local rar = select(5, C_PetJournal.GetPetStats(self.curPetID))
            ns.PetCard:Show(self, { petID = self.curPetID, speciesID = sp, name = cn or nmv, level = lv, petType = pt, rarity = rar })
        end)
        card:SetScript("OnLeave", function() ns.PetCard:Hide() end)
        frame.cards[s] = card
    end

    -- TEAM FACTS (bottom) — totals + a plain-language read on the team
    local factsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    factsLabel:SetPoint("TOP", frame, "TOPLEFT", 368, -498); factsLabel:SetText("Team facts")
    centerDivider(-514)
    local facts = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    facts:SetPoint("TOP", frame, "TOPLEFT", 368, -518); facts:SetWidth(228)
    facts:SetJustifyH("CENTER"); facts:SetSpacing(3)
    frame.facts = facts
end

-- refresh one team card from the live loadout
local function refreshTeamCard(s)
    local card = frame.cards and frame.cards[s]; if not card then return end
    local petID = C_PetJournal.GetPetLoadOutInfo(s)
    card.curPetID = petID
    if s == state.activeSlot then card:SetBackdropBorderColor(0.95, 0.82, 0.2, 1)
    else card:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.9) end
    if not petID then
        card.ico:Hide(); card.pBorder:Hide(); card.stripe:Hide(); card.lvl:SetText("")
        card.nm:SetText(""); card.breed:SetText(""); card.hp:SetText(""); card.hpBar:Hide(); card.hpBarBg:Hide()
        for i = 1, 3 do card.abil[i]:Hide() end
        if card.model.ClearModel then card.model:ClearModel() end
        card.empty:Show()
        return
    end
    card.empty:Hide()
    local speciesID, customName, level, _, _, displayID, _, name, icon, petType = C_PetJournal.GetPetInfoByPetID(petID)
    local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
    card.curPet = { petID = petID, speciesID = speciesID, name = customName or name, level = level, petType = petType, rarity = rarity }
    local rc = RARITY_COLOR[rarity or 2] or RARITY_COLOR[2]
    card.ico:SetTexture(icon); card.ico:Show()
    card.pBorder:SetColorTexture(rc[1], rc[2], rc[3], 1); card.pBorder:Show()
    card.stripe:SetColorTexture(rc[1], rc[2], rc[3], 1); card.stripe:Show()
    card.lvl:SetText(level and tostring(level) or "")
    card.nm:SetTextColor(rc[1], rc[2], rc[3]); card.nm:SetText(customName or name or "?")
    local breed = ns.Breed and ns.Breed:Get(petID)
    if petType and ns.Types.ABBR[petType] then
        card.breed:SetText(colorCode(ns.Types:Color(petType)) .. ns.Types:Abbr(petType) .. "|r" .. (breed and ("  |cff8ec5ff" .. breed .. "|r") or ""))
    else card.breed:SetText(breed and ("|cff8ec5ff" .. breed .. "|r") or "") end
    -- health bar reflects current/max; recolors as it drops
    card.hpBarBg:Show(); card.hpBar:Show()
    local frac = (maxHealth and maxHealth > 0 and health) and (health / maxHealth) or 1
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    card.hpBar:SetWidth(math.max(1, 94 * frac))
    if frac > 0.5 then card.hpBar:SetColorTexture(0.2, 0.7, 0.2, 0.95)
    elseif frac > 0.2 then card.hpBar:SetColorTexture(0.85, 0.65, 0.1, 0.95)
    else card.hpBar:SetColorTexture(0.8, 0.2, 0.2, 0.95) end
    card.hp:SetText(("%d / %d"):format(health or 0, maxHealth or health or 0))
    local layout = ns.Abilities:GetLayout(s)
    for i = 1, 3 do
        local ab = card.abil[i]
        local pair = layout and layout[i]
        local chosen = pair and ((pair[1] and pair[1].selected and pair[1]) or (pair[2] and pair[2].selected and pair[2]) or pair[1])
        if chosen then
            ab.ability = chosen
            ab.ico:SetTexture(chosen.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            ab:Show()
        else ab.ability = nil; ab:Hide() end
    end
    if card.model and displayID and card.model.SetDisplayInfo then
        if card.model.ClearModel then card.model:ClearModel() end
        pcall(function()
            card.model:SetDisplayInfo(displayID)
            if card.model.SetCamDistanceScale then card.model:SetCamDistanceScale(1.0) end
            if card.model.SetPortraitZoom then card.model:SetPortraitZoom(0) end
        end)
    end
end

-- (Abilities now live on each team card — see BuildLoadout/refreshTeamCard.)

-- ---- TEAMS / QUEUE (right) ------------------------------------------------
function UI:BuildTeams()
    -- Teams / Queue selector (a dropdown replaces the tab buttons) + New Group
    local modeDD = makeDropdown(frame, 116, {
        { text = "Teams", value = "teams" },
        { text = "Queue", value = "queue" },
    }, function(v) state.rightMode = v; UI:RefreshRight() end, "Teams")
    modeDD:SetPoint("TOPLEFT", 500, -38); frame.modeDD = modeDD
    local newG = btn(frame, "+ Group", 80, 20); newG:SetPoint("LEFT", modeDD, "RIGHT", 8, 0)
    newG:SetScript("OnClick", function()
        UI:PromptText("New group name", "", function(n) if n and n ~= "" then ns.Groups:Create(n) end end)
    end)

    frame.teamsHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.teamsHint:SetPoint("TOPLEFT", 500, -64)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 500, -80); list:SetSize(348, ROW_H * TEAM_ROWS)
    list:EnableMouseWheel(true)
    for i = 1, TEAM_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        -- group-header background bar (shown only for header rows)
        row.headerBg = row:CreateTexture(nil, "BACKGROUND")
        row.headerBg:SetPoint("TOPLEFT", 0, -3); row.headerBg:SetPoint("BOTTOMRIGHT", 0, 3)
        row.headerBg:SetColorTexture(0.20, 0.17, 0.10, 0.95); row.headerBg:Hide()
        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetSize(20, 20); ico:SetPoint("LEFT", 4, 0); row.ico = ico
        -- a team row shows its 3 pet portraits on the left (Rematch-style)
        row.pics = {}
        for k = 1, 3 do
            local pic = row:CreateTexture(nil, "ARTWORK")
            pic:SetSize(26, 26); pic:SetPoint("LEFT", 4 + (k - 1) * 28, 0); pic:SetTexCoord(unpack(ICON_CROP))
            local bd = row:CreateTexture(nil, "BACKGROUND")
            bd:SetPoint("TOPLEFT", pic, "TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", 1, -1)
            pic.bd = bd; pic:Hide(); bd:Hide()
            row.pics[k] = pic
        end
        local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nm:SetPoint("LEFT", 24, 0); nm:SetPoint("RIGHT", -62, 0)
        nm:SetJustifyH("LEFT"); nm:SetJustifyV("MIDDLE"); nm:SetWordWrap(true)
        if nm.SetMaxLines then nm:SetMaxLines(2) end
        row.nm = nm
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

    -- bottom row: separate Export / Import. (Send-to-player still works via a
    -- team's right-click menu; the always-visible send box is gone.)
    local exportB = btn(frame, "Export team", 104, 22); exportB:SetPoint("BOTTOMLEFT", 500, 16)
    exportB:SetScript("OnClick", function()
        local id = ns.db and ns.db.loaded
        local team = id and ns.db.teams[id]
        if not team then ns:Print("Load a team first (click it on the right) to export it."); return end
        UI:ShowText(('Export — "%s" (team + script) to share / wow-petguide / tdBattlePetScript'):format(team.name),
            "export", ns.Serialize:ExportStrategy(team))
    end)
    local importB = btn(frame, "Import", 104, 22); importB:SetPoint("LEFT", exportB, "RIGHT", 8, 0)
    importB:SetScript("OnClick", function()
        UI:ShowText("Import — paste a team or backup string", "import", "")
    end)
    frame.importBtn = importB
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
        local n, err, info = ns.Serialize:Import(v)
        ns:Print(n and ("Imported " .. n .. " team(s).") or err); p:Hide()
        if info and info.code then
            local pushed = ns.Integration and ns.Integration.ImportScript and ns.Integration:ImportScript(info.name, info.code)
            if pushed then
                ns:Print(('Created "%s" (%d pets) and loaded its script into tdBattlePetScript — start a battle on this team and it arms automatically.'):format(info.name, info.pets or 0))
            else
                ns:Print(('Created "%s" (%d pets). tdBattlePetScript isn\'t available to auto-load the script — copy it in manually:'):format(info.name, info.pets or 0))
                UI:ShowText(('Paste this into tdBattlePetScript and name it "%s"'):format(info.name),
                    "export", "-----BEGIN PET BATTLE SCRIPT-----\n" .. info.code .. "\n-----END PET BATTLE SCRIPT-----")
            end
        end
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
-- Remember the last-clicked pet. The team cards in the center now show full
-- per-pet detail, so this no longer drives a separate "selected pet" panel.
function UI:ShowCard(pet)
    if pet then state.selectedPet = pet end
end

-- a plain-language read on a team: survivability, punch, speed, and the enemy
-- types it's strong against / tough against (deduped, top few).
local function teamCommentary(h, p, s, n, ptypes)
    local bits = {}
    local avgH, avgS = h / n, s / n
    if avgH >= 1500 then bits[#bits + 1] = "great survivability"
    elseif avgH >= 1200 then bits[#bits + 1] = "solid survivability"
    else bits[#bits + 1] = "fragile but hits fast" end
    if avgS >= 290 then bits[#bits + 1] = "very fast" elseif avgS <= 240 then bits[#bits + 1] = "on the slow side" end
    if (p / n) >= 290 then bits[#bits + 1] = "hard-hitting" end

    local strongSet, toughSet = {}, {}
    for _, pt in ipairs(ptypes) do
        local sv = ns.Types:FamilyStrongVs(pt); if sv then strongSet[sv] = true end
        local tv = ns.Types:FamilyToughVs(pt);  if tv then toughSet[tv] = true end
    end
    local function list(set) local o = {} for k in pairs(set) do o[#o + 1] = k end table.sort(o); return o end
    local strong, tough = list(strongSet), list(toughSet)
    local out = "This team has " .. table.concat(bits, ", ") .. "."
    if #strong > 0 then out = out .. " Strong against " .. table.concat(strong, ", ") .. "." end
    if #tough > 0 then out = out .. " Tough against " .. table.concat(tough, ", ") .. "." end
    return out
end

-- Summarize the currently loaded team (totals + type coverage + commentary).
function UI:RefreshFacts()
    if not frame or not frame.facts then return end
    local h, p, s, n, typeNames, ptypes = 0, 0, 0, 0, {}, {}
    for slot = 1, 3 do
        local petID = C_PetJournal.GetPetLoadOutInfo(slot)
        if petID then
            local health, _, power, speed = C_PetJournal.GetPetStats(petID)
            h = h + (health or 0); p = p + (power or 0); s = s + (speed or 0); n = n + 1
            local pt = select(10, C_PetJournal.GetPetInfoByPetID(petID))
            if pt and ns.Types.NAME[pt] then typeNames[#typeNames + 1] = ns.Types.NAME[pt]; ptypes[#ptypes + 1] = pt end
        end
    end
    if n == 0 then frame.facts:SetText("No pets slotted.") return end
    frame.facts:SetText(("|cffffffff%d|r HP   |cffffffff%d|r Power   |cffffffff%d|r Speed\n|cffaaaaaaTypes:|r %s\n\n|cffd0e6ff%s|r")
        :format(h, p, s, table.concat(typeNames, ", "), teamCommentary(h, p, s, n, ptypes)))
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
    if not frame or not frame.cards then return end
    if frame.abilFlyout then frame.abilFlyout:Hide() end
    for s = 1, 3 do refreshTeamCard(s) end
    local id = ns.db and ns.db.loaded
    frame.nameBox:SetText(id and ns.db.teams[id] and ns.db.teams[id].name or "")
    self:RefreshFacts()
end

-- Right column dispatches to Teams or Queue.
function UI:RefreshRight()
    if not frame then return end
    if frame.modeDD then frame.modeDD:SelectText(state.rightMode == "queue" and "Queue" or "Teams") end
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

-- icon + rarity for a saved team-pet entry (petID preferred, else species)
local function petEntryIcon(p)
    if not p then return nil end
    if p.petID and C_PetJournal.GetPetInfoByPetID then
        local icon = select(9, C_PetJournal.GetPetInfoByPetID(p.petID))
        local rarity = select(5, C_PetJournal.GetPetStats(p.petID))
        if icon then return icon, rarity end
    end
    if p.speciesID and C_PetJournal.GetPetInfoBySpeciesID then
        local icon = select(2, C_PetJournal.GetPetInfoBySpeciesID(p.speciesID))
        if icon then return icon end
    end
end

-- anchor a row's name fontstring (clearing prior points) to leave room for
-- whatever sits on its left (team portraits vs a single icon vs nothing)
local function setNameLeft(row, x)
    row.nm:ClearAllPoints()
    row.nm:SetPoint("LEFT", row, "LEFT", x, 0)
    row.nm:SetPoint("RIGHT", row, "RIGHT", -62, 0)
end

local function hideTeamPics(row)
    if not row.pics then return end
    for k = 1, 3 do row.pics[k]:Hide(); row.pics[k].bd:Hide() end
end

local function showTeamPics(row, team)
    if not row.pics then return end
    local pets = team and team.pets
    -- always render 3 slots; an empty/leveling slot (e.g. a Rematch "random"
    -- slot) shows a dim placeholder box so the row reads as a full 3-pet team.
    for k = 1, 3 do
        local pic = row.pics[k]
        local icon, rarity = petEntryIcon(pets and pets[k])
        if icon then
            pic:SetTexture(icon); pic:SetDesaturated(false)
            local rc = RARITY_COLOR[rarity or 2] or RARITY_COLOR[2]
            pic.bd:SetColorTexture(rc[1], rc[2], rc[3], 1); pic.bd:Show(); pic:Show()
        else
            pic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); pic:SetDesaturated(true)
            pic.bd:SetColorTexture(0.18, 0.18, 0.22, 1); pic.bd:Show(); pic:Show()
        end
    end
end

function UI:RefreshTeams()
    if not frame then return end
    frame.teamsHint:SetText("Click a group to expand/collapse. Right-click a group for options.")
    local groups, teams = ns.Groups:List(), ns.Teams:List()
    local byGroup, ungrouped = {}, {}
    for _, t in ipairs(teams) do
        if t.group then byGroup[t.group] = byGroup[t.group] or {}; table.insert(byGroup[t.group], t)
        else table.insert(ungrouped, t) end
    end
    -- groups start COLLAPSED by default each session: a group is expanded only
    -- if its key is explicitly set to false (set when the user clicks it).
    local function isCollapsed(key) return state.collapsed[key] ~= false end
    rightDisp = {}
    for _, g in ipairs(groups) do
        local teamsIn = byGroup[g.id] or {}
        local collapsed = isCollapsed(gkey(g.id))
        rightDisp[#rightDisp + 1] = { header = true, name = g.name, groupID = g.id, count = #teamsIn, collapsed = collapsed }
        if not collapsed then for _, t in ipairs(teamsIn) do rightDisp[#rightDisp + 1] = { team = t } end end
    end
    if #groups > 0 then
        local collapsed = isCollapsed("__ungrouped")
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
            clearPetRow(row); hideTeamPics(row); setNameLeft(row, 26)
            row.headerBg:Show()
            -- a real +/- texture (the old unicode arrows didn't render in-game)
            row.ico:SetTexCoord(0, 1, 0, 1); row.ico:SetSize(16, 16)
            row.ico:SetTexture(d.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            row.ico:Show()
            local cnt = (d.count and d.count > 0) and ("  |cff888888(" .. d.count .. ")|r") or ""
            row.nm:SetText("|cffffd100" .. d.name .. "|r" .. cnt)
            row.up:Hide(); row.dn:Hide()
            if d.groupID then
                row.del:SetScript("OnClick", function() ns.Groups:Delete(d.groupID) end); row.del:Show()
            else row.del:Hide() end
            local key = d.groupID or "__ungrouped"
            local function toggle() state.collapsed[key] = (state.collapsed[key] == false); UI:RefreshRight() end
            row:SetScript("OnClick", function(_, mouse)
                if mouse == "RightButton" then
                    local items = {}
                    if state.selectedTeam then
                        items[#items + 1] = { text = "Move selected team here", fn = function() ns.Groups:Assign(state.selectedTeam, d.groupID) end }
                    end
                    if d.groupID then
                        items[#items + 1] = { text = "Rename group", fn = function() UI:PromptText("Rename group", d.name, function(n) ns.Groups:Rename(d.groupID, n) end) end }
                        items[#items + 1] = { text = "Delete group", fn = function() ns.Groups:Delete(d.groupID) end }
                    end
                    items[#items + 1] = { text = d.collapsed and "Expand" or "Collapse", fn = toggle }
                    UI:ShowMenu(items)
                else
                    toggle()
                end
            end)
            row:Show()
        elseif d.team then
            local t = d.team
            row.ico:Hide(); row.headerBg:Hide(); clearPetRow(row)
            -- show the team's 3 pet portraits, name to their right
            showTeamPics(row, ns.db.teams[t.id]); setNameLeft(row, 82)
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
                        { text = "Send to player…", fn = function() UI:PromptText("Send \"" .. t.name .. "\" to player", "", function(who) if who and who ~= "" then ns.Comm:Send(t.id, who) end end) end },
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
            hideTeamPics(row); row.headerBg:Hide(); setNameLeft(row, 44)
            row.ico:SetSize(28, 28)   -- reset (header rows shrink this to 16)
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
