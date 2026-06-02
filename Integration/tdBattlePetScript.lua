--[[ Long Live Pets ----------------------------------------------------------
  Integration/tdBattlePetScript.lua

  Optional bridge to tdBattlePetScript (by DengSir, MIT-licensed). This file is
  our own original glue code — it does not contain any tdBattlePetScript code.
  tdBattlePetScript remains a separate addon you install alongside this one;
  because it is MIT-licensed it may also be bundled with proper attribution
  (see NOTICE.md).

  A team may carry an optional `script` field (the name of a tdBattlePetScript
  script). When such a team is loaded and tdBattlePetScript is present, we hand
  off to it. The hand-off is written defensively so a future API change in
  tdBattlePetScript can never throw an error in this addon.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Integration = {}
ns.Integration = Integration

function Integration:IsAvailable()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("tdBattlePetScript")
end

-- Associate (or clear) a tdBattlePetScript script name on a team.
function Integration:SetScript(teamKey, scriptName)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then
        ns:Print('No team called "' .. tostring(teamKey) .. '".')
        return
    end
    scriptName = scriptName and scriptName:gsub("^%s+", ""):gsub("%s+$", "")
    if scriptName == "" then scriptName = nil end
    t.script = scriptName

    if scriptName then
        ns:Print('Linked "' .. t.name .. '" to script "' .. scriptName .. '".')
        if not self:IsAvailable() then
            ns:Print("Heads up: tdBattlePetScript isn't loaded, so the script won't run yet.")
        end
    else
        ns:Print('Cleared the script on "' .. t.name .. '".')
    end
    if ns.UI then ns.UI:Refresh() end
end

-- Called by Teams:Load after the pets are slotted.
function Integration:OnTeamLoaded(team)
    if not team or not team.script then return end
    if not self:IsAvailable() then
        ns:Print('"' .. (team.name or "?") .. '" has a script set, but tdBattlePetScript isn\'t loaded.')
        return
    end

    -- Hand-off point. Resolve a selection entry-point on tdBattlePetScript's
    -- public surface without hard-coding a single name, so we don't break if
    -- the API shifts. If none is found we simply remember the choice and tell
    -- the user, rather than erroring.
    local tdbps = _G.tdBattlePetScript
    local selectors = { "SelectScript", "SetScript", "UseScript", "Select" }
    if type(tdbps) == "table" then
        for _, fn in ipairs(selectors) do
            if type(tdbps[fn]) == "function" then
                local ok = pcall(tdbps[fn], tdbps, team.script)
                if ok then return end
            end
        end
    end

    ns._pendingScript = team.script
    ns:Print('Tip: open tdBattlePetScript and pick "' .. team.script .. '" to run it.')
end
