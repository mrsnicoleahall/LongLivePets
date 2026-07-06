--[[ Long Live Pets ----------------------------------------------------------
  Teams.lua — the team list: create/update, load, rename, delete, notes,
  imported teams, and tracking of the currently-loaded team.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Teams = {}
ns.Teams = Teams

local function db() return ns.db end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Teams:All() return db().teams end
function Teams:Get(id) return db().teams[id] end

function Teams:GetByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local target = name:lower()
    for id, t in pairs(db().teams) do
        if t.name and t.name:lower() == target then return id, t end
    end
end

-- Accept either a team id or a (case-insensitive) team name.
function Teams:Resolve(key)
    key = trim(key)
    if key == "" then return nil end
    if db().teams[key] then return key, db().teams[key] end
    return self:GetByName(key)
end

local function newID()
    local id = tostring(db().nextID)
    db().nextID = db().nextID + 1
    return id
end

-- Next ordering value within a group bucket (groupID may be nil = ungrouped).
local function nextOrder(groupID)
    local m = 0
    for _, t in pairs(db().teams) do
        if t.group == groupID and (t.order or 0) > m then m = t.order end
    end
    return m + 1
end

-- Save the currently slotted pets as a team. Updating by name preserves the
-- team's group, notes, script, win record, and target bindings.
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

    local existingID, prev = self:GetByName(name)
    local id = existingID or newID()

    db().teams[id] = {
        name    = name,
        pets    = pets,
        updated = time(),
        group   = prev and prev.group,
        notes   = prev and prev.notes,
        script  = prev and prev.script,
        wins    = prev and prev.wins or 0,
        losses  = prev and prev.losses or 0,
        targets = prev and prev.targets,
        order   = prev and prev.order or nextOrder(prev and prev.group or nil),
    }

    ns:Print((existingID and 'Updated team "' or 'Saved team "') .. name .. '".')
    if ns.UI then ns.UI:Refresh() end
    return id
end

-- Create a team from imported data (pets carry speciesID, not petID).
function Teams:CreateImported(parsed)
    if not parsed or not parsed.name then return nil end
    local id = newID()
    local group
    if parsed._groupName and parsed._groupName ~= "" then
        group = ns.Groups:Resolve(parsed._groupName) or ns.Groups:Create(parsed._groupName)
    end
    db().teams[id] = {
        name    = parsed.name,
        pets    = parsed.pets or {},
        notes   = parsed.notes,
        script  = parsed.script,
        group   = group,
        wins    = 0, losses = 0,
        updated = time(),
        imported = true,
        order   = nextOrder(group),
    }
    if ns.UI then ns.UI:Refresh() end
    return id
end

function Teams:Load(key)
    local id, t = self:Resolve(key)
    if not t then
        ns:Print('No team called "' .. trim(key) .. '".')
        return
    end
    if ns.Loadout:Apply(t.pets) then
        db().loaded = id
        ns:Print('Loaded "' .. t.name .. '".')
        if ns.Integration and t.script then ns.Integration:OnTeamLoaded(t) end
        if ns.UI then ns.UI:RefreshLoadout(); ns.UI:RefreshRight() end
    end
end

-- Reload whatever team is currently marked as loaded (re-rolls random slots,
-- re-pulls leveling pets from the queue).
function Teams:Reload()
    local id = db().loaded
    if id and db().teams[id] then
        self:Load(id)
    else
        ns:Print("No team is loaded yet.")
    end
end

function Teams:Delete(key)
    local id, t = self:Resolve(key)
    if not t then
        ns:Print('No team called "' .. trim(key) .. '".')
        return
    end
    db().teams[id] = nil
    if db().loaded == id then db().loaded = nil end
    for npc, tid in pairs(db().targets) do
        if tid == id then db().targets[npc] = nil end
    end
    ns:Print('Deleted "' .. t.name .. '".')
    if ns.UI then ns.UI:Refresh() end
end

function Teams:Rename(key, newName)
    local _, t = self:Resolve(key)
    if not t then ns:Print('No team called "' .. trim(key) .. '".'); return end
    newName = trim(newName)
    if newName == "" then
        ns:Print("Give the new name:  /llp rename <old> => <new>")
        return
    end
    t.name = newName
    ns:Print('Renamed to "' .. newName .. '".')
    if ns.UI then ns.UI:Refresh() end
end

function Teams:SetNotes(key, notes)
    local _, t = self:Resolve(key)
    if not t then ns:Print('No team called "' .. tostring(key) .. '".'); return end
    notes = trim(notes)
    t.notes = notes ~= "" and notes or nil
    ns:Print(t.notes and ('Note set on "' .. t.name .. '".') or ('Note cleared on "' .. t.name .. '".'))
    if ns.UI then ns.UI:Refresh() end
end

-- Mark / unmark a slot in a saved team as a "leveling" slot.
function Teams:SetLevelingSlot(key, slot, on)
    local _, t = self:Resolve(key)
    if not t then ns:Print('No team called "' .. tostring(key) .. '".'); return end
    slot = tonumber(slot)
    if not slot or not t.pets[slot] then ns:Print("That slot is empty."); return end
    t.pets[slot].leveling = on and true or false
    ns:Print(('Slot %d on "%s" %s a leveling slot.'):format(slot, t.name, on and "is now" or "is no longer"))
    if ns.UI then ns.UI:Refresh() end
end

-- Sorted, display-ready array: by group order, then team order, then name.
function Teams:List()
    local groupOrder = {}
    for gid, g in pairs(db().groups) do groupOrder[gid] = g.order or 0 end

    local out = {}
    for id, t in pairs(db().teams) do
        out[#out + 1] = {
            id = id, name = t.name or "(unnamed)",
            group = t.group, script = t.script, notes = t.notes,
            wins = t.wins or 0, losses = t.losses or 0,
            order = t.order or 0,
            loaded = (id == db().loaded),
        }
    end
    table.sort(out, function(a, b)
        local ga = a.group and (groupOrder[a.group] or 0) or -1   -- ungrouped first
        local gb = b.group and (groupOrder[b.group] or 0) or -1
        if ga ~= gb then return ga < gb end
        if a.order ~= b.order then return a.order < b.order end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Move a team to a position within a group bucket (groupID nil = ungrouped),
-- renumbering that bucket. newIndex is 1-based; clamped.
function Teams:Reorder(id, newGroupID, newIndex)
    local t = db().teams[id]
    if not t then return end
    t.group = newGroupID

    local bucket = {}
    for tid, tt in pairs(db().teams) do
        if tt.group == newGroupID and tid ~= id then bucket[#bucket + 1] = tid end
    end
    table.sort(bucket, function(a, b)
        return (db().teams[a].order or 0) < (db().teams[b].order or 0)
    end)

    newIndex = newIndex or (#bucket + 1)
    if newIndex < 1 then newIndex = 1 end
    if newIndex > #bucket + 1 then newIndex = #bucket + 1 end
    table.insert(bucket, newIndex, id)

    for i, tid in ipairs(bucket) do db().teams[tid].order = i end
    if ns.UI then ns.UI:Refresh() end
end
