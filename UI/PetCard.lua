--[[ Long Live Pets ----------------------------------------------------------
  PetCard.lua — a hover "card" for a pet, shown via GameTooltip. Pulls stats and
  flavor from Blizzard's public pet APIs; original assembly code.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local PetCard = {}
ns.PetCard = PetCard

local RARITY_NAME = { [1] = "Poor", [2] = "Common", [3] = "Uncommon", [4] = "Rare", [5] = "Epic" }
local RARITY_COLOR = {
    [1] = { .62, .62, .62 }, [2] = { 1, 1, 1 }, [3] = { .12, 1, 0 },
    [4] = { 0, .44, .87 }, [5] = { .64, .21, .93 },
}

-- Build the card as a list of line descriptors (testable without a real
-- tooltip): { kind="title"|"line"|"double"|"wrap", ... }.
function PetCard:BuildLines(pet)
    local lines = {}
    lines[#lines + 1] = { kind = "title", text = pet.name or "Pet",
        color = RARITY_COLOR[pet.rarity or 2] }

    local typeName = pet.petType and ns.Types.NAME[pet.petType] or "?"
    local rarityName = RARITY_NAME[pet.rarity or 0]
    local sub = ("Level %d  %s"):format(pet.level or 1, typeName)
    if rarityName then sub = sub .. "  (" .. rarityName .. ")" end
    local breed = pet.breed or (ns.Breed and ns.Breed:Get(pet.petID))
    if breed then sub = sub .. "  |cff8ec5ff" .. breed .. "|r" end
    lines[#lines + 1] = { kind = "line", text = sub, color = { .8, .8, .8 } }

    if C_PetJournal and C_PetJournal.GetPetStats then
        local health, _, power, speed = C_PetJournal.GetPetStats(pet.petID)
        if health then
            lines[#lines + 1] = { kind = "double", left = "Health", right = tostring(health) }
            lines[#lines + 1] = { kind = "double", left = "Power",  right = tostring(power) }
            lines[#lines + 1] = { kind = "double", left = "Speed",  right = tostring(speed) }
        end
    end

    if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID and pet.speciesID then
        local _, _, _, _, source, desc = C_PetJournal.GetPetInfoBySpeciesID(pet.speciesID)
        if desc and desc ~= "" then
            lines[#lines + 1] = { kind = "gap" }
            lines[#lines + 1] = { kind = "wrap", text = desc, color = { .9, .9, .9 } }
        end
        if source and source ~= "" then
            lines[#lines + 1] = { kind = "gap" }
            lines[#lines + 1] = { kind = "wrap", text = source, color = { .6, .6, .6 } }
        end
    end

    -- Counter hint based on the pet's family type.
    local beats = pet.petType and ns.Types:FamilyStrongVs(pet.petType)
    if beats then
        lines[#lines + 1] = { kind = "gap" }
        lines[#lines + 1] = { kind = "line",
            text = ("Family is strong vs: %s"):format(beats), color = { .5, .8, .5 } }
    end

    return lines
end

function PetCard:Show(anchor, pet)
    if not GameTooltip or not pet then return end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    for _, l in ipairs(self:BuildLines(pet)) do
        local c = l.color or { 1, 1, 1 }
        if l.kind == "title" then
            GameTooltip:AddLine(l.text, c[1], c[2], c[3])
        elseif l.kind == "double" then
            GameTooltip:AddDoubleLine(l.left, l.right, .8, .8, .8, 1, 1, 1)
        elseif l.kind == "wrap" then
            GameTooltip:AddLine(l.text, c[1], c[2], c[3], true)
        elseif l.kind == "gap" then
            GameTooltip:AddLine(" ")
        else
            GameTooltip:AddLine(l.text, c[1], c[2], c[3])
        end
    end
    GameTooltip:Show()
end

function PetCard:Hide()
    if GameTooltip then GameTooltip:Hide() end
end
