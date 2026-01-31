--[[
  Attack State Machine v1.0
  
  A deterministic, event-driven state machine for continuous monster targeting.
  Ensures LINEAR attack behavior: one target at a time, until death.
  
  Key Principles:
  1. SINGLE SOURCE OF TRUTH: Only this module issues attack commands
  2. STATE-BASED: Clear states prevent race conditions
  3. STICKY TARGETING: Once locked, stay locked until target dies
  4. EVENT-DRIVEN: Reacts to game events in real-time
  5. ANTI-SPAM: Intelligent attack re-issue without flooding server
  
  States:
  - IDLE: No target, waiting for monsters
  - ACQUIRING: Found target, sending attack command
  - ATTACKING: Currently attacking, monitoring target health
  - CONFIRMING: Verifying attack registered with server
  - RECOVERING: Attack was lost, re-acquiring same target
  
  Integration:
  - Replaces scattered attack logic in target.lua and event_targeting.lua
  - Uses EventBus for real-time monitoring
  - Integrates with MonsterAI for threat assessment
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

AttackStateMachine = AttackStateMachine or {}
AttackStateMachine.VERSION = "1.0"
AttackStateMachine.DEBUG = false

-- ============================================================================
-- STATES
-- ============================================================================

local STATE = {
  IDLE = "IDLE",           -- No target
  ACQUIRING = "ACQUIRING", -- Sending attack command
  ATTACKING = "ATTACKING", -- Locked on target
  CONFIRMING = "CONFIRMING", -- Waiting for server confirmation
  RECOVERING = "RECOVERING"  -- Re-acquiring lost attack
}

AttackStateMachine.STATE = STATE

-- ============================================================================
-- CONFIGURATION (Tunable)
-- IMPROVED v3.0: Stricter values for linear targeting (anti-zigzag)
-- ============================================================================

--------------------------------------------------------------------------------
-- CLIENTSERVICE HELPERS (using global ClientHelper for consistency)
--------------------------------------------------------------------------------
local function getClient()
  return ClientHelper and ClientHelper.getClient() or ClientService
end

local function getClientVersion()
  return ClientHelper and ClientHelper.getClientVersion() or ((g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200)
end

local CONFIG = {
  -- Attack timing
  -- IMPROVED v4.0: Increased intervals for less spam, more consistent attacking
  ATTACK_REISSUE_INTERVAL = 1000,   -- Re-issue attack every 1000ms (server only needs periodic keepalive)
  ATTACK_CONFIRM_TIMEOUT = 800,     -- Max time to wait for server confirmation
  ATTACK_RECOVER_ATTEMPTS = 5,      -- Max recovery attempts before giving up
  ATTACK_COOLDOWN = 200,            -- Minimum time between attack commands (prevents spam)
  
  -- Target switching thresholds (STRICTER v3.0)
  SWITCH_PRIORITY_THRESHOLD = 500,  -- INCREASED: Need 500+ priority advantage to force switch (was 100)
  SWITCH_HP_THRESHOLD = 80,         -- INCREASED: Current target must be above 80% HP to allow switch (was 50%)
  SWITCH_COOLDOWN = 5000,           -- INCREASED: Minimum 5 seconds between target switches (was 800ms)
  
  -- Health thresholds for stickiness (STRICTER v3.0)
  CRITICAL_HP = 30,                 -- INCREASED: Below 30%, NEVER switch (was 15%)
  LOW_HP = 50,                      -- INCREASED: Below 50%, require huge priority advantage (was 30%)
  WOUNDED_HP = 75,                  -- INCREASED: Below 75%, require significant advantage (was 50%)
  
  -- Performance
  UPDATE_INTERVAL = 50,             -- State machine tick interval (50ms = 20 FPS)
  HEALTH_CHECK_INTERVAL = 100,      -- How often to check target health
  
  -- Debug
  LOG_STATE_CHANGES = false
}

AttackStateMachine.CONFIG = CONFIG

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

local state = {
  -- Current state
  current = STATE.IDLE,
  previousState = nil,
  stateEnterTime = 0,
  
  -- Target tracking
  targetId = nil,
  targetCreature = nil,
  targetHealth = 100,
  targetPriority = 0,
  targetConfig = nil,
  
  -- Attack tracking
  lastAttackCommand = 0,
  lastAttackConfirmed = 0,
  attackConfirmed = false,
  recoverAttempts = 0,
  
  -- Switch tracking
  lastSwitchTime = 0,
  switchRequested = false,
  pendingTarget = nil,
  pendingPriority = 0,
  
  -- Statistics
  stats = {
    attacksIssued = 0,
    attacksConfirmed = 0,
    switchesBlocked = 0,
    switchesAllowed = 0,
    recoveries = 0,
    targetsKilled = 0
  }
}

-- Cached player reference
local player = nil

-- ============================================================================
-- UTILITY FUNCTIONS (use ClientHelper for DRY)
-- ============================================================================

local nowMs = ClientHelper and ClientHelper.nowMs or function()
  return now or (os.time() * 1000)
end

local function log(msg)
  if AttackStateMachine.DEBUG then
    print("[AttackSM] " .. msg)
  end
end

local function logState(newState, reason)
  if CONFIG.LOG_STATE_CHANGES or AttackStateMachine.DEBUG then
    print(string.format("[AttackSM] %s -> %s (%s)", state.current, newState, reason or ""))
  end
end

local function updatePlayerRef()
  if not player or not pcall(function() return player:getPosition() end) then
    local Client = getClient()
    player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()) or nil
  end
  return player
end

-- ============================================================================
-- OPENTIBIABR TARGETING ENHANCEMENT (v3.1)
-- Use fast creature lookup when available
-- ============================================================================
local OpenTibiaBRTargeting = nil
local function loadOpenTibiaBRTargeting()
  if OpenTibiaBRTargeting then return OpenTibiaBRTargeting end
  local ok, result = pcall(function()
    return dofile("nExBot/targetbot/opentibiabr_targeting.lua")
  end)
  if ok and result then
    OpenTibiaBRTargeting = result
  end
  return OpenTibiaBRTargeting
end

-- ============================================================================
-- SAFE CREATURE ACCESS HELPERS (v4.0 - Using SafeCreature module for DRY)
-- ============================================================================

-- Use global SafeCreature module
local SC = SafeCreature

-- Safe creature property access (delegates to SafeCreature)
local function getCreatureId(creature)
  return SC and SC.getId(creature) or nil
end

-- Fast creature lookup by ID (uses OpenTibiaBR when available)
local function getCreatureById(creatureId)
  if not creatureId then return nil end
  
  -- Try OpenTibiaBR fast lookup first
  local otbr = loadOpenTibiaBRTargeting()
  if otbr and otbr.getCreatureById then
    local creature = otbr.getCreatureById(creatureId)
    if creature then return creature end
  end
  
  -- Fallback: check current attack target
  local Client = getClient()
  local target = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
  if target and getCreatureId(target) == creatureId then
    return target
  end
  
  return nil
end

local function getCreatureHealth(creature)
  return SC and SC.getHealthPercent(creature) or 0
end

local function isCreatureDead(creature)
  if SC then return SC.isDead(creature) end
  if not creature then return true end
  local ok, dead = pcall(function() return creature:isDead() end)
  if ok and dead then return true end
  return getCreatureHealth(creature) <= 0
end

-- Fast creature validation by ID (v3.1)
local function isCreatureValidById(creatureId)
  if not creatureId then return false end
  
  -- Try OpenTibiaBR fast validation first
  local otbr = loadOpenTibiaBRTargeting()
  if otbr and otbr.isCreatureValid then
    return otbr.isCreatureValid(creatureId)
  end
  
  -- Fallback: get creature and check
  local creature = getCreatureById(creatureId)
  return creature and not isCreatureDead(creature)
end

local function getCreaturePosition(creature)
  return SC and SC.getPosition(creature) or nil
end

local function getCreatureName(creature)
  return SC and SC.getName(creature) or "Unknown"
end

-- ============================================================================
-- STATE MACHINE CORE
-- ============================================================================

-- Transition to a new state
local function transition(newState, reason)
  if state.current == newState then return end
  
  logState(newState, reason)
  state.previousState = state.current
  state.current = newState
  state.stateEnterTime = nowMs()
  
  -- Emit state change event
  if EventBus and EventBus.emit then
    pcall(function()
      EventBus.emit("attacksm:state_changed", newState, state.previousState, reason)
    end)
  end
end

-- Get current attacking creature from game
local function getGameAttackTarget()
  local Client = getClient()
  if (Client and Client.getAttackingCreature) then
    local ok, creature = pcall(Client.getAttackingCreature)
    return ok and creature or nil
  elseif g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(g_game.getAttackingCreature)
    return ok and creature or nil
  end
  return nil
end

-- Issue attack command (centralized, rate-limited)
-- IMPROVED v3.0: Now triggers engagement lock for linear targeting
local function issueAttack(creature, reason)
  if not creature or isCreatureDead(creature) then return false end
  
  local currentTime = nowMs()
  
  -- Rate limiting
  if (currentTime - state.lastAttackCommand) < CONFIG.ATTACK_COOLDOWN then
    return false
  end
  
  -- Issue the attack
  local success = false
  local Client = getClient()
  if (Client and Client.attack) then
    local ok, err = pcall(function() Client.attack(creature) end)
    success = ok
    if ok then
      state.lastAttackCommand = currentTime
      state.attackConfirmed = false
      state.stats.attacksIssued = state.stats.attacksIssued + 1
      log("Attack issued: " .. getCreatureName(creature) .. " (" .. (reason or "unknown") .. ")")
      
      -- ENGAGEMENT LOCK: Start engagement with this target
      -- This prevents target switching once we start attacking
      if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.startEngagement then
        local creatureId = getCreatureId(creature)
        local health = nil
        pcall(function() health = creature:getHealthPercent() end)
        MonsterAI.Scenario.startEngagement(creatureId, health)
      end
    else
      log("Attack failed: " .. tostring(err))
    end
  elseif g_game and g_game.attack then
    local ok, err = pcall(function() g_game.attack(creature) end)
    success = ok
    if ok then
      state.lastAttackCommand = currentTime
      state.attackConfirmed = false
      state.stats.attacksIssued = state.stats.attacksIssued + 1
      log("Attack issued (g_game fallback): " .. getCreatureName(creature) .. " (" .. (reason or "unknown") .. ")")
      
      if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.startEngagement then
        local creatureId = getCreatureId(creature)
        local health = nil
        pcall(function() health = creature:getHealthPercent() end)
        MonsterAI.Scenario.startEngagement(creatureId, health)
      end
    else
      log("Attack failed (g_game fallback): " .. tostring(err))
    end
  end
  
  return success
end

-- Check if attack is confirmed (game is actually attacking our target)
local function isAttackConfirmed()
  local gameTarget = getGameAttackTarget()
  if not gameTarget then return false end
  
  local gameTargetId = getCreatureId(gameTarget)
  return gameTargetId and gameTargetId == state.targetId
end

-- ============================================================================
-- PRIORITY CALCULATION
-- ============================================================================

-- Calculate target priority (unified with TargetBot.Creature)
local function calculatePriority(creature, dist)
  if not creature then return 0 end
  
  -- Use TargetBot's calculation if available
  if TargetBot and TargetBot.Creature and TargetBot.Creature.calculateParams then
    local ok, params = pcall(function()
      return TargetBot.Creature.calculateParams(creature, nil)
    end)
    if ok and params and params.priority then
      return params.priority
    end
  end
  
  -- Fallback: Basic priority calculation
  local priority = 0
  
  -- Config priority (primary factor)
  if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
    local configs = TargetBot.Creature.getConfigs(creature)
    if configs and #configs > 0 then
      for i = 1, #configs do
        local cfg = configs[i]
        if cfg.priority and cfg.priority > 0 then
          priority = priority + (cfg.priority * 100)
          break
        end
      end
    end
  end
  
  -- Distance bonus
  dist = dist or 10
  priority = priority + math.max(0, (10 - dist)) * 5
  
  -- Health bonus (wounded targets)
  local hp = getCreatureHealth(creature)
  if hp < 100 then
    priority = priority + ((100 - hp) * 0.5)
  end
  
  return priority
end

-- Check if a switch to new target should be allowed
-- IMPROVED v3.1: Config priority (user-set) takes precedence over calculated priority
-- When a monster with HIGHER user-configured priority appears, switch immediately!
local function shouldAllowSwitch(newCreature, newPriority)
  if not state.targetCreature or isCreatureDead(state.targetCreature) then
    -- Target is dead - end engagement and allow switch
    if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.endEngagement then
      MonsterAI.Scenario.endEngagement("target_dead")
    end
    return true, "current_dead"
  end
  
  local currentTime = nowMs()
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- FAST PATH: CONFIG PRIORITY CHECK (User-set priority takes precedence!)
  -- If new creature has HIGHER user-configured priority, bypass most checks
  -- This is the KEY feature for multi-monster configurations
  -- ═══════════════════════════════════════════════════════════════════════════
  local newConfigPriority = 0
  local currentConfigPriority = 0
  
  if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
    -- Get new creature's config priority
    local newConfigs = TargetBot.Creature.getConfigs(newCreature)
    if newConfigs and #newConfigs > 0 then
      for i = 1, #newConfigs do
        local cfg = newConfigs[i]
        if cfg.priority and cfg.priority > newConfigPriority then
          newConfigPriority = cfg.priority
        end
      end
    end
    
    -- Get current target's config priority
    local currentConfigs = TargetBot.Creature.getConfigs(state.targetCreature)
    if currentConfigs and #currentConfigs > 0 then
      for i = 1, #currentConfigs do
        local cfg = currentConfigs[i]
        if cfg.priority and cfg.priority > currentConfigPriority then
          currentConfigPriority = cfg.priority
        end
      end
    end
    
    -- FAST PATH: Higher config priority = IMMEDIATE SWITCH
    -- Only a reduced cooldown applies (500ms instead of 5000ms)
    if newConfigPriority > currentConfigPriority then
      local configSwitchCooldown = 500  -- Much shorter cooldown for config priority switches
      if (currentTime - state.lastSwitchTime) >= configSwitchCooldown then
        state.stats.switchesAllowed = (state.stats.switchesAllowed or 0) + 1
        log("CONFIG PRIORITY SWITCH: " .. newConfigPriority .. " > " .. currentConfigPriority)
        return true, "config_priority"
      end
    end
  end
  
  -- Check MonsterAI engagement lock (only if not bypassed by config priority)
  if MonsterAI and MonsterAI.Scenario and MonsterAI.Scenario.shouldAllowTargetSwitch then
    local newCreatureId = getCreatureId(newCreature)
    local newHealth = getCreatureHealth(newCreature)
    local allowed, reason = MonsterAI.Scenario.shouldAllowTargetSwitch(newCreatureId, newPriority, newHealth)
    if not allowed then
      state.stats.switchesBlocked = (state.stats.switchesBlocked or 0) + 1
      return false, "monsterai_" .. (reason or "blocked")
    end
  end
  
  -- Standard switch cooldown
  if (currentTime - state.lastSwitchTime) < CONFIG.SWITCH_COOLDOWN then
    state.stats.switchesBlocked = (state.stats.switchesBlocked or 0) + 1
    return false, "cooldown"
  end
  
  -- Current target health check
  local currentHp = getCreatureHealth(state.targetCreature)
  
  -- CRITICAL HP: Never switch (unless config priority is higher - handled above)
  if currentHp < CONFIG.CRITICAL_HP then
    state.stats.switchesBlocked = (state.stats.switchesBlocked or 0) + 1
    return false, "critical_hp"
  end
  
  -- Priority comparison (calculated priority, not config priority)
  local priorityAdvantage = newPriority - state.targetPriority
  local requiredAdvantage = CONFIG.SWITCH_PRIORITY_THRESHOLD
  
  -- Adjust required advantage based on current target health
  if currentHp < CONFIG.LOW_HP then
    requiredAdvantage = requiredAdvantage * 3  -- 1500 priority needed
  elseif currentHp < CONFIG.WOUNDED_HP then
    requiredAdvantage = requiredAdvantage * 2  -- 1000 priority needed
  end
  
  if priorityAdvantage >= requiredAdvantage then
    state.stats.switchesAllowed = (state.stats.switchesAllowed or 0) + 1
    return true, "priority_advantage"
  end
  
  state.stats.switchesBlocked = (state.stats.switchesBlocked or 0) + 1
  return false, "insufficient_priority"
end

-- ============================================================================
-- STATE HANDLERS
-- ============================================================================

-- IDLE: Looking for targets
local function handleIdle()
  -- Check if there's a game target we should sync with
  local gameTarget = getGameAttackTarget()
  if gameTarget and not isCreatureDead(gameTarget) then
    -- Sync with existing game target
    state.targetId = getCreatureId(gameTarget)
    state.targetCreature = gameTarget
    state.targetHealth = getCreatureHealth(gameTarget)
    state.targetPriority = calculatePriority(gameTarget)
    state.attackConfirmed = true
    state.lastAttackConfirmed = nowMs()
    transition(STATE.ATTACKING, "sync_with_game")
    return
  end
  
  -- Look for best target
  local bestTarget, bestPriority = AttackStateMachine.findBestTarget()
  if bestTarget then
    state.targetCreature = bestTarget
    state.targetId = getCreatureId(bestTarget)
    state.targetHealth = getCreatureHealth(bestTarget)
    state.targetPriority = bestPriority
    state.recoverAttempts = 0
    transition(STATE.ACQUIRING, "new_target")
  end
end

-- ACQUIRING: Sending attack command
local function handleAcquiring()
  if not state.targetCreature or isCreatureDead(state.targetCreature) then
    transition(STATE.IDLE, "target_lost")
    return
  end
  
  -- Issue attack
  if issueAttack(state.targetCreature, "acquire") then
    transition(STATE.CONFIRMING, "attack_sent")
  else
    -- Retry on next tick
    if (nowMs() - state.stateEnterTime) > 1000 then
      -- Timeout - give up on this target
      transition(STATE.IDLE, "acquire_timeout")
    end
  end
end

-- CONFIRMING: Waiting for server confirmation
local function handleConfirming()
  if not state.targetCreature or isCreatureDead(state.targetCreature) then
    state.stats.targetsKilled = state.stats.targetsKilled + 1
    transition(STATE.IDLE, "target_died")
    return
  end
  
  -- Check if confirmed
  if isAttackConfirmed() then
    state.attackConfirmed = true
    state.lastAttackConfirmed = nowMs()
    state.stats.attacksConfirmed = state.stats.attacksConfirmed + 1
    transition(STATE.ATTACKING, "confirmed")
    return
  end
  
  local elapsed = nowMs() - state.stateEnterTime
  
  -- Timeout - try again
  if elapsed > CONFIG.ATTACK_CONFIRM_TIMEOUT then
    state.recoverAttempts = state.recoverAttempts + 1
    if state.recoverAttempts >= CONFIG.ATTACK_RECOVER_ATTEMPTS then
      transition(STATE.IDLE, "confirm_failed")
    else
      transition(STATE.ACQUIRING, "retry")
    end
  end
end

-- ATTACKING: Locked on target, monitoring
local function handleAttacking()
  -- Check target death
  if not state.targetCreature or isCreatureDead(state.targetCreature) then
    state.stats.targetsKilled = state.stats.targetsKilled + 1
    log("Target killed: " .. getCreatureName(state.targetCreature))
    state.targetCreature = nil
    state.targetId = nil
    transition(STATE.IDLE, "target_killed")
    return
  end
  
  -- Update health
  state.targetHealth = getCreatureHealth(state.targetCreature)
  
  -- Check if attack is still active
  if not isAttackConfirmed() then
    -- Attack was lost - enter recovery
    transition(STATE.RECOVERING, "attack_lost")
    return
  end
  
  -- Update last confirmed time
  state.lastAttackConfirmed = nowMs()
  
  -- Check for pending switch request
  if state.switchRequested and state.pendingTarget then
    local allowed, reason = shouldAllowSwitch(state.pendingTarget, state.pendingPriority)
    if allowed then
      -- Switch to new target
      state.targetCreature = state.pendingTarget
      state.targetId = getCreatureId(state.pendingTarget)
      state.targetHealth = getCreatureHealth(state.pendingTarget)
      state.targetPriority = state.pendingPriority
      state.lastSwitchTime = nowMs()
      state.recoverAttempts = 0
      log("Switching target: " .. reason)
      transition(STATE.ACQUIRING, "switch")
    else
      log("Switch blocked: " .. reason)
    end
    state.switchRequested = false
    state.pendingTarget = nil
    state.pendingPriority = 0
  end
  
  -- Periodic attack re-issue (keep server connection alive)
  local timeSinceAttack = nowMs() - state.lastAttackCommand
  if timeSinceAttack > CONFIG.ATTACK_REISSUE_INTERVAL then
    issueAttack(state.targetCreature, "keepalive")
  end
end

-- RECOVERING: Re-acquiring lost attack
local function handleRecovering()
  if not state.targetCreature or isCreatureDead(state.targetCreature) then
    state.stats.targetsKilled = state.stats.targetsKilled + 1
    transition(STATE.IDLE, "target_died_recovery")
    return
  end
  
  state.recoverAttempts = state.recoverAttempts + 1
  state.stats.recoveries = state.stats.recoveries + 1
  
  if state.recoverAttempts >= CONFIG.ATTACK_RECOVER_ATTEMPTS then
    log("Recovery failed after " .. state.recoverAttempts .. " attempts")
    transition(STATE.IDLE, "recovery_failed")
    return
  end
  
  -- Try to re-acquire
  if issueAttack(state.targetCreature, "recover") then
    transition(STATE.CONFIRMING, "recovery_attack_sent")
  end
end

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================

local lastUpdate = 0

local function update()
  -- Check if TargetBot is enabled
  if TargetBot and TargetBot.isOn and not TargetBot.isOn() then
    if state.current ~= STATE.IDLE then
      transition(STATE.IDLE, "targetbot_disabled")
    end
    return
  end
  
  -- Check explicit disable flag
  if TargetBot and TargetBot.explicitlyDisabled then
    if state.current ~= STATE.IDLE then
      transition(STATE.IDLE, "explicitly_disabled")
    end
    return
  end
  
  -- Rate limit updates
  local currentTime = nowMs()
  if (currentTime - lastUpdate) < CONFIG.UPDATE_INTERVAL then
    return
  end
  lastUpdate = currentTime
  
  -- Update player reference
  updatePlayerRef()
  if not player then return end
  
  -- State handlers
  if state.current == STATE.IDLE then
    handleIdle()
  elseif state.current == STATE.ACQUIRING then
    handleAcquiring()
  elseif state.current == STATE.CONFIRMING then
    handleConfirming()
  elseif state.current == STATE.ATTACKING then
    handleAttacking()
  elseif state.current == STATE.RECOVERING then
    handleRecovering()
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get current state
function AttackStateMachine.getState()
  return state.current
end

-- Get current target
function AttackStateMachine.getTarget()
  return state.targetCreature
end

-- Get target ID
function AttackStateMachine.getTargetId()
  return state.targetId
end

-- Is currently attacking?
function AttackStateMachine.isAttacking()
  return state.current == STATE.ATTACKING or state.current == STATE.CONFIRMING
end

-- Is attack confirmed by server?
function AttackStateMachine.isConfirmed()
  return state.attackConfirmed and isAttackConfirmed()
end

-- Request a target switch (will be evaluated based on priority)
function AttackStateMachine.requestSwitch(creature, priority)
  if not creature or isCreatureDead(creature) then return false end
  
  local newId = getCreatureId(creature)
  if newId == state.targetId then return false end -- Already targeting this
  
  priority = priority or calculatePriority(creature)
  
  -- If idle, just acquire directly
  if state.current == STATE.IDLE then
    state.targetCreature = creature
    state.targetId = newId
    state.targetHealth = getCreatureHealth(creature)
    state.targetPriority = priority
    state.recoverAttempts = 0
    transition(STATE.ACQUIRING, "direct_acquire")
    return true
  end
  
  -- Queue the switch request for evaluation
  state.switchRequested = true
  state.pendingTarget = creature
  state.pendingPriority = priority
  
  return true
end

-- Force switch to a specific target (bypasses priority check)
function AttackStateMachine.forceSwitch(creature)
  if not creature or isCreatureDead(creature) then return false end
  
  state.targetCreature = creature
  state.targetId = getCreatureId(creature)
  state.targetHealth = getCreatureHealth(creature)
  state.targetPriority = calculatePriority(creature)
  state.lastSwitchTime = nowMs()
  state.recoverAttempts = 0
  state.switchRequested = false
  state.pendingTarget = nil
  
  transition(STATE.ACQUIRING, "force_switch")
  return true
end

-- Stop attacking
function AttackStateMachine.stop()
  state.targetCreature = nil
  state.targetId = nil
  state.switchRequested = false
  state.pendingTarget = nil
  transition(STATE.IDLE, "manual_stop")
  
  -- Cancel game attack
  local Client = getClient()
  if Client and Client.cancelAttackAndFollow then
    pcall(Client.cancelAttackAndFollow)
  elseif g_game and g_game.cancelAttackAndFollow then
    pcall(g_game.cancelAttackAndFollow)
  end
end

-- Reset all state
function AttackStateMachine.reset()
  state.current = STATE.IDLE
  state.previousState = nil
  state.stateEnterTime = 0
  state.targetId = nil
  state.targetCreature = nil
  state.targetHealth = 100
  state.targetPriority = 0
  state.targetConfig = nil
  state.lastAttackCommand = 0
  state.lastAttackConfirmed = 0
  state.attackConfirmed = false
  state.recoverAttempts = 0
  state.lastSwitchTime = 0
  state.switchRequested = false
  state.pendingTarget = nil
  state.pendingPriority = 0
  
  log("State machine reset")
end

-- Get statistics
function AttackStateMachine.getStats()
  return {
    state = state.current,
    targetId = state.targetId,
    targetHealth = state.targetHealth,
    attackConfirmed = state.attackConfirmed,
    stats = state.stats
  }
end

-- Find best target (uses EventTargeting or CreatureCache)
function AttackStateMachine.findBestTarget()
  updatePlayerRef()
  if not player then return nil, 0 end
  
  local ok, playerPos = pcall(function() return player:getPosition() end)
  if not ok or not playerPos then return nil, 0 end
  
  local bestTarget = nil
  local bestPriority = 0
  
  -- Get live monsters
  local creatures = nil
  if EventTargeting and EventTargeting.getLiveMonsterCount then
    local count, liveCreatures = EventTargeting.getLiveMonsterCount()
    if liveCreatures and #liveCreatures > 0 then
      creatures = liveCreatures
    end
  end
  
  -- Fallback to spectators
  if not creatures or #creatures == 0 then
    local Client = getClient()
    if Client and Client.getSpectatorsInRange then
      creatures = Client.getSpectatorsInRange(playerPos, false, 8, 8)
    elseif g_map and g_map.getSpectatorsInRange then
      creatures = g_map.getSpectatorsInRange(playerPos, false, 8, 8)
    end
  end
  
  if not creatures then return nil, 0 end
  
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature then
      -- Check if monster
      local okMonster, isMonster = pcall(function() return creature:isMonster() end)
      if okMonster and isMonster and not isCreatureDead(creature) then
        local creaturePos = getCreaturePosition(creature)
        if creaturePos and creaturePos.z == playerPos.z then
          -- Check if in targetbot config
          local hasConfig = false
          if TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
            local configs = TargetBot.Creature.getConfigs(creature)
            hasConfig = configs and #configs > 0
          end
          
          if hasConfig then
            local dist = math.max(math.abs(playerPos.x - creaturePos.x), math.abs(playerPos.y - creaturePos.y))
            local priority = calculatePriority(creature, dist)
            
            if priority > bestPriority then
              bestPriority = priority
              bestTarget = creature
            end
          end
        end
      end
    end
  end
  
  return bestTarget, bestPriority
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- ============================================================================

if EventBus then
  -- Monster appears - check if higher priority than current
  EventBus.on("monster:appear", function(creature)
    if not creature then return end
    if TargetBot and TargetBot.isOn and not TargetBot.isOn() then return end
    
    -- If idle, let normal update handle it
    if state.current == STATE.IDLE then return end
    
    -- Check priority
    local priority = calculatePriority(creature)
    if priority > state.targetPriority then
      AttackStateMachine.requestSwitch(creature, priority)
    end
  end, 30)
  
  -- Monster health changed
  EventBus.on("monster:health", function(creature, percent)
    if not creature then return end
    
    local creatureId = getCreatureId(creature)
    if creatureId == state.targetId then
      state.targetHealth = percent or 0
      
      -- Check for death
      if percent and percent <= 0 then
        state.stats.targetsKilled = state.stats.targetsKilled + 1
        transition(STATE.IDLE, "target_health_zero")
      end
    end
  end, 50)
  
  -- Monster dies/disappears
  EventBus.on("monster:disappear", function(creature)
    if not creature then return end
    
    local creatureId = getCreatureId(creature)
    if creatureId == state.targetId then
      state.stats.targetsKilled = state.stats.targetsKilled + 1
      transition(STATE.IDLE, "target_disappeared")
    end
  end, 50)
  
  -- Combat target changed (sync with game state)
  EventBus.on("combat:target", function(creature, oldCreature)
    if not creature then
      -- Attack was cancelled externally
      if state.current == STATE.ATTACKING then
        transition(STATE.RECOVERING, "external_cancel")
      end
      return
    end
    
    local newId = getCreatureId(creature)
    if newId ~= state.targetId and state.current ~= STATE.IDLE then
      -- Game switched to different target - sync
      state.targetCreature = creature
      state.targetId = newId
      state.targetHealth = getCreatureHealth(creature)
      state.targetPriority = calculatePriority(creature)
      state.attackConfirmed = true
      state.lastAttackConfirmed = nowMs()
      log("Synced with game target: " .. getCreatureName(creature))
    end
  end, 40)
  
  -- TargetBot disabled
  EventBus.on("targetbot/disabled", function()
    AttackStateMachine.reset()
  end, 100)
  
  -- Player moved - re-evaluate paths
  EventBus.on("player:move", function(newPos, oldPos)
    -- Path validity might have changed, but don't interrupt current attack
  end, 10)
end

-- ============================================================================
-- INTERNAL UPDATE LOOP
-- ============================================================================

-- The update function is called automatically by the TargetBot macro in target.lua
-- This runs silently as part of the targeting system - no separate button needed
AttackStateMachine.update = update

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize on load
updatePlayerRef()
log("Attack State Machine v" .. AttackStateMachine.VERSION .. " initialized")

-- Export for other modules
return AttackStateMachine
