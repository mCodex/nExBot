--[[
  DEPRECATED: Friend Healer has been merged into HealBot.lua
  This file exists only for backward compatibility.
  All functionality moved to core/HealBot.lua
  See HealBot UI panel → "Ally" button for friend healing configuration.
]]
pcall(dofile, "core/HealBot.lua")

-- Re-export to maintain any global references
if not HealBot then
  warn("[new_healer] HealBot not loaded, friend healer UI will not be available")
end
