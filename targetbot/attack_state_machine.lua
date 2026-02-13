--[[
  Attack State Machine v3.0 — Persistent Attack Rewrite

  Deterministic FSM for monster target management.
  SOLE authority for issuing g_game.attack() when TargetBot is active.

  v3.0 CRITICAL FIXES vs v2.0:
  -----------------------------------------------------------------------
  1. REAFFIRM path — requestAttack(sameTarget) in ENGAGING resets retries
     instead of returning false.  This is the #1 fix for "attack once then
     stop" — target.lua now keeps pumping the same target until it sticks.

  2. STOP_DEBOUNCE reduced 800ms → 150ms (from CombatConstants).  The old
     800ms window after any IDLE transition silently blocked re-engagement.

  3. GRACE_PERIOD increased to 1500ms (from CombatConstants).  OTBR's
     getAttackingCreature() returns nil transiently for 200-500ms; the old
     600-1000ms barely covered two consecutive nil reads.

  4. Exponential backoff on confirmation failure.  Instead of linear
     ENGAGING → 3 retries → IDLE, we do grace → reaffirm → extended grace
     → force send → extended grace → only then IDLE.  5 retries with
     growing timeouts.

  5. pendingSwitch processed in ENGAGING too (not just LOCKED).  Higher-
     priority targets found during confirmation are no longer silently
     dropped.

  6. shouldSwitch() no longer embeds MonsterAI knowledge — delegates to
     PriorityEngine's SwitchGate (when available) or uses simple config
     priority comparison.

  7. hold_target integration — creature-ID memory + spectator re-scan
     built into IDLE handler.  core/hold_target.lua can be retired.

  States:
    IDLE      — No target.  Passive game-sync + hold-target re-scan.
    ENGAGING  — Attack sent, awaiting server confirmation.  Auto-retries
                with exponential backoff.
    LOCKED    — Server confirmed.  Keepalive + grace-based nil tolerance.
  
  Principles:
    SRP — Manages attack wire protocol only.  No priority calculation.
    DRY — Uses SafeCreature + CombatConstants.  No local wrappers.
]]

-- ============================================================================
-- MODULE
-- ============================================================================

AttackStateMachine = AttackStateMachine or {}
AttackStateMachine.VERSION = "3.0"
AttackStateMachine.DEBUG   = false

-- ============================================================================
-- STATES
-- ============================================================================

local STATE = {
  IDLE      = "IDLE",
  ENGAGING  = "ENGAGING",
  LOCKED    = "LOCKED",
}
AttackStateMachine.STATE = STATE

-- ============================================================================
-- DEPENDENCIES (resolved lazily — may not exist at load time)
-- ============================================================================

local SC   -- SafeCreature (utils/safe_creature.lua)
local CC   -- CombatConstants (targetbot/combat_constants.lua)

local function ensureDeps()
  if not SC then SC = SafeCreature or {} end
  if not CC then
    -- Try global first (loaded by _Loader via targetbot's init)
    CC = CombatConstants
    if not CC then
      -- Inline minimal defaults so ASM works standalone during boot
      CC = {
        TICK_INTERVAL = 100, COMMAND_COOLDOWN = 350, CONFIRM_TIMEOUT = 1200,
        GRACE_PERIOD = 1500, KEEPALIVE_INTERVAL = 2000, STOP_DEBOUNCE = 150,
        REAFFIRM_RETRY_MAX = 5, ENGAGE_BACKOFF_BASE = 1500,
        ENGAGE_BACKOFF_GROWTH = 1.5, SWITCH_COOLDOWN = 2500,
        CONFIG_SWITCH_COOLDOWN = 400, CRITICAL_HP = 25,
        PATH_SKIP_DURATION = 10000,
      }
    end
  end
end

-- ============================================================================
-- CLIENT + CREATURE HELPERS (single source: SafeCreature / ClientService)
-- ============================================================================

local function nowMs()
  if ClientHelper and ClientHelper.nowMs then return ClientHelper.nowMs() end
  return now or (os.time() * 1000)
end

local function getClient()
  return ClientHelper and ClientHelper.getClient() or ClientService
end

local function cId(c)
  if not c then return nil end
  ensureDeps()
  if SC.getId then return SC.getId(c) end
  local ok, v = pcall(function() return c:getId() end)
  return ok and v or nil
end

local function cHp(c)
  if not c then return 0 end
  ensureDeps()
  if SC.getHealthPercent then return SC.getHealthPercent(c) end
  local ok, v = pcall(function() return c:getHealthPercent() end)
  return ok and v or 0
end

local function cDead(c)
  if not c then return true end
  ensureDeps()
  if SC.isDead then return SC.isDead(c) end
  local ok, v = pcall(function() return c:isDead() end)
  return (ok and v == true) or cHp(c) <= 0
end

local function cName(c)
  if not c then return "?" end
  ensureDeps()
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
  currentTimeout  = 0,     -- current confirm timeout (grows with backoff)

  -- Debounce / switch
  lastStopAt      = 0,
  lastSwitchAt    = 0,
  pendingSwitch   = nil,   -- { creature, priority } or nil

  -- Hold-target memory (replaces core/hold_target.lua)
  holdTargetId    = nil,
  holdTargetName  = nil,

  -- Path-blocked skip list
  skipList        = {},

  -- Stats
  stats = {
    commands   = 0,
    confirms   = 0,
    kills      = 0,
    switches   = 0,
    skips      = 0,
    reaffirms  = 0,
  },
}

