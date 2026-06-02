--[[ Long Live Pets ----------------------------------------------------------
  Database.lua — SavedVariables bootstrap.

  Our own data shape (deliberately independent of any other addon):

    LongLivePetsDB = {
      schema   = <number>,            -- bump when the shape changes
      nextID   = <number>,            -- monotonic id source for teams
      teams    = {                    -- keyed by stringified id
        ["1"] = {
          name    = "Aquatic Stomp",
          updated = <epoch seconds>,
          script  = "MyScriptName" | nil,   -- optional tdBattlePetScript link
          pets    = {                       -- by battle slot (1..n)
            [1] = { petID = "BattlePet-...", speciesID = 123,
                    abilities = { ab1, ab2, ab3 } },
            ...
          },
        },
        ...
      },
      settings = { ... },
    }
----------------------------------------------------------------------------]]

local ns = _G.LongLivePets

local SCHEMA = 1

function ns:InitDB()
    LongLivePetsDB = LongLivePetsDB or {}
    local db = LongLivePetsDB

    db.nextID   = db.nextID   or 1
    db.teams    = db.teams    or {}
    db.settings = db.settings or {}
    db.schema   = SCHEMA

    ns.db = db
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ns.name then return end
    ns:InitDB()
end)
