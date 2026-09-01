-- cavebot/session_driver.lua
-- Bridges the strict S9 NavigationSession result contract back onto the
-- CaveBot goto callback contract, so the outer WaypointEngine loop can drive
-- the session without knowing anything about it. Pure function of its inputs;
-- no OTClient globals (the player/game pass through the args).
--
-- Result -> callback mapping:
--   STEP_DISPATCHED / EDGE_COMPLETED / TRANSITION_BEGIN -> "walking" (wait ack)
--   WAITING_ACK                                         -> "walking" (in-flight)
--   WAITING_BLOCKER / FAILED_RETRYABLE / REPLAN         -> "retry"
--   COMPLETED / NO_ACTIVE_EDGE                          -> true (route done)
--   FAILED_TERMINAL                                     -> false
--
-- ponytail: loaded via core/cavebot safeDofile whose pcall swallows load-time
-- errors, so like waypoint_policy this file must have NO load-time deps; the
-- navigation.domain require is deferred to first call (registry-backed in
-- sandbox, plain require in busted).
local SessionDriver = {}

local D

local function domain()
  if not D then D = require("navigation.domain") end
  return D
end

function SessionDriver.shouldUse(nav)
  if not nav then return false end
  if type(nav.isRouteBuilt) ~= "function" then return false end
  local ok, built = pcall(nav.isRouteBuilt, nav)
  return ok and built == true
end

function SessionDriver.tickAndMap(bridge, playerPos, opts)
  opts = opts or {}
  local res = bridge:tick({
    playerPos = playerPos,
    combatActive = opts.combatActive or false,
    preempted = opts.preempted or false,
    mapGeneration = opts.mapGeneration,
  })
  if not res or not res.status then return "retry", "none" end
  local d = domain()
  local st = res.status
  if st == d.NavStatus.COMPLETED then return true, "none" end
  if st == d.NavStatus.FAILED_TERMINAL then return false, "static" end
  -- Route exhausted: the session reports NO_ACTIVE_EDGE only after _selectSuccessor
  -- exhausts the route (buildRoute always selects edge 1 first), so this is the
  -- deterministic route-completion signal.
  if st == d.NavStatus.PROGRESS and res.reason == "NO_ACTIVE_EDGE" then
    return true, "none"
  end
  if st == d.NavStatus.WAITING_BLOCKER
     or st == d.NavStatus.FAILED_RETRYABLE
     or st == d.NavStatus.REPLAN then
    return "retry", "none"
  end
  -- PROGRESS / WAITING_ACK / ACTION_REQUIRED / TRANSITION_PENDING
  return "walking", "none"
end

if nExBot and nExBot.Nav then nExBot.Nav["cavebot.session_driver"] = SessionDriver end
return SessionDriver
