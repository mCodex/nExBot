-- route_validator.lua
-- Validates compiled routes and emits actionable diagnostics.

CaveBot = CaveBot or {}

local RouteValidator = {}

local function push(list, severity, code, message, index)
  list[#list + 1] = {
    severity = severity,
    code = code,
    message = message,
    index = index,
  }
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t or {}) do
    n = n + 1
  end
  return n
end

function RouteValidator.validate(route)
  local issues = {}
  route = route or {}
  local nodes = route.nodes or {}
  local gotoIndices = route.gotoIndices or {}

  if #nodes == 0 then
    push(issues, "error", "empty-route", "Route has no waypoint nodes")
  end

  if #gotoIndices == 0 then
    push(issues, "error", "missing-goto", "Route has no goto waypoints")
  end

  for _, node in ipairs(nodes) do
    if node.parseError then
      push(issues, "error", "parse-error", "Waypoint parse failed: " .. tostring(node.parseError), node.index)
    end
  end

  for _, edge in ipairs(route.gotoEdges or {}) do
    if edge.dz and math.abs(edge.dz) > 1 then
      push(issues, "error", "invalid-floor-jump", "Goto floor jump larger than 1 level", edge.from)
    end
  end

  local floorCount = countKeys(route.byFloor)
  if floorCount > 1 and #(route.floorTransitions or {}) == 0 then
    push(issues, "warning", "multi-floor-without-transitions", "Route spans multiple floors but has no consecutive goto floor transitions")
  end

  for key, count in pairs(route.positionHistogram or {}) do
    if count >= 4 then
      push(issues, "warning", "high-duplicate-waypoints", "Waypoint position repeated many times: " .. key .. " x" .. count)
    end
  end

  local errors = 0
  local warnings = 0
  for _, issue in ipairs(issues) do
    if issue.severity == "error" then
      errors = errors + 1
    elseif issue.severity == "warning" then
      warnings = warnings + 1
    end
  end

  return {
    ok = errors == 0,
    errors = errors,
    warnings = warnings,
    issues = issues,
  }
end

CaveBot.RouteValidator = RouteValidator
return RouteValidator
