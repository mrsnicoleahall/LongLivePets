--[[ Long Live Pets ----------------------------------------------------------
  Markers.lua — tag pets with one of the 8 raid-target icons. Stored per
  speciesID so a marker follows the pet across characters.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Markers = {}
ns.Markers = Markers

Markers.NAMES = {
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull",
}

local function db() return ns.db end

function Markers:Texture(index)
    if not index then return nil end
    return ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"):format(index)
end

function Markers:Get(speciesID)
    if not speciesID then return nil end
    return db().markers[speciesID]
end

function Markers:Set(speciesID, index)
    if not speciesID then return end
    if not index then
        db().markers[speciesID] = nil
    else
        db().markers[speciesID] = index
    end
    if ns.UI then ns.UI:Refresh() end
end

function Markers:Clear(speciesID)
    self:Set(speciesID, nil)
end

-- Cycle to the next marker (nil -> 1 -> 2 ... -> 8 -> nil). Handy for a
-- single-click toggle.
function Markers:Cycle(speciesID)
    local cur = self:Get(speciesID) or 0
    local nxt = cur + 1
    if nxt > 8 then nxt = nil end
    self:Set(speciesID, nxt)
    return nxt
end
