--[[ Long Live Pets ----------------------------------------------------------
  CounterBuilder.lua — given an enemy composition (a list of family types) and
  your owned pets, score and pick the best 3-pet counter team, with reasons.
  Pure logic — no game API, fully unit-testable.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local CounterBuilder = {}
ns.CounterBuilder = CounterBuilder

-- Score one pet against the enemy types. Returns score, reasons, answers
-- (answers[i] = true if this pet offensively or defensively answers enemy i).
function CounterBuilder:ScorePet(pet, enemyTypes)
    local score, reasons, answers = 0, {}, {}
    for i, e in ipairs(enemyTypes) do
        local eName = ns.Types.NAME[e] or "?"
        if ns.Types:StrongAttackerIndexVs(e) == pet.petType then
            score = score + 3
            reasons[#reasons + 1] = "strong vs their " .. eName
            answers[i] = true
        elseif ns.Types:ToughTypeIndexVs(e) == pet.petType then
            score = score + 2
            reasons[#reasons + 1] = "resists their " .. eName
            answers[i] = true
        end
    end
    if (pet.level or 0) >= 25 then score = score + 1 end
    if (pet.rarity or 0) >= 4 then score = score + 1 end
    return score, reasons, answers
end

-- Build a counter team. Returns { picks = { {pet, score, reasons}, ... },
-- covered, total }. Greedy: each pick maximizes NEW enemy coverage, then score.
function CounterBuilder:Build(comp, ownedPets, maxPicks)
    maxPicks = maxPicks or 3
    local enemyTypes = (comp and comp.types) or {}

    local pool = {}
    for _, p in ipairs(ownedPets or {}) do
        if p.petType then
            local s, reasons, answers = self:ScorePet(p, enemyTypes)
            pool[#pool + 1] = { pet = p, score = s, reasons = reasons, answers = answers }
        end
    end

    local covered = {}
    local function newCoverage(c)
        local n = 0
        for i in pairs(c.answers) do if not covered[i] then n = n + 1 end end
        return n
    end

    local picks = {}
    while #picks < maxPicks and #pool > 0 do
        table.sort(pool, function(a, b)
            local na, nb = newCoverage(a), newCoverage(b)
            if na ~= nb then return na > nb end
            if a.score ~= b.score then return a.score > b.score end
            return (a.pet.name or "") < (b.pet.name or "")
        end)
        local best = table.remove(pool, 1)
        for i in pairs(best.answers) do covered[i] = true end
        picks[#picks + 1] = best
    end

    local cov = 0
    for _ in pairs(covered) do cov = cov + 1 end
    return { picks = picks, covered = cov, total = #enemyTypes }
end
