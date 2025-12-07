--[[
  State Machine Architecture for nExBot
  Implements ROADMAP Feature 32:
  - Finite State Machine (FSM) for CaveBot and TargetBot
  - Clear state definitions and transitions
  - State-based decision making
  - Event-driven state changes
  
  Author: nExBot Team
  Version: 1.0
]]

StateMachine = {}

-- ============================================================================
-- CORE STATE MACHINE IMPLEMENTATION
-- ============================================================================

-- Create a new state machine instance
function StateMachine.create(name, config)
  local sm = {
    name = name,
    currentState = nil,
    previousState = nil,
    states = {},
    transitions = {},
    eventHandlers = {},
    stateHistory = {},
    historyLimit = config and config.historyLimit or 20,
    onStateChange = nil,
    lastStateChange = 0,
    stateData = {},
    isLocked = false,
    lockReason = nil
  }
  
  -- Add a state
  function sm:addState(stateName, callbacks)
    self.states[stateName] = {
      name = stateName,
      onEnter = callbacks.onEnter,
      onUpdate = callbacks.onUpdate,
      onExit = callbacks.onExit,
      canEnter = callbacks.canEnter,
      priority = callbacks.priority or 0
    }
    return self
  end
  
  -- Add a transition rule
  function sm:addTransition(fromState, toState, condition)
    if not self.transitions[fromState] then
      self.transitions[fromState] = {}
    end
    
    table.insert(self.transitions[fromState], {
      to = toState,
      condition = condition
    })
    return self
  end
  
  -- Set the initial state
  function sm:setInitialState(stateName)
    if self.states[stateName] then
      self.currentState = stateName
      self.lastStateChange = now
      local state = self.states[stateName]
      if state.onEnter then
        state.onEnter(nil, self.stateData)
      end
    end
    return self
  end
  
  -- Transition to a new state
  function sm:transitionTo(stateName, data)
    if self.isLocked then
      return false, "State machine locked: " .. (self.lockReason or "unknown")
    end
    
    local newState = self.states[stateName]
    if not newState then
      return false, "State not found: " .. stateName
    end
    
    -- Check if we can enter the new state
    if newState.canEnter and not newState.canEnter(self.currentState, data) then
      return false, "Cannot enter state: " .. stateName
    end
    
    local oldState = self.currentState
    local oldStateObj = self.states[oldState]
    
    -- Exit current state
    if oldStateObj and oldStateObj.onExit then
      oldStateObj.onExit(stateName, self.stateData)
    end
    
    -- Update state
    self.previousState = oldState
    self.currentState = stateName
    self.stateData = data or {}
    self.lastStateChange = now
    
    -- Record history
    table.insert(self.stateHistory, 1, {
      from = oldState,
      to = stateName,
      timestamp = now,
      data = data
    })
    
    -- Trim history
    while #self.stateHistory > self.historyLimit do
      table.remove(self.stateHistory)
    end
    
    -- Enter new state
    if newState.onEnter then
      newState.onEnter(oldState, self.stateData)
    end
    
    -- Notify listeners
    if self.onStateChange then
      self.onStateChange(oldState, stateName, self.stateData)
    end
    
    -- Fire event
    self:fireEvent("stateChanged", {
      from = oldState,
      to = stateName,
      data = self.stateData
    })
    
    return true
  end
  
  -- Update the current state (call from macro/loop)
  function sm:update()
    if self.isLocked then return end
    
    local currentStateObj = self.states[self.currentState]
    if not currentStateObj then return end
    
    -- Check automatic transitions
    local transitions = self.transitions[self.currentState]
    if transitions then
      for _, transition in ipairs(transitions) do
        if transition.condition and transition.condition(self.stateData) then
          self:transitionTo(transition.to)
          return
        end
      end
    end
    
    -- Update current state
    if currentStateObj.onUpdate then
      currentStateObj.onUpdate(self.stateData)
    end
  end
  
  -- Lock the state machine (prevent transitions)
  function sm:lock(reason)
    self.isLocked = true
    self.lockReason = reason
  end
  
  -- Unlock the state machine
  function sm:unlock()
    self.isLocked = false
    self.lockReason = nil
  end
  
  -- Register event handler
  function sm:on(event, handler)
    if not self.eventHandlers[event] then
      self.eventHandlers[event] = {}
    end
    table.insert(self.eventHandlers[event], handler)
    return self
  end
  
  -- Fire an event
  function sm:fireEvent(event, data)
    local handlers = self.eventHandlers[event]
    if handlers then
      for _, handler in ipairs(handlers) do
        handler(data)
      end
    end
  end
  
  -- Get current state info
  function sm:getState()
    return self.currentState
  end
  
  function sm:getPreviousState()
    return self.previousState
  end
  
  function sm:isInState(stateName)
    return self.currentState == stateName
  end
  
  function sm:getTimeInState()
    return now - self.lastStateChange
  end
  
  function sm:getHistory()
    return self.stateHistory
  end
  
  -- Force state (for debugging/recovery)
  function sm:forceState(stateName, data)
    self:unlock()
    return self:transitionTo(stateName, data)
  end
  
  return sm
