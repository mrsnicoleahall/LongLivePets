--[[ Long Live Pets ----------------------------------------------------------
  Slash.lua — /llp command parser, plus a one-line login greeting.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local function usage()
    ns:Print("commands:")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp                 — open or close the window")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp save <name>     — save the slotted pets as a team")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp load <name>     — load a saved team")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp delete <name>   — delete a team")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp rename <old> => <new>")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp script <team> => <scriptname>   (needs tdBattlePetScript)")
    DEFAULT_CHAT_FRAME:AddMessage("  /llp list            — list saved teams")
end

SLASH_LONGLIVEPETS1 = "/llp"
SLASH_LONGLIVEPETS2 = "/longlivepets"

SlashCmdList["LONGLIVEPETS"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        ns.UI:Toggle()

    elseif cmd == "save" then
        ns.Teams:SaveCurrent(rest)

    elseif cmd == "load" then
        ns.Teams:Load(rest)

    elseif cmd == "delete" or cmd == "del" then
        ns.Teams:Delete(rest)

    elseif cmd == "rename" then
        local old, new = rest:match("^(.-)%s*=>%s*(.+)$")
        if old and new then
            ns.Teams:Rename(old, new)
        else
            ns:Print("usage:  /llp rename <old> => <new>")
        end

    elseif cmd == "script" then
        local team, script = rest:match("^(.-)%s*=>%s*(.+)$")
        if team and team ~= "" then
            ns.Integration:SetScript(team, script)
        else
            ns:Print("usage:  /llp script <team> => <scriptname>")
        end

    elseif cmd == "list" then
        local teams = ns.Teams:List()
        if #teams == 0 then
            ns:Print("no teams saved yet.")
        else
            ns:Print(("saved teams (%d):"):format(#teams))
            for _, t in ipairs(teams) do
                DEFAULT_CHAT_FRAME:AddMessage("  • " .. t.name .. (t.script and "  |cff8ec5ff(script)|r" or ""))
            end
        end

    else
        usage()
    end
end

ns:On("PLAYER_LOGIN", function()
    ns:Print(("v%s loaded — type |cffffd100/llp|r to open."):format(ns.version))
end)
