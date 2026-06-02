--[[ Long Live Pets ----------------------------------------------------------
  Teams.lua — the team list: create/update, load, rename, delete, query.
  All persistence goes through ns.db (see Database.lua).
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Teams = {}
ns.Teams = Teams

local function db() return ns.db end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Teams:All()
    return db().teams
end

function Teams:Get(id)
    return db().teams[id]
end

function Teams:GetByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local target = name:lower()
    for id, t in pairs(db().teams) do
        if t.name and t.name:lower() == target then
            return id, t
        end
    end
end

-- Accept either a team id or a (case-insensitive) team name.
function Teams:Resolve(key)
    key = trim(key)
    if key == "" then return nil end
    if db().teams[key] then return key, db().teams[key] end
    return self:GetByName(key)
end

-- Save the currently slotted pets as a team. If a team with this name already
-- exists, it is updated in place (its optional script link is preserved).
function Teams:SaveCurrent(name)
    name = trim(name)
    if name == "" then
        ns:Print("Give the team a name:  /llp save <name>")
        return
    end

    local pets = ns.Loadout:Capture()
    if not next(pets) then
        ns:Print("No pets are slotted right now — slot a team first.")
        return
    end

    local existingID, existing = self:GetByName(name)
    local id = existingID or tostring(db().nextID)
    if not existingID then
        db().nextID = db().nextID + 1
    end

    db().teams[id] = {
        name    = name,
        pets    = pets,
        updated = time(),
        script  = existing and existing.script or nil,
    }

    ns:Print((existingID and 'Updated team "' or 'Saved team "') .. name .. '".')
    if ns.UI then ns.UI:Refresh() end
    return id
end

function Teams:Load(key)
    local _, t = self:Resolve(key)
    if not t then
        ns:Print('No team called "' .. trim(key) .. '".')
        return
    end
    if ns.Loadout:Apply(t.pets) then
        ns:Print('Loaded "' .. t.name .. '".')
        if ns.Integration and t.script then
            ns.Integration:OnTeamLoaded(t)
        end
    end
end

function Teams:Delete(key)
    local id, t = self:Resolve(key)
    if not t then
        ns:Print('No team called "' .. trim(key) .. '".')
        return
    end
    db().teams[id] = nil
    ns:Print('Deleted "' .. t.name .. '".')
    if ns.UI then ns.UI:Refresh() end
end

function Teams:Rename(key, newName)
    local _, t = self:Resolve(key)
    if not t then
        ns:Print('No team called "' .. trim(key) .. '".')
        return
    end
    newName = trim(newName)
    if newName == "" then
        ns:Print("Give the new name:  /llp rename <old> => <new>")
        return
    end
    t.name = newName
    ns:Print('Renamed to "' .. newName .. '".')
    if ns.UI then ns.UI:Refresh() end
end

-- Sorted, display-ready array: { { id=, name=, script= }, ... }
function Teams:List()
    local out = {}
    for id, t in pairs(db().teams) do
        out[#out + 1] = { id = id, name = t.name or "(unnamed)", script = t.script }
    end
    table.sort(out, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return out
end