end

-- ============================================================================
-- CAVEBOT STATE MACHINE
-- ============================================================================

-- Define CaveBot states
local CaveBotStates = {
  IDLE = "idle",
  WALKING = "walking",
  HUNTING = "hunting",
  LOOTING = "looting",
  REFILLING = "refilling",
  BANKING = "banking",
  DEPOSITING = "depositing",
  WITHDRAWING = "withdrawing",
  SELLING = "selling",
  BUYING = "buying",
  TRAVELING = "traveling",
  PAUSED = "paused",
  EMERGENCY = "emergency",
  DEATH_RECOVERY = "death_recovery"
}

-- Create CaveBot state machine
StateMachine.CaveBot = StateMachine.create("CaveBot", {historyLimit = 50})

-- Add all states
StateMachine.CaveBot
  :addState(CaveBotStates.IDLE, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Entered IDLE state")
    end,
    onUpdate = function(data)
      -- Wait for actions
    end,
    priority = 0
  })
  
  :addState(CaveBotStates.WALKING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Walking to destination")
    end,
    onUpdate = function(data)
      -- Walking logic handled by CaveBot.doWalking()
    end,
    canEnter = function(from, data)
      return not isInPz() or from == CaveBotStates.REFILLING
    end,
    priority = 1
  })
  
  :addState(CaveBotStates.HUNTING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Hunting mode active")
    end,
    onUpdate = function(data)
      -- Hunting logic - monsters around, attacking
    end,
    canEnter = function(from, data)
      return not isInPz()
    end,
    priority = 5
  })
  
  :addState(CaveBotStates.LOOTING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Looting bodies")
    end,
    onUpdate = function(data)
      -- Looting logic
    end,
    priority = 4
  })
  
  :addState(CaveBotStates.REFILLING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Refilling supplies")
    end,
    onUpdate = function(data)
      -- Refill process
    end,
    priority = 8
  })
  
  :addState(CaveBotStates.BANKING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Banking operations")
    end,
    onUpdate = function(data)
      -- Bank interactions
    end,
    priority = 7
  })
  
  :addState(CaveBotStates.DEPOSITING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Depositing items")
    end,
    priority = 6
  })
  
  :addState(CaveBotStates.WITHDRAWING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Withdrawing items")
    end,
    priority = 6
  })
  
  :addState(CaveBotStates.SELLING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Selling items")
    end,
    priority = 6
  })
  
  :addState(CaveBotStates.BUYING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Buying supplies")
    end,
    priority = 6
  })
  
  :addState(CaveBotStates.TRAVELING, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Traveling")
    end,
    priority = 3
  })
  
  :addState(CaveBotStates.PAUSED, {
    onEnter = function(from, data)
      -- info("[CaveBot FSM] Paused")
    end,
    onExit = function(to, data)
      -- info("[CaveBot FSM] Resuming from pause")
    end,
    priority = 0
  })
  
  :addState(CaveBotStates.EMERGENCY, {
    onEnter = function(from, data)
      warn("[CaveBot FSM] EMERGENCY STATE - " .. (data.reason or "unknown reason"))
    end,
    canEnter = function() return true end,
    priority = 100  -- Highest priority
  })
  
  :addState(CaveBotStates.DEATH_RECOVERY, {
    onEnter = function(from, data)
      warn("[CaveBot FSM] Death recovery mode")
    end,
    priority = 99
  })

