--[[ Long Live Pets ----------------------------------------------------------
  Queue.lua — the leveling queue.

  The queue is an ordered list of pet GUIDs you want to level. A team slot can
  be flagged `leveling = true`; when such a team is loaded, those slots are
  filled from the front of the queue with pets that are not yet level 25.
  Pets that reach 25 are pruned automatically.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Queue = {}
ns.Queue = Queue

local MAX_LEVEL = 25

local function db() return ns.db end

local function levelOf(petID)
    if not petID then return nil end
    local _, _, level = C_PetJournal.GetPetInfoByPetID(petID)
    return level
end

-- Remove pets that no longer exist or have hit max level.
function Queue:Prune()
    local q = db().queue
    local i = 1
    while i <= #q do
        local lvl = levelOf(q[i])
        if not lvl or lvl >= MAX_LEVEL then
            table.remove(q, i)
        else
            i = i + 1
        end
    end
end

function Queue:Contains(petID)
    for _, p in ipairs(db().queue) do
        if p == petID then return true end
    end
    return false
end

function Queue:Add(petID)
    if not petID then return end
    if self:Contains(petID) then return end
    table.insert(db().queue, petID)
    if ns.UI then ns.UI:Refresh() end
end

function Queue:Remove(petID)
    local q = db().queue
    for i, p in ipairs(q) do
        if p == petID then table.remove(q, i); break end
    end
    if ns.UI then ns.UI:Refresh() end
end

-- Add whatever pet is currently in a given battle slot to the queue.
function Queue:AddFromSlot(slot)
    slot = tonumber(slot)
    if not slot then ns:Print("Usage: /llp queue add <slot 1-3>"); return end
    local petID = C_PetJournal.GetPetLoadOutInfo(slot)
    if not petID then ns:Print("Nothing in slot " .. slot .. "."); return end
    self:Add(petID)
    ns:Print("Added the pet in slot " .. slot .. " to the leveling queue.")
end

-- Ordered list of queued pets that still need leveling.
function Queue:Pending()
    self:Prune()
    return db().queue
end

-- Pick the Nth (1-based) pending leveling pet for slot-filling.
function Queue:NthPending(n)
    local q = self:Pending()
    return q[n]
end

function Queue:Clear()
    wipe(db().queue)
    if ns.UI then ns.UI:Refresh() end
end

ns:On("PET_JOURNAL_LIST_UPDATE", function()
    if ns.db then ns.Queue:Prune() end
end)
