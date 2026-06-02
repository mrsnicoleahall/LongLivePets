--[[ Long Live Pets ----------------------------------------------------------
  Roster.lua — read your owned battle pets and filter them. This is the data
  engine behind the (original) pet browser window; no Blizzard journal UI is
  touched.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Roster = {}
ns.Roster = Roster

-- Build a plain list of the pets you own.
function Roster:GetOwnedPets()
    local pets = {}
    if not C_PetJournal or not C_PetJournal.GetNumPets then return pets end
    local n = C_PetJournal.GetNumPets()
    for i = 1, n do
        local petID, speciesID, owned, customName, level, _, _, name, icon, petType =
            C_PetJournal.GetPetInfoByIndex(i)
        if owned and petID then
            local rarity
            if C_PetJournal.GetPetStats then
                local _, _, _, _, r = C_PetJournal.GetPetStats(petID)
                rarity = r
            end
            pets[#pets + 1] = {
                petID = petID, speciesID = speciesID,
                name = (customName and customName ~= "" and customName) or name or "Pet",
                level = level or 1, petType = petType, icon = icon, rarity = rarity,
            }
        end
    end
    return pets
end

--[[ Filter owned pets. opts:
       search    : substring match on name (case-insensitive)
       level     : exact level
       minLevel  : level >=
       typeIndex : pet family index (1..10)
       strongVs  : enemy type (name/index) -> pets that hit it for +50%
       toughVs   : enemy type (name/index) -> pets that resist its hits
       maxOnly   : true -> level 25 only
       rarity    : minimum rarity
----------------------------------------------------------------------------]]
function Roster:Filter(opts)
    opts = opts or {}
    local search = opts.search and opts.search ~= "" and opts.search:lower() or nil
    local strongIdx = opts.strongVs and ns.Types:StrongAttackerIndexVs(opts.strongVs)
    local toughIdx  = opts.toughVs and ns.Types:ToughTypeIndexVs(opts.toughVs)

    local out = {}
    for _, p in ipairs(self:GetOwnedPets()) do
        local ok = true
        if search and not p.name:lower():find(search, 1, true) then ok = false end
        if ok and opts.maxOnly and p.level ~= 25 then ok = false end
        if ok and opts.level and p.level ~= opts.level then ok = false end
        if ok and opts.minLevel and p.level < opts.minLevel then ok = false end
        if ok and opts.typeIndex and p.petType ~= opts.typeIndex then ok = false end
        if ok and strongIdx and p.petType ~= strongIdx then ok = false end
        if ok and toughIdx and p.petType ~= toughIdx then ok = false end
        if ok and opts.rarity and (p.rarity or 0) < opts.rarity then ok = false end
        if ok then out[#out + 1] = p end
    end

    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Put a pet into a battle slot (used by the browser).
function Roster:SlotPet(petID, slot)
    slot = tonumber(slot) or 1
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
        ns:Print("Can't change pets during a battle."); return
    end
    if InCombatLockdown() then ns:Print("Can't change pets in combat."); return end
    C_PetJournal.SetPetLoadOutInfo(slot, petID)
end
