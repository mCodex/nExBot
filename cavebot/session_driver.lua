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
--   COMPLETED                                           -> true
--   FAILED_TERMINAL                                     -> false
local SessionDriver = {}

local domain = require("navigation.domain")
local D = domain

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
  local st = res.status
  if st == D.NavStatus.COMPLETED then return true, "none" end
  if st == D.NavStatus.FAILED_TERMINAL then return false, "static" end
  if st == D.NavStatus.WAITING_BLOCKER
     or st == D.NavStatus.FAILED_RETRYABLE
     or st == D.NavStatus.REPLAN then
    return "retry", "none"
  end
  -- PROGRESS / WAITING_ACK / ACTION_REQUIRED / TRANSITION_PENDING
  return "walking", "none"
end

if nExBot and nExBot.Nav then nExBot.Nav["cavebot.session_driver"] = SessionDriver end
return SessionDriver
