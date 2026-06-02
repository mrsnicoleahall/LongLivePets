--[[ Long Live Pets ----------------------------------------------------------
  Loadout.lua — read the slotted pets, and write a saved team back into the
  slots. Handles three kinds of saved slot:
    * a specific pet you own        (petID)        — normal saved teams
    * a "leveling" slot             (leveling)     — pulled from the queue
    * a species reference           (speciesID)    — imported teams
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

function Loadout:Capture()
    local pets = {}
    for slot = 1, self:GetNumSlots() do
        local petID, ab1, ab2, ab3 = C_PetJournal.GetPetLoadOutInfo(slot)
        if petID then
            local speciesID = C_PetJournal.GetPetInfoByPetID(petID)
            pets[slot] = {
                petID = petID, speciesID = speciesID,
                abilities = { ab1, ab2, ab3 }, leveling = false,
            }
        end
    end
    return pets
end

-- Best-effort: find an owned pet of a species (prefers the highest level).
-- Used for imported teams that only know the species, not your specific pet.
function Loadout:FindPetForSpecies(speciesID)
    if not speciesID or not C_PetJournal.GetNumPets then return nil end
    local numPets = C_PetJournal.GetNumPets()
    local best, bestLevel
    for i = 1, numPets do
        local petID, sid, owned, _, level = C_PetJournal.GetPetInfoByIndex(i)
        if owned and sid == speciesID then
            if not bestLevel or (level or 0) > bestLevel then
                best, bestLevel = petID, level or 0
            end
        end
    end
    return best
end

local function canModify()
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

function Loadout:Apply(pets)
    if not pets then return false end
    if not canModify() then return false end

    local levelingIndex = 0  -- which leveling slot we're on (for queue picks)

    for slot = 1, self:GetNumSlots() do
        local p = pets[slot]
        if p then
            local petID = p.petID

            if p.leveling then
                levelingIndex = levelingIndex + 1
                petID = ns.Queue and ns.Queue:NthPending(levelingIndex) or nil

            elseif not petID and p.speciesID then
                petID = self:FindPetForSpecies(p.speciesID)
            end

            if petID then
                C_PetJournal.SetPetLoadOutInfo(slot, petID)
                -- Only re-apply saved abilities for fixed pets, not leveling
                -- pulls (a leveling pet keeps its own abilities).
                if not p.leveling and p.abilities then
                    for i = 1, 3 do
                        if p.abilities[i] then
                            C_PetJournal.SetAbility(slot, i, p.abilities[i])
                        end
                    end
                end
            end
        end
    end
    return true
end
