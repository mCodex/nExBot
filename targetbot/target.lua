-- TargetBot targeting pipeline shim
-- Loads the split module chain in dependency order
-- Pathfinding → Core coordinator → Event handler glue
dofile("/targetbot/target_pathfinding.lua")
dofile("/targetbot/target_coordinator.lua")
dofile("/targetbot/target_events.lua")
