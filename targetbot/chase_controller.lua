--[[
  ChaseController v1.0.0 - Unified Chase Mode State Machine
  
  DESIGN PRINCIPLES:
  - SRP: Single source of truth for chase mode state
  - DRY: No scattered chase mode logic across modules
  - KISS: Simple state machine with clear transitions
  
  OTClientBR Chase Modes (from const.h):
  - DontChase = 0 (Stand mode - no auto-walk)
  - ChaseOpponent = 1 (Client auto-walks to attacked creature)
  
  USAGE:
  - ChaseController.setChase(true/false) -- Enable/disable chase
  - ChaseController.requestPrecisionMode("reason") -- Temporarily disable for precision control
  - ChaseController.releasePrecisionMode("reason") -- Release precision mode
  - ChaseController.isChasing() -- Check if native chase is active
]]

local ChaseController = {}

-- ============================================================================
-- CLIENT SERVICE ABSTRACTION
-- ============================================================================

local function getClient()
  return ClientService
end

local function getGame()
  local Client = getClient()
  return (Client and Client.g_game) or g_game
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Desired chase mode (what TargetBot config wants)
  desiredChase = false,
  
  -- Current active mode (what's actually set)
  currentMode = -1,  -- -1 = unknown
  
  -- Precision mode holds (temporary overrides)
  precisionHolds = {},
  
  -- Last mode change timestamp (rate limiting)
  lastModeChange = 0,
  MODE_CHANGE_COOLDOWN = 100,  -- ms between mode changes
  
  -- Native chase tracking
  usingNativeChase = false,
}

-- ============================================================================
-- CORE API
-- ============================================================================

-- Set the desired chase mode (from TargetBot config)
function ChaseController.setDesiredChase(enabled)
  state.desiredChase = enabled
  ChaseController.syncMode()
end

-- Request precision control (temporarily disables native chase)
-- Returns a release token
function ChaseController.requestPrecisionMode(reason)
  reason = reason or "unknown"
  state.precisionHolds[reason] = true
  ChaseController.syncMode()
  return reason
end

-- Release precision control hold
function ChaseController.releasePrecisionMode(reason)
  if reason then
    state.precisionHolds[reason] = nil
  end
  ChaseController.syncMode()
end

-- Check if any precision holds are active
function ChaseController.hasPrecisionHolds()
  for _ in pairs(state.precisionHolds) do
    return true
  end
  return false
end

-- Get the effective chase mode considering all factors
function ChaseController.getEffectiveMode()
  -- If precision control is needed, always use Stand mode
  if ChaseController.hasPrecisionHolds() then
    return 0  -- DontChase
  end
  
  -- Otherwise, use desired mode
  return state.desiredChase and 1 or 0
end

-- Sync the actual game chase mode with our desired state
function ChaseController.syncMode()
  local game = getGame()
  if not game then return end
  
  local desiredMode = ChaseController.getEffectiveMode()
  
  -- Rate limit mode changes
  if now - state.lastModeChange < state.MODE_CHANGE_COOLDOWN then
    -- Still schedule the change
    schedule(state.MODE_CHANGE_COOLDOWN, function()
      ChaseController.syncMode()
    end)
    return
  end
  
  -- Get current mode
  local Client = getClient()
  local currentMode = -1
  if Client and Client.getChaseMode then
    currentMode = Client.getChaseMode()
  elseif game.getChaseMode then
    currentMode = game.getChaseMode()
  end
  
  -- Only change if different
  if currentMode ~= desiredMode then
    if Client and Client.setChaseMode then
      Client.setChaseMode(desiredMode)
    elseif game.setChaseMode then
      game.setChaseMode(desiredMode)
    end
    
    state.currentMode = desiredMode
    state.lastModeChange = now
    state.usingNativeChase = (desiredMode == 1)
    
    -- Update TargetBot flag for other modules
    if TargetBot then
      TargetBot.usingNativeChase = state.usingNativeChase
    end
    
    -- Emit event for other modules
    if EventBus then
      EventBus.emit("chase/mode_changed", desiredMode, state.precisionHolds)
    end
  end
