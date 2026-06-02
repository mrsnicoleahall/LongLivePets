-- Headless test harness: mocks just enough of the WoW API to exercise the
-- Long Live Pets core (no UI build needed — Refresh() early-returns while the
-- frame is nil).

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1; print("  ok   "..label)
  else FAIL = FAIL + 1; print("  FAIL "..label) end
end

-- ---- WoW API mocks --------------------------------------------------------
local firstFrame
local function makeFrame()
  local f = { _scripts = {} }
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:SetScript(k, fn) self._scripts[k] = fn end
  function f:GetScript(k) return self._scripts[k] end
  function f:CreateFontString() return makeFrame() end
  function f:CreateTexture() return makeFrame() end
  function f:IsShown() return self._shown end
  function f:Show() self._shown = true end
  function f:Hide() self._shown = false end
  function f:GetText() return self._text or "" end
  function f:SetText(s) self._text = s end
  setmetatable(f, { __index = function() return function() end end })
  firstFrame = firstFrame or f
  return f
end
function CreateFrame() return makeFrame() end

UIParent = makeFrame()

local applied = {}        -- what got written back into the slots on Load
local slotPets             -- current "slotted" pets (mock state)
local function setSlots(t) slotPets = t end

C_PetJournal = {
  GetNumPetLoadOutSlots = function() return 3 end,
  GetPetLoadOutInfo = function(slot)
    local p = slotPets and slotPets[slot]
    if not p then return nil end
    return p.petID, p.a1, p.a2, p.a3
  end,
  GetPetInfoByPetID = function(petID) return 9000 end,
  SetPetLoadOutInfo = function(slot, petID) applied[slot] = petID end,
  SetAbility = function(slot, idx, ab) end,
}
C_PetBattles = { IsInBattle = function() return false end }
C_AddOns = {
  GetAddOnMetadata = function(_, k) return k == "Version" and "0.1.0" or nil end,
  IsAddOnLoaded = function(n) return false end,
}
function InCombatLockdown() return false end
time = os.time
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("    | "..tostring(m)) end }

-- ---- load addon files in TOC order ----------------------------------------
local ns = {}
local files = {
  "Core/Init.lua", "Core/Database.lua", "Core/Loadout.lua", "Core/Teams.lua",
  "UI/MainWindow.lua", "Integration/tdBattlePetScript.lua", "Core/Slash.lua",
}
for _, f in ipairs(files) do
  local chunk = assert(loadfile(f))
  chunk("LongLivePets", ns)
end

local function fire(event, ...)
  local h = ns.frame._scripts.OnEvent
  if h then h(ns.frame, event, ...) end
end
local function slash(cmd) SlashCmdList["LONGLIVEPETS"](cmd) end

-- ---- exercise it ----------------------------------------------------------
print("\n[1] login lifecycle")
fire("ADDON_LOADED", "LongLivePets")
fire("PLAYER_LOGIN")
check(type(LongLivePetsDB) == "table", "SavedVariables initialized")
check(LongLivePetsDB.nextID == 1, "nextID starts at 1")

print("\n[2] save current team")
setSlots({ [1]={petID="PET-A",a1=11,a2=12,a3=13},
           [2]={petID="PET-B",a1=21,a2=22,a3=23},
           [3]={petID="PET-C",a1=31,a2=32,a3=33} })
slash("save Aqua Team")
local id, t = ns.Teams:GetByName("Aqua Team")
check(t ~= nil, "team saved by name")
check(t and t.pets[2].petID == "PET-B", "slot 2 pet captured")
check(t and t.pets[3].abilities[1] == 31, "slot 3 ability captured")
check(LongLivePetsDB.nextID == 2, "nextID advanced")

print("\n[3] update existing (same name) does not duplicate")
slash("save Aqua Team")
check(LongLivePetsDB.nextID == 2, "nextID unchanged on update")
check(#ns.Teams:List() == 1, "still one team")

print("\n[4] load team writes pets back into slots")
applied = {}
setSlots({})  -- clear slots
slash("load Aqua Team")
check(applied[1] == "PET-A" and applied[2] == "PET-B" and applied[3] == "PET-C",
      "all three pets applied on load")

print("\n[5] rename")
slash("rename Aqua Team => Aqua Stomp")
check(ns.Teams:GetByName("Aqua Stomp") ~= nil, "renamed team findable")
check(ns.Teams:GetByName("Aqua Team") == nil, "old name gone")

print("\n[6] script link (tdBattlePetScript not loaded)")
slash("script Aqua Stomp => DungeonScript")
local _, t2 = ns.Teams:GetByName("Aqua Stomp")
check(t2 and t2.script == "DungeonScript", "script name stored on team")

print("\n[7] guards: empty name / no pets")
local before = #ns.Teams:List()
slash("save   ")                 -- blank name
setSlots({}); slash("save Empty")-- nothing slotted
check(#ns.Teams:List() == before, "no junk teams created by bad input")

print("\n[8] delete")
slash("delete Aqua Stomp")
check(#ns.Teams:List() == 0, "team deleted")
check(ns.Teams:GetByName("Aqua Stomp") == nil, "name no longer resolves")

print("\n[9] load missing team is graceful")
slash("load Does Not Exist")     -- should just print, not error
check(true, "no error on missing load")

print("\n[10] UI build + refresh (window construction path)")
setSlots({ [1]={petID="PET-X",a1=1,a2=2,a3=3} })
slash("save Windowed Team")
local okBuild = pcall(function() ns.UI:Show() end)        -- builds the frame
check(okBuild, "BuildFrame ran without error")
local okRefresh = pcall(function() ns.UI:Refresh() end)   -- populate rows
check(okRefresh, "Refresh ran without error")
local okToggle = pcall(function() ns.UI:Toggle(); ns.UI:Toggle() end)
check(okToggle, "Toggle open/close without error")

print(("\n==== %d passed, %d failed ===="):format(PASS, FAIL))
os.exit(FAIL == 0 and 0 or 1)
