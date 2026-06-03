--[[ Long Live Pets ----------------------------------------------------------
  Serialize.lua — export / import / backup of teams as portable strings.

  Shared teams travel by speciesID + ability IDs (account-agnostic); on import
  the slot's pet is resolved to one you own when the team is loaded. Our own
  original wire format, base64-wrapped so it's a clean copy-paste blob:

      LLP1:<base64>     a single team
      LLPBK1:<base64>   a backup of every team

  Decoded payload (pre-base64), one team per line:
      n=<name>|g=<group>|s=<script>|no=<notes>|p1=<sp>:<a1>:<a2>:<a3>:<lvl>|...
  Field values are %xx-escaped for | = % and newlines.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Serialize = {}
ns.Serialize = Serialize

-- ---- base64 (standard alphabet; original implementation) ------------------
local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, #B do DEC[B:sub(i, i)] = i - 1 end

function Serialize.encode64(data)
    local out, len = {}, #data
    for i = 1, len, 3 do
        local b1 = data:byte(i)
        local b2 = data:byte(i + 1)
        local b3 = data:byte(i + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B:sub(c1 + 1, c1 + 1)
        out[#out + 1] = B:sub(c2 + 1, c2 + 1)
        out[#out + 1] = b2 and B:sub(c3 + 1, c3 + 1) or "="
        out[#out + 1] = b3 and B:sub(c4 + 1, c4 + 1) or "="
    end
    return table.concat(out)
end

function Serialize.decode64(data)
    data = data:gsub("[^" .. "%w%+/=" .. "]", "")
    local out = {}
    for i = 1, #data, 4 do
        local c1 = DEC[data:sub(i, i)]
        local c2 = DEC[data:sub(i + 1, i + 1)]
        local s3 = data:sub(i + 2, i + 2)
        local s4 = data:sub(i + 3, i + 3)
        if not c1 or not c2 then break end
        local c3 = DEC[s3]
        local c4 = DEC[s4]
        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if s3 ~= "=" and c3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if s4 ~= "=" and c4 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

-- ---- field escaping -------------------------------------------------------
local function esc(s)
    return (tostring(s or ""):gsub("[%%|=\r\n]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end
local function unesc(s)
    return (tostring(s or ""):gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- ---- team <-> payload line ------------------------------------------------
local function teamToLine(t)
    local groupName = ""
    if t.group and ns.db.groups[t.group] then groupName = ns.db.groups[t.group].name end
    local parts = {
        "n=" .. esc(t.name),
        "g=" .. esc(groupName),
        "s=" .. esc(t.script or ""),
        "no=" .. esc(t.notes or ""),
    }
    for slot = 1, 3 do
        local p = t.pets and t.pets[slot]
        if p then
            local ab = p.abilities or {}
            parts[#parts + 1] = ("p%d=%s:%s:%s:%s:%s"):format(
                slot, tostring(p.speciesID or 0),
                tostring(ab[1] or 0), tostring(ab[2] or 0), tostring(ab[3] or 0),
                p.leveling and "1" or "0")
        end
    end
    return table.concat(parts, "|")
end

local function lineToTeam(line)
    local t = { pets = {} }
    for field in line:gmatch("[^|]+") do
        local key, val = field:match("^(%w+)=(.*)$")
        if key == "n" then t.name = unesc(val)
        elseif key == "g" then t._groupName = unesc(val)
        elseif key == "s" then local s = unesc(val); t.script = s ~= "" and s or nil
        elseif key == "no" then local s = unesc(val); t.notes = s ~= "" and s or nil
        elseif key and key:match("^p%d$") then
            local slot = tonumber(key:sub(2))
            local sp, a1, a2, a3, lvl = val:match("^(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%d)$")
            if slot and sp then
                t.pets[slot] = {
                    speciesID = tonumber(sp),
                    abilities = { tonumber(a1), tonumber(a2), tonumber(a3) },
                    leveling = lvl == "1",
                }
            end
        end
    end
    return t
end

-- ---- public API -----------------------------------------------------------
-- Encode a team object directly (used by export and by send-to-player).
function Serialize:EncodeTeam(t)
    if not t then return nil end
    return "LLP1:" .. self.encode64(teamToLine(t))
end

function Serialize:ExportTeam(teamKey)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then ns:Print('No team "' .. tostring(teamKey) .. '".'); return end
    return self:EncodeTeam(t)
end

-- Export ONE team as a shareable strategy string: a header (name + the 3 pet
-- species) plus, if the team has one, its tdBattlePetScript code wrapped in the
-- standard BEGIN/END markers (the universal format tdBattlePetScript and
-- wow-petguide understand). Round-trips back through Import.
function Serialize:ExportStrategy(team)
    if not team then return nil end
    local sp = {}
    for slot = 1, 3 do
        local p = team.pets and team.pets[slot]
        local id = p and p.speciesID
        if not id and p and p.petID and C_PetJournal and C_PetJournal.GetPetInfoByPetID then
            id = (C_PetJournal.GetPetInfoByPetID(p.petID))
        end
        sp[slot] = id or 0
    end
    local code = team.scriptCode
    if (not code or code == "") and ns.Integration and ns.Integration.GetScriptCode then
        code = ns.Integration:GetScriptCode(team.script)
    end
    local header = ("%s:LLP:%d:%d:%d:N:"):format(team.name or "Team", sp[1], sp[2], sp[3])
    if code and code ~= "" then
        return header .. "\n-----BEGIN PET BATTLE SCRIPT-----\n" .. code .. "\n-----END PET BATTLE SCRIPT-----"
    end
    return header
end

function Serialize:BackupAll()
    local lines = {}
    for _, t in pairs(ns.db.teams) do lines[#lines + 1] = teamToLine(t) end
    return "LLPBK1:" .. self.encode64(table.concat(lines, "\n"))
end

-- Import a wow-petguide / Rematch "strategy" string: a team header, human
-- notes, and a tdBattlePetScript block. We can't decode Rematch's packed pet
-- codes, but the SCRIPT names the team's own pets by speciesID — e.g.
-- change(Emperor Crab:746) / self(Tolai Hare Pup:730) — so we read the team's
-- pets straight from there. Returns 1, nil, { name=, code= } on success.
function Serialize:ImportStrategy(str)
    local norm = tostring(str or ""):gsub("\\n", "\n")          -- literal \n -> newline
    local name = (norm:match("^%s*([^:\n]+)") or "Imported team"):gsub("^%s+", ""):gsub("%s+$", "")
    local code = norm:match("BEGIN PET BATTLE SCRIPT[%-%s]*(.-)[%-%s]*END PET BATTLE SCRIPT")
    if code then code = code:gsub("^%s+", ""):gsub("%s+$", "") end

    -- team pets: prefer explicit numeric species in the header (this is how OUR
    -- export writes them); otherwise read the species the script CONTROLS
    -- (change()/self() tokens — never enemy() tokens).
    local pets, seen, order = {}, {}, {}
    local header = norm:match("^(.-)\n") or norm:match("^(.-)%-+BEGIN PET BATTLE SCRIPT") or norm
    for field in header:gmatch("[^:]+") do
        if field:match("^%d+$") then           -- a WHOLE-number field = a species (our own export)
            local sid = tonumber(field)
            if sid and sid > 0 and not seen[sid] then seen[sid] = true; order[#order + 1] = sid end
        end
    end
    if #order == 0 and code then
        local function collect(pat)
            for sid in code:gmatch(pat) do
                sid = tonumber(sid)
                if sid and not seen[sid] then seen[sid] = true; order[#order + 1] = sid end
            end
        end
        collect("[Cc]hange%([^:%(%)]+:(%d+)%)")
        collect("self%([^:%(%)]+:(%d+)%)")
    end
    -- Solo scripts name no pets (just use(ability:id) calls). Resolve the team
    -- pet(s) from the abilities the script uses — find the owned species whose
    -- ability list matches them.
    if #order == 0 and code and ns.Roster and ns.Roster.FindSpeciesByAbilities then
        local abil = {}
        for id in code:gmatch("use%([^:%(%)]+:(%d+)%)")     do abil[#abil + 1] = tonumber(id) end
        for id in code:gmatch("ability%([^:%(%)]+:(%d+)%)") do abil[#abil + 1] = tonumber(id) end
        for _, sid in ipairs(ns.Roster:FindSpeciesByAbilities(abil, 3)) do
            if not seen[sid] then seen[sid] = true; order[#order + 1] = sid end
        end
    end
    for i = 1, math.min(3, #order) do pets[i] = { speciesID = order[i] } end

    -- best-effort notes: the prose between the header flags and the script
    local notes = norm:match(":[YNyn]:(.-)%-+BEGIN PET BATTLE SCRIPT") or norm:match(":[YNyn]:(.+)$")
    if notes then
        notes = notes:gsub("%[/?url[^%]]*%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #notes > 400 then notes = notes:sub(1, 400) .. "…" end
        if notes == "" then notes = nil end
    end

    local id = ns.Teams:CreateImported({ name = name, pets = pets, notes = notes, script = code and name or nil })
    if not id then return nil, "Could not create that team." end
    if code then ns.db.teams[id].scriptCode = code end
    return 1, nil, { name = name, code = code, pets = #pets }
end

-- Returns number of teams imported, or nil + error message.
-- Third return (optional) carries strategy-script info for the caller to show.
function Serialize:Import(str)
    str = tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local payload
    if str:match("^LLP1:") then
        payload = self.decode64(str:sub(6))
    elseif str:match("^LLPBK1:") then
        payload = self.decode64(str:sub(8))
    elseif str:find("PET BATTLE SCRIPT", 1, true) then
        return self:ImportStrategy(str)
    else
        return nil, "That isn't a Long Live Pets string. Use the Export button (or /llp export <team>) to make one. "
            .. "For Rematch teams use /llp importrematch; for a tdBattlePetScript script, paste it into tdBattlePetScript, then link it to a team via right-click → Set / edit script."
    end
    if not payload or payload == "" then return nil, "Could not decode that string." end

    local count = 0
    for line in (payload .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            local parsed = lineToTeam(line)
            if parsed.name then
                local id = ns.Teams:CreateImported(parsed)
                if id then count = count + 1 end
            end
        end
    end
    return count
end