local player   = nil
local lastTick = 0

-- ============================================================================
-- LOGGING
-- ============================================================================

local function log(msg)
  if AttackStateMachine.DEBUG then print("[ASM] " .. msg) end
end

local function logTransition(to, reason)
  if AttackStateMachine.DEBUG then
    print(string.format("[ASM] %s -> %s (%s)", state.current, to, reason or ""))
  end
end

-- ============================================================================
-- STATE TRANSITION
-- ============================================================================

local function transition(to, reason)
  if state.current == to then return end
  logTransition(to, reason)

  state.previous = state.current
  state.current  = to
  state.enteredAt = nowMs()

  if to == STATE.IDLE then
    state.lastStopAt = nowMs()
    state.retries = 0
    state.currentTimeout = 0
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
    end
  return player
end

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

local function isConfirmed()
  local gt = gameTarget()
  if not gt then return false end
  -- Compare by ID — avoids stale object reference issues on OTBR
  local gtId = cId(gt)
  return gtId ~= nil and gtId == state.targetId
end

--- Issue a single attack command.  Rate-limited by COMMAND_COOLDOWN.
local function sendAttack(creature, reason)
  if not creature or cDead(creature) then return false end
  ensureDeps()

  local t = nowMs()
  if (t - state.lastCommandAt) < CC.COMMAND_COOLDOWN then return false end
  if (t - state.lastStopAt) < CC.STOP_DEBOUNCE then
    log("Suppressed: stop debounce")
    return false
  end

  local ok = false
  -- Route through ClientService (ACL) — single path
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

local function cancelAttack()
  local C = getClient()
  if C and C.cancelAttackAndFollow then
    pcall(C.cancelAttackAndFollow)
  elseif g_game and g_game.cancelAttackAndFollow then
    pcall(g_game.cancelAttackAndFollow)
  end
end

-- ============================================================================
-- TARGET MANAGEMENT
-- ============================================================================

local function clearTarget()
  -- Save hold-target memory before clearing
  if state.targetId and state.creature and not cDead(state.creature) then
    state.holdTargetId   = state.targetId
    state.holdTargetName = cName(state.creature)
  end
  state.creature    = nil
  state.targetId    = nil
  state.hp          = 100
  state.priority    = 0
  state.pendingSwitch = nil
  state.currentTimeout = 0
end

local function setTarget(creature, priority, reason)
  state.creature       = creature
  state.targetId       = cId(creature)
  state.hp             = cHp(creature)
  state.priority       = priority or 0
  state.retries        = 0
  state.pendingSwitch  = nil
  state.lastSwitchAt   = nowMs()
  state.currentTimeout = 0
  state.stats.switches = state.stats.switches + 1

  -- Update hold memory
  state.holdTargetId   = state.targetId
  state.holdTargetName = cName(creature)

  transition(STATE.ENGAGING, reason or "new_target")
  -- Fire attack immediately (saves 100-250ms vs waiting for next tick)
  sendAttack(creature, "engage_immediate")
end

