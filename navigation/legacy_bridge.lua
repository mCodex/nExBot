--[[
  navigation/legacy_bridge.lua — reroutes legacy CaveBot navigation calls to
  the strict NavigationSession (S9). Public CaveBot API signatures are kept
  (GoTo, gotoFirstPreviousReachableWaypoint, …); internals delegate here.

  The bridge is the ONLY production wiring point:
    * builds the OTClient port (adapter_otclient),
    * constructs every dependency (recovery, transitions, obstacles, ml),
    * registers CaveBot as the movement owner,
    * drives session:tick from the caller's run loop.

  It never dispatches movement directly — only through the session's strict,
  ack-driven flow.
]]

local AdapterOTClient = require("navigation.adapter_otclient")
local Session = require("navigation.session")
local Recovery = require("navigation.recovery")
local Transitions = require("navigation.transitions")
local Obstacles = require("navigation.obstacles")
local MLShadow = require("navigation.ml_shadow")
local RouteGraph = require("navigation.route_graph")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

local bridge = {}

local function buildDeps(port, session)
  return {
    recovery = Recovery.new(),
    transitions = Transitions.new(),
    obstacles = Obstacles.new(port),
    ml = MLShadow.new(session),
  }
end

--- Create the production bridge.
-- @param opts { port = port|nil, owner = "CAVEBOT"|nil, runLoop = nil }
function bridge.new(opts)
  opts = opts or {}
  local self = setmetatable({}, { __index = bridge })
  self.port = opts.port or AdapterOTClient.create()
  self.owner = opts.owner or "CAVEBOT"

  self.session = Session.new(self.port, {})
  self.deps = buildDeps(self.port, self.session)
  self.session.deps = self.deps

  self.movement = self.port.movement
  self._ownsMovement = false
  self._focus = nil

  -- Register as movement owner once (arbitration via movement_coordinator).
  if self.movement and self.movement.acquireOwnership then
    self._ownsMovement = self.movement.acquireOwnership(self.owner, 10) or false
  end

  -- Legacy call sites invoke the facade with DOT syntax
  -- (nExBot.Navigation.checkDrift(...)), so bind instance closures for those.
  -- NOTE: these MUST be called with DOT (bridge.buildRoute(...)), not colon.
  for _, name in ipairs({ "buildRoute", "isRouteBuilt", "getNextWaypoint",
    "checkDrift", "checkCorridor", "hasPassedWaypoint", "getGotoIndices",
    "invalidate", "recoverCorridor" }) do
    local fn = bridge[name]
    self[name] = function(...) return fn(self, ...) end
  end
  return self
end

--- Drive one navigation tick from the caller's run loop.
-- @param playerPos table
-- @return NavigationResult
function bridge:tick(playerPos)
  local ctx = {
    playerPos = playerPos,
    mapGeneration = self.port.world and self.port.world.getMapGeneration
      and self.port.world.getMapGeneration() or nil,
    nowMs = self.port.time and self.port.time.nowMs and self.port.time.nowMs() or 0,
    combatActive = false,
  }
  return self.session:tick(ctx)
end

--- Build a single-edge route to a destination and start walking.
-- Keeps the strict path flags: never ignoreNonPathable / ignoreNonWalkable.
function bridge:goTo(dest, opts)
  opts = opts or {}
  local playerPos = opts.playerPos or (player and player.getPosition and player:getPosition())
  if not dest or not playerPos then return false end
  if dest.z ~= playerPos.z then return false end

  local route = {
    id = "goto-" .. (opts.nonce or tostring(os.time())),
    nodes = {
      { id = "n1", pos = D.copyPos(playerPos), kind = D.NODE_KIND.ANCHOR },
      { id = "n2", pos = D.copyPos(dest), kind = D.NODE_KIND.ANCHOR },
    },
    edges = {
      { id = "e1", kind = D.EDGE_KIND.WALK, toNode = "n2",
        entryPos = D.copyPos(playerPos), toPos = D.copyPos(dest) },
    },
  }
  self.session:setRoute(route)
  self.session:selectEdge(1)
  self._focus = "n2"
  return true
end

--- Focus the previous reachable route node (recovery entry point kept public).
function bridge:focusNode(nodeId)
  local focus = self.session:focusNode(nodeId)
  self._focus = nodeId
  return focus
end

function bridge:routeFromWaypoints(waypoints)
  local route = RouteGraph.fromWaypoints(waypoints)
  if not route then return false end
  self.session:setRoute(route)
  return true
end

function bridge:snapshot()
  return {
    session = self.session:snapshot(),
    metrics = Obs.snapshot(),
    ownsMovement = self._ownsMovement,
    focus = self._focus,
  }
end

