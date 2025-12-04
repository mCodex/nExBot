--[[
  ============================================================================
  nExBot Bot State Manager
  ============================================================================
  
  Centralized state management for all bot components using Singleton pattern.
  Replaces scattered global variables with organized, typed state objects.
  
  DESIGN PATTERNS:
  - Singleton: Single source of truth for all bot state
  - Observer-Ready: State accessors that can integrate with EventBus
  - Encapsulation: Private state with public accessors
  
  BENEFITS:
  - Predictable state changes through defined accessors
  - Easy debugging - all state in one place
  - Serialization support for saving/loading sessions
  - Performance tracking built-in
  
  USAGE:
    local BotState = require("core.bot_state")
    BotState:initialize()
    
    -- Access state
    local target = BotState:getTarget()
    local standTime = BotState:getStandTime()
  
  Author: nExBot Team
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  LOCAL CACHING FOR PERFORMANCE
  ============================================================================
]]
local table_insert = table.insert
local os_time = os.time
local collectgarbage = collectgarbage
local type = type
local pairs = pairs
local tostring = tostring

--[[
  ============================================================================
  STATE OBJECT DEFINITION
  ============================================================================
  
  All bot state is organized into logical categories for maintainability.
  Each category tracks related data that changes together.
  ============================================================================
]]

local BotState = {
  -- ========================================
  -- CORE STATE
  -- Fundamental bot lifecycle information
  -- ========================================
  initialized = false,    -- Whether initialize() has been called
  startTime = 0,          -- Unix timestamp when bot started
  
  -- ========================================
  -- PLAYER STATE
  -- Tracks the local player's actions and status
  -- ========================================
  player = {
    standTime = 0,        -- Timestamp of last movement
    isUsingPotion = false,-- Currently drinking a potion (prevents spam)
    isUsing = false,      -- Generic "using item" flag for cooldown management
    lastAction = 0,       -- Timestamp of last significant action
    lastPosition = nil    -- Last known position {x, y, z}
  },
  
  -- ========================================
  -- COMBAT STATE
  -- Current combat situation and cooldowns
  -- ========================================
  combat = {
    currentTarget = nil,  -- Currently targeted creature (or nil)
    lastAttackTime = 0,   -- Timestamp of last attack action
    lastSpellTime = 0,    -- Timestamp of last spell cast
    customCooldowns = {}  -- Spell-specific cooldowns: {spell -> {time, cooldown}}
  },
  
  -- ========================================
  -- CAVEBOT STATE
  -- Navigation and hunting progress
  -- ========================================
  cavebot = {
    lastLabel = "",       -- Name of last reached label waypoint
    roundData = {},       -- Statistics per round: {kills, loot, time}
    currentRound = 0,     -- Number of completed hunting rounds
    lastWaypoint = 0,     -- Index of last reached waypoint
    isRefilling = false   -- Currently in refill/deposit phase
  },
  
  -- ========================================
  -- LOOT STATE
  -- Collected loot tracking for statistics
  -- ========================================
  loot = {
    containers = {},      -- Active loot containers to process
    items = {},           -- Array of {item, value, time} for session
    totalValue = 0,       -- Running total gold value of loot
    lastLootTime = 0      -- Timestamp of last loot pickup
  },
  
  -- ========================================
  -- PERFORMANCE STATE
  -- Monitoring and profiling data
  -- ========================================
  performance = {
    tickCount = 0,        -- Total macro ticks executed
    avgTickTime = 0,      -- Running average of tick duration (ms)
    memoryUsage = 0,      -- Last measured memory (KB)
    peakMemory = 0        -- Highest memory usage seen (KB)
  }
}

--[[
  ============================================================================
  INITIALIZATION
  ============================================================================
]]

--- Initializes the bot state manager
-- Sets up event hooks for automatic state tracking
-- Should be called once at bot startup
-- 
-- @return self for method chaining
function BotState:initialize()
  -- Guard against double initialization
  if self.initialized then
    return self
  end
  
  self.initialized = true
  self.startTime = os_time()
  self.player.standTime = now or 0
  
  -- ========================================
  -- POSITION CHANGE TRACKING
  -- Updates standTime when player moves
  -- ========================================
  if onPlayerPositionChange then
    onPlayerPositionChange(function(newPos, oldPos)
      self.player.standTime = now
      self.player.lastPosition = newPos
    end)
  end
  
  -- ========================================
  -- POTION USAGE TRACKING
  -- Prevents potion spam by tracking consumption
  -- Detects "Aaaah..." message (mode 34 = monster say/effect)
  -- ========================================
  if onTalk then
    onTalk(function(name, level, mode, text, channelId, pos)
      -- Early return if no player exists
      if not player then return end
      
      -- Check if it's our character's potion message
      if name == player:getName() and mode == 34 then
        if text == "Aaaah..." then
          self.player.isUsingPotion = true
          -- Potion exhaustion is ~950ms
          schedule(950, function()
            self.player.isUsingPotion = false
          end)
        end
      end
    end)
  end
  
  return self
