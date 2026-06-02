--[[ Long Live Pets ----------------------------------------------------------
  Loadout.lua — read the currently slotted battle pets and write a saved team
  back into the slots, using Blizzard's C_PetJournal API directly.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Loadout = {}
ns.Loadout = Loadout

local DEFAULT_SLOTS = 3

function Loadout:GetNumSlots()
    if C_PetJournal.GetNumPetLoadOutSlots then
        local n = C_PetJournal.GetNumPetLoadOutSlots()
        if n and n > 0 then return n end
    end
    return DEFAULT_SLOTS
end

-- Snapshot the slots into our own plain-data shape.
function Loadout:Capture()
    local pets = {}
    for slot = 1, self:GetNumSlots() do
        local petID, ab1, ab2, ab3 = C_PetJournal.GetPetLoadOutInfo(slot)
        if petID then
            local speciesID = C_PetJournal.GetPetInfoByPetID(petID)
            pets[slot] = {
                petID     = petID,
                speciesID = speciesID,
                abilities = { ab1, ab2, ab3 },
            }
        end
    end
    return pets
end

-- Returns true if we are clear to change the loadout right now.
local function CanModify()
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
        ns:Print("Can't change pets during a pet battle.")
        return false
    end
    if InCombatLockdown() then
        ns:Print("Can't change pets while in combat.")
        return false
    end
    return true
end

-- Write a saved team's pets back into the battle slots.
function Loadout:Apply(pets)
    if not pets then return false end
    if not CanModify() then return false end

    for slot = 1, self:GetNumSlots() do
        local p = pets[slot]
        if p and p.petID then
            C_PetJournal.SetPetLoadOutInfo(slot, p.petID)
            if p.abilities then
                for i = 1, 3 do
                    if p.abilities[i] then
                        C_PetJournal.SetAbility(slot, i, p.abilities[i])
                    end
                end
            end
        end
    end
    return true
end
