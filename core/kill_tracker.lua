--[[
  Kill Tracker
  
  Tracks killed monsters with positions for corpse access.
  Provides public accessor for the killed monsters list.
  
  Extracted from event_bus.lua for SRP compliance.
  Domain logic belongs in its own module, not in infrastructure.
]]

KillTracker = {}

-- Track killed monsters with their positions for corpse access
local killedMonsters = {}  -- { [creatureId] = { pos, name, timestamp } }
local KILLED_MONSTER_EXPIRY_MS = 15000  -- 15 seconds

-- Bounded capacity to prevent unbounded growth
local MAX_KILLED_ENTRIES = 200

--- Record a monster kill.
-- @param creatureId number
-- @param name string
-- @param pos table {x, y, z}
function KillTracker.recordKill(creatureId, name, pos)
  if not creatureId or not pos then return end
  
  -- Evict oldest if at capacity
  local count = 0
  for _ in pairs(killedMonsters) do count = count + 1 end
  if count >= MAX_KILLED_ENTRIES then
    local oldestId, oldestTime = nil, math.huge
    for id, data in pairs(killedMonsters) do
      if data.timestamp < oldestTime then
        oldestTime = data.timestamp
        oldestId = id
      end
    end
    if oldestId then killedMonsters[oldestId] = nil end
  end
  
  local nowMs = now or (g_clock and g_clock.millis and g_clock.millis()) or 0
  killedMonsters[creatureId] = {
    pos = { x = pos.x, y = pos.y, z = pos.z },
    name = name or "Unknown",
    timestamp = nowMs
  }
end

--- Get killed monster data by creature ID.
-- @param creatureId number
-- @return table|nil { pos, name, timestamp }
function KillTracker.getKilled(creatureId)
  return killedMonsters[creatureId]
end

--- Get all killed monsters (for iteration).
-- @return table
function KillTracker.getAll()
  return killedMonsters
end

--- Get count of tracked kills.
-- @return number
function KillTracker.getCount()
  local count = 0
  for _ in pairs(killedMonsters) do count = count + 1 end
  return count
end

--- Clean up expired entries.
function KillTracker.cleanup()
  local nowMs = now or (g_clock and g_clock.millis and g_clock.millis()) or 0
  for id, data in pairs(killedMonsters) do
    if (nowMs - data.timestamp) > KILLED_MONSTER_EXPIRY_MS then
      killedMonsters[id] = nil
    end
  end
end

--- Clear all tracked kills.
function KillTracker.reset()
  killedMonsters = {}
end

return KillTracker
