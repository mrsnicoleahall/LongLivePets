--[[ Long Live Pets ----------------------------------------------------------
  Slash.lua — /llp command parser, keybinding hook, and login greeting.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

-- keybinding (see bindings.xml)
_G.BINDING_HEADER_LONGLIVEPETS = "Long Live Pets"
_G.BINDING_NAME_LONGLIVEPETS_TOGGLE = "Open/close the window"
function LongLivePets_Toggle() ns.UI:Toggle() end

local function split(rest)
    return rest:match("^(.-)%s*=>%s*(.+)$")
end

local function help()
    ns:Print("commands:")
    local lines = {
        "/llp                       open / close the window",
        "/llp save <name>           save the slotted pets as a team",
        "/llp load <name>           load a team",
        "/llp reload                reload the current team",
        "/llp rename <old> => <new> rename a team",
        "/llp delete <name>         delete a team",
        "/llp note <team> => <text> set/clear a team note",
        "/llp group add <name>",
        "/llp group set <team> => <group>",
        "/llp group clear <team> | rename <old> => <new> | delete <name>",
        "/llp queue add <slot> | list | clear",
        "/llp levelslot <team> <slot> [off]",
        "/llp target bind <team> [npcID] | unbind | auto on|off",
        "/llp export <team>         show a shareable string",
        "/llp import [string]       import a team/backup",
        "/llp backup                export all teams",
        "/llp pets                  open the pet browser",
        "/llp find <text> | strong <type> | tough <type> | ability <text>",
        "/llp counter <type>        counter advice for an enemy type",
        "/llp record win|loss [team]",
        "/llp minimap               toggle the minimap button",
        "/llp list",
    }
    for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end
end

local handlers = {}

handlers.save   = function(rest) ns.Teams:SaveCurrent(rest) end
handlers.load   = function(rest) ns.Teams:Load(rest) end
handlers.reload = function()     ns.Teams:Reload() end
handlers.delete = function(rest) ns.Teams:Delete(rest) end
handlers.del    = handlers.delete

handlers.rename = function(rest)
    local a, b = split(rest)
    if a and b then ns.Teams:Rename(a, b) else ns:Print("usage: /llp rename <old> => <new>") end
end

handlers.note = function(rest)
    local a, b = split(rest)
    if a then ns.Teams:SetNotes(a, b or "") else ns:Print("usage: /llp note <team> => <text>") end
end

handlers.script = function(rest)
    local a, b = split(rest)
    if a and a ~= "" then ns.Integration:SetScript(a, b) else ns:Print("usage: /llp script <team> => <name>") end
end

handlers.group = function(rest)
    local sub, args = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "add" or sub == "new" then
        ns.Groups:Create(args)
    elseif sub == "rename" then
        local a, b = split(args)
        if a and b then ns.Groups:Rename(a, b) else ns:Print("usage: /llp group rename <old> => <new>") end
    elseif sub == "delete" or sub == "del" then
        ns.Groups:Delete(args)
    elseif sub == "set" then
        local a, b = split(args)
        if a and b then ns.Groups:Assign(a, b) else ns:Print("usage: /llp group set <team> => <group>") end
    elseif sub == "clear" then
        ns.Groups:Assign(args, nil)
    else
        ns:Print("usage: /llp group add|set|clear|rename|delete ...")
    end
end

handlers.queue = function(rest)
    local sub, args = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "add" then
        ns.Queue:AddFromSlot(args)
    elseif sub == "clear" then
        ns.Queue:Clear(); ns:Print("Leveling queue cleared.")
    elseif sub == "list" then
        local q = ns.Queue:Pending()
        if #q == 0 then ns:Print("Leveling queue is empty.") else
            ns:Print(("Leveling queue (%d):"):format(#q))
            for i, petID in ipairs(q) do
                local _, _, lvl = C_PetJournal.GetPetInfoByPetID(petID)
                local name = (C_PetJournal.GetPetInfoByPetID and select(8, C_PetJournal.GetPetInfoByPetID(petID))) or "pet"
                DEFAULT_CHAT_FRAME:AddMessage(("  %d. %s (lvl %s)"):format(i, tostring(name), tostring(lvl or "?")))
            end
        end
    else
        ns:Print("usage: /llp queue add <slot> | list | clear")
    end
end

handlers.levelslot = function(rest)
    local team, slot, off = rest:match("^(.-)%s+(%d+)%s*(%a*)$")
    if team and slot then
        ns.Teams:SetLevelingSlot(team, slot, off:lower() ~= "off")
    else
        ns:Print("usage: /llp levelslot <team> <slot 1-3> [off]")
    end
end

handlers.target = function(rest)
    local sub, args = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "bind" then
        local team, npc = args:match("^(.-)%s*(%d*)$")
        ns.Targets:Bind(team, npc ~= "" and npc or nil)
    elseif sub == "unbind" then
        ns.Targets:Unbind(args ~= "" and args or nil)
    elseif sub == "auto" then
        local on = args:lower() == "on"
        ns.db.settings.autoLoadOnTarget = on
        ns:Print("Auto-load on target: " .. (on and "ON" or "OFF") .. ".")
    else
        ns:Print("usage: /llp target bind <team> [npcID] | unbind [npcID] | auto on|off")
    end
end

handlers.export = function(rest)
    local str = ns.Serialize:ExportTeam(rest)
    if str then ns.UI:ShowText("Export — copy this string", "export", str) end
end

handlers.import = function(rest)
    if rest and rest ~= "" then
        local n, err = ns.Serialize:Import(rest)
        if n then ns:Print(("Imported %d team(s)."):format(n)) else ns:Print(err) end
    else
        ns.UI:ShowText("Import — paste a team/backup string", "import", "", function(v)
            local n, err = ns.Serialize:Import(v)
            if n then ns:Print(("Imported %d team(s)."):format(n)) else ns:Print(err) end
        end)
    end
end

handlers.backup = function()
    ns.UI:ShowText("Backup — copy this string", "export", ns.Serialize:BackupAll())
end

handlers.counter = function(rest)
    local c = ns.Types:CounterFor(rest)
    if not c then ns:Print("usage: /llp counter <type>  (e.g. Aquatic)"); return end
    ns:Print(("vs %s: bring a |cff44ff44%s|r attacker (extra damage), and a |cff44ff44%s|r pet resists their hits.")
        :format(c.enemy, c.strongAttacker, c.toughType))
end

handlers.record = function(rest)
    local res, team = rest:match("^(%S+)%s*(.-)$")
    res = (res or ""):lower()
    if res == "win" then ns.Battle:Record(team ~= "" and team or nil, true)
    elseif res == "loss" or res == "lose" then ns.Battle:Record(team ~= "" and team or nil, false)
    else ns:Print("usage: /llp record win|loss [team]") end
end

handlers.minimap = function() ns.Minimap:Toggle() end

handlers.pets = function() ns.PetBrowser:Toggle() end

handlers.find = function(rest)
    local mode, arg = rest:match("^(%S+)%s+(.+)$")
    local opts = {}
    if mode and mode:lower() == "strong" then opts.strongVs = arg
    elseif mode and mode:lower() == "tough" then opts.toughVs = arg
    elseif mode and mode:lower() == "ability" then opts.ability = arg
    else opts.search = rest end
    local pets = ns.Roster:Filter(opts)
    if #pets == 0 then ns:Print("no matching pets."); return end
    ns:Print(("matches (%d):"):format(#pets))
    for i = 1, math.min(#pets, 20) do
        local p = pets[i]
        DEFAULT_CHAT_FRAME:AddMessage(("  %s (L%d %s)"):format(
            p.name, p.level, ns.Types.NAME[p.petType] or "?"))
    end
end

handlers.list = function()
    local teams = ns.Teams:List()
    if #teams == 0 then ns:Print("no teams saved yet."); return end
    ns:Print(("saved teams (%d):"):format(#teams))
    for _, t in ipairs(teams) do
        local extra = ""
        if (t.wins + t.losses) > 0 then extra = (" |cffaaaaaa%d-%d|r"):format(t.wins, t.losses) end
        if t.script then extra = extra .. " (script)" end
        DEFAULT_CHAT_FRAME:AddMessage("  • " .. t.name .. extra)
    end
end

handlers.help = help

SLASH_LONGLIVEPETS1 = "/llp"
SLASH_LONGLIVEPETS2 = "/longlivepets"

SlashCmdList["LONGLIVEPETS"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.UI:Toggle()
    elseif handlers[cmd] then
        handlers[cmd](rest)
    else
        help()
    end
end

ns:On("PLAYER_LOGIN", function()
    ns:Print(("v%s loaded — type |cffffd100/llp|r to open, |cffffd100/llp help|r for commands."):format(ns.version))
end)
