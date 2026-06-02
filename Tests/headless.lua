-- Headless test harness for Long Live Pets.
-- Mocks just enough of the WoW API to exercise the addon's logic outside the
-- game. Run from the repo root:  luajit Tests/headless.lua

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1; print("  ok   "..label)
  else FAIL = FAIL + 1; print("  FAIL "..label) end
end

-- ---- generic WoW frame mock ----------------------------------------------
-- A universal stub that is both callable and indexable, so chained access on
-- unknown template widgets (e.g. scroll.EditBox:SetText()) never errors.
local U
U = setmetatable({}, { __index = function() return U end, __call = function() return U end })

local function makeFrame()
  local f = { _scripts = {} }
  function f:RegisterEvent() end
  function f:UnregisterEvent() end
  function f:SetScript(k, fn) self._scripts[k] = fn end
  function f:GetScript(k) return self._scripts[k] end
  function f:CreateFontString() return makeFrame() end
  function f:CreateTexture() return makeFrame() end
  -- rawget so the universal __index stub can't shadow these bookkeeping fields
  function f:IsShown() return rawget(self, "_shown") or false end
  function f:Show() rawset(self, "_shown", true) end
  function f:Hide() rawset(self, "_shown", false) end
  function f:GetText() return rawget(self, "_text") or "" end
  function f:SetText(s) rawset(self, "_text", s) end
  setmetatable(f, { __index = function() return U end })
  return f
end
function CreateFrame() return makeFrame() end
UIParent = makeFrame()

-- ---- misc WoW globals -----------------------------------------------------
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, str)
  local parts = {}
  for token in (str..sep):gmatch("([^"..sep.."]*)"..sep) do parts[#parts+1] = token end
  return unpack(parts)
end
function InCombatLockdown() return false end
function GetCursorPosition() return 0, 0 end
time = os.time
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) end }   -- quiet
Enum = { BattlePetOwner = { Ally = 0, Enemy = 1 } }
GameTooltip = makeFrame()
Minimap = makeFrame()

-- ability data: id -> {name, desc}; species -> {ability ids}
local abilityById = {
  [1] = { name = "Water Jet",   desc = "Hits hard." },
  [2] = { name = "Sticky Web",  desc = "Slows the target with webbing." },
  [3] = { name = "Slicing Wind",desc = "Flying damage." },
  [4] = { name = "Bite",        desc = "Beast damage." },
}
local speciesAbilities = { [100] = {1}, [200] = {2}, [300] = {3}, [400] = {4}, [500] = {4} }

C_PetBattles = {
  IsInBattle = function() return false end,
  GetAbilityInfoByID = function(id)
    local a = abilityById[id]; if not a then return end
    return id, a.name, "icon", 0, a.desc, 1, 1, false
  end,
}
C_AddOns = {
  GetAddOnMetadata = function(_, k) return k == "Version" and "0.3.0" or nil end,
  IsAddOnLoaded = function() return false end,
}

-- ---- targeting mock -------------------------------------------------------
local curTarget   -- guid string or nil
function UnitExists(u) return u == "target" and curTarget ~= nil end
function UnitIsPlayer() return false end
function UnitGUID(u) return u == "target" and curTarget or nil end

-- ---- pet journal mock -----------------------------------------------------
local mockPets = {
  ["PET-A"] = { speciesID = 100, level = 25, name = "Alpha", petType = 9,  rarity = 4 },
  ["PET-B"] = { speciesID = 200, level = 10, name = "Beta",  petType = 6,  rarity = 3 },
  ["PET-C"] = { speciesID = 300, level = 25, name = "Gamma", petType = 3,  rarity = 4 },
  ["LVL-1"] = { speciesID = 400, level = 5,  name = "Lvl1",  petType = 5,  rarity = 2 },
  ["LVL-2"] = { speciesID = 500, level = 8,  name = "Lvl2",  petType = 8,  rarity = 3 },
}
local petOrder = { "PET-A", "PET-B", "PET-C", "LVL-1", "LVL-2" }

local slotPets
local function setSlots(t) slotPets = t end
local applied = {}

