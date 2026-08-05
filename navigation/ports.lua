--[[
  navigation/ports.lua — Infrastructure ports for the Navigation context.

  The domain (session/executor/validator/recovery/…) depends ONLY on these
  functions. Production adapter: navigation/adapter_otclient.lua.
  Deterministic adapter: navigation/adapter_fake.lua (also used in tests).

  All functions must be safe to call at any time and must never throw.
]]

local P = {}

-- Port contract: a table with the following fields (each optional; a missing
-- field degrades the capability and the domain will fail safe, never guess).
--
--   world = {
--     getMapGeneration() -> number|nil
--     getTile(pos) -> { walkable=bool, pathable=bool, hazard=string|nil,
--                       floorChange=bool, doorClosed=bool, bridgeBroken=bool,
--                       unknown=bool } | nil   -- nil = void/unknown tile
--     getTileBlockReason(pos, opts) -> obstacleType|nil  (diagnosis)
--     getClearance(pos, maxR) -> number  -- free tiles to nearest blocking tile
--     getMinimapColor(pos) -> number|nil
--     isField(pos) -> bool
--     fieldAgeMs(pos) -> number|nil
--   }
--   path = {
--     findPath(startPos, goalPos, opts) -> { directions={...}, positions={...},
--                                            cost=number } | nil
--       opts: { maxSteps, ignoreCreatures, allowFields, allowFloorChange }
--     -- STRICT by default: no ignoreNonPathable / ignoreNonWalkable flags.
--   }
--   movement = {
--     walk(dir) -> bool            -- single keyboard step (prewalk)
--     autoWalk(destPos, chunkSize) -> bool
--     stopAutoWalk()
--     isWalking() -> bool          -- informational ONLY, never progress
--     acquireOwnership(owner, priority) -> bool
--     releaseOwnership(owner)
--     getOwner() -> string
--     onPositionChange(cb(newPos, oldPos)) -> unsubscribe
--     onZChange(cb(newPos, oldPos)) -> unsubscribe
--     onWalkError(cb(reason)) -> unsubscribe
--   }
--   action = {
--     use(pos, itemId) -> bool
--     useWith(pos, itemId, targetPos) -> bool
--     hasItem(itemId) -> bool
--   }
--   time = {
--     nowMs() -> number
--   }
--   bus = {
--     emit(event, payload)
--   }
--   log = {
--     info(msg), warn(msg), debug(msg)
--   }
--
-- Deterministic policy: unknown capability => nil/false, never "true".

function P.create(overrides)
  local port = {}
  port.world = {}
  port.path = {}
  port.movement = {}
  port.action = {}
  port.time = { nowMs = function() return os.time() * 1000 end }
  port.bus = { emit = function() end }
  port.log = { info = function() end, warn = function() end, debug = function() end }

  if overrides then
    for layer, tbl in pairs(overrides) do
      if type(tbl) == "table" then
        for k, v in pairs(tbl) do port[layer][k] = v end
      else
        port[layer] = tbl
      end
    end
  end
  return port
end

-- Null implementations (fail safe): every call returns nil/false.
function P.nullWorld()
  return {
    getMapGeneration = function() return nil end,
    getTile = function() return nil end,
    getTileBlockReason = function() return nil end,
    getClearance = function() return 1 end,
    getMinimapColor = function() return nil end,
    isField = function() return false end,
    fieldAgeMs = function() return nil end,
  }
end

function P.nullPath()
  return { findPath = function() return nil end }
end

function P.nullMovement()
  return {
    walk = function() return false end,
    autoWalk = function() return false end,
    stopAutoWalk = function() end,
    isWalking = function() return false end,
    acquireOwnership = function() return true end,
    releaseOwnership = function() end,
    getOwner = function() return "NONE" end,
    onPositionChange = function() return function() end end,
    onZChange = function() return function() end end,
    onWalkError = function() return function() end end,
  }
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.ports"] = P end
return P
