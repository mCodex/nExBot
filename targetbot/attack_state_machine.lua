--[[
  Attack State Machine v2.0 — Clean rewrite

  Deterministic state machine for monster target management.
  SOLE authority for issuing attack commands when TargetBot is active.

  Design principles:
  - 3 states (IDLE → ENGAGING → LOCKED) — down from 5
  - Single rate-limited sendAttack() — never spams the server
  - Grace-based confirmation in LOCKED — tolerates OpenTibiaBR transient nils
  - No RECOVERING state — grace expiry simply re-enters ENGAGING
  - 100ms tick rate (down from 50ms — 10 FPS is sufficient for combat)
  - SRP: Only manages attack state. Target selection is external (target.lua).
  - Path-blocked detection exposed as external filter, not in state handlers.

  States:
    IDLE     — No target. Passive game-sync only. Awaits requestAttack().
    ENGAGING — Attack command sent, awaiting server confirmation. Auto-retries.
    LOCKED   — Server confirmed. Monitors target until death or explicit switch.
]]

-- ============================================================================
-- MODULE
-- ============================================================================

AttackStateMachine = AttackStateMachine or {}
AttackStateMachine.VERSION = "2.0"
AttackStateMachine.DEBUG = false

-- ============================================================================
-- STATES
-- ============================================================================

local STATE = {
  IDLE     = "IDLE",
  ENGAGING = "ENGAGING",
  LOCKED   = "LOCKED",
}

AttackStateMachine.STATE = STATE

-- ============================================================================
-- CLIENT HELPERS (reuse global ClientHelper — DRY)
-- ============================================================================

local function getClient()
  return ClientHelper and ClientHelper.getClient() or ClientService
end

local nowMs = (ClientHelper and ClientHelper.nowMs) or function()
  return now or (os.time() * 1000)
end

-- ============================================================================
-- CONFIGURATION (minimal surface, client-tuned)
-- ============================================================================

local CONFIG = {
  -- Timing
  TICK_INTERVAL      = 100,   -- State machine tick rate (ms)
  COMMAND_COOLDOWN   = 400,   -- Hard minimum between attack commands (ms)
  CONFIRM_TIMEOUT    = 1200,  -- Max wait in ENGAGING for confirmation (ms)
  GRACE_PERIOD       = 600,   -- Stay LOCKED despite transient nil reports (ms)
  KEEPALIVE_INTERVAL = 2000,  -- Re-issue attack while LOCKED to keep server alive (ms)
  STOP_DEBOUNCE      = 800,   -- After stop/IDLE, block requestAttack for this long (ms)
  ENGAGE_RETRIES     = 3,     -- Max retries in ENGAGING before forfeit

  -- Target switching
  SWITCH_COOLDOWN        = 3000,  -- Min time between target switches (ms)
  CONFIG_SWITCH_COOLDOWN = 500,   -- Reduced cooldown for user-configured priority switch
  CRITICAL_HP            = 30,    -- Below this HP%, never switch away

  -- Path-blocked skip list (external filter, not used in state handlers)
  PATH_SKIP_DURATION = 10000,

  -- Debug
  LOG_STATE_CHANGES = false,
}

--- Apply client-specific timing overrides via ACL.
local function applyClientTuning()
  local isOTBR = ClientService and ClientService.isOpenTibiaBR and ClientService.isOpenTibiaBR()
  if isOTBR then
    -- OpenTibiaBR reports getAttackingCreature()=nil transiently for 200-500ms
    -- during normal attacks. Use generous values to avoid false re-engage cycles.
    CONFIG.COMMAND_COOLDOWN   = 500
    CONFIG.CONFIRM_TIMEOUT    = 1500
    CONFIG.GRACE_PERIOD       = 1000
    CONFIG.KEEPALIVE_INTERVAL = 2500
    CONFIG.STOP_DEBOUNCE      = 1000
  end
end

applyClientTuning()
AttackStateMachine.CONFIG = CONFIG

-- ============================================================================
-- CREATURE HELPERS (delegate to SafeCreature when loaded)
-- ============================================================================

local SC = SafeCreature or {}

local function cId(c)
  if not c then return nil end
  if SC.getId then return SC.getId(c) end
  local ok, v = pcall(function() return c:getId() end)
  return ok and v or nil
end

local function cHp(c)
  if not c then return 0 end
  if SC.getHealthPercent then return SC.getHealthPercent(c) end
  local ok, v = pcall(function() return c:getHealthPercent() end)
  return ok and v or 0
