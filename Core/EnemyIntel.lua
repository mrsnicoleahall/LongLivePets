--[[ Long Live Pets ----------------------------------------------------------
  EnemyIntel.lua — learn each tamer/NPC's pet composition by observing your own
  battles, so the counter-builder has something to work against. Our own data,
  built from play; no third-party database.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local EnemyIntel = {}
ns.EnemyIntel = EnemyIntel

local function db() return ns.db end

-- Store a composition for an NPC. Pure; testable.
function EnemyIntel:Record(npcID, name, types, species)
    if not npcID then return end
    db().enemyIntel[npcID] = {
        name = name, types = types or {}, species = species or {}, seen = time(),
    }
end

function EnemyIntel:Get(npcID)
    return npcID and db().enemyIntel[npcID] or nil
end

function EnemyIntel:GetForCurrentTarget()
    local id = ns.Targets and ns.Targets:CurrentNpcID()
    return id and self:Get(id), id
end

-- Read the enemy side of a live pet battle and store it.
function EnemyIntel:Capture()
    if not (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) then return end
    local enemy = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy) or 1
    local n = C_PetBattles.GetNumPets and C_PetBattles.GetNumPets(enemy)
    if not n or n == 0 then return end

    local types, species = {}, {}
    for i = 1, n do
        if C_PetBattles.GetPetType then types[i] = C_PetBattles.GetPetType(enemy, i) end
        if C_PetBattles.GetPetSpeciesID then species[i] = C_PetBattles.GetPetSpeciesID(enemy, i) end
    end

    local npcID = self._pendingNpc
    if npcID then self:Record(npcID, self._pendingName, types, species) end
end

-- Snapshot the target right as the battle opens (we may lose the unit later).
ns:On("PET_BATTLE_OPENING_START", function()
    EnemyIntel._pendingNpc  = ns.Targets and ns.Targets:CurrentNpcID()
    EnemyIntel._pendingName = (UnitName and UnitExists and UnitExists("target")) and UnitName("target") or nil
end)
ns:On("PET_BATTLE_OPENING_DONE", function() EnemyIntel:Capture() end)