end

-- Check if native chase is currently active
function ChaseController.isChasing()
  return state.usingNativeChase and not ChaseController.hasPrecisionHolds()
end

-- Get current chase mode from game
function ChaseController.getCurrentMode()
  local game = getGame()
  if not game then return 0 end
  
  local Client = getClient()
  if Client and Client.getChaseMode then
    return Client.getChaseMode()
  elseif game.getChaseMode then
    return game.getChaseMode()
  end
  
  return state.currentMode
end

-- ============================================================================
-- CONVENIENCE METHODS
-- ============================================================================

-- Enable chase mode
function ChaseController.enableChase()
  ChaseController.setDesiredChase(true)
end

-- Disable chase mode
function ChaseController.disableChase()
  ChaseController.setDesiredChase(false)
end

-- Temporarily disable chase for wave avoidance
function ChaseController.startWaveAvoidance()
  return ChaseController.requestPrecisionMode("wave_avoid")
end

function ChaseController.endWaveAvoidance()
  ChaseController.releasePrecisionMode("wave_avoid")
end

-- Temporarily disable chase for keep distance
function ChaseController.startKeepDistance()
  return ChaseController.requestPrecisionMode("keep_distance")
end

function ChaseController.endKeepDistance()
  ChaseController.releasePrecisionMode("keep_distance")
end

-- Clear all precision holds (e.g., on target change)
function ChaseController.clearPrecisionHolds()
  state.precisionHolds = {}
  ChaseController.syncMode()
end

-- ============================================================================
-- AUTO-WALK STATE MANAGEMENT
-- ============================================================================

-- Stop any active auto-walk (uses native API)
function ChaseController.stopAutoWalk()
  local Client = getClient()
  local game = getGame()
  
  -- Use native stopAutoWalk if available
  local player = (Client and Client.getLocalPlayer and Client.getLocalPlayer())
              or (game and game.getLocalPlayer and game.getLocalPlayer())
  
  if player then
    if player.isAutoWalking and player:isAutoWalking() then
      if player.stopAutoWalk then
        player:stopAutoWalk()
      end
    end
  end
  
  -- Also send stop command
  if game and game.stop then
    game.stop()
  end
end

-- Check if player is auto-walking (native API)
function ChaseController.isAutoWalking()
  local Client = getClient()
  local game = getGame()
  
  local player = (Client and Client.getLocalPlayer and Client.getLocalPlayer())
              or (game and game.getLocalPlayer and game.getLocalPlayer())
  
  if player and player.isAutoWalking then
    return player:isAutoWalking()
  end
  
  return false
end

-- ============================================================================
-- ATTACK INTEGRATION
-- ============================================================================

-- Called before attacking a new target
function ChaseController.onTargetChange(creature, config)
  -- Clear precision holds on target change (fresh start)
  ChaseController.clearPrecisionHolds()
  
  -- Determine if chase should be enabled for this target/config
  local shouldChase = config and config.chase and not config.keepDistance
  ChaseController.setDesiredChase(shouldChase)
  
  -- If chase is enabled but we need precision control, request it
  if config then
    if config.avoidAttacks then
      ChaseController.requestPrecisionMode("wave_avoid")
    end
    if config.keepDistance then
      ChaseController.requestPrecisionMode("keep_distance")
    end
  end
end

-- Called when attack is cancelled
function ChaseController.onAttackCancelled()
  ChaseController.disableChase()
  ChaseController.clearPrecisionHolds()
  ChaseController.stopAutoWalk()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Hook into EventBus if available
if EventBus then
  EventBus.on("combat:target", function(creature, oldCreature)
    if not creature then
      ChaseController.onAttackCancelled()
    end
  end, 100)  -- High priority
  
  EventBus.on("player:health", function(hp, maxHp)
    -- On death/relogin, reset state
    if hp <= 0 then
      ChaseController.onAttackCancelled()
    end
  end, 100)
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

-- Make ChaseController globally available (OTClient doesn't have _G)
ChaseController = ChaseController  -- This makes it globally accessible

return ChaseController