end

--[[
  ============================================================================
  PLAYER STATE ACCESSORS
  ============================================================================
]]

--- Gets time since player last moved
-- Used for AFK detection, standing actions, etc.
-- 
-- @return (number) Milliseconds since last movement
function BotState:getStandTime()
  return (now or 0) - self.player.standTime
end

--- Checks if player is currently drinking a potion
-- Prevents potion spam during the ~950ms cooldown
-- 
-- @return (boolean) True if potion is being consumed
function BotState:isUsingPotion()
  return self.player.isUsingPotion
end

--- Checks if player is using any item
-- Generic flag for action cooldown management
-- 
-- @return (boolean) True if player is busy with an item
function BotState:isUsing()
  return self.player.isUsing
end

--- Sets the "using item" flag with optional auto-clear
-- 
-- @param value (boolean) New using state
-- @param duration (number|nil) Auto-clear after this many ms
function BotState:setUsing(value, duration)
  self.player.isUsing = value
  if value and duration then
    schedule(duration, function()
      self.player.isUsing = false
    end)
  end
end

--[[
  ============================================================================
  COMBAT STATE ACCESSORS
  ============================================================================
]]

--- Sets the current combat target
-- Returns the previous target for comparison
-- 
-- @param target (Creature|nil) New target or nil to clear
-- @return (Creature|nil) Previous target
function BotState:setTarget(target)
  local oldTarget = self.combat.currentTarget
  self.combat.currentTarget = target
  self.combat.lastAttackTime = now or 0
  return oldTarget
end

--- Gets the current combat target
-- @return (Creature|nil) Current target
function BotState:getTarget()
  return self.combat.currentTarget
end

--- Records a spell cast for custom cooldown tracking
-- Some spells have cooldowns not tracked by the game client
-- 
-- @param spellName (string) Name/words of the spell
-- @param cooldown (number) Cooldown duration in milliseconds
function BotState:recordSpellCast(spellName, cooldown)
  local key = spellName:lower()
  self.combat.customCooldowns[key] = {
    time = now,
    cooldown = cooldown
  }
  self.combat.lastSpellTime = now
end

--- Checks if a spell is off cooldown
-- Uses custom cooldown tracking for precise timing
-- 
-- @param spellName (string) Name/words of the spell
-- @param cooldown (number|nil) Optional: check against this cooldown instead
-- @return (boolean) True if spell can be cast
function BotState:canCastSpell(spellName, cooldown)
  local key = spellName:lower()
  local data = self.combat.customCooldowns[key]
  
  -- Never cast before = can cast now
  if not data then return true end
  
  -- Use provided cooldown or stored one
  local cd = cooldown or data.cooldown
  return (now - data.time) >= cd
end

--- Clears all custom spell cooldowns
-- Useful when reloading spell configurations
function BotState:clearSpellCooldowns()
  self.combat.customCooldowns = {}
end

--[[
  ============================================================================
  CAVEBOT STATE ACCESSORS
  ============================================================================
]]

--- Sets the last reached label waypoint
-- Labels are named waypoints used for navigation control
-- 
-- @param label (string) Label name
function BotState:setLastLabel(label)
  self.cavebot.lastLabel = label or ""
end

--- Gets the last reached label
-- @return (string) Label name or empty string
function BotState:getLastLabel()
  return self.cavebot.lastLabel
end

--- Increments and returns the round counter
-- A "round" is typically one complete hunting loop
-- 
-- @return (number) New round number
function BotState:incrementRound()
  self.cavebot.currentRound = self.cavebot.currentRound + 1
  return self.cavebot.currentRound
end

--- Gets the current round number
-- @return (number) Current round count
function BotState:getRound()
  return self.cavebot.currentRound
end

--- Sets refilling state
-- @param refilling (boolean) Whether currently refilling
function BotState:setRefilling(refilling)
  self.cavebot.isRefilling = refilling
end

--- Checks if cavebot is refilling
-- @return (boolean) True if in refill phase
function BotState:isRefilling()
  return self.cavebot.isRefilling
end

--[[
  ============================================================================
  LOOT STATE ACCESSORS
  ============================================================================
]]

--- Adds a container to the loot queue
-- Containers are processed by the looting module
-- 
-- @param container (Container) Container to loot
function BotState:addLootContainer(container)
  table_insert(self.loot.containers, container)
end

--- Gets all pending loot containers
-- @return (table) Array of containers
function BotState:getLootContainers()
  return self.loot.containers
end

--- Clears the loot container queue
function BotState:clearLootContainers()
  self.loot.containers = {}
end