-- Add transitions
StateMachine.CaveBot
  :addTransition(CaveBotStates.IDLE, CaveBotStates.HUNTING, function(data)
    return TargetBot and TargetBot.isActive()
  end)
  
  :addTransition(CaveBotStates.HUNTING, CaveBotStates.LOOTING, function(data)
    return TargetBot and TargetBot.isLooting and TargetBot.isLooting()
  end)
  
  :addTransition(CaveBotStates.HUNTING, CaveBotStates.WALKING, function(data)
    return not TargetBot or not TargetBot.isActive()
  end)
  
  :addTransition(CaveBotStates.LOOTING, CaveBotStates.HUNTING, function(data)
    return TargetBot and not TargetBot.isLooting()
  end)

-- Set initial state
StateMachine.CaveBot:setInitialState(CaveBotStates.IDLE)

-- ============================================================================
-- TARGETBOT STATE MACHINE
-- ============================================================================

local TargetBotStates = {
  IDLE = "idle",
  SCANNING = "scanning",
  TARGETING = "targeting",
  ATTACKING = "attacking",
  CHASING = "chasing",
  LOOTING = "looting",
  AVOIDING = "avoiding",
  RETREATING = "retreating"
}

StateMachine.TargetBot = StateMachine.create("TargetBot", {historyLimit = 30})

StateMachine.TargetBot
  :addState(TargetBotStates.IDLE, {
    onEnter = function(from, data)
      -- Not actively targeting
    end,
    priority = 0
  })
  
  :addState(TargetBotStates.SCANNING, {
    onEnter = function(from, data)
      -- Looking for targets
    end,
    priority = 1
  })
  
  :addState(TargetBotStates.TARGETING, {
    onEnter = function(from, data)
      -- Target acquired, preparing to attack
    end,
    priority = 2
  })
  
  :addState(TargetBotStates.ATTACKING, {
    onEnter = function(from, data)
      -- Actively attacking target
    end,
    priority = 5
  })
  
  :addState(TargetBotStates.CHASING, {
    onEnter = function(from, data)
      -- Following target
    end,
    priority = 4
  })
  
  :addState(TargetBotStates.LOOTING, {
    onEnter = function(from, data)
      -- Looting corpses
    end,
    priority = 3
  })
  
  :addState(TargetBotStates.AVOIDING, {
    onEnter = function(from, data)
      -- Avoiding dangerous monsters
    end,
    priority = 8
  })
  
  :addState(TargetBotStates.RETREATING, {
    onEnter = function(from, data)
      warn("[TargetBot FSM] Retreating!")
    end,
    priority = 10
  })

StateMachine.TargetBot:setInitialState(TargetBotStates.IDLE)

-- ============================================================================
-- GLOBAL STATE COORDINATOR
-- ============================================================================

StateMachine.Coordinator = {
  stateMachines = {
    cavebot = StateMachine.CaveBot,
    targetbot = StateMachine.TargetBot
  },
  globalState = "normal",
  lastUpdate = 0
}

-- Get combined state
function StateMachine.Coordinator.getCombinedState()
  return {
    cavebot = StateMachine.CaveBot:getState(),
    targetbot = StateMachine.TargetBot:getState(),
    global = StateMachine.Coordinator.globalState
  }
end

-- Set global state (affects all state machines)
function StateMachine.Coordinator.setGlobalState(state)
  local oldState = StateMachine.Coordinator.globalState
  StateMachine.Coordinator.globalState = state
  
  -- Handle global state changes
  if state == "emergency" then
    StateMachine.CaveBot:transitionTo(CaveBotStates.EMERGENCY, {reason = "Global emergency"})
    StateMachine.TargetBot:transitionTo(TargetBotStates.RETREATING)
  elseif state == "paused" then
    StateMachine.CaveBot:transitionTo(CaveBotStates.PAUSED)
    StateMachine.TargetBot:transitionTo(TargetBotStates.IDLE)
  end
