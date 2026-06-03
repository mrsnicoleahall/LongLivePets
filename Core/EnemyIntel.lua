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

    -- On Midnight, enemy pet info can be "secret" mid-battle. Only keep plain
    -- numbers (type() doesn't convert, so it can't taint us); skip anything
    -- secret rather than risk storing/serializing a protected value.
    local types, species = {}, {}
    for i = 1, n do
        local pt = C_PetBattles.GetPetType and C_PetBattles.GetPetType(enemy, i)
        local sp = C_PetBattles.GetPetSpeciesID and C_PetBattles.GetPetSpeciesID(enemy, i)
        if type(pt) == "number" then types[i] = pt end
        if type(sp) == "number" then species[i] = sp end
    end

    local npcID = self._pendingNpc
    if npcID then self:Record(npcID, self._pendingName, types, species) end
end

-- Snapshot the target right as the battle opens. On Midnight the enemy's unit
-- GUID/name become protected "secret" values once the battle starts — reading
-- them taints us and breaks secure addons (tdBattlePetScript). So we use the
-- id/name Targets cached the last time we targeted them OUT of battle.
ns:On("PET_BATTLE_OPENING_START", function()
    EnemyIntel._pendingNpc  = ns.Targets and ns.Targets._lastNpcID or nil
    EnemyIntel._pendingName = ns.Targets and ns.Targets._lastName or nil
end)
ns:On("PET_BATTLE_OPENING_DONE", function() EnemyIntel:Capture() end)
