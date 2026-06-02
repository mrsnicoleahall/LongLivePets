--[[ Long Live Pets ----------------------------------------------------------
  Battle.lua — win/loss record per team.

  Manual recording is always available and exact. Auto-recording is best-effort:
  we read the winner from PET_BATTLE_FINAL_ROUND and attribute it to whichever
  team is currently loaded. If a future client tweak is needed, the manual
  commands (/llp record win|loss) are the reliable fallback.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Battle = {}
ns.Battle = Battle

-- Modern clients expose Enum.BattlePetOwner.Ally; fall back to the historical
-- ally index if it isn't present.
local ALLY_OWNER = (Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally) or 0

function Battle:Record(teamKey, didWin)
    local _, t
    if teamKey == nil then
        local id = ns.db and ns.db.loaded
        if id then t = ns.db.teams[id] end
    else
        _, t = ns.Teams:Resolve(teamKey)
    end
    if not t then ns:Print("No team to record against (load one first)."); return end
    t.wins   = t.wins   or 0
    t.losses = t.losses or 0
    if didWin then t.wins = t.wins + 1 else t.losses = t.losses + 1 end
    ns:Print(('%s: %d-%d.'):format(t.name, t.wins, t.losses))
    if ns.UI then ns.UI:Refresh() end
end

function Battle:RecordOf(t)
    local w, l = t.wins or 0, t.losses or 0
    return w, l
end

-- ---- best-effort auto-recording -------------------------------------------
local pendingWinner

ns:On("PET_BATTLE_FINAL_ROUND", function(winner)
    pendingWinner = winner
end)

ns:On("PET_BATTLE_CLOSE", function()
    if pendingWinner == nil then return end
    local winner = pendingWinner
    pendingWinner = nil
    if not ns.db or not ns.db.loaded then return end
    local t = ns.db.teams[ns.db.loaded]
    if not t then return end
    t.wins   = t.wins   or 0
    t.losses = t.losses or 0
    if winner == ALLY_OWNER then t.wins = t.wins + 1 else t.losses = t.losses + 1 end
    if ns.UI then ns.UI:Refresh() end
end)
