-- route_compiler.lua
-- Compiles parsed waypoint nodes into a deterministic route graph.

CaveBot = CaveBot or {}

local RouteCompiler = {}

local function positionKey(p)
  if not p then return nil end
  return table.concat({ tostring(p.x), tostring(p.y), tostring(p.z) }, ":")
end

local function addFloorIndex(byFloor, z, idx)
  if not z then return end
  local list = byFloor[z]
  if not list then
    list = {}
    byFloor[z] = list
  end
  list[#list + 1] = idx
end

function RouteCompiler.compile(nodes)
  local route = {
    nodes = nodes or {},
    nodeCount = 0,
    gotoIndices = {},
    byFloor = {},
    sequentialEdges = {},
    gotoEdges = {},
    floorTransitions = {},
    positionHistogram = {},
    anchorByFloor = {},
  }

  route.nodeCount = #route.nodes
  if route.nodeCount == 0 then
    return route
  end

  for i, node in ipairs(route.nodes) do
    if node.pos then
      addFloorIndex(route.byFloor, node.pos.z, i)
      local k = positionKey(node.pos)
      if k then
        route.positionHistogram[k] = (route.positionHistogram[k] or 0) + 1
      end
    end

    if node.isGoto then
      route.gotoIndices[#route.gotoIndices + 1] = i
      if node.pos and not route.anchorByFloor[node.pos.z] then
        route.anchorByFloor[node.pos.z] = i
      end
    end

    local nextIdx = (i % route.nodeCount) + 1
    route.sequentialEdges[#route.sequentialEdges + 1] = { from = i, to = nextIdx }
  end

  for i = 1, #route.gotoIndices do
    local fromIdx = route.gotoIndices[i]
    local toIdx = route.gotoIndices[(i % #route.gotoIndices) + 1]
    local from = route.nodes[fromIdx]
    local to = route.nodes[toIdx]
    local dz = nil
    if from and from.pos and to and to.pos then
      dz = to.pos.z - from.pos.z
      if dz ~= 0 then
        route.floorTransitions[#route.floorTransitions + 1] = {
          from = fromIdx,
          to = toIdx,
          fromZ = from.pos.z,
          toZ = to.pos.z,
          dz = dz,
        }
      end
    end

    route.gotoEdges[#route.gotoEdges + 1] = {
      from = fromIdx,
      to = toIdx,
      dz = dz,
    }
  end

  return route
end

CaveBot.RouteCompiler = RouteCompiler
return RouteCompiler