end

local function cDead(c)
  if not c then return true end
  if SC.isDead then return SC.isDead(c) end
  local ok, v = pcall(function() return c:isDead() end)
  return (ok and v == true) or cHp(c) <= 0
end

local function cName(c)
  if not c then return "?" end
  if SC.getName then return SC.getName(c) end
  local ok, v = pcall(function() return c:getName() end)
  return ok and v or "?"
end

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

local state = {
  current         = STATE.IDLE,
  previous        = nil,
  enteredAt       = 0,

  -- Target
  targetId        = nil,
  creature        = nil,
  hp              = 100,
  priority        = 0,

  -- Attack tracking
  lastCommandAt   = 0,
  lastConfirmedAt = 0,
  retries         = 0,

  -- Debounce / switch
  lastStopAt      = 0,
  lastSwitchAt    = 0,
  pendingSwitch   = nil,  -- { creature, priority } or nil

  -- Path-blocked skip list (populated by external code)
  skipList        = {},   -- creatureId → expireTimestamp

  -- Statistics
  stats = {
    commands  = 0,
    confirms  = 0,
    kills     = 0,
    switches  = 0,
    skips     = 0,
  },
}

local player = nil
local lastTick = 0

-- ============================================================================
-- LOGGING
-- ============================================================================

local function log(msg)
  if AttackStateMachine.DEBUG then
    print("[ASM] " .. msg)
  end
end

local function logTransition(to, reason)
  if CONFIG.LOG_STATE_CHANGES or AttackStateMachine.DEBUG then
    print(string.format("[ASM] %s -> %s (%s)", state.current, to, reason or ""))
  end
end

-- ============================================================================
-- STATE TRANSITION (single point of change)
-- ============================================================================

local function transition(to, reason)
  if state.current == to then return end
  logTransition(to, reason)

  state.previous = state.current
  state.current = to
  state.enteredAt = nowMs()

  if to == STATE.IDLE then
    state.lastStopAt = nowMs()
    state.retries = 0
  end

  if EventBus and EventBus.emit then
    pcall(EventBus.emit, "attacksm:state_changed", to, state.previous, reason)
  end
end

-- ============================================================================
-- GAME INTERACTION
-- ============================================================================

local function updatePlayer()
  if not player or not pcall(function() return player:getPosition() end) then
    local C = getClient()
    player = (C and C.getLocalPlayer and C.getLocalPlayer())
          or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
          or nil
  end
  return player
end

--- Get the creature the game client currently targets.
local function gameTarget()
  local C = getClient()
  if C and C.getAttackingCreature then
    local ok, c = pcall(C.getAttackingCreature)
    return ok and c or nil
  end
  if g_game and g_game.getAttackingCreature then
    local ok, c = pcall(g_game.getAttackingCreature)
    return ok and c or nil
  end
  return nil
end

--- Is the game client currently attacking our tracked target?
local function isConfirmed()
  local gt = gameTarget()
  return gt ~= nil and cId(gt) == state.targetId
end

--- Issue a single attack command. Rate-limited by COMMAND_COOLDOWN.
--- Returns true if the command was actually sent.
local function sendAttack(creature, reason)
  if not creature or cDead(creature) then return false end

  local t = nowMs()
  if (t - state.lastCommandAt) < CONFIG.COMMAND_COOLDOWN then return false end
  if (t - state.lastStopAt) < CONFIG.STOP_DEBOUNCE then
    log("Suppressed: stop debounce")
    return false
  end

  local ok = false
  local C = getClient()
  if C and C.attack then
    ok = pcall(C.attack, creature)
  elseif g_game and g_game.attack then
    ok = pcall(g_game.attack, creature)
  end

  if ok then
    state.lastCommandAt = t
    state.stats.commands = state.stats.commands + 1
    log("Attack -> " .. cName(creature) .. " (" .. (reason or "") .. ")")

    -- MonsterAI engagement lock (anti-zigzag)
    if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.startEngagement then
      pcall(MonsterAI.Scenario.startEngagement, cId(creature), cHp(creature))
    end
  end

  return ok
end

--- Cancel game attack via ACL-safe path.
local function cancelAttack()
  local C = getClient()
  if C and C.cancelAttackAndFollow then
    pcall(C.cancelAttackAndFollow)
  elseif g_game and g_game.cancelAttackAndFollow then
    pcall(g_game.cancelAttackAndFollow)
  end
end

