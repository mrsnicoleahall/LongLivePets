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

-- tdBattlePetScript stores its Rematch-plugin scripts keyed by the Rematch
-- teamID, each as { name=, code= }. The script's name is the team name, which
-- is exactly what our Integration:Arm looks up. So during import we can re-link
-- each team to its script automatically.
local function rematchScriptNameFor(rematchTeamID)
    local td = _G.TD_DB_BATTLEPETSCRIPT_GLOBAL
    local R = td and td.global and td.global.scripts and td.global.scripts.Rematch
    local e = R and rematchTeamID and R[rematchTeamID]
    return type(e) == "table" and e.name or nil
end

-- Non-destructive: link tdBattlePetScript scripts to EXISTING LLP teams (for
-- when teams were already imported). Matches a team to its script two ways:
--   1. via the Rematch teamID (if Rematch data is loaded): team name -> Rematch
--      teamID -> script  (covers renamed scripts too)
--   2. by exact script-name == team-name  (works with only tdBattlePetScript)
function M:LinkScripts()
    local td = _G.TD_DB_BATTLEPETSCRIPT_GLOBAL
    local R = td and td.global and td.global.scripts and td.global.scripts.Rematch
    if type(R) ~= "table" or not next(R) then
        ns:Print("No tdBattlePetScript scripts found. Enable |cffffd100tdBattlePetScript|r, |cffffd100/reload|r, then run |cffffd100/llp linkscripts|r again.")
        return
    end

    -- script names that exist (for the name==name fallback)
    local scriptByName = {}
    for _, e in pairs(R) do
        if type(e) == "table" and e.name then scriptByName[e.name:lower()] = e.name end
    end

    -- team-name -> script-name via the Rematch teamID map (most precise)
    local viaTeamID = {}
    local RT = _G.Rematch5SavedTeams
    if type(RT) == "table" then
        for tid, t in pairs(RT) do
            if type(t) == "table" and t.name then
                local e = R[tid]
                if type(e) == "table" and e.name then viaTeamID[t.name:lower()] = e.name end
            end
        end
    end

    local n = 0
    for _, team in pairs(ns.db.teams) do
        if team.name then
            local key = team.name:lower()
            local sn = viaTeamID[key] or scriptByName[key]
            if sn and team.script ~= sn then team.script = sn; n = n + 1 end
        end
    end
    ns:Print(("Linked |cff44ff44%d|r team(s) to tdBattlePetScript scripts."):format(n))
    if not next(viaTeamID) then
        ns:Print("(Enable |cffffd100Rematch [Community]|r too and re-run to also match scripts that were renamed.)")
    end
    if ns.UI then ns.UI:Refresh() end
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
    local nTeams, nPets, nScripts = 0, 0, 0
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
                        elseif type(p) == "string" and p:find("^random") then
                            -- Rematch "random" = a leveling/wildcard slot; keep it
                            -- as a leveling slot so the team still has 3 slots.
                            pets[slot] = { leveling = true }
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
                    -- re-link the tdBattlePetScript script for this team, if any
                    local scriptName = rematchScriptNameFor(tid)
                    if scriptName then team.script = scriptName; nScripts = nScripts + 1 end
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

    ns:Print(("Imported |cff44ff44%d teams|r and |cff44ff44%d groups|r from Rematch (%d pets, %d scripts linked)."):format(nTeams, nGroups, nPets, nScripts))
    if nScripts > 0 then
        ns:Print(("Auto-linked |cff44ff44%d|r tdBattlePetScript scripts by team. Load a team and start a battle to arm its script."):format(nScripts))
    end
    ns:Print("Abilities: LLP remembers each team's ability picks when you Save it. Imported teams use each pet's current abilities until you re-save them (Rematch's packed ability data can't be decoded safely).")
    if ns.UI then ns.UI:Refresh() end
end