-- ============================================================================
-- SWITCH EVALUATION (simplified — no MonsterAI coupling)
-- ============================================================================

local function getConfigPriority(creature)
  if not (TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs) then return 0 end
  local ok, configs = pcall(TargetBot.Creature.getConfigs, creature)
  if not ok or not configs then return 0 end
  local best = 0
  for i = 1, #configs do
    local p = configs[i].priority or 0
    if p > best then best = p end
  end
  return best
end

local function shouldSwitch(newCreature, newPriority)
  ensureDeps()

  -- Always allow if current target is dead/gone
  if not state.creature or cDead(state.creature) then
    return true, "target_dead"
  end

  local t = nowMs()

  -- Fast path: user-configured priority override
  local newCfg = getConfigPriority(newCreature)
  local curCfg = getConfigPriority(state.creature)
  if newCfg > curCfg and (t - state.lastSwitchAt) >= CC.CONFIG_SWITCH_COOLDOWN then
    return true, "config_priority"
  end

  -- Delegate to PriorityEngine's SwitchGate if available
  if PriorityEngine and PriorityEngine.shouldAllowSwitch then
    local allowed, reason = PriorityEngine.shouldAllowSwitch(
      cId(newCreature), newPriority or 0, cHp(newCreature))
    if not allowed then return false, "engine_" .. (reason or "locked") end
    if allowed then return true, "engine_" .. (reason or "allowed") end
  end

  -- Fallback: MonsterAI engagement lock
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.shouldAllowTargetSwitch then
    local allowed, reason = MonsterAI.Scenario.shouldAllowTargetSwitch(
      cId(newCreature), newPriority or 0, cHp(newCreature))
    if not allowed then return false, "monsterai_" .. (reason or "locked") end
  end

  -- Standard switch cooldown
  if (t - state.lastSwitchAt) < CC.SWITCH_COOLDOWN then
    return false, "cooldown"
  end

  -- Never switch from critical HP target
  if cHp(state.creature) < CC.CRITICAL_HP then
    return false, "critical_hp"
  end

  -- Require significant priority advantage
  if (newPriority or 0) - state.priority >= 500 then
    return true, "priority"
  end

  return false, "insufficient"
end

-- ============================================================================
-- PATH-BLOCKED SKIP LIST (external filter — SRP)
-- ============================================================================

function AttackStateMachine.isSkipped(creatureId)
  if not creatureId then return false end
  local exp = state.skipList[creatureId]
  if not exp then return false end
  if nowMs() >= exp then state.skipList[creatureId] = nil; return false end
  return true
end

function AttackStateMachine.skipCreature(cid, duration)
  if not cid then return end
  ensureDeps()
  state.skipList[cid] = nowMs() + (duration or CC.PATH_SKIP_DURATION)
  state.stats.skips = state.stats.skips + 1
end

function AttackStateMachine.clearSkipList() state.skipList = {} end

function AttackStateMachine.getSkippedCount()
  local t, n = nowMs(), 0
  for _, exp in pairs(state.skipList) do if t < exp then n = n + 1 end end
  return n
end

-- ============================================================================
-- STATE HANDLERS
-- ============================================================================

--- IDLE: No target.  Hold-target re-scan + passive game sync.
local function handleIdle()
  ensureDeps()
  if (nowMs() - state.lastStopAt) < CC.STOP_DEBOUNCE then return end

  -- Hold-target: re-scan for previously attacked creature
  if state.holdTargetId then
    local C = getClient()
    local pPos = player and pcall(function() return player:getPosition() end) and player:getPosition()
    if pPos then
      local specs
      if C and C.getSpectatorsInRange then
        local ok, s = pcall(C.getSpectatorsInRange, pPos, 7, 5, false)
        specs = ok and s or {}
      elseif g_map and g_map.getSpectatorsInRange then
        local ok, s = pcall(g_map.getSpectatorsInRange, pPos, 7, 5, false)
        specs = ok and s or {}
      else
        specs = {}
      end
      for _, spec in ipairs(specs) do
        if cId(spec) == state.holdTargetId and not cDead(spec) then
          log("Hold-target re-acquired: " .. cName(spec))
          setTarget(spec, state.priority, "hold_reacquire")
          return
        end
      end
    end
    -- If hold target not found for 10s, clear memory
    if (nowMs() - state.lastStopAt) > 10000 then
      state.holdTargetId   = nil
      state.holdTargetName = nil
    end
  end

  -- Passive sync: adopt game's current target
  local gt = gameTarget()
  if gt and not cDead(gt) then
    state.creature      = gt
    state.targetId      = cId(gt)
    state.hp            = cHp(gt)
    state.priority      = 0
    state.lastConfirmedAt = nowMs()
    state.holdTargetId  = state.targetId
    state.holdTargetName = cName(gt)
    transition(STATE.LOCKED, "game_sync")
  end
