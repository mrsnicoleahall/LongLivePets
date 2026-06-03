--[[ Long Live Pets ----------------------------------------------------------
  MigrateRematch.lua — one-time import of teams + groups from Rematch.

  Rematch (and the community fork) store data in the shared globals
  Rematch5SavedTeams / Rematch5SavedGroups. When those are loaded in memory
  (i.e. Rematch / Rematch [Community] is enabled), `/llp importrematch` copies:
    - each team's name, 3 pets, notes, and target NPCs
    - groups (by name) and the team→group assignment + order

  We read pet GUIDs straight across (Long Live Pets loads by GUID), and resolve
  each to a speciesID for display. This is our own original glue — no Rematch
  code is used.

  Not migrated: ability selections (Rematch encodes them in its own "tags"
  format; pets keep their current abilities) and team→script links (your
  tdBattlePetScript scripts themselves carry over automatically since that addon
  is shared — re-link a script to a team via right-click → Set script).
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local M = {}
ns.MigrateRematch = M

local function speciesOf(petID)
    if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        return (C_PetJournal.GetPetInfoByPetID(petID))
    end
end

local function count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function M:Run()
    local RT = _G.Rematch5SavedTeams
    local RG = _G.Rematch5SavedGroups

    -- Report exactly what we can see, so it's clear if data isn't loaded.
    ns:Print(("Rematch data in memory: |cffffd100%d|r teams, |cffffd100%d|r groups.")
        :format(count(RT), count(RG)))

    if type(RT) ~= "table" or not next(RT) then
        ns:Print("No teams found. Enable |cffffd100Rematch [Community]|r on the AddOns screen, |cffffd100/reload|r, then run |cffffd100/llp importrematch|r again.")
        return
    end
    if type(RG) ~= "table" or not next(RG) then
        ns:Print("|cffff9900Note:|r no group data is loaded, so teams will import ungrouped. (Make sure Rematch [Community] is enabled, then /reload and re-run to get groups.)")
    end

    -- 1. groups: create an LLP group per Rematch group
    local gmap, nGroups = {}, 0    -- rematchGroupID -> llp group id
    if type(RG) == "table" then
        local gids = {}
        for gid in pairs(RG) do gids[#gids + 1] = gid end
        table.sort(gids)
        for _, gid in ipairs(gids) do
            local g = RG[gid]
            local name = (type(g) == "table" and g.name) or gid
            if not ns.Groups:Resolve(name) then nGroups = nGroups + 1 end
            gmap[gid] = ns.Groups:Resolve(name) or ns.Groups:Create(name)
        end
    end

    -- 2. desired order of each team (its index within its group's team list)
    local order = {}
    if type(RG) == "table" then
        for _, g in pairs(RG) do
            if type(g) == "table" and type(g.teams) == "table" then
                for i, tid in ipairs(g.teams) do order[tid] = i end
            end
        end
    end

    -- 3. teams (each wrapped so one bad team can't abort the whole import)
    local nTeams, nPets = 0, 0
    for tid, t in pairs(RT) do
        if type(t) == "table" and t.name then
            pcall(function()
                local pets = {}
                if type(t.pets) == "table" then
                    for slot = 1, 3 do
                        local p = t.pets[slot]
                        if type(p) == "string" and p:find("^BattlePet%-") then
                            pets[slot] = { petID = p, speciesID = speciesOf(p) }
                            nPets = nPets + 1
                        end
                    end
                end

                local id = ns.Teams:CreateImported({
                    name = t.name,
                    notes = (type(t.notes) == "string" and t.notes ~= "") and t.notes or nil,
                    pets = pets,
                })

                local team = id and ns.db.teams[id]
                if team then
                    -- assign group directly from the id map (most reliable)
                    if t.groupID and gmap[t.groupID] then team.group = gmap[t.groupID] end
                    if order[tid] then team.order = order[tid] end
                    if type(t.targets) == "table" then
                        team.targets = {}
                        for _, npc in ipairs(t.targets) do
                            if tonumber(npc) then
                                team.targets[tonumber(npc)] = true
                                ns.db.targets[tonumber(npc)] = id
                            end
                        end
                    end
                    nTeams = nTeams + 1
                end
            end)
        end
    end

    ns:Print(("Imported |cff44ff44%d teams|r and |cff44ff44%d groups|r from Rematch (%d pets, plus notes & targets)."):format(nTeams, nGroups, nPets))
    ns:Print("Abilities default to each pet's current set; tdBattlePetScript scripts already carried over — re-link per team via right-click → Set script if you used them.")
    if ns.UI then ns.UI:Refresh() end
end
