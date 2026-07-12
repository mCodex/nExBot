-- TargetBot creature attack shim
-- Loads the split module chain in dependency order
-- Spells → Wave avoidance → Attack/walk coordinator + lure
dofile("/targetbot/attack_spells.lua")
dofile("/targetbot/attack_waves.lua")
dofile("/targetbot/attack_coordinator.lua")