end

--- ENGAGING: Attack sent, awaiting server confirmation.
--- Exponential backoff on timeout.  Processes pendingSwitch.
local function handleEngaging()
  ensureDeps()

  -- Target died?
  if not state.creature or cDead(state.creature) then
    state.stats.kills = state.stats.kills + 1
    clearTarget()
    transition(STATE.IDLE, "target_died")
    return
  end

  -- Process pending switch (v3.0 FIX: also in ENGAGING, not only LOCKED)
  if state.pendingSwitch then
    local ps = state.pendingSwitch
    state.pendingSwitch = nil
    local allowed, reason = shouldSwitch(ps.creature, ps.priority)
    if allowed then
      setTarget(ps.creature, ps.priority, "switch_engaging:" .. reason)
      return
    end
    log("Switch denied in ENGAGING: " .. reason)
  end

  -- Already confirmed?  Promote to LOCKED
  if isConfirmed() then
    state.lastConfirmedAt = nowMs()
    state.stats.confirms  = state.stats.confirms + 1
    transition(STATE.LOCKED, "confirmed")
    return
  end

  -- Compute current timeout with exponential backoff
  if state.currentTimeout == 0 then
    state.currentTimeout = CC.ENGAGE_BACKOFF_BASE
  end

  -- Timeout → retry or forfeit
  if (nowMs() - state.enteredAt) > state.currentTimeout then
    state.retries = state.retries + 1
    if state.retries >= CC.REAFFIRM_RETRY_MAX then
      log("Engage failed after " .. state.retries .. " retries (backoff)")
      clearTarget()
      transition(STATE.IDLE, "timeout")
      return
    end
    -- Grow timeout for next attempt
    state.currentTimeout = math.min(
      state.currentTimeout * CC.ENGAGE_BACKOFF_GROWTH,
      5000  -- hard cap 5s
    )
    state.enteredAt = nowMs()
    log("Retry " .. state.retries .. "/" .. CC.REAFFIRM_RETRY_MAX ..
        " (timeout=" .. math.floor(state.currentTimeout) .. "ms)")
  end

  -- Send attack command (rate-limited by COMMAND_COOLDOWN internally)
  sendAttack(state.creature, "engage")
end

--- LOCKED: Attack confirmed.  Grace-based nil tolerance + keepalive.
local function handleLocked()
  ensureDeps()

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
  elseif (nowMs() - state.lastConfirmedAt) > CC.GRACE_PERIOD then
    -- Attack genuinely lost → re-engage with backoff
    log("Attack lost after " .. CC.GRACE_PERIOD .. "ms grace")
    state.retries = 0
    state.currentTimeout = 0  -- reset backoff for fresh ENGAGING
    transition(STATE.ENGAGING, "grace_expired")
    return
  end

  -- Process pending switch
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

  -- Periodic keepalive
  if (nowMs() - state.lastCommandAt) > CC.KEEPALIVE_INTERVAL then
    sendAttack(state.creature, "keepalive")
  end
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================

local function update()
  ensureDeps()

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
  if (t - lastTick) < CC.TICK_INTERVAL then return end
  lastTick = t

  updatePlayer()
  if not player then return end

  -- Dispatch
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

function AttackStateMachine.getState()    return state.current end
function AttackStateMachine.getTarget()   return state.creature end
function AttackStateMachine.getTargetId() return state.targetId end

function AttackStateMachine.isActive()
  return state.current ~= STATE.IDLE
end
AttackStateMachine.isAttacking = AttackStateMachine.isActive

function AttackStateMachine.isLocked()
  return state.current == STATE.LOCKED
end

function AttackStateMachine.isConfirmed()
  return state.current == STATE.LOCKED and isConfirmed()
end

