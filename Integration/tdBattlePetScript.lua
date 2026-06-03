--[[ Long Live Pets ----------------------------------------------------------
  Integration/tdBattlePetScript.lua

  Optional bridge to tdBattlePetScript (by DengSir, MIT-licensed). This is our
  own original glue code — it contains no tdBattlePetScript code.

  A team may carry an optional `script` field (the NAME of a saved
  tdBattlePetScript). When such a team is loaded, we find that script and "arm"
  it via tdBattlePetScript's Director, so that in a pet battle you can mash your
  tdBattlePetScript auto key (e.g. A) to run it. We also re-arm when a battle
  opens, since tdBattlePetScript clears the active script at battle end.

  Everything is wrapped defensively: if tdBattlePetScript is missing or its API
  shifts, we degrade to a chat hint and never error.
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local Integration = {}
ns.Integration = Integration

function Integration:IsAvailable()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("tdBattlePetScript")
        and _G.tdBattlePetScript ~= nil
end

local function addon() return _G.tdBattlePetScript end
local function getModule(name)
    local a = addon()
    if a and a.GetModule then
        local ok, m = pcall(a.GetModule, a, name, true)
        if ok then return m end
    end
end

-- Find a saved script object by its display name, across enabled plugins.
function Integration:FindScriptByName(name)
    if not name then return nil end
    local a = addon()
    local SM = getModule("ScriptManager")
    if not (a and SM and a.IterateEnabledPlugins) then return nil end
    local found
    pcall(function()
        for _, plugin in a:IterateEnabledPlugins() do
            for _, script in SM:IteratePluginScripts(plugin) do
                if script and script.GetName and script:GetName() == name then
                    found = script
                    return
                end
            end
        end
    end)
    return found
end

-- Arm the linked script so the tdBattlePetScript auto key will run it.
-- Returns true if it was found & set.
function Integration:Arm(team, quiet)
    if not team or not team.script then return false end
    if not self:IsAvailable() then
        if not quiet then ns:Print('"' .. (team.name or "?") .. '" has a script, but tdBattlePetScript isn\'t loaded.') end
        return false
    end
    -- Make sure tdBattlePetScript auto-selects in battle as a fallback.
    local a = addon()
    if a and a.SetSetting then pcall(a.SetSetting, a, "autoSelect", true) end

    local Director = getModule("Director")
    local scriptObj = self:FindScriptByName(team.script)
    if Director and scriptObj and Director.SetScript then
        pcall(Director.SetScript, Director, scriptObj)
        if not quiet then
            ns:Print('Armed script "' .. team.script .. '" — in battle, mash your tdBattlePetScript auto key (e.g. A) to run it.')
        end
        return true
    end
    if not quiet then
        ns:Print('Could not find a tdBattlePetScript named "' .. team.script .. '". Open tdBattlePetScript and check the exact name.')
    end
    return false
end

-- Associate (or clear) a script name on a team.
function Integration:SetScript(teamKey, scriptName)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then ns:Print('No team called "' .. tostring(teamKey) .. '".'); return end
    scriptName = scriptName and scriptName:gsub("^%s+", ""):gsub("%s+$", "")
    if scriptName == "" then scriptName = nil end
    t.script = scriptName
    if scriptName then
        ns:Print('Linked "' .. t.name .. '" to script "' .. scriptName .. '".')
        if not self:IsAvailable() then ns:Print("(tdBattlePetScript isn't loaded yet.)") end
    else
        ns:Print('Cleared the script on "' .. t.name .. '".')
    end
    if ns.UI then ns.UI:Refresh() end
end

-- Test that a team's linked script resolves and can be armed (use outside a
-- battle to confirm the link works).
function Integration:Test(teamKey)
    local _, t = ns.Teams:Resolve(teamKey)
    if not t then ns:Print('No team called "' .. tostring(teamKey) .. '".'); return end
    if not t.script then ns:Print('"' .. t.name .. '" has no script linked. Right-click it → Set Script.'); return end
    if not self:IsAvailable() then ns:Print("tdBattlePetScript isn't loaded — enable it on the AddOns screen."); return end
    if self:FindScriptByName(t.script) then
        self:Arm(t)
        ns:Print('OK: found "' .. t.script .. '". Start a battle and mash your auto key (A) to run it.')
    else
        ns:Print('Not found: no saved tdBattlePetScript named "' .. t.script .. '". Open tdBattlePetScript and copy the exact script name.')
    end
end

-- Called by Teams:Load after pets are slotted.
function Integration:OnTeamLoaded(team)
    ns._armedTeamID = nil
    if not team or not team.script then return end
    ns._armedTeamID = team   -- remember to re-arm when a battle opens
    self:Arm(team)
end

-- Re-arm when a battle opens (tdBattlePetScript clears its script at battle
-- end). We arm on both OPENING_START and OPENING_DONE so the script is ready as
-- early as possible regardless of which fires first on this client.
local function reArm()
    if ns._armedTeamID then ns.Integration:Arm(ns._armedTeamID, true) end
end
ns:On("PET_BATTLE_OPENING_START", reArm)
ns:On("PET_BATTLE_OPENING_DONE", reArm)
