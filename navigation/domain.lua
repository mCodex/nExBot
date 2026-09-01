--[[
  navigation/domain.lua — Navigation bounded context: shared vocabulary.

  Pure Lua. No OTClient globals, no IO, no logging.
  All navigation code speaks these terms; nothing else does.
]]

local D = {}

-- ── Direction constants (match OTClient direction enum 0..7) ──────────────
D.DIR = {
  NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3,
  NE = 4, SE = 5, SW = 6, NW = 7,
}
D.DIR_TO_OFFSET = {
  [0] = { x = 0,  y = -1 },
  [1] = { x = 1,  y = 0  },
  [2] = { x = 0,  y = 1  },
  [3] = { x = -1, y = 0  },
  [4] = { x = 1,  y = -1 },
  [5] = { x = 1,  y = 1  },
  [6] = { x = -1, y = 1  },
  [7] = { x = -1, y = -1 },
}
D.OPPOSITE = { [0] = 2, [1] = 3, [2] = 0, [3] = 1, [4] = 6, [5] = 7, [6] = 4, [7] = 5 }
D.ADJACENT = {
  [0] = { [0] = true, [1] = true, [3] = true, [4] = true, [7] = true },
  [1] = { [1] = true, [0] = true, [2] = true, [4] = true, [5] = true },
  [2] = { [2] = true, [1] = true, [3] = true, [5] = true, [6] = true },
  [3] = { [3] = true, [0] = true, [2] = true, [6] = true, [7] = true },
  [4] = { [4] = true, [0] = true, [1] = true },
  [5] = { [5] = true, [1] = true, [2] = true },
  [6] = { [6] = true, [2] = true, [3] = true },
  [7] = { [7] = true, [3] = true, [0] = true },
}

function D.isDiagonal(dir) return dir ~= nil and dir >= 4 end
function D.offsetOf(dir) return D.DIR_TO_OFFSET[dir] end

function D.addOffset(pos, off)
  return { x = pos.x + off.x, y = pos.y + off.y, z = pos.z }
end

