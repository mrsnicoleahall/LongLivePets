--[[ Long Live Pets ----------------------------------------------------------
  Breed.lua — thin wrapper over the embedded LibPetBreedInfo-1.0 to return a
  pet's breed string (e.g. "B/B", "P/S", "S/S"). If the library isn't present
  it degrades to nil so nothing breaks.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Breed = {}
ns.Breed = Breed

local function lib()
    return LibStub and LibStub("LibPetBreedInfo-1.0", true)
end

-- Breed string for an owned pet (by GUID), or nil.
function Breed:Get(petID)
    if not petID then return nil end
    local L = lib()
    if not L then return nil end
    local breedID = L:GetBreedByPetID(petID)
    return breedID and L:GetBreedName(breedID) or nil
end

-- Breed from explicit stats (species/level/rarity/health/power/speed), or nil.
function Breed:GetByStats(speciesID, level, rarity, health, power, speed)
    local L = lib()
    if not L or not speciesID then return nil end
    local breedID = L:GetBreedByStats(speciesID, level, rarity, health, power, speed)
    return breedID and L:GetBreedName(breedID) or nil
end
