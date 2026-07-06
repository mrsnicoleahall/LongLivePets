--[[ Long Live Pets ----------------------------------------------------------
  Comm.lua — send a team to another Long Live Pets user over addon messages.
  The team string (see Serialize) is split into chunks, sent by WHISPER, and
  reassembled on the other side, where the recipient is offered to save it.
  Chunk/assemble logic is pure and unit-tested; transport is guarded.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Comm = {}
ns.Comm = Comm

local PREFIX = "LLP"
local CHUNK = 220

Comm._incoming = {}   -- [sender] = { total, parts = {} }
Comm.pending = nil    -- last fully-received offer: { sender, str }

-- Split a string into addon-message-sized chunks.
function Comm:Chunk(str, size)
    size = size or CHUNK
    local chunks = {}
    for i = 1, #str, size do chunks[#chunks + 1] = str:sub(i, i + size - 1) end
    if #chunks == 0 then chunks[1] = "" end
    return chunks
end

local function body(index, total, chunk)
    return ("%d|%d|%s"):format(index, total, chunk)
end

function Comm:Transmit(name, msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", name)
    end
end

-- Send a team (by key) to a player.
function Comm:Send(teamKey, name)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then ns:Print('No team "' .. tostring(teamKey) .. '".'); return end
    if not name or name == "" then ns:Print("Usage: /llp send <team> => <player>"); return end
    local str = ns.Serialize:EncodeTeam(t)
    local chunks = self:Chunk(str)
    for i, c in ipairs(chunks) do
        self:Transmit(name, body(i, #chunks, c))
    end
    ns:Print(('Sent "%s" to %s.'):format(t.name, name))
end

-- Feed one received message. When all chunks for a sender arrive, fire OnComplete.
function Comm:Receive(sender, msg)
    local idx, total, chunk = msg:match("^(%d+)|(%d+)|(.*)$")
    idx, total = tonumber(idx), tonumber(total)
    if not idx or not total then return end

    local st = self._incoming[sender]
    if not st or st.total ~= total then
        st = { total = total, parts = {} }
        self._incoming[sender] = st
    end
    st.parts[idx] = chunk

    for i = 1, total do
        if st.parts[i] == nil then return end   -- still waiting
    end
    local str = table.concat(st.parts)
    self._incoming[sender] = nil
    self:OnComplete(sender, str)
end

function Comm:OnComplete(sender, str)
    self.pending = { sender = sender, str = str }
    ns:Print(('%s sent you a team — type |cffffd100/llp accept|r to save it.'):format(sender or "Someone"))
end

-- Save the last received team.
function Comm:Accept()
    if not self.pending then ns:Print("No incoming team to accept."); return end
    local n = ns.Serialize:Import(self.pending.str)
    self.pending = nil
    if n and n > 0 then ns:Print("Saved the shared team.") else ns:Print("Could not read that team.") end
end

ns:On("CHAT_MSG_ADDON", function(prefix, message, _, sender)
    if prefix ~= PREFIX then return end
    ns.Comm:Receive(sender, message)
end)

ns:On("PLAYER_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
end)