-- ============================================================================
-- TARGET MANAGEMENT (internal)
-- ============================================================================

local function clearTarget()
  state.creature = nil
  state.targetId = nil
  state.hp = 100
  state.priority = 0
  state.pendingSwitch = nil
end

local function setTarget(creature, priority, reason)
  state.creature = creature
  state.targetId = cId(creature)
  state.hp = cHp(creature)
  state.priority = priority or 0
  state.retries = 0
  state.pendingSwitch = nil
  state.lastSwitchAt = nowMs()
  state.stats.switches = state.stats.switches + 1
  transition(STATE.ENGAGING, reason or "new_target")
  -- Fire attack immediately instead of waiting for next tick (saves 100-250ms)
  sendAttack(creature, "engage_immediate")
end

-- ============================================================================
-- SWITCH EVALUATION
-- ============================================================================

local function getConfigPriority(creature)
  if not (TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs) then return 0 end
  local configs = TargetBot.Creature.getConfigs(creature)
  if not configs then return 0 end
  local best = 0
  for i = 1, #configs do
    local p = configs[i].priority or 0
    if p > best then best = p end
  end
  return best
end

local function shouldSwitch(newCreature, newPriority)
  -- Always allow if current target is dead/gone
  if not state.creature or cDead(state.creature) then
    return true, "target_dead"
  end

  local t = nowMs()

  -- Fast path: user-configured priority override
  local newCfg = getConfigPriority(newCreature)
  local curCfg = getConfigPriority(state.creature)
  if newCfg > curCfg and (t - state.lastSwitchAt) >= CONFIG.CONFIG_SWITCH_COOLDOWN then
    return true, "config_priority"
  end

  -- MonsterAI engagement lock
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.shouldAllowTargetSwitch then
    local allowed, reason = MonsterAI.Scenario.shouldAllowTargetSwitch(
      cId(newCreature), newPriority or 0, cHp(newCreature))
    if not allowed then return false, "monsterai_" .. (reason or "locked") end
  end

  -- Standard switch cooldown
  if (t - state.lastSwitchAt) < CONFIG.SWITCH_COOLDOWN then
    return false, "cooldown"
  end

  -- Never switch from critical HP target
  if cHp(state.creature) < CONFIG.CRITICAL_HP then
    return false, "critical_hp"
  end

  -- Require significant calculated-priority advantage
  if (newPriority or 0) - state.priority >= 500 then
    return true, "priority"
  end

  return false, "insufficient"
end

-- ============================================================================
-- PATH-BLOCKED SKIP LIST
-- External filter for target selection (NOT used in state handlers — SRP).
-- Populated by creature_attack.lua or target.lua, queried by findBestTarget.
-- ============================================================================

function AttackStateMachine.isSkipped(creatureId)
  if not creatureId then return false end
  local exp = state.skipList[creatureId]
  if not exp then return false end
  if nowMs() >= exp then
    state.skipList[creatureId] = nil
    return false
  end
  return true
end

function AttackStateMachine.skipCreature(cid, duration)
  if not cid then return end
  state.skipList[cid] = nowMs() + (duration or CONFIG.PATH_SKIP_DURATION)
  state.stats.skips = state.stats.skips + 1
  log("Skip creature " .. tostring(cid))
end

function AttackStateMachine.clearSkipList()
  state.skipList = {}
end

function AttackStateMachine.getSkippedCount()
  local t, n = nowMs(), 0
  for _, exp in pairs(state.skipList) do
    if t < exp then n = n + 1 end
  end
  return n
end

-- ============================================================================
-- STATE HANDLERS
-- ============================================================================

--- IDLE: No target. Respect debounce, then passively sync with game target.
local function handleIdle()
  if (nowMs() - state.lastStopAt) < CONFIG.STOP_DEBOUNCE then return end

  -- Passive sync: if game is already attacking something, adopt it
  local gt = gameTarget()
  if gt and not cDead(gt) then
    state.creature = gt
    state.targetId = cId(gt)
    state.hp = cHp(gt)
    state.priority = 0  -- External caller will update via requestAttack
    state.lastConfirmedAt = nowMs()
    transition(STATE.LOCKED, "game_sync")
  end
end

