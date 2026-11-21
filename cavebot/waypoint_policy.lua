-- Pure waypoint approach policy. Runtime facts are supplied by the caller.
local WaypointPolicy = {}

local MAX_STEPS = 50
local TRANSITION_KEYBOARD_DISTANCE = 3

local function walkableNeighborCount(topology)
  if topology.walkableNeighbors ~= nil then return topology.walkableNeighbors end
  if not topology.isWalkable or not topology.adjacentPositions then return nil end

  local count = 0
  for i = 1, math.min(#topology.adjacentPositions, 8) do
    if topology.isWalkable(topology.adjacentPositions[i]) then count = count + 1 end
  end
  return count
end

function WaypointPolicy.classify(waypoint, topology)
  waypoint = waypoint or {}
  topology = topology or {}

  if topology.floorChanged or topology.recovery then
    return "recovery"
  end

  if waypoint.isFloorChange or waypoint.transition or topology.isFloorChange
      or topology.adjacentFloorChange then
    return "transition"
  end

  local walkableNeighbors = walkableNeighborCount(topology)
  if waypoint.isCorridor or waypoint.corner and walkableNeighbors and walkableNeighbors <= 2 then
    return "corridor"
  end

  return "normal"
end

function WaypointPolicy.forApproach(context)
  context = context or {}
  local classification = context.classification or "normal"
  local maxSteps = math.min(math.max(1, context.maxSteps or MAX_STEPS), MAX_STEPS)

  if classification == "transition" or classification == "recovery" then
    local distance = context.distance or math.huge
    local dispatch = "auto"
    if classification == "recovery" or distance <= TRANSITION_KEYBOARD_DISTANCE then
      dispatch = "keyboard"
    end
    return {
      arrivalPrecision = 0,
      dispatch = dispatch,
      maxSteps = maxSteps,
      allowAdvance = context.floorObserved == true,
    }
  end

  if classification == "corridor" then
    return {
      arrivalPrecision = 0,
      dispatch = "keyboard",
      maxSteps = maxSteps,
      allowAdvance = true,
    }
  end

  return {
    arrivalPrecision = context.precision or 1,
    dispatch = "auto",
    maxSteps = maxSteps,
    allowAdvance = true,
  }
end

if nExBot then
  nExBot.Nav = nExBot.Nav or {}
  nExBot.Nav["cavebot.waypoint_policy"] = WaypointPolicy
end

return WaypointPolicy
