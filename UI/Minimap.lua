--[[ Long Live Pets ----------------------------------------------------------
  Minimap.lua — a simple, self-contained minimap button (no external libs).
  Drag it around the minimap edge; left-click opens the window.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Minimap_ = {}
ns.Minimap = Minimap_

local button
local RADIUS = 80

local function position()
    if not button then return end
    local angle = math.rad(ns.db.settings.minimap.angle or 215)
    button:SetPoint("CENTER", Minimap, "CENTER",
        RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

function Minimap_:Create()
    if button then position(); return end
    if not Minimap then return end

    button = CreateFrame("Button", "LongLivePetsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- circular icon (mask trims the square art into a clean round button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\LongLivePets\\Textures\\icon.png")
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 7, -6)
    if icon.SetMask then
        icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end
    button.icon = icon

    -- the standard tracking-border ring drawn on top
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)

    button:SetScript("OnClick", function() ns.UI:Toggle() end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            px, py = px / scale, py / scale
            ns.db.settings.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            position()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Long Live Pets")
        GameTooltip:AddLine("Click to open the team window.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    position()
    button:SetShown(not ns.db.settings.minimap.hide)
end

function Minimap_:Toggle()
    ns.db.settings.minimap.hide = not ns.db.settings.minimap.hide
    if not button then self:Create() end
    if button then button:SetShown(not ns.db.settings.minimap.hide) end
    ns:Print(ns.db.settings.minimap.hide and "Minimap button hidden." or "Minimap button shown.")
end

-- Create on login, and again on entering world as a safety net (some UIs
-- finish setting up the minimap late).
local function ensure() if ns.db then ns.Minimap:Create() end end
ns:On("PLAYER_LOGIN", ensure)
ns:On("PLAYER_ENTERING_WORLD", ensure)