--- ENGAGING: Attack sent, waiting for server confirmation.
--- Sends one command per COMMAND_COOLDOWN. Retries up to ENGAGE_RETRIES.
local function handleEngaging()
  -- Target died?
  if not state.creature or cDead(state.creature) then
    state.stats.kills = state.stats.kills + 1
    clearTarget()
    transition(STATE.IDLE, "target_died")
    return
  end

  -- Already confirmed? Promote to LOCKED immediately.
  if isConfirmed() then
    state.lastConfirmedAt = nowMs()
    state.stats.confirms = state.stats.confirms + 1
    transition(STATE.LOCKED, "confirmed")
    return
  end

  -- Timeout → retry or forfeit
  if (nowMs() - state.enteredAt) > CONFIG.CONFIRM_TIMEOUT then
    state.retries = state.retries + 1
    if state.retries >= CONFIG.ENGAGE_RETRIES then
      log("Engage failed after " .. state.retries .. " retries")
      clearTarget()
      transition(STATE.IDLE, "timeout")
      return
    end
    state.enteredAt = nowMs()  -- Reset for next attempt
  end

  -- Send attack command (will no-op if still within COMMAND_COOLDOWN)
  sendAttack(state.creature, "engage")
end

--- LOCKED: Attack confirmed. Monitor target, handle grace, keepalive.
local function handleLocked()
  -- Target died?
  if not state.creature or cDead(state.creature) then
    state.stats.kills = state.stats.kills + 1
    log("Kill: " .. cName(state.creature))
    clearTarget()
    transition(STATE.IDLE, "target_killed")
    return
  end

  -- Update health cache
  state.hp = cHp(state.creature)

  -- Confirmation check with grace window
  if isConfirmed() then
    state.lastConfirmedAt = nowMs()
  elseif (nowMs() - state.lastConfirmedAt) > CONFIG.GRACE_PERIOD then
    -- Attack genuinely lost → re-engage (single retry path, no separate state)
    log("Attack lost after " .. CONFIG.GRACE_PERIOD .. "ms grace")
    state.retries = 0
    transition(STATE.ENGAGING, "grace_expired")
    return
  end

  -- Process pending switch request
  if state.pendingSwitch then
    local ps = state.pendingSwitch
    state.pendingSwitch = nil
    local allowed, reason = shouldSwitch(ps.creature, ps.priority)
    if allowed then
      setTarget(ps.creature, ps.priority, "switch:" .. reason)
    else
      log("Switch denied: " .. reason)
    end
    return
  end

  -- Periodic keepalive (re-issue to keep server connection)
  if (nowMs() - state.lastCommandAt) > CONFIG.KEEPALIVE_INTERVAL then
    sendAttack(state.creature, "keepalive")
  end
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================

local function update()
  -- TargetBot must be enabled
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    if state.current ~= STATE.IDLE then
      clearTarget()
      transition(STATE.IDLE, "targetbot_off")
    end
    return
  end

  if TargetBot and TargetBot.explicitlyDisabled then
    if state.current ~= STATE.IDLE then
      clearTarget()
      transition(STATE.IDLE, "disabled")
    end
    return
  end

  -- Tick rate limiting
  local t = nowMs()
  if (t - lastTick) < CONFIG.TICK_INTERVAL then return end
  lastTick = t

  updatePlayer()
  if not player then return end

  -- Dispatch to current state handler
  if state.current == STATE.IDLE then
    handleIdle()
  elseif state.current == STATE.ENGAGING then
    handleEngaging()
  elseif state.current == STATE.LOCKED then
    handleLocked()
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function AttackStateMachine.getState()
  return state.current
end

function AttackStateMachine.getTarget()
  return state.creature
end

function AttackStateMachine.getTargetId()
  return state.targetId
end

--- Returns true if ASM is actively managing a target (ENGAGING or LOCKED).
function AttackStateMachine.isActive()
  return state.current ~= STATE.IDLE
end

--- Backward-compatible alias for isActive().
AttackStateMachine.isAttacking = AttackStateMachine.isActive

--- Returns true only when attack is server-confirmed (LOCKED + game agrees).
function AttackStateMachine.isLocked()
  return state.current == STATE.LOCKED
end

function AttackStateMachine.isConfirmed()
  return state.current == STATE.LOCKED and isConfirmed()
end

function AttackStateMachine.wasRecentlyStopped()
  return (nowMs() - state.lastStopAt) < CONFIG.STOP_DEBOUNCE
end

