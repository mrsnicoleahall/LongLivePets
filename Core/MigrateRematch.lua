--[[ Long Live Pets ----------------------------------------------------------
  MigrateRematch.lua — one-command import of everything from Rematch.

  Rematch and the community fork store data in the shared globals
  Rematch5SavedTeams / Rematch5SavedGroups (both write to the SAME tables). When
  those are loaded in memory (i.e. Rematch / Rematch [Community] is enabled),
  a single `/llp importrematch` copies:
    - each team's name, its 3 pets, notes, and target NPCs
    - real groups (by name) plus the team -> group assignment and order
    - battle scripts: any tdBattlePetScript strategy attached to a team is copied
      into tdBattlePetScript's own "Base" plugin and linked to the team, so it
      keeps working even after you remove Rematch entirely.

  Design notes:
    - Pet GUIDs carry straight across (Long Live Pets loads by GUID); we resolve
      each to a speciesID for display.
    - The import is idempotent: re-running skips any team whose name already
      exists, so you can run it again safely (e.g. after enabling more addons).
    - Rematch's meta groups ("Ungrouped Teams", "Favorite Teams") are skipped;
      their teams import as ungrouped.
    - Not migrated: ability selections (Rematch packs those into its own "tags"
      format that can't be decoded safely) — imported teams use each pet's
      current abilities until you re-save them.

  This is our own original glue — no Rematch code is used.
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

-- The Rematch plugin inside tdBattlePetScript keeps each strategy keyed by the
-- Rematch teamID, as { name=, code= }. (The script name is normally the team
-- name.) Returns that table (or nil).
local function rematchScripts()
    local td = _G.TD_DB_BATTLEPETSCRIPT_GLOBAL
    return td and td.global and td.global.scripts and td.global.scripts.Rematch
end

-- Core linker (silent). Points every LLP team at its tdBattlePetScript by name,
-- matched two ways, most precise first:
--   1. via the Rematch teamID map (team name -> Rematch teamID -> script name);
--      this also follows scripts that were renamed away from the team name.
--   2. by exact script-name == team-name, scanning every tdBattlePetScript
--      plugin (so scripts we copied into "Base" during import match too).
-- Returns (count linked, sawTeamIDMap).
local function relinkAll()
    local td = _G.TD_DB_BATTLEPETSCRIPT_GLOBAL
    local scripts = td and td.global and td.global.scripts
    if type(scripts) ~= "table" or not next(scripts) then return 0, false end

    -- script name -> canonical name, across ALL plugins (name==name fallback)
    local scriptByName = {}
    for _, plugin in pairs(scripts) do
        if type(plugin) == "table" then
            for _, e in pairs(plugin) do
                if type(e) == "table" and e.name then scriptByName[e.name:lower()] = e.name end
            end
        end
    end

    -- team name -> script name via the Rematch teamID map (most precise)
    local viaTeamID = {}
    local R, RT = scripts.Rematch, _G.Rematch5SavedTeams
    if type(R) == "table" and type(RT) == "table" then
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
    return n, next(viaTeamID) ~= nil
end

-- Public, verbose re-link — for teams that were already imported (or imported
-- while tdBattlePetScript was disabled). Non-destructive.
function M:LinkScripts()
    local n, sawTeamIDMap = relinkAll()
    if n == 0 and not rematchScripts() then
        ns:Print("No tdBattlePetScript scripts found. Enable |cffffd100tdBattlePetScript|r, |cffffd100/reload|r, then run |cffffd100/llp linkscripts|r again.")
        return
    end
    ns:Print(("Linked |cff44ff44%d|r team(s) to tdBattlePetScript scripts."):format(n))
    if not sawTeamIDMap then
        ns:Print("(Enable |cffffd100Rematch [Community]|r too and re-run to also match scripts that were renamed.)")
    end
    if ns.UI then ns.UI:Refresh() end
end

function M:Run()
    local RT = _G.Rematch5SavedTeams
    local RG = _G.Rematch5SavedGroups
    local R  = rematchScripts()

    -- Report exactly what we can see, so it's clear if data isn't loaded.
    ns:Print(("Rematch data in memory: |cffffd100%d|r teams, |cffffd100%d|r groups.")
        :format(count(RT), count(RG)))

    if type(RT) ~= "table" or not next(RT) then
        ns:Print("No teams found. Enable |cffffd100Rematch|r (or |cffffd100Rematch [Community]|r) on the AddOns screen, |cffffd100/reload|r, then run |cffffd100/llp importrematch|r again.")
        return
    end
    if type(RG) ~= "table" or not next(RG) then
        ns:Print("|cffff9900Note:|r no group data is loaded, so teams will import ungrouped. (Make sure Rematch is enabled, /reload, and re-run to get groups.)")
    end

    -- Index existing LLP teams by name so re-running never duplicates a team.
    local existingByName = {}
    for _, t in pairs(ns.db.teams) do
        if t.name then existingByName[t.name:lower()] = true end
    end

    -- 1. groups: one LLP group per REAL Rematch group. Skip meta groups
    --    ("Ungrouped Teams" / "Favorite Teams"); their teams import ungrouped.
    local gmap, nGroups = {}, 0    -- rematchGroupID -> llp group id
    if type(RG) == "table" then
        local gids = {}
        for gid in pairs(RG) do gids[#gids + 1] = gid end
        table.sort(gids)
        for _, gid in ipairs(gids) do
            local g = RG[gid]
            local isMeta = (type(g) == "table" and g.meta == true)
                or gid == "group:none" or gid == "group:favorites"
            if not isMeta then
                local name = (type(g) == "table" and g.name) or gid
                if not ns.Groups:Resolve(name) then nGroups = nGroups + 1 end
                gmap[gid] = ns.Groups:Resolve(name) or ns.Groups:Create(name)
            end
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
    local nTeams, nPets, nSkipped = 0, 0, 0
    for tid, t in pairs(RT) do
        if type(t) == "table" and t.name then
            if existingByName[t.name:lower()] then
                nSkipped = nSkipped + 1
            else
                pcall(function()
                    local pets = {}
                    if type(t.pets) == "table" then
                        for slot = 1, 3 do
                            local p = t.pets[slot]
                            if type(p) == "string" and p:find("^BattlePet%-") then
                                pets[slot] = { petID = p, speciesID = speciesOf(p) }
                                nPets = nPets + 1
                            elseif type(p) == "string" and p:find("^random") then
                                -- Rematch "random" = a leveling/wildcard slot; keep
                                -- it as a leveling slot so the team still has 3 slots.
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
                        -- assign group directly from the id map (nil = ungrouped)
                        if t.groupID and gmap[t.groupID] then team.group = gmap[t.groupID] end
                        if order[tid] then team.order = order[tid] end
                        -- copy this team's battle script into tdBattlePetScript's
                        -- always-on "Base" plugin, so it survives Rematch removal.
                        local e = type(R) == "table" and R[tid]
                        if type(e) == "table" and e.name and e.name ~= ""
                            and e.code and e.code ~= "" and ns.Integration then
                            pcall(function() ns.Integration:ImportScript(e.name, e.code) end)
                        end
                        if type(t.targets) == "table" then
                            team.targets = {}
                            for _, npc in ipairs(t.targets) do
                                if tonumber(npc) then
                                    team.targets[tonumber(npc)] = true
                                    ns.db.targets[tonumber(npc)] = id
                                end
                            end
                        end
                        existingByName[t.name:lower()] = true
                        nTeams = nTeams + 1
                    end
                end)
            end
        end
    end

    -- 4. one linking pass over every team (covers the copies above, teamID
    --    matches, renamed scripts, and any script name == team name).
    local nScripts = relinkAll()

    ns:Print(("Imported |cff44ff44%d teams|r and |cff44ff44%d groups|r from Rematch (%d pets, %d scripts linked).")
        :format(nTeams, nGroups, nPets, nScripts))
    if nSkipped > 0 then
        ns:Print(("Skipped |cffffd100%d|r team(s) already in Long Live Pets (safe to re-run)."):format(nSkipped))
    end
    if nScripts > 0 then
        ns:Print(("Copied + linked |cff44ff44%d|r battle scripts. Load a team and start a battle, then mash your tdBattlePetScript auto key to run its script."):format(nScripts))
    end
    ns:Print("Abilities: Long Live Pets remembers each team's ability picks when you Save it. Imported teams use each pet's current abilities until you re-save them (Rematch's packed ability data can't be decoded safely).")
    if ns.UI then ns.UI:Refresh() end
end
