--[[ Long Live Pets ----------------------------------------------------------
  Groups.lua — folders that teams can be organized into.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Groups = {}
ns.Groups = Groups

local function db() return ns.db end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Groups:Get(id) return db().groups[id] end

function Groups:GetByName(name)
    name = trim(name)
    if name == "" then return nil end
    local target = name:lower()
    for id, g in pairs(db().groups) do
        if g.name and g.name:lower() == target then return id, g end
    end
end

function Groups:Resolve(key)
    key = trim(key)
    if key == "" then return nil end
    if db().groups[key] then return key, db().groups[key] end
    return self:GetByName(key)
end

function Groups:Create(name)
    name = trim(name)
    if name == "" then ns:Print("Give the group a name."); return end
    local existing = self:GetByName(name)
    if existing then return existing end
    local id = tostring(db().nextGroupID)
    db().nextGroupID = db().nextGroupID + 1
    db().groups[id] = { name = name, order = db().nextGroupID }
    ns:Print('Created group "' .. name .. '".')
    if ns.UI then ns.UI:Refresh() end
    return id
end

function Groups:Rename(key, newName)
    local _, g = self:Resolve(key)
    if not g then ns:Print('No group "' .. tostring(key) .. '".'); return end
    newName = trim(newName)
    if newName == "" then return end
    g.name = newName
    if ns.UI then ns.UI:Refresh() end
end

-- Delete a group; its teams are moved to "ungrouped" (group = nil).
function Groups:Delete(key)
    local id, g = self:Resolve(key)
    if not g then ns:Print('No group "' .. tostring(key) .. '".'); return end
    for _, t in pairs(db().teams) do
        if t.group == id then t.group = nil end
    end
    db().groups[id] = nil
    ns:Print('Deleted group "' .. g.name .. '" (its teams kept, now ungrouped).')
    if ns.UI then ns.UI:Refresh() end
end

-- Assign a team to a group (group may be nil/"" to ungroup).
function Groups:Assign(teamKey, groupKey)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then ns:Print('No team "' .. tostring(teamKey) .. '".'); return end
    if not groupKey or trim(groupKey) == "" then
        t.group = nil
        ns:Print('Moved "' .. t.name .. '" to ungrouped.')
    else
        local gid = self:Resolve(groupKey) or self:Create(groupKey)
        t.group = gid
        ns:Print('Moved "' .. t.name .. '" to "' .. db().groups[gid].name .. '".')
    end
    if ns.UI then ns.UI:Refresh() end
end

-- Sorted array of groups: { {id, name}, ... }
function Groups:List()
    local out = {}
    for id, g in pairs(db().groups) do
        out[#out + 1] = { id = id, name = g.name or "(group)", order = g.order or 0 }
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name:lower() < b.name:lower()
    end)
    return out
end
