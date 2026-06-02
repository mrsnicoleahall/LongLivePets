--[[ Long Live Pets ----------------------------------------------------------
  MainWindow.lua — a small, movable window listing your saved teams with
  Load / Delete buttons and a "Save current" control. Built with stock
  Blizzard templates so it inherits the game's look and needs no art.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local UI = {}
ns.UI = UI

local ROW_H    = 22
local MAX_ROWS = 14

local frame
local rows = {}

local function BuildFrame()
    frame = CreateFrame("Frame", "LongLivePetsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(340, 440)
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
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Long Live Pets")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Save-current controls -------------------------------------------------
    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetSize(110, 22)
    save:SetPoint("TOPLEFT", 16, -46)
    save:SetText("Save current")

    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(168, 22)
    edit:SetPoint("LEFT", save, "RIGHT", 14, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(40)

    local function commitSave()
        local name = edit:GetText()
        if name and name ~= "" then
            ns.Teams:SaveCurrent(name)
            edit:SetText("")
            edit:ClearFocus()
        end
    end
    save:SetScript("OnClick", commitSave)
    edit:SetScript("OnEnterPressed", commitSave)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    -- Team list -------------------------------------------------------------
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 16, -82)
    list:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.list = list

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", 2, 0)
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

function UI:Refresh()
    if not frame then return end
    local teams = ns.Teams:List()
    frame.empty:SetShown(#teams == 0)

    for i, row in ipairs(rows) do
        local t = teams[i]
        if t then
            local label = t.name
            if t.script then label = label .. "  |cff8ec5ff(script)|r" end
            row.name:SetText(label)
            row.load:SetScript("OnClick", function() ns.Teams:Load(t.id) end)
            row.del:SetScript("OnClick", function() ns.Teams:Delete(t.id) end)
            row:Show()
        else
            row:Hide()
        end
    end

    if #teams > MAX_ROWS then
        ns:Print(("Showing the first %d of %d teams here; use /llp list for the rest.")
            :format(MAX_ROWS, #teams))
    end
end

function UI:Toggle()
    if not frame then BuildFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        self:Refresh()
    end
end

function UI:Show()
    if not frame then BuildFrame() end
    frame:Show()
    self:Refresh()
end