-- ── Legacy-facing facade (WaypointNavigator replacement) ───────────────────
-- These keep the shapes legacy call sites destructure (buildRoute, checkDrift,
-- checkCorridor -> status/dist/recovery, getNextWaypoint -> idx/pos,
-- getGotoIndices, hasPassedWaypoint, isRouteBuilt, invalidate). All geometry
-- derives from the strict session's route graph; recovery delegates to the
-- session so invariant-5 suppression structurally kills the WP26 refocus loop.

local function chebyshev(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- Distance from a point to a segment (only on the player's floor).
local function pointSegmentDist(p, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  local t = 0
  if len2 > 0 then
    t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
    t = math.max(0, math.min(1, t))
  end
  local px = a.x + t * dx
  local py = a.y + t * dy
  return math.max(math.abs(p.x - px), math.abs(p.y - py))
end

function bridge.buildRoute(self, waypointCache, floor)
  self.waypointCache = waypointCache
  if type(waypointCache) ~= "table" then return false end
  local waypoints, ids = {}, {}
  for i, wp in ipairs(waypointCache) do
    if wp and wp.isGoto ~= false and wp.z and (not floor or wp.z == floor) then
      waypoints[#waypoints + 1] = { x = wp.x, y = wp.y, z = wp.z }
      ids[#ids + 1] = i
    end
  end
  local route = RouteGraph.fromWaypoints(waypoints)
  if not route then return false end
  for i, node in ipairs(route.nodes) do node.cacheIndex = ids[i] end
  self.session:setRoute(route)
  if #route.edges > 0 then self.session:selectEdge(1) end
  return true
end

function bridge.isRouteBuilt(self)
  local route = self.session and self.session.route
  return not not (route and route.nodes and #route.nodes >= 2)
end

function bridge.getNextWaypoint(self, playerPos)
  local route = self.session and self.session.route
  if not route or not route.nodes then return nil end
  local bestIdx, bestNode
  for _, node in ipairs(route.nodes) do
    local p = node.pos
    if p and p.z == playerPos.z and (not bestNode
       or chebyshev(p, playerPos) < chebyshev(bestNode.pos, playerPos)) then
      bestIdx, bestNode = node.cacheIndex, node
    end
  end
  if bestNode then return bestIdx or bestNode.id, D.copyPos(bestNode.pos) end
  return nil
end

function bridge._offRouteDistance(self, playerPos)
  local route = self.session and self.session.route
  if not route or not route.nodes or #route.nodes < 2 then return nil end
  local best = math.huge
  for i = 1, #route.nodes - 1 do
    local a, b = route.nodes[i].pos, route.nodes[i + 1].pos
    if a and b and a.z == playerPos.z and b.z == playerPos.z then
      local d = pointSegmentDist(playerPos, a, b)
      if d < best then best = d end
    end
  end
  if best == math.huge then return nil end
  return best
end

function bridge.checkDrift(self, playerPos, threshold)
  local dist = self:_offRouteDistance(playerPos)
  if dist == nil then return false, nil end
  return dist > (threshold or 8), dist
end

function bridge.checkCorridor(self, playerPos)
  local dist = self:_offRouteDistance(playerPos)
  if dist == nil then return nil, nil, nil end
  local status = dist > 15 and "outside" or "inside"
  local recovery
  if status == "outside" then
    local idx = self:getNextWaypoint(playerPos)
    recovery = { nextWpIdx = idx }
  end
  return status, dist, recovery
end

function bridge.hasPassedWaypoint(self, playerPos, idx, destPos)
  if not playerPos or not destPos then return false end
  local route = self.session and self.session.route
  if not route or not route.nodes then return false end
  local node
  for _, n in ipairs(route.nodes) do
    if n.cacheIndex == idx then node = n break end
  end
  if not node or not node.pos then return false end
  -- The player is "past" the node when farther from it than the destination is.
  return chebyshev(playerPos, node.pos) >= chebyshev(destPos, node.pos) + 0.5
end

function bridge.getGotoIndices(self)
  local route = self.session and self.session.route
  if not route or not route.nodes then return {} end
  local out = {}
  for _, node in ipairs(route.nodes) do
    if node.cacheIndex then out[#out + 1] = node.cacheIndex end
  end
  return out
end

function bridge.invalidate(self)
  if self.session and self.session.invalidate then self.session.invalidate() end
end

-- WP26-safe corridor recovery: delegate to the strict session recovery (route
-- graph targets + invariant-5 suppression). Never re-focuses the same node
-- without new evidence, so the repeated-refocus log cannot be produced.
function bridge.recoverCorridor(self, playerPos)
  if not self.session.deps.recovery then return false end
  self.session.state = D.SESSION_STATE.RECOVERING
  local res = self.session.deps.recovery:tick(self.session, {
    playerPos = playerPos, nowMs = 0,
  })
  return not not (res and res.recovered)
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.legacy_bridge"] = bridge end
return bridge