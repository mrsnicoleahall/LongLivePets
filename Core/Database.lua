--[[ Long Live Pets ----------------------------------------------------------
  Database.lua — SavedVariables bootstrap and schema.

    LongLivePetsDB = {
      schema      = 2,
      nextID      = <n>,            -- id source for teams
      nextGroupID = <n>,            -- id source for groups

      teams = {                     -- keyed by stringified id
        ["1"] = {
          name    = "Aquatic Stomp",
          group   = "2" | nil,      -- owning group id
          notes   = "..." | nil,
          script  = "MyScript" | nil,   -- optional tdBattlePetScript link
          wins    = <n>, losses = <n>,
          updated = <epoch>,
          pets    = {               -- by battle slot (1..n)
            [1] = { petID="BattlePet-..", speciesID=123,
                    abilities={a1,a2,a3}, leveling=false },
            ...
          },
        },
      },

      groups  = { ["1"] = { name="Dungeons", order=1 }, ... },
      queue   = { "BattlePet-..", ... },     -- ordered leveling queue (petIDs)
      targets = { [<npcID>] = "<teamID>" },  -- target -> team binding
      loaded  = "<teamID>" | nil,            -- last team we loaded
      settings = {
        autoLoadOnTarget = false,
        minimap = { hide = false, angle = 215 },
      },
    }
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local SCHEMA = 2

function ns:InitDB()
    LongLivePetsDB = LongLivePetsDB or {}
    local db = LongLivePetsDB

    db.nextID      = db.nextID      or 1
    db.nextGroupID = db.nextGroupID or 1
    db.teams       = db.teams       or {}
    db.groups      = db.groups      or {}
    db.queue       = db.queue       or {}
    db.targets     = db.targets     or {}
    db.settings    = db.settings    or {}

    local s = db.settings
    if s.autoLoadOnTarget == nil then s.autoLoadOnTarget = false end
    s.minimap = s.minimap or { hide = false, angle = 215 }

    db.schema = SCHEMA
    ns.db = db
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ns.name then return end
    ns:InitDB()
end)