--- Records a looted item for statistics
-- 
-- @param item (Item) The looted item
-- @param value (number) Gold value of the item
function BotState:addLootItem(item, value)
  table_insert(self.loot.items, {
    item = item,
    value = value or 0,
    time = now
  })
  self.loot.totalValue = self.loot.totalValue + (value or 0)
  self.loot.lastLootTime = now
end

--- Gets total gold value of looted items this session
-- @return (number) Total gold value
function BotState:getTotalLootValue()
  return self.loot.totalValue
end

--- Gets count of looted items
-- @return (number) Item count
function BotState:getLootItemCount()
  return #self.loot.items
end

--[[
  ============================================================================
  PERFORMANCE STATE ACCESSORS
  ============================================================================
]]

--- Records a macro tick for performance monitoring
-- Called each tick to track execution time
-- 
-- @param duration (number) Tick duration in milliseconds
function BotState:recordTick(duration)
  self.performance.tickCount = self.performance.tickCount + 1
  
  -- Exponential moving average for smooth trending
  -- Weight: 0.1 for new value, 0.9 for history
  if self.performance.tickCount == 1 then
    self.performance.avgTickTime = duration
  else
    self.performance.avgTickTime = 
      (self.performance.avgTickTime * 0.9) + (duration * 0.1)
  end
end

--- Updates and returns memory usage
-- Calls collectgarbage to get accurate reading
-- 
-- @return (number) Memory usage in KB
function BotState:updateMemoryUsage()
  self.performance.memoryUsage = collectgarbage("count")
  
  -- Track peak memory
  if self.performance.memoryUsage > self.performance.peakMemory then
    self.performance.peakMemory = self.performance.memoryUsage
  end
  
  return self.performance.memoryUsage
end

--- Gets comprehensive performance statistics
-- @return (table) Performance data object
function BotState:getPerformanceStats()
  return {
    tickCount = self.performance.tickCount,
    avgTickTime = self.performance.avgTickTime,
    memoryUsage = self.performance.memoryUsage,
    peakMemory = self.performance.peakMemory,
    uptime = os_time() - self.startTime
  }
end

--[[
  ============================================================================
  SERIALIZATION
  ============================================================================
  
  These functions enable saving/loading bot state to persist across sessions.
  Only serializes data that makes sense to persist (not runtime-only data).
  ============================================================================
]]

--- Serializes state to a saveable table
-- Only includes persistent data, not runtime state
-- 
-- @return (table) Serializable state object
function BotState:serialize()
  return {
    cavebot = {
      lastLabel = self.cavebot.lastLabel,
      currentRound = self.cavebot.currentRound,
      roundData = self.cavebot.roundData
    },
    loot = {
      totalValue = self.loot.totalValue,
      itemCount = #self.loot.items
    },
    performance = {
      tickCount = self.performance.tickCount,
      peakMemory = self.performance.peakMemory
    }
  }
end

--- Deserializes state from a saved table
-- Restores persistent data from previous session
-- 
-- @param data (table) Previously serialized state
function BotState:deserialize(data)
  if not data or type(data) ~= "table" then return end
  
  if data.cavebot then
    self.cavebot.lastLabel = data.cavebot.lastLabel or ""
    self.cavebot.currentRound = data.cavebot.currentRound or 0
    self.cavebot.roundData = data.cavebot.roundData or {}
  end
  
  if data.loot then
    self.loot.totalValue = data.loot.totalValue or 0
  end
  
  if data.performance then
    self.performance.tickCount = data.performance.tickCount or 0
    self.performance.peakMemory = data.performance.peakMemory or 0
  end
end

--[[
  ============================================================================
  RESET FUNCTIONS
  ============================================================================
]]

--- Resets all runtime state to defaults
-- Does not affect persistent data like round counts
function BotState:reset()
  -- Player state
  self.player.standTime = now or 0
  self.player.isUsingPotion = false
  self.player.isUsing = false
  self.player.lastAction = 0
  
  -- Combat state
  self.combat.currentTarget = nil
  self.combat.lastAttackTime = 0
  self.combat.lastSpellTime = 0
  self.combat.customCooldowns = {}
  
  -- Loot state (clear runtime data)
  self.loot.containers = {}
  self.loot.items = {}
  -- Note: totalValue is NOT reset (accumulated across session)
end

--- Performs a full reset including all accumulated data
-- Use when starting a completely fresh session
function BotState:fullReset()
  self:reset()
  
  -- Also reset accumulated data
  self.cavebot.lastLabel = ""
  self.cavebot.roundData = {}
  self.cavebot.currentRound = 0
  self.loot.totalValue = 0
  self.performance.tickCount = 0
  self.performance.avgTickTime = 0
  self.performance.peakMemory = 0
end

--[[
  ============================================================================
  MODULE EXPORT
  ============================================================================
]]

return BotState