end

-- Update all state machines
function StateMachine.Coordinator.update()
  StateMachine.CaveBot:update()
  StateMachine.TargetBot:update()
  StateMachine.Coordinator.lastUpdate = now
end

-- ============================================================================
-- STATE EXPORT CONSTANTS
-- ============================================================================

StateMachine.States = {
  CaveBot = CaveBotStates,
  TargetBot = TargetBotStates
}

-- ============================================================================
-- DEBUGGING & MONITORING
-- ============================================================================

function StateMachine.getDebugInfo()
  local info = "=== State Machine Debug ===\n"
  
  info = info .. "\n[CaveBot]"
  info = info .. "\n  Current: " .. (StateMachine.CaveBot:getState() or "nil")
  info = info .. "\n  Previous: " .. (StateMachine.CaveBot:getPreviousState() or "nil")
  info = info .. "\n  Time in state: " .. math.floor(StateMachine.CaveBot:getTimeInState() / 1000) .. "s"
  info = info .. "\n  Locked: " .. (StateMachine.CaveBot.isLocked and "Yes" or "No")
  
  info = info .. "\n\n[TargetBot]"
  info = info .. "\n  Current: " .. (StateMachine.TargetBot:getState() or "nil")
  info = info .. "\n  Previous: " .. (StateMachine.TargetBot:getPreviousState() or "nil")
  info = info .. "\n  Time in state: " .. math.floor(StateMachine.TargetBot:getTimeInState() / 1000) .. "s"
  
  info = info .. "\n\n[Global State]: " .. StateMachine.Coordinator.globalState
  
  info = info .. "\n\n[Recent Transitions (CaveBot)]:"
  local history = StateMachine.CaveBot:getHistory()
  for i = 1, math.min(5, #history) do
    local h = history[i]
    info = info .. "\n  " .. (h.from or "nil") .. " -> " .. h.to
  end
  
  return info
end

-- ============================================================================
-- INTEGRATION HELPERS
-- ============================================================================

-- Helper to transition CaveBot based on label type
function StateMachine.CaveBot.transitionByLabel(labelType)
  local labelStateMap = {
    ["hunt"] = CaveBotStates.HUNTING,
    ["lure"] = CaveBotStates.HUNTING,
    ["refill"] = CaveBotStates.REFILLING,
    ["bank"] = CaveBotStates.BANKING,
    ["depositor"] = CaveBotStates.DEPOSITING,
    ["withdraw"] = CaveBotStates.WITHDRAWING,
    ["sell"] = CaveBotStates.SELLING,
    ["buy"] = CaveBotStates.BUYING,
    ["travel"] = CaveBotStates.TRAVELING,
    ["stand"] = CaveBotStates.WALKING,
    ["goto"] = CaveBotStates.WALKING,
    ["walk"] = CaveBotStates.WALKING
  }
  
  local state = labelStateMap[labelType]
  if state then
    StateMachine.CaveBot:transitionTo(state, {label = labelType})
  end
end

-- Check if CaveBot is in hunting-related state
function StateMachine.CaveBot.isHunting()
  local state = StateMachine.CaveBot:getState()
  return state == CaveBotStates.HUNTING or state == CaveBotStates.LOOTING
end

-- Check if CaveBot is in refill-related state
function StateMachine.CaveBot.isRefilling()
  local state = StateMachine.CaveBot:getState()
  return state == CaveBotStates.REFILLING or 
         state == CaveBotStates.BANKING or
         state == CaveBotStates.DEPOSITING or
         state == CaveBotStates.WITHDRAWING or
         state == CaveBotStates.SELLING or
         state == CaveBotStates.BUYING
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
info("[StateMachine] Architecture loaded - Feature 32 active")
info("[StateMachine] CaveBot states: " .. #StateMachine.CaveBot.states)
info("[StateMachine] TargetBot states: " .. #StateMachine.TargetBot.states)
