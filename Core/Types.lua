--[[ Long Live Pets ----------------------------------------------------------
  Types.lua — battle-pet type chart and counter helper.

  The pet-battle type wheel is public game knowledge (a fixed 10-type matrix).
  This is our own encoding of it, used to suggest counters ("Strong Vs" /
  "Tough Vs"). A full filtered pet browser is on the roadmap; this gives the
  underlying data + a /llp counter helper now.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Types = {}
ns.Types = Types

-- canonical index -> name
Types.NAME = {
    [1] = "Humanoid", [2] = "Dragonkin", [3] = "Flying", [4] = "Undead",
    [5] = "Critter", [6] = "Magic", [7] = "Elemental", [8] = "Beast",
    [9] = "Aquatic", [10] = "Mechanical",
}

-- name (lowercase) -> index
Types.INDEX = {}
for i, n in pairs(Types.NAME) do Types.INDEX[n:lower()] = i end

-- attacker -> defender it hits for +50%
local STRONG = {
    [1] = 2, [2] = 6, [6] = 3, [3] = 9, [9] = 7,
    [7] = 10, [10] = 8, [8] = 5, [5] = 4, [4] = 1,
}
-- attacker -> defender it hits for -33% (so that defender resists this attacker)
local WEAK = {
    [1] = 8, [2] = 4, [3] = 2, [4] = 9, [5] = 1,
    [6] = 10, [7] = 5, [8] = 3, [9] = 6, [10] = 7,
}

-- reverse of STRONG: which attacker type is strong against this defender
local STRONG_BY_DEFENDER = {}
for atk, def in pairs(STRONG) do STRONG_BY_DEFENDER[def] = atk end

function Types:ToIndex(typeNameOrIndex)
    if type(typeNameOrIndex) == "number" then return typeNameOrIndex end
    return self.INDEX[tostring(typeNameOrIndex):lower()]
end

-- Given an enemy pet's type, what should I bring?
--   strongAttacker = a pet type whose attacks hit the enemy for +50%
--   toughType      = a pet type that takes only -33% from the enemy's attacks
function Types:CounterFor(enemyType)
    local e = self:ToIndex(enemyType)
    if not e then return nil end
    return {
        enemy         = self.NAME[e],
        strongAttacker = self.NAME[STRONG_BY_DEFENDER[e]],
        toughType     = self.NAME[WEAK[e]],
    }
end

-- The pet-family index that deals +50% to a given enemy type.
function Types:StrongAttackerIndexVs(enemyType)
    local e = self:ToIndex(enemyType)
    return e and STRONG_BY_DEFENDER[e] or nil
end

-- The pet-family index that takes only -33% from a given enemy type.
function Types:ToughTypeIndexVs(enemyType)
    local e = self:ToIndex(enemyType)
    return e and WEAK[e] or nil
end

-- The enemy type this family deals +50% to (used for pet-card hints).
function Types:FamilyStrongVs(familyTypeIndex)
    local d = familyTypeIndex and STRONG[familyTypeIndex]
    return d and self.NAME[d] or nil
end
