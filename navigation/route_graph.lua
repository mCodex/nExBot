--[[
  navigation/route_graph.lua — route graph construction (T3).

  Normalizes legacy CaveBot waypoints ("x,y,z" / "x,y,z,label" action strings)
  into the strict route graph { id, nodes, edges } the Session consumes.

    * nodes: every waypoint becomes a node (id n1..nN, pos, kind).
    * edges: consecutive nodes -> WALK edges; a Z delta between consecutive
      waypoints becomes a floor-transition edge (STAIRS_UP/DOWN) with
      expectedFloorDelta, so transitions go through the coordinator.
    * A trailing `,0` / `,stairs` marker maps to STAIRS_UP.

  Pure Lua; no OTClient globals.
]]

local domain = require("navigation.domain")
local D = domain

local RouteGraph = {}

-- Normalize a single waypoint entry into { pos = {x,y,z}, marker = string|nil }.
local function parseWaypoint(wp)
  if type(wp) == "table" then
    if wp.pos then return { pos = D.copyPos(wp.pos), marker = wp.kind or wp.marker } end
    if wp.x and wp.y and wp.z then return { pos = D.copyPos(wp), marker = nil } end
    return nil
  end
  if type(wp) ~= "string" then return nil end
  local parts = {}
  for p in wp:gmatch("[^,]+") do parts[#parts + 1] = p end
  if #parts < 3 then return nil end
  local marker = parts[4] and parts[4] ~= "0" and parts[4] or nil
  return {
    pos = { x = tonumber(parts[1]), y = tonumber(parts[2]), z = tonumber(parts[3]) },
    marker = marker,
  }
end

local function edgeKindFor(a, b)
  if not a.pos or not b.pos then return D.EDGE_KIND.WALK end
  local dz = b.pos.z - a.pos.z
  if dz > 0 then return D.EDGE_KIND.STAIRS_UP end
  if dz < 0 then return D.EDGE_KIND.STAIRS_DOWN end
  if a.marker == "stairs" or b.marker == "stairs" then return D.EDGE_KIND.STAIRS_UP end
  return D.EDGE_KIND.WALK
end

--- Build a route from a legacy waypoint list.
-- @param waypoints list of "x,y,z[,...]" strings or {x=,y=,z=} tables
-- @return route or nil when the list is unusable
function RouteGraph.fromWaypoints(waypoints)
  if type(waypoints) ~= "table" or #waypoints < 2 then return nil end
  local nodes = {}
  local edges = {}
  local prev = nil
  for i, wp in ipairs(waypoints) do
    local parsed = parseWaypoint(wp)
    if not parsed or not parsed.pos then return nil end
    local node = { id = "n" .. i, pos = parsed.pos }
    if i == 1 then
      node.kind = D.NODE_KIND.ANCHOR
    elseif i == #waypoints then
      node.kind = D.NODE_KIND.ANCHOR
    end
    nodes[#nodes + 1] = node
    if prev then
      local kind = edgeKindFor(prev, parsed)
      local edge = {
        id = "e" .. (i - 1),
        kind = kind,
        toNode = node.id,
        entryPos = D.copyPos(prev.pos),
        toPos = D.copyPos(parsed.pos),
      }
      if D.TRANSITION_EDGES[kind] then
        edge.expectedFloorDelta = parsed.pos.z - prev.pos.z
      end
      edges[#edges + 1] = edge
    end
    prev = parsed
  end
  return { id = "route-" .. (waypoints.id or 1), nodes = nodes, edges = edges }
end

--- Rebuild the route when the waypoint list changes (profile edit).
-- Returns nil when nothing structurally changed.
function RouteGraph.rebuild(current, waypoints)
  local nextRoute = RouteGraph.fromWaypoints(waypoints)
  if not nextRoute then return nil end
  if not current then return nextRoute end
  if #current.nodes ~= #nextRoute.nodes then return nextRoute end
  for i, n in ipairs(current.nodes) do
    local m = nextRoute.nodes[i]
    if not m or not D.posEquals(n.pos, m.pos) then return nextRoute end
  end
  return nil
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.route_graph"] = RouteGraph end
return RouteGraph