function D.posEquals(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

function D.chebyshev(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function D.posKey(pos)
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

function D.copyPos(pos)
  return { x = pos.x, y = pos.y, z = pos.z }
end

-- Direction from a to b (both must be adjacent). Nil if not adjacent.
function D.directionBetween(from, to)
  local dx = to.x - from.x
  local dy = to.y - from.y
  if math.abs(dx) > 1 or math.abs(dy) > 1 or (dx == 0 and dy == 0) then return nil end
  local key = (dx < 0 and -1 or (dx > 0 and 1 or 0)) .. "," .. (dy < 0 and -1 or (dy > 0 and 1 or 0))
  local map = {
    ["0,-1"] = 0, ["1,0"] = 1, ["0,1"] = 2, ["-1,0"] = 3,
    ["1,-1"] = 4, ["1,1"] = 5, ["-1,1"] = 6, ["-1,-1"] = 7,
  }
  return map[key]
end

-- ── Node kinds / edge kinds ────────────────────────────────────────────────
D.NODE_KIND = {
  ANCHOR = "ANCHOR", CORNER = "CORNER", CHOKE = "CHOKE",
  ACTION_ENTRY = "ACTION_ENTRY", TRANSITION_ENTRY = "TRANSITION_ENTRY",
  TRANSITION_EXIT = "TRANSITION_EXIT",
}

D.EDGE_KIND = {
  WALK = "WALK", STAIRS_UP = "STAIRS_UP", STAIRS_DOWN = "STAIRS_DOWN",
  LADDER_UP = "LADDER_UP", LADDER_DOWN = "LADDER_DOWN", HOLE_DOWN = "HOLE_DOWN",
  USE_HOLE = "USE_HOLE", ROPE_UP = "ROPE_UP", SHOVEL_HOLE = "SHOVEL_HOLE",
  DOOR = "DOOR", MACHETE = "MACHETE", SCYTHE = "SCYTHE",
  FIELD_CROSSING = "FIELD_CROSSING", BRIDGE = "BRIDGE", TELEPORT = "TELEPORT",
  SCRIPTED = "SCRIPTED",
}

D.CRITICAL_EDGES = {
  [D.EDGE_KIND.STAIRS_UP] = true, [D.EDGE_KIND.STAIRS_DOWN] = true,
  [D.EDGE_KIND.LADDER_UP] = true, [D.EDGE_KIND.LADDER_DOWN] = true,
  [D.EDGE_KIND.HOLE_DOWN] = true, [D.EDGE_KIND.USE_HOLE] = true,
  [D.EDGE_KIND.ROPE_UP] = true, [D.EDGE_KIND.SHOVEL_HOLE] = true,
  [D.EDGE_KIND.DOOR] = true, [D.EDGE_KIND.MACHETE] = true,
  [D.EDGE_KIND.SCYTHE] = true, [D.EDGE_KIND.BRIDGE] = true,
  [D.EDGE_KIND.TELEPORT] = true, [D.EDGE_KIND.SCRIPTED] = true,
}

D.TRANSITION_EDGES = {
  [D.EDGE_KIND.STAIRS_UP] = true, [D.EDGE_KIND.STAIRS_DOWN] = true,
  [D.EDGE_KIND.LADDER_UP] = true, [D.EDGE_KIND.LADDER_DOWN] = true,
  [D.EDGE_KIND.HOLE_DOWN] = true, [D.EDGE_KIND.USE_HOLE] = true,
  [D.EDGE_KIND.ROPE_UP] = true, [D.EDGE_KIND.SHOVEL_HOLE] = true,
  [D.EDGE_KIND.TELEPORT] = true,
}

-- ── Failure taxonomy ───────────────────────────────────────────────────────
D.FAILURE = {
  NO_PATH_CURRENT_MAP = "NO_PATH_CURRENT_MAP",
  FIRST_STEP_BLOCKED = "FIRST_STEP_BLOCKED",
  TEMPORARY_CREATURE_BLOCK = "TEMPORARY_CREATURE_BLOCK",
  STATIC_TOPOLOGY_BLOCK = "STATIC_TOPOLOGY_BLOCK",
  FIELD_BLOCK = "FIELD_BLOCK",
  DOOR_REQUIRED = "DOOR_REQUIRED",
  TOOL_REQUIRED = "TOOL_REQUIRED",
  BROKEN_BRIDGE = "BROKEN_BRIDGE",
  BROKEN_BRIDGE_NO_ALTERNATE = "BROKEN_BRIDGE_NO_ALTERNATE",
  STALE_PATH = "STALE_PATH",
  PARTIAL_AUTOWALK = "PARTIAL_AUTOWALK",
  SERVER_STEP_REJECTED = "SERVER_STEP_REJECTED",
  NO_POSITION_ACK = "NO_POSITION_ACK",
  PATH_DIVERGENCE = "PATH_DIVERGENCE",
  WRONG_FLOOR = "WRONG_FLOOR",
  WRONG_TRANSITION_EXIT = "WRONG_TRANSITION_EXIT",
  MISSING_TOOL = "MISSING_TOOL",
  ACTION_NO_EFFECT = "ACTION_NO_EFFECT",
  COMBAT_PREEMPTED = "COMBAT_PREEMPTED",
  MANUAL_PREEMPTED = "MANUAL_PREEMPTED",
  MAP_RELOADED = "MAP_RELOADED",
  RECOVERY_TARGET_UNREACHABLE = "RECOVERY_TARGET_UNREACHABLE",
  ROUTE_CONFIGURATION_ERROR = "ROUTE_CONFIGURATION_ERROR",
  TRANSITION_TIMEOUT = "TRANSITION_TIMEOUT",
  TRANSITION_FIRST_STEP_INVALID = "TRANSITION_FIRST_STEP_INVALID",
  UNKNOWN_FAILURE = "UNKNOWN_FAILURE",
}

-- ── Retry phases (single retry owner, session-managed) ────────────────────
D.RETRY_PHASE = {
  RETRY_SAME_VALIDATED_STEP = "RETRY_SAME_VALIDATED_STEP",
  REFRESH_CURRENT_PATH = "REFRESH_CURRENT_PATH",
  WAIT_TEMPORARY_BLOCKER = "WAIT_TEMPORARY_BLOCKER",
  RESOLVE_OBSTACLE = "RESOLVE_OBSTACLE",
  LOCAL_REPLAN = "LOCAL_REPLAN",
  REJOIN_CURRENT_EDGE = "REJOIN_CURRENT_EDGE",
  BACKTRACK_CONFIRMED_ANCHOR = "BACKTRACK_CONFIRMED_ANCHOR",
  ROUTE_EDGE_RECOVERY = "ROUTE_EDGE_RECOVERY",
  FAILED_SAFE = "FAILED_SAFE",
}

-- ── NavigationResult contract ──────────────────────────────────────────────
D.NavStatus = {
  PROGRESS = "PROGRESS",
  WAITING_ACK = "WAITING_ACK",
  WAITING_BLOCKER = "WAITING_BLOCKER",
  REPLAN = "REPLAN",
  ACTION_REQUIRED = "ACTION_REQUIRED",
  TRANSITION_PENDING = "TRANSITION_PENDING",
  COMPLETED = "COMPLETED",
  FAILED_RETRYABLE = "FAILED_RETRYABLE",
  FAILED_TERMINAL = "FAILED_TERMINAL",
}

-- Never return success unless a command was issued or progress observed.
function D.result(status, reason, extra)
  local r = {
    status = status, reason = reason or "NO_REASON",
    commandIssued = false, observedProgress = false,
    retryAfterMs = nil, evidenceRevision = 0,
  }
  if extra then
    for k, v in pairs(extra) do r[k] = v end
  end
  return r
end

-- ── Reason codes (shared vocabulary for records + diagnostics) ─────────────
D.REASON = {
  STEP_VALIDATED = "STEP_VALIDATED",
  STEP_REJECTED_BLOCKED = "STEP_REJECTED_BLOCKED",
  DIAGONAL_CORNER_REJECTED = "DIAGONAL_CORNER_REJECTED",
  MOVEMENT_DISPATCHED = "MOVEMENT_DISPATCHED",
  MOVEMENT_ACKNOWLEDGED = "MOVEMENT_ACKNOWLEDGED",
  PARTIAL_AUTOWALK = "PARTIAL_AUTOWALK",
  PATH_DIVERGED = "PATH_DIVERGED",
  PATH_INVALIDATED = "PATH_INVALIDATED",
  GEOMETRIC_CORRIDOR_FALSE_POSITIVE = "GEOMETRIC_CORRIDOR_FALSE_POSITIVE",
  RECOVERY_TARGET_UNREACHABLE = "RECOVERY_TARGET_UNREACHABLE",
  RECOVERY_TARGET_DUPLICATE_SUPPRESSED = "RECOVERY_TARGET_DUPLICATE_SUPPRESSED",
  RECOVERY_ANCHOR_SELECTED = "RECOVERY_ANCHOR_SELECTED",
  RECOVERY_REQUIRES_REPLAN = "RECOVERY_REQUIRES_REPLAN",
  RECOVERY_FAILED_SAFE = "RECOVERY_FAILED_SAFE",
  TRANSITION_ENTRY_CONFIRMED = "TRANSITION_ENTRY_CONFIRMED",
  TRANSITION_ACTION_DISPATCHED = "TRANSITION_ACTION_DISPATCHED",
  WAITING_EXPECTED_Z_CHANGE = "WAITING_EXPECTED_Z_CHANGE",
  EXPECTED_TRANSITION_COMPLETED = "EXPECTED_TRANSITION_COMPLETED",
  WRONG_TRANSITION_EXIT = "WRONG_TRANSITION_EXIT",
  UNEXPECTED_Z_CHANGE = "UNEXPECTED_Z_CHANGE",
  CRITICAL_EDGE_NOT_SKIPPED = "CRITICAL_EDGE_NOT_SKIPPED",
  TRANSITION_BEGIN = "TRANSITION_BEGIN",
  TRANSITION_STEP_DISPATCHED = "TRANSITION_STEP_DISPATCHED",
  OBSTACLE_RESOLVED = "OBSTACLE_RESOLVED",
  ML_SHADOW_RECOMMENDATION = "ML_SHADOW_RECOMMENDATION",
  ML_REJECTED_BY_GUARDRAIL = "ML_REJECTED_BY_GUARDRAIL",
  NAVIGATION_FAILED_SAFE = "NAVIGATION_FAILED_SAFE",
  RECOVERY_NO_CHANGE = "RECOVERY_NO_CHANGE",
}

-- ── Transition classification ──────────────────────────────────────────────
D.TRANSITION_CLASS = {
  EXPECTED_TRANSITION_COMPLETED = "EXPECTED_TRANSITION_COMPLETED",
  EXPECTED_TRANSITION_WRONG_EXIT = "EXPECTED_TRANSITION_WRONG_EXIT",
  EXPECTED_TRANSITION_TIMEOUT = "EXPECTED_TRANSITION_TIMEOUT",
  ACCIDENTAL_Z_CHANGE = "ACCIDENTAL_Z_CHANGE",
  REVERSE_TRANSITION = "REVERSE_TRANSITION",
  TELEPORT = "TELEPORT",
  RECONNECT_RESTORE = "RECONNECT_RESTORE",
  UNKNOWN_Z_CHANGE = "UNKNOWN_Z_CHANGE",
}

-- ── Obstacle types ─────────────────────────────────────────────────────────
D.OBSTACLE = {
  TEMPORARY_CREATURE = "TEMPORARY_CREATURE",
  STATIC_UNWALKABLE = "STATIC_UNWALKABLE",
  FIRE_FIELD = "FIRE_FIELD",
  ENERGY_FIELD = "ENERGY_FIELD",
  POISON_FIELD = "POISON_FIELD",
  MAGIC_WALL = "MAGIC_WALL",
  WILD_GROWTH = "WILD_GROWTH",
  CLOSED_DOOR = "CLOSED_DOOR",
  LOCKED_DOOR = "LOCKED_DOOR",
  ROPE_SPOT = "ROPE_SPOT",
  SHOVEL_SPOT = "SHOVEL_SPOT",
  MACHETE_TARGET = "MACHETE_TARGET",
  SCYTHE_TARGET = "SCYTHE_TARGET",
  PARCEL_OR_MOVABLE = "PARCEL_OR_MOVABLE",
  BROKEN_BRIDGE = "BROKEN_BRIDGE",
  VOID_OR_MISSING_TILE = "VOID_OR_MISSING_TILE",
  UNKNOWN_MAP = "UNKNOWN_MAP",
  SERVER_REJECTED_STEP = "SERVER_REJECTED_STEP",
}

-- ── Field safety decision ──────────────────────────────────────────────────
D.FIELD_DECISION = {
  FIELD_SAFE_TO_CROSS = "FIELD_SAFE_TO_CROSS",
  FIELD_WAIT_FOR_DECAY = "FIELD_WAIT_FOR_DECAY",
  FIELD_LOCAL_DETOUR = "FIELD_LOCAL_DETOUR",
  FIELD_REMOVE_WITH_ACTION = "FIELD_REMOVE_WITH_ACTION",
  FIELD_ROUTE_BLOCKED = "FIELD_ROUTE_BLOCKED",
  FIELD_UNKNOWN_FAIL_SAFE = "FIELD_UNKNOWN_FAIL_SAFE",
}

-- ── NavigationResult / record constants ────────────────────────────────────
D.EVIDENCE_INVALIDATORS = {
  PLAYER_MOVED = "PLAYER_MOVED",
  MAP_GENERATION_CHANGED = "MAP_GENERATION_CHANGED",
  PATH_RESULT_CHANGED = "PATH_RESULT_CHANGED",
  ACTIVE_EDGE_CHANGED = "ACTIVE_EDGE_CHANGED",
  COMBAT_STATE_CHANGED = "COMBAT_STATE_CHANGED",
  TRANSITION_COMPLETED = "TRANSITION_COMPLETED",
  COOLDOWN_NEW_ATTEMPT = "COOLDOWN_NEW_ATTEMPT",
}

-- Movement command state
D.COMMAND_STATE = {
  DISPATCHED = "DISPATCHED",
  ACKNOWLEDGING = "ACKNOWLEDGING",
  COMPLETED = "COMPLETED",
  DIVERGED = "DIVERGED",
  REJECTED = "REJECTED",
  PREEMPTED = "PREEMPTED",
}

-- Session state
D.SESSION_STATE = {
  IDLE = "IDLE",
  EDGE_ACTIVE = "EDGE_ACTIVE",
  TRANSITION_PENDING = "TRANSITION_PENDING",
  RECOVERING = "RECOVERING",
  WAITING_BLOCKER = "WAITING_BLOCKER",
  FAILED_SAFE = "FAILED_SAFE",
}

-- Edge completion gates
D.EDGE_STATE = {
  ACTIVE = "ACTIVE",
  COMPLETED = "COMPLETED",
  BLOCKED = "BLOCKED",
  DEFERRED = "DEFERRED",
}

-- Movement owners (arbitration)
D.MOVEMENT_OWNER = {
  CAVEBOT = "CAVEBOT",
  TARGETBOT = "TARGETBOT",
  MANUAL = "MANUAL",
  NONE = "NONE",
}

if nExBot and nExBot.Nav then nExBot.Nav["navigation.domain"] = D end
return D