C_PetJournal = {
  GetNumPetLoadOutSlots = function() return 3 end,
  GetPetLoadOutInfo = function(slot)
    local p = slotPets and slotPets[slot]
    if not p then return nil end
    return p.petID, p.a1, p.a2, p.a3
  end,
  GetPetInfoByPetID = function(petID)
    local p = mockPets[petID]
    if not p then return nil end
    return p.speciesID, nil, p.level, nil, nil, nil, nil, p.name
  end,
  GetNumPets = function() return #petOrder end,
  GetPetInfoByIndex = function(i)
    local petID = petOrder[i]
    local p = petID and mockPets[petID]
    if not p then return nil end
    return petID, p.speciesID, true, nil, p.level, false, false, p.name, "icon", p.petType
  end,
  GetPetStats = function(petID)
    local p = mockPets[petID]
    return 100, 100, 10, 10, p and p.rarity or 1
  end,
  GetPetInfoBySpeciesID = function(speciesID)
    return "Species" .. tostring(speciesID), "icon", 1, nil,
      "Found somewhere.", "A short description."
  end,
  GetPetAbilityList = function(speciesID, idTable, levelTable)
    for _, id in ipairs(speciesAbilities[speciesID] or {}) do
      idTable[#idTable + 1] = id
      levelTable[#levelTable + 1] = 1
    end
  end,
  SetPetLoadOutInfo = function(slot, petID) applied[slot] = petID end,
  SetAbility = function() end,
}

-- ---- load addon in TOC order ----------------------------------------------
local ns = {}
local files = {
  "Core/Init.lua", "Core/Database.lua", "Core/Types.lua", "Core/Loadout.lua",
  "Core/Roster.lua", "Core/Groups.lua", "Core/Queue.lua", "Core/Teams.lua",
  "Core/Targets.lua", "Core/Serialize.lua", "Core/Battle.lua",
  "UI/MainWindow.lua", "UI/PetCard.lua", "UI/PetBrowser.lua", "UI/Minimap.lua",
  "Integration/tdBattlePetScript.lua", "Core/Slash.lua",
}
for _, f in ipairs(files) do assert(loadfile(f))("LongLivePets", ns) end

local function fire(e, ...) local h = ns.frame._scripts.OnEvent; if h then h(ns.frame, e, ...) end end
local function slash(c) SlashCmdList["LONGLIVEPETS"](c) end

-- ===========================================================================
print("\n[1] lifecycle"); fire("ADDON_LOADED", "LongLivePets"); fire("PLAYER_LOGIN")
check(type(LongLivePetsDB) == "table", "DB initialized")
check(LongLivePetsDB.schema == 2, "schema v2")

print("\n[2] save / load / abilities")
setSlots({ [1]={petID="PET-A",a1=11,a2=12,a3=13},
           [2]={petID="PET-B",a1=21,a2=22,a3=23},
           [3]={petID="PET-C",a1=31,a2=32,a3=33} })
slash("save Aqua")
local _, t = ns.Teams:GetByName("Aqua")
check(t and t.pets[2].petID == "PET-B", "pet captured")
applied = {}; slash("load Aqua")
check(applied[1]=="PET-A" and applied[3]=="PET-C", "pets applied on load")
check(ns.db.loaded ~= nil, "loaded team tracked")

print("\n[3] groups")
slash("group add Dungeons")
slash("group set Aqua => Dungeons")
local gid = ns.Groups:Resolve("Dungeons")
check(t.group == gid, "team assigned to group")
check(ns.Teams:List()[1].group == gid, "List reports group")
slash("group clear Aqua")
check(t.group == nil, "ungrouped via clear")
slash("group set Aqua => Dungeons")
slash("group delete Dungeons")
check(t.group == nil, "group delete ungroups its teams")

print("\n[4] notes")
slash("note Aqua => watch out for the moth")
check(t.notes == "watch out for the moth", "note set")
slash("note Aqua => ")
check(t.notes == nil, "note cleared")

print("\n[5] win/loss (manual + auto)")
slash("record win Aqua"); slash("record loss Aqua")
check(t.wins == 1 and t.losses == 1, "manual record")
ns.db.loaded = (select(1, ns.Teams:GetByName("Aqua")))
fire("PET_BATTLE_FINAL_ROUND", Enum.BattlePetOwner.Ally); fire("PET_BATTLE_CLOSE")
check(t.wins == 2, "auto-record win for loaded team")

print("\n[6] export / import round-trip")
local str = ns.Serialize:ExportTeam("Aqua")
check(type(str)=="string" and str:match("^LLP1:"), "export produces LLP1 string")
wipe(ns.db.teams)
local n = ns.Serialize:Import(str)
check(n == 1, "import reports 1 team")
local _, imp = ns.Teams:GetByName("Aqua")
check(imp and imp.pets[1].speciesID == 100, "imported pet species preserved")
check(imp and imp.pets[1].abilities[1] == 11, "imported ability preserved")
applied = {}; ns.Teams:Load((select(1, ns.Teams:GetByName("Aqua"))))
check(applied[1]=="PET-A" and applied[2]=="PET-B", "species resolved to owned pets on load")

print("\n[7] backup / restore all")
slash("save Second")
local backup = ns.Serialize:BackupAll()
wipe(ns.db.teams)
local restored = ns.Serialize:Import(backup)
check(restored == 2, "backup restores all teams")

print("\n[8] base64 round-trip")
local sample = "Hello, \1\2\255 world | = %"
check(ns.Serialize.decode64(ns.Serialize.encode64(sample)) == sample, "base64 lossless")

print("\n[9] targets + auto-load")
curTarget = "Creature-0-3299-0-0-12345-000ABCDEF0"
slash("save Tamer")
slash("target bind Tamer")
check(ns.Targets:GetTeamForNpc(12345) ~= nil, "team bound to npc 12345")
ns.db.settings.autoLoadOnTarget = true
ns.db.loaded = nil; applied = {}
fire("PLAYER_TARGET_CHANGED")
check(ns.db.loaded == ns.Targets:GetTeamForNpc(12345), "auto-loaded bound team on target")

print("\n[10] leveling queue + leveling slot")
setSlots({ [1]={petID="LVL-1"}, [2]={petID="PET-B"}, [3]={petID="PET-C"} })
slash("queue add 1")
check(ns.Queue:Contains("LVL-1"), "pet queued")
slash("save Leveler")
slash("levelslot Leveler 1")
applied = {}
ns.Teams:Load((select(1, ns.Teams:GetByName("Leveler"))))
check(applied[1] == "LVL-1", "leveling slot filled from queue front")
mockPets["LVL-1"].level = 25
ns.Queue:Prune()
check(not ns.Queue:Contains("LVL-1"), "maxed pet pruned from queue")

print("\n[11] counter advice")
local c = ns.Types:CounterFor("Aquatic")
check(c and c.strongAttacker and c.toughType, "counter returns advice")
check(ns.Types:CounterFor("nonsense") == nil, "bad type rejected")

print("\n[12] roster + filters")
mockPets["LVL-1"].level = 5   -- reset (the queue test dinged it to 25)
check(#ns.Roster:GetOwnedPets() == 5, "owned pets listed")
check(#ns.Roster:Filter({ search = "Alpha" }) == 1, "name search")
check(#ns.Roster:Filter({ maxOnly = true }) == 2, "level-25 filter")
check(#ns.Roster:Filter({ typeIndex = 6 }) == 1, "type filter (Magic)")
check(#ns.Roster:Filter({ strongVs = "Aquatic" }) == 1, "Strong-Vs filter (Flying beats Aquatic)")
check(#ns.Roster:Filter({ toughVs = "Aquatic" }) == 1, "Tough-Vs filter (Magic resists Aquatic)")
applied = {}; ns.Roster:SlotPet("PET-A", 2)
check(applied[2] == "PET-A", "browser slots a pet")

print("\n[13] ability-text search")
check(#ns.Roster:Filter({ ability = "web" }) == 1, "ability search finds 'web' (Sticky Web)")
check(#ns.Roster:Filter({ ability = "damage" }) == 3, "ability search matches descriptions")
check(#ns.Roster:Filter({ ability = "nonexistent" }) == 0, "ability search rejects misses")

print("\n[14] pet card")
local lines = ns.PetCard:BuildLines({ name = "Alpha", petType = 9, rarity = 4, level = 25, petID = "PET-A", speciesID = 100 })
check(lines[1] and lines[1].kind == "title" and lines[1].text == "Alpha", "card title is the pet name")
local hasHealth, hasDesc = false, false
for _, l in ipairs(lines) do
  if l.kind == "double" and l.left == "Health" then hasHealth = true end
  if l.kind == "wrap" and l.text == "A short description." then hasDesc = true end
end
check(hasHealth, "card shows stats")
check(hasDesc, "card shows description")

print("\n[15] UI build paths")
check(pcall(function() ns.UI:Show(); ns.UI:Refresh() end), "team window builds + refreshes")
check(pcall(function() ns.UI:ShowText("t","export","blob") end), "copy dialog builds")
check(pcall(function() ns.PetBrowser:Show(); ns.PetBrowser:Refresh() end), "pet browser builds + refreshes")
check(pcall(function() ns.Minimap:Create() end), "minimap button builds")
check(pcall(function() ns.PetCard:Show(ns.frame, { name="X", petType=1, level=1, petID="PET-A", speciesID=100 }) end), "pet card renders")

print(("\n==== %d passed, %d failed ===="):format(PASS, FAIL))
os.exit(FAIL == 0 and 0 or 1)
