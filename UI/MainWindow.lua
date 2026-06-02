--[[ Long Live Pets ----------------------------------------------------------
  MainWindow.lua — the team window: grouped team list with Load/Delete, a
  "Save current" control, action buttons (Reload / New group / Backup /
  Import), and a copy/paste dialog for export & import.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local UI = {}
ns.UI = UI

local ROW_H    = 22
local MAX_ROWS = 18

local frame
local rows = {}

-- ---- copy / paste dialog --------------------------------------------------
local dialog
local function buildDialog()
    dialog = CreateFrame("Frame", "LongLivePetsDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(460, 240)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    if dialog.SetBackdrop then
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end

    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dialog.title:SetPoint("TOP", 0, -14)

    local scroll = CreateFrame("ScrollFrame", nil, dialog, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -40)
    scroll:SetPoint("BOTTOMRIGHT", -36, 44)
    dialog.edit = scroll.EditBox or scroll:GetScrollChild()
    if dialog.edit then
        dialog.edit:SetWidth(400)
        dialog.edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
    end

    local accept = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    accept:SetSize(120, 22)
    accept:SetPoint("BOTTOMRIGHT", -16, 14)
    dialog.accept = accept

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    dialog:Hide()
end

-- mode "export": read-only, text preselected. mode "import": editable + Import.
function UI:ShowText(title, mode, text, onAccept)
    if not dialog then buildDialog() end
    dialog.title:SetText(title)
    if dialog.edit then
        dialog.edit:SetText(text or "")
        dialog.edit:SetFocus()
        if mode == "export" then dialog.edit:HighlightText() end
    end
    if mode == "import" then
        dialog.accept:SetText("Import")
        dialog.accept:Show()
        dialog.accept:SetScript("OnClick", function()
            local v = dialog.edit and dialog.edit:GetText() or ""
            dialog:Hide()
            if onAccept then onAccept(v) end
        end)
    else
        dialog.accept:Hide()
    end
    dialog:Show()
end

-- ---- main window ----------------------------------------------------------
local function buildFrame()
    frame = CreateFrame("Frame", "LongLivePetsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(360, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
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

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\AddOns\\LongLivePets\\Textures\\icon.png")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Long Live Pets")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- save-current row
    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetSize(108, 22)
    save:SetPoint("TOPLEFT", 16, -46)
    save:SetText("Save current")

    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(192, 22)
    edit:SetPoint("LEFT", save, "RIGHT", 14, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(40)
    local function commitSave()
        local name = edit:GetText()
        if name and name ~= "" then
            ns.Teams:SaveCurrent(name); edit:SetText(""); edit:ClearFocus()
        end
    end
    save:SetScript("OnClick", commitSave)
    edit:SetScript("OnEnterPressed", commitSave)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    -- action buttons row
    local function actionButton(label, x, onClick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(78, 20)
        b:SetPoint("TOPLEFT", x, -76)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    actionButton("Reload", 16, function() ns.Teams:Reload() end)
    actionButton("Backup", 98, function()
        UI:ShowText("Backup — copy this text", "export", ns.Serialize:BackupAll())
    end)
    actionButton("Import", 180, function()
        UI:ShowText("Import — paste a team or backup", "import", "", function(v)
            local n, err = ns.Serialize:Import(v)
            if n then ns:Print(("Imported %d team(s)."):format(n)) else ns:Print(err) end
        end)
    end)
    actionButton("Help", 262, function() SlashCmdList["LONGLIVEPETS"]("help") end)

    -- list
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 16, -104)
    list:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.list = list

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", 4, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -116, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name

        local load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        load:SetSize(50, 18)
        load:SetPoint("RIGHT", -56, 0)
        load:SetText("Load")
        row.load = load

        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetSize(50, 18)
        del:SetPoint("RIGHT", 0, 0)
        del:SetText("Delete")
        row.del = del

        row:Hide()
        rows[i] = row
    end

    local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOP", 0, -10)
    empty:SetText('No teams yet. Slot your pets, then click "Save current".')
    frame.empty = empty
end

-- flat display list: group headers interleaved with their teams
local function buildDisplay()
    local groups = ns.Groups:List()
    local teams = ns.Teams:List()
    local byGroup, ungrouped = {}, {}
    for _, t in ipairs(teams) do
        if t.group then
            byGroup[t.group] = byGroup[t.group] or {}
            table.insert(byGroup[t.group], t)
        else
            table.insert(ungrouped, t)
        end
    end
    local disp = {}
    for _, g in ipairs(groups) do
        local items = byGroup[g.id]
        if items then
            disp[#disp + 1] = { header = true, name = g.name }
            for _, t in ipairs(items) do disp[#disp + 1] = { team = t } end
        end
    end
    if #ungrouped > 0 then
        if next(byGroup) then disp[#disp + 1] = { header = true, name = "Ungrouped" } end
        for _, t in ipairs(ungrouped) do disp[#disp + 1] = { team = t } end
    end
    return disp, #teams
end

function UI:Refresh()
    if not frame then return end
    local disp, total = buildDisplay()
    frame.empty:SetShown(total == 0)

    for i, row in ipairs(rows) do
        local d = disp[i]
        if not d then
            row:Hide()
        elseif d.header then
            row.name:SetText("|cffffd100" .. d.name .. "|r")
            row.load:Hide(); row.del:Hide()
            row:Show()
        else
            local t = d.team
            local label = t.name
            if t.loaded then label = "|cff44ff44>|r " .. label end
            local tags = ""
            if (t.wins or 0) + (t.losses or 0) > 0 then
                tags = tags .. ("  |cffaaaaaa%d-%d|r"):format(t.wins, t.losses)
            end
            if t.script then tags = tags .. "  |cff8ec5ff(s)|r" end
            if t.notes then tags = tags .. "  |cffd0a0ff(n)|r" end
            row.name:SetText(label .. tags)
            row.load:SetScript("OnClick", function() ns.Teams:Load(t.id) end)
            row.del:SetScript("OnClick", function() ns.Teams:Delete(t.id) end)
            row.load:Show(); row.del:Show()
            row:Show()
        end
    end

    if #disp > MAX_ROWS then
        ns:Print(("Showing the first %d rows; use /llp list for everything."):format(MAX_ROWS))
    end
end

function UI:Toggle()
    if not frame then buildFrame() end
    if frame:IsShown() then frame:Hide() else frame:Show(); self:Refresh() end
end

function UI:Show()
    if not frame then buildFrame() end
    frame:Show(); self:Refresh()
end
