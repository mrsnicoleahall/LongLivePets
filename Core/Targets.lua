--[[ Long Live Pets ----------------------------------------------------------
  Targets.lua — bind a team to a tamer/NPC so it can auto-load when you target
  them. Bindings are keyed by numeric npcID parsed from the unit GUID.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Targets = {}
ns.Targets = Targets

local function db() return ns.db end

-- Pull the npcID out of a creature GUID like "Creature-0-..-<npcID>-<spawn>".
function Targets:NpcIDFromGUID(guid)
    if not guid then return nil end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if (kind == "Creature" or kind == "Vehicle" or kind == "GameObject") and npcID then
        return tonumber(npcID)
    end
    return nil
end

function Targets:CurrentNpcID()
    if not UnitExists("target") or UnitIsPlayer("target") then return nil end
    return self:NpcIDFromGUID(UnitGUID("target"))
end

-- Bind a team to the current target (or to an explicit npcID).
function Targets:Bind(teamKey, npcID)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then ns:Print('No team "' .. tostring(teamKey) .. '".'); return end
    npcID = tonumber(npcID) or self:CurrentNpcID()
    if not npcID then
        ns:Print("Target a battle-pet tamer/NPC first (or pass an npcID).")
        return
    end
    db().targets[npcID] = nil           -- clear any stale binding for this npc
    db().targets[npcID] = (select(1, ns.Teams:Resolve(teamKey)))
    t.targets = t.targets or {}
    t.targets[npcID] = true
    ns:Print(('Bound "%s" to target %d. Target them to load it.'):format(t.name, npcID))
end

function Targets:Unbind(npcID)
    npcID = tonumber(npcID) or self:CurrentNpcID()
    if not npcID then return end
    local teamID = db().targets[npcID]
    db().targets[npcID] = nil
    if teamID and ns.db.teams[teamID] and ns.db.teams[teamID].targets then
        ns.db.teams[teamID].targets[npcID] = nil
    end
    ns:Print("Unbound target " .. npcID .. ".")
end

function Targets:GetTeamForNpc(npcID)
    if not npcID then return nil end
    local teamID = db().targets[npcID]
    if teamID and db().teams[teamID] then return teamID end
    return nil
end

-- Auto-load on target change (opt-in; never during combat or a pet battle).
ns:On("PLAYER_TARGET_CHANGED", function()
    if not ns.db or not ns.db.settings.autoLoadOnTarget then return end
    if InCombatLockdown() then return end
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return end
    local npcID = ns.Targets:CurrentNpcID()
    local teamID = npcID and ns.Targets:GetTeamForNpc(npcID)
    if teamID and teamID ~= ns.db.loaded then
        ns.Teams:Load(teamID)
    end
end)