function AttackStateMachine.wasRecentlyStopped()
  ensureDeps()
  return (nowMs() - state.lastStopAt) < CC.STOP_DEBOUNCE
end

--- Request attack.  v3.0 CHANGE: same-target REAFFIRM instead of reject.
function AttackStateMachine.requestAttack(creature, priority)
  if not creature or cDead(creature) then return false end
  ensureDeps()
  if (nowMs() - state.lastStopAt) < CC.STOP_DEBOUNCE then return false end

  local id = cId(creature)

  -- REAFFIRM path: same target in ENGAGING → reset retries, keep going
  if id == state.targetId then
    if state.current == STATE.ENGAGING then
      -- Refresh creature ref (may be newer object), reset retries
      state.creature = creature
      state.retries  = 0
      state.currentTimeout = 0
      state.enteredAt = nowMs()
      state.stats.reaffirms = state.stats.reaffirms + 1
      log("Reaffirm in ENGAGING: " .. cName(creature))
      sendAttack(creature, "reaffirm")
      return true
    end
    -- LOCKED or same target → update priority, no-op otherwise
    if priority and priority > state.priority then
      state.priority = priority
    end
    return true  -- "accepted" — we're already on it
  end

  -- New target
  if state.current == STATE.IDLE then
    setTarget(creature, priority, "request")
    return true
  end

  -- ENGAGING or LOCKED with different target → queue for switch eval
  state.pendingSwitch = { creature = creature, priority = priority or 0 }
  return true
end

--- Force-attack.  Bypasses priority checks and stop debounce.
function AttackStateMachine.forceAttack(creature)
  if not creature or cDead(creature) then return false end

  local id = cId(creature)
  if id == state.targetId and state.current ~= STATE.IDLE then
    -- Already targeting — just refresh
    state.creature = creature
    state.retries  = 0
    state.currentTimeout = 0
    sendAttack(creature, "force_refresh")
    return true
  end

  state.lastStopAt = 0
  setTarget(creature, getConfigPriority(creature) * 100, "force")
  return true
end

--- Stop attacking.
function AttackStateMachine.stop()
  clearTarget()
  transition(STATE.IDLE, "stop")
  cancelAttack()

  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.endEngagement then
    pcall(MonsterAI.Scenario.endEngagement, "manual_stop")
  end
end

--- Reset all internal state.
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
  state.currentTimeout  = 0
  state.lastStopAt      = 0
  state.lastSwitchAt    = 0
  state.pendingSwitch   = nil
  state.holdTargetId    = nil
  state.holdTargetName  = nil
  state.skipList        = {}
  state.stats = { commands = 0, confirms = 0, kills = 0, switches = 0, skips = 0, reaffirms = 0 }
  log("Reset")
end

--- Hold-target: manually set the ID to remember.
function AttackStateMachine.setHoldTarget(creatureId, name)
  state.holdTargetId   = creatureId
  state.holdTargetName = name or "?"
end

function AttackStateMachine.getHoldTargetId()
  return state.holdTargetId
end

function AttackStateMachine.clearHoldTarget()
  state.holdTargetId   = nil
  state.holdTargetName = nil
end

function AttackStateMachine.getStats()
  return {
    state        = state.current,
    targetId     = state.targetId,
    targetHealth = state.hp,
    holdTargetId = state.holdTargetId,
    stats        = state.stats,
  }
end

-- Backward-compatible aliases
AttackStateMachine.requestSwitch = AttackStateMachine.requestAttack
AttackStateMachine.forceSwitch   = AttackStateMachine.forceAttack

-- Backward-compatible stubs
function AttackStateMachine.isPathBlocked() return false end
function AttackStateMachine.findBestTarget() return nil, 0 end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

if EventBus then
  -- Game combat target changed
  EventBus.on("combat:target", function(creature, oldCreature)
    if not creature then return end  -- Nil → grace window handles it

    local id = cId(creature)
    if id == state.targetId then
      state.lastConfirmedAt = nowMs()
    elseif state.current ~= STATE.IDLE then
      -- External override (player click, party sync)
      state.creature      = creature
      state.targetId      = id
      state.hp            = cHp(creature)
      state.lastConfirmedAt = nowMs()
      state.holdTargetId  = id
      state.holdTargetName = cName(creature)
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
