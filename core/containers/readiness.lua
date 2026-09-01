-- readiness.lua
-- Derives the current readiness level from registry state and role assignments.
-- Consumers declare the minimum readiness they require; this module computes it.
-- Does NOT emit events directly — that is Discovery's responsibility.

local Readiness = {}

-- Ordered readiness levels (weakest to strongest).
Readiness.LEVELS = {
  "FAILED",
  "DEGRADED",
  "SESSION_READY",
  "ROOTS_READY",
  "SURVIVAL_READY",
  "QUIVER_READY",
  "AMMO_READY",
  "COMBAT_READY",
  "LOOT_READY",
  "FULLY_DISCOVERED",
}

local LEVEL_ORDER = {}
for i, v in ipairs(Readiness.LEVELS) do
  LEVEL_ORDER[v] = i
end

-- Legacy status → equivalent modern level for meetsLevel comparisons.
local LEGACY_LEVEL = {
  ready       = "FULLY_DISCOVERED",
  degraded    = "DEGRADED",
  discovering = "SESSION_READY",
  notStarted  = "SESSION_READY",
}

-- Returns true when status meets or exceeds the required level.
function Readiness.meetsLevel(status, required)
  -- Resolve legacy aliases.
  local resolvedStatus = LEGACY_LEVEL[status] or status
  local s = LEVEL_ORDER[resolvedStatus] or 0
  local r = LEVEL_ORDER[required] or 0
  return s >= r
end

-- Compute a readiness snapshot from registry state plus role and vocation context.
-- registry      : Registry instance
-- generation    : current session generation
-- context       : {
--     isPaladin        : bool
--     roleAssignments  : map of role → identity (may be nil)
--     configuredRoles  : set of required role strings
-- }
function Readiness.compute(registry, generation, context)
  -- Backward compat: old callers pass a boolean as 3rd arg.
  if type(context) == "boolean" then
    context = { isPaladin = context }
  end
  context = context or {}
  local isPaladin = context.isPaladin or false
  local roles = context.roleAssignments or {}

  local queued    = registry:countByState("queued")
  local opening   = registry:countByState("opening")
  local opened    = registry:countByState("opened")
  local inspected = registry:countByState("inspected")
  local failed    = registry:countByState("failed")
  local total     = queued + opening + opened + inspected + failed

  -- Determine which roles are resolved.
  local mainReady     = Readiness._roleReady(registry, roles, "MAIN")
  local survivalReady = Readiness._roleReady(registry, roles, "HEALING_SUPPLIES")
  local lootReady     = Readiness._roleReady(registry, roles, "LOOT")
  local ammoReady     = Readiness._roleReady(registry, roles, "AMMO_RESERVE")
  local quiverReady   = false

  if isPaladin then
    quiverReady = Readiness._roleReady(registry, roles, "QUIVER")
  else
    -- Non-paladins: quiver is not required; treat as satisfied.
    quiverReady = true
  end

  local discovering = queued > 0 or opening > 0

  -- Backward compat: when no role assignments are configured, fall back to
  -- the old three-value vocabulary so legacy consumers still work.
  local hasRoles = next(roles) ~= nil
  if not hasRoles then
    local legacyStatus
    if failed > 0 and not discovering then
      legacyStatus = "degraded"
    elseif discovering then
      legacyStatus = "discovering"
    else
      legacyStatus = "ready"
    end
    return {
      generation         = generation,
      status             = legacyStatus,
      mainBackpackReady  = legacyStatus == "ready" or legacyStatus == "degraded",
      survivalReady      = legacyStatus == "ready",
      quiverRequired     = isPaladin,
      quiverReady        = false,
      ammoReady          = false,
      lootReady          = false,
      queuedCount        = queued,
      openingCount       = opening,
      openedCount        = opened,
      inspectedCount     = inspected,
      failedCount        = failed,
      totalCount         = total,
      discovering        = discovering,
      completedAt        = (not discovering) and os.time() or nil,
      reasons            = {},
    }
  end
  local status

  if total == 0 and not discovering then
    -- No nodes at all — session just started.
    status = "SESSION_READY"
  elseif not mainReady then
    if failed > 0 and not discovering then
      status = "FAILED"
    else
      status = "SESSION_READY"
    end
  elseif mainReady and not survivalReady and not discovering then
    status = failed > 0 and "DEGRADED" or "ROOTS_READY"
  elseif survivalReady and not (isPaladin and not quiverReady) then
    -- Survival is ready.  Check higher levels.
    if isPaladin and not quiverReady then
      status = "SURVIVAL_READY"
    elseif isPaladin and quiverReady and not ammoReady then
      status = "QUIVER_READY"
    elseif (not isPaladin or ammoReady) then
      -- All required supplies ready.
      if lootReady and not discovering then
        if failed > 0 then
          status = "DEGRADED"
        else
          status = "FULLY_DISCOVERED"
        end
      elseif lootReady then
        status = "LOOT_READY"
      else
        status = "COMBAT_READY"
      end
    else
      status = "QUIVER_READY"
    end
  elseif survivalReady then
    status = "SURVIVAL_READY"
  else
    status = "ROOTS_READY"
  end

  -- Final override: if critical failure is unrecoverable.
  if status ~= "FAILED" and failed > 0 and not mainReady and not discovering then
    status = "FAILED"
  end

  return {
    generation         = generation,
    status             = status,
    -- Individual flags for consumers.
    mainBackpackReady  = mainReady,
    survivalReady      = survivalReady,
    quiverRequired     = isPaladin,
    quiverReady        = isPaladin and quiverReady or false,
    ammoReady          = isPaladin and ammoReady or false,
    lootReady          = lootReady,
    -- Progress counters.
    queuedCount        = queued,
    openingCount       = opening,
    openedCount        = opened,
    inspectedCount     = inspected,
    failedCount        = failed,
    totalCount         = total,
    discovering        = discovering,
    completedAt        = (not discovering) and os.time() or nil,
    reasons            = {},
  }
end

-- Returns true when the given role is satisfied:
--   - role is not configured (not a blocking requirement), OR
--   - role IS configured and the assigned container is opened/inspected.
function Readiness._roleReady(registry, roles, role)
  local identity = roles[role]
  -- Not configured → not blocking.
  if not identity then return true end
  local node = registry:get(identity)
  if not node then return false end
  return node.state == "opened" or node.state == "inspected"
end

return Readiness

