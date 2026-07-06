--[[ Long Live Pets ----------------------------------------------------------
  Abilities.lua — read and set a loaded pet's ability loadout.

  A battle pet has 3 ability slots; each slot offers 2 options (the second
  unlocks at a higher level). GetPetAbilityList returns up to 6 ability IDs:
  indices 1-3 are the first option of each slot, 4-6 the second. The currently
  selected ability per slot comes from GetPetLoadOutInfo.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Abilities = {}
ns.Abilities = Abilities

local function abilityInfo(id)
    if not id then return nil end
    local entry = { id = id, name = "?", icon = nil }
    if C_PetBattles and C_PetBattles.GetAbilityInfoByID then
        local _, name, icon, _, desc = C_PetBattles.GetAbilityInfoByID(id)
        entry.name, entry.icon, entry.desc = name or "?", icon, desc
    end
    return entry
end

-- Returns slots = { [1] = { optionA, optionB }, ... }, petID, petLevel.
-- Each option = { id, name, icon, desc, selected, reqLevel, locked }.
function Abilities:GetLayout(loadoutSlot)
    local petID, a1, a2, a3 = C_PetJournal.GetPetLoadOutInfo(loadoutSlot)
    if not petID then return nil end
    local speciesID, _, petLevel = C_PetJournal.GetPetInfoByPetID(petID)

    local ids, levels = {}, {}
    if C_PetJournal.GetPetAbilityList then
        C_PetJournal.GetPetAbilityList(speciesID, ids, levels)
    end
    local selected = { a1, a2, a3 }

    local slots = {}
    for i = 1, 3 do
        local A = abilityInfo(ids[i])
        local B = abilityInfo(ids[i + 3])
        if A then A.selected = (selected[i] == A.id); A.reqLevel = levels[i] or 1 end
        if B then
            B.selected = (selected[i] == B.id)
            B.reqLevel = levels[i + 3] or 1
            B.locked = (petLevel or 25) < B.reqLevel
        end
        slots[i] = { A, B }
    end
    return slots, petID, petLevel
end

-- Choose ability `abilityID` for ability-slot `abilitySlot` (1-3) of the pet in
-- battle slot `loadoutSlot`.
function Abilities:Set(loadoutSlot, abilitySlot, abilityID)
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
        ns:Print("Can't change abilities during a battle."); return
    end
    if C_PetJournal.SetAbility then
        C_PetJournal.SetAbility(loadoutSlot, abilitySlot, abilityID)
    end
end
