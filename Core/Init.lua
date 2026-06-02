--[[ Long Live Pets ----------------------------------------------------------
  Init.lua — namespace, version, lightweight event dispatcher, chat helper.

  Original work. This addon is an independent, clean-room implementation and
  contains no code from Rematch or any other addon. See NOTICE.md.
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

-- Expose the private namespace globally so all files (and the integration
-- layer) share one table.
_G.LongLivePets = ns
ns.name = ADDON_NAME

-- Version string, read from the TOC. C_AddOns is the modern (current-WoW)
-- home for addon metadata.
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.1.0"

-- ---------------------------------------------------------------------------
-- Tiny event system: ns:On(event, handler). Events are registered lazily the
-- first time a handler subscribes, and every handler is called inside pcall so
-- one bad listener can't take down the rest.
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame

local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then
            ns:Print("|cffff5555internal error|r in " .. event .. ": " .. tostring(err))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Chat helper
-- ---------------------------------------------------------------------------
local PREFIX = "|cff8ec5ffLong Live Pets|r: "

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end