--- Request to attack a creature. Respects debounce and switch priority.
--- If IDLE, starts immediately. If LOCKED, queues for priority evaluation.
function AttackStateMachine.requestAttack(creature, priority)
  if not creature or cDead(creature) then return false end
  if (nowMs() - state.lastStopAt) < CONFIG.STOP_DEBOUNCE then return false end

  local id = cId(creature)
  if id == state.targetId then return false end  -- Already targeting

  if state.current == STATE.IDLE then
    setTarget(creature, priority, "request")
    return true
  end

  -- Queue for evaluation in handleLocked
  state.pendingSwitch = { creature = creature, priority = priority or 0 }
  return true
end

--- Force-attack a creature. Bypasses priority checks and stop debounce.
--- Used by hold_target and other explicit user-initiated overrides.
function AttackStateMachine.forceAttack(creature)
  if not creature or cDead(creature) then return false end

  local id = cId(creature)
  if id == state.targetId and state.current ~= STATE.IDLE then return false end

  state.lastStopAt = 0  -- Clear debounce for force attacks
  setTarget(creature, getConfigPriority(creature) * 100, "force")
  return true
end

--- Stop attacking. Cancels game attack and enters IDLE with debounce.
function AttackStateMachine.stop()
  clearTarget()
  transition(STATE.IDLE, "stop")
  cancelAttack()

  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.endEngagement then
    pcall(MonsterAI.Scenario.endEngagement, "manual_stop")
  end
end

--- Reset all internal state (used when TargetBot is disabled/toggled).
function AttackStateMachine.reset()
  state.current         = STATE.IDLE
  state.previous        = nil
  state.enteredAt       = 0
  state.targetId        = nil
  state.creature        = nil
  state.hp              = 100
  state.priority        = 0
  state.lastCommandAt   = 0
  state.lastConfirmedAt = 0
  state.retries         = 0
  state.lastStopAt      = 0
  state.lastSwitchAt    = 0
  state.pendingSwitch   = nil
  state.skipList         = {}
  state.stats = { commands = 0, confirms = 0, kills = 0, switches = 0, skips = 0 }
  log("Reset")
end

function AttackStateMachine.getStats()
  return {
    state        = state.current,
    targetId     = state.targetId,
    targetHealth = state.hp,
    stats        = state.stats,
  }
end

-- Backward-compatible aliases (consumers use requestSwitch/forceSwitch)
AttackStateMachine.requestSwitch = AttackStateMachine.requestAttack
AttackStateMachine.forceSwitch   = AttackStateMachine.forceAttack

-- Backward-compatible stubs (path-blocked moved to external filter)
function AttackStateMachine.isPathBlocked() return false end
function AttackStateMachine.findBestTarget() return nil, 0 end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- Only bookkeeping updates — minimal state transitions (death/disappear only)
-- ============================================================================

if EventBus then
  -- Game combat target changed
  -- NOTE: On OpenTibiaBR, combat:target(nil) fires transiently during normal
  -- attacks. We NEVER transition on nil — the grace window in handleLocked
  -- handles confirmation loss cleanly.
  EventBus.on("combat:target", function(creature, oldCreature)
    if not creature then return end  -- Nil → grace window handles it

    local id = cId(creature)
    if id == state.targetId then
      -- Same target confirmed — update bookkeeping
      state.lastConfirmedAt = nowMs()
    elseif state.current ~= STATE.IDLE then
      -- Different target → external override (player click, party sync, etc.)
      state.creature = creature
      state.targetId = id
      state.hp = cHp(creature)
      state.lastConfirmedAt = nowMs()
      if state.current ~= STATE.LOCKED then
        transition(STATE.LOCKED, "external_sync")
      end
    end
  end, 40)

  -- Monster health changed
  EventBus.on("monster:health", function(creature, percent)
    if not creature then return end
    if cId(creature) == state.targetId then
      state.hp = percent or 0
      if percent and percent <= 0 then
        state.stats.kills = state.stats.kills + 1
        clearTarget()
        transition(STATE.IDLE, "health_zero")
      end
    end
  end, 50)

  -- Monster disappeared
  EventBus.on("monster:disappear", function(creature)
    if not creature then return end
    if cId(creature) == state.targetId then
      state.stats.kills = state.stats.kills + 1
      clearTarget()
      transition(STATE.IDLE, "disappeared")
    end
  end, 50)

  -- TargetBot disabled
  EventBus.on("targetbot/disabled", function()
    AttackStateMachine.reset()
  end, 100)
end

-- ============================================================================
-- TICK & INIT
-- ============================================================================

AttackStateMachine.update = update

updatePlayer()
log("Attack State Machine v" .. AttackStateMachine.VERSION .. " loaded")

return AttackStateMachine
