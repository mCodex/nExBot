--[[
  Combat Constants v1.0 — Single source of truth

  All timing constants used by the attack pipeline are defined here.
  ASM, ChaseController, MonsterAI.Scenario, PriorityEngine, and target.lua
  all read from this module instead of defining their own.

  Principles:
  - KISS: One table, flat keys, no logic
  - DRY:  Every subsystem imports instead of hardcoding
  - SRP:  Constants only — no functions, no state
]]

local CC = {}

CC.VERSION = "1.0"

-- ==========================================================================
-- CLIENT-AGNOSTIC DEFAULTS
-- ==========================================================================

-- ASM: Attack State Machine timing
CC.TICK_INTERVAL          = 100    -- ASM tick rate (ms)
CC.COMMAND_COOLDOWN       = 350    -- Min between g_game.attack() calls (ms)
CC.CONFIRM_TIMEOUT        = 1200   -- Max wait for server confirmation (ms)
CC.GRACE_PERIOD           = 1500   -- Stay LOCKED despite transient nil (ms)
CC.KEEPALIVE_INTERVAL     = 2000   -- Re-send attack while LOCKED (ms)
CC.STOP_DEBOUNCE          = 150    -- After stop, block requestAttack (ms) — was 800
CC.REAFFIRM_RETRY_MAX     = 5     -- Max retries before forfeit — was 3
CC.ENGAGE_BACKOFF_BASE    = 1500   -- First retry timeout (ms)
CC.ENGAGE_BACKOFF_GROWTH  = 1.5   -- Exponential backoff multiplier

-- Target switching
CC.SWITCH_COOLDOWN         = 2500  -- Min between target switches (ms)
CC.CONFIG_SWITCH_COOLDOWN  = 400   -- Reduced cooldown for config priority switch (ms)
CC.CRITICAL_HP             = 25    -- Below this HP%, never switch away
CC.FINISH_KILL_HP          = 25    -- PriorityEngine finish-kill threshold

-- Path-blocked
CC.PATH_SKIP_DURATION      = 10000 -- Skip unreachable creature for this long (ms)

-- Chase & Movement
CC.CHASE_NIL_GRACE         = 1500  -- Grace before cancelling chase on nil target (ms)
CC.MOVEMENT_RATE_LIMIT     = 100   -- Min between chase mode changes (ms)
CC.OSCILLATION_WINDOW      = 2000  -- Anti-oscillation detection window (ms)
CC.OSCILLATION_MAX         = 4     -- Max direction reversals before pause

-- MonsterAI: Scenario & engagement
CC.ENGAGEMENT_GRACE        = 1500  -- Scenario engagement validation grace (ms) — was 350
CC.SCENARIO_DETECT_INTERVAL = 200  -- Scenario re-detect throttle (ms)

-- PriorityEngine
CC.PRIORITY_SCALE          = 1000  -- config.priority * this = base score
CC.STICKINESS_BASE         = 100   -- Base bonus for current target
CC.STICKINESS_FINISH_KILL  = 300   -- Bonus when current target < FINISH_KILL_HP
CC.SWITCH_GATE_PENALTY     = 0     -- Hard-blocked targets get score = 0 (absolute gate)
CC.RECALC_IDLE_INTERVAL    = 2000  -- Full recalc when stable + no new creatures (ms)
CC.RECALC_ACTIVE_INTERVAL  = 150   -- Full recalc during active combat (ms)
CC.PRIORITY_CACHE_TTL      = 400   -- Cached priority valid for this long (ms)

-- Anti-zigzag
CC.ZIGZAG_RATE_LIMIT       = 5000  -- Seconds between allowed switches (ms)
CC.ZIGZAG_MAX_SWITCHES     = 3     -- Max switches before hard block
CC.ZIGZAG_DECAY_TIME       = 10000 -- Time before switch counter decays (ms)

-- ==========================================================================
-- CLIENT-SPECIFIC OVERRIDES
-- Called once at boot by ASM after ACL detection completes.
-- ==========================================================================

function CC.applyClientTuning(isOTBR)
  if isOTBR then
    CC.COMMAND_COOLDOWN     = 450
    CC.CONFIRM_TIMEOUT      = 1500
    CC.KEEPALIVE_INTERVAL   = 2500
    CC.ENGAGE_BACKOFF_BASE  = 1800
  end
  -- OTCv8 uses the defaults above (faster client, less latency)
end

-- ==========================================================================
-- FREEZE (prevent accidental mutation after init)
-- ==========================================================================

local _frozen = false

function CC.freeze()
  _frozen = true
end

-- Make the table read-only after freeze (debug aid, not enforced in prod)
-- OTClient sandbox doesn't support __newindex on plain tables reliably,
-- so this is opt-in.

return CC
