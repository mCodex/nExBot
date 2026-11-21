--[[
  navigation/obstacles.lua — inline obstacle resolution for action edges (T6).

  Resolves a failure on an ACTION edge by performing the required item action
  (door keys, machete, shovel, rope, ...). On success it invalidates the edge
  path and lets the session replan strictly — the obstacle module never
  authorizes a permissive walk.

  handleFailure(session, failure, playerPos) -> bool (true = resolved inline;
  session short-circuits and does NOT record a retry/failure for this one).

  Port contract: unknown capability (no action port / missing item) = NOT
  handled here; the failure propagates to retry (fail-safe by construction).
]]

local domain = require("navigation.domain")
local D = domain
local Obs = require("navigation.observability")

local ObstacleResolver = {}

-- itemId requirements per action edge kind. Keep the ids symbolic; the real
-- client adapter maps them to OTClient item ids.
local RESOLVER = {
  [D.EDGE_KIND.DOOR] = { kind = "use",   itemIds = { "door_key" },   effect = "OPEN_DOOR" },
  [D.EDGE_KIND.MACHETE] = { kind = "useWith", itemIds = { "machete" }, effect = "CUT_JUNGLE" },
  [D.EDGE_KIND.SCYTHE] = { kind = "useWith", itemIds = { "scythe" },  effect = "CUT_GRASS" },
  [D.EDGE_KIND.SHOVEL_HOLE] = { kind = "use",   itemIds = { "shovel" },  effect = "DIG_HOLE" },
  [D.EDGE_KIND.ROPE_UP] = { kind = "use",   itemIds = { "rope" },     effect = "USE_ROPE" },
  [D.EDGE_KIND.HOLE_DOWN] = { kind = "use",   itemIds = { "rope" },     effect = "USE_ROPE" },
  [D.EDGE_KIND.BRIDGE] = { kind = "use",     itemIds = { "plank" },    effect = "REPAIR_BRIDGE" },
}

-- Only resolve when the failure is consistent with a static obstacle at the
-- edge's action position (never resolve transient/movement failures).
local RESOLVABLE_FAILURES = {
  [D.FAILURE.STATIC_TOPOLOGY_BLOCK] = true,
  [D.FAILURE.DOOR_REQUIRED] = true,
  [D.FAILURE.TOOL_REQUIRED] = true,
  [D.FAILURE.MISSING_TOOL] = true,
  [D.FAILURE.BROKEN_BRIDGE] = true,
}

local function new(ports)
  local self = setmetatable({}, { __index = ObstacleResolver })
  self.ports = ports or {}
  self.lastResolved = nil

  -- Session calls handleFailure with DOT syntax (deps.obstacles.handleFailure
  -- (session, failure, playerPos)), so bind the instance here.
  self.handleFailure = function(session, failure, playerPos)
    return ObstacleResolver.handleFailure(self, session, failure, playerPos)
  end
  self.snapshot = function()
    return ObstacleResolver.snapshot(self)
  end
  return self
end
ObstacleResolver.new = new

local function atActionPos(session, target)
  local world = session.ports and session.ports.world
  local tile = world and world.getTile and world.getTile(target)
  if not tile then
    -- No map signal: unknown capability must NOT be treated as resolvable.
    return false, "UNKNOWN_TILE"
  end
  if tile.doorClosed then return true, "DOOR_CLOSED" end
  if not tile.walkable and tile.bridgeBroken then return true, "BROKEN_BRIDGE" end
  if not tile.walkable then return true, "STATIC_BLOCK" end
  return false, "CLEAR"
end

function ObstacleResolver:handleFailure(session, failure, _playerPos)
  local edge = session.activeEdge
  if not edge then return false end
  local spec = RESOLVER[edge.kind]
  if not spec then return false end
  if not RESOLVABLE_FAILURES[failure] then return false end

  local target = edge.actionPos or edge.toPos
  if not target then return false end

  local matches, detail = atActionPos(session, target)
  if not matches then return false end

  local action = self.ports.action
  if not action or not action.use then return false end

  -- Find the required item in inventory. Missing item -> not handled (retry).
  local itemId = nil
  for _, id in ipairs(spec.itemIds) do
    if action.hasItem and action.hasItem(id) then itemId = id break end
  end
  if not itemId then
    Obs.bump("missingToolCount", 1)
    return false
  end

  local ok
  if spec.kind == "useWith" then
    ok = action.useWith and action.useWith(target, itemId, target)
  else
    ok = action.use and action.use(target, itemId)
  end
  if not ok then
    Obs.bump("actionNoEffectCount", 1)
    return false
  end

  self.lastResolved = {
    edgeId = edge.id, effect = spec.effect, itemId = itemId,
    target = D.copyPos(target), detail = detail,
  }
  Obs.record({
    reasonCodes = { D.REASON.OBSTACLE_RESOLVED },
    detail = self.lastResolved,
  })

  -- Invalidate so the session strictly replans (never a permissive pass).
  if session.invalidated then session:invalidated("OBSTACLE_RESOLVED") end
  session.edgePath = nil
  return true
end

function ObstacleResolver:snapshot()
  return { lastResolved = self.lastResolved }
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.obstacles"] = ObstacleResolver end
return ObstacleResolver