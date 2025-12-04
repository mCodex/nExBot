--[[
  NexBot Bot State Manager
  Centralized state management for all bot components
  Replaces scattered global variables with organized state
  
  Author: NexBot Team
  Version: 1.0.0
]]

local BotState = {
  -- Core state
  initialized = false,
  startTime = 0,
  
  -- Player state tracking
  player = {
    standTime = 0,
    isUsingPotion = false,
    isUsing = false,
    lastAction = 0
  },
  
  -- Combat state
  combat = {
    currentTarget = nil,
    lastAttackTime = 0,
    lastSpellTime = 0,
    customCooldowns = {}
  },
  
  -- CaveBot state
  cavebot = {
    lastLabel = "",
    roundData = {},
    currentRound = 0
  },
  
  -- BotServer state (party coordination)
  botServer = {
    members = {},
    channel = nil,
    lastSync = 0
  },
  
  -- Loot tracking
  loot = {
    containers = {},
    items = {},
    totalValue = 0
  },
  
  -- Performance metrics
  performance = {
    tickCount = 0,
    avgTickTime = 0,
    memoryUsage = 0
  }
}

-- Initialize the state manager
function BotState:initialize()
  self.initialized = true
  self.startTime = os.time()
  self.player.standTime = now or 0
  
  -- Set up position change tracking
  if onPlayerPositionChange then
    onPlayerPositionChange(function(newPos, oldPos)
      self.player.standTime = now
    end)
  end
  
  -- Set up potion usage tracking
  if onTalk then
    onTalk(function(name, level, mode, text, channelId, pos)
      if player and name == player:getName() and mode == 34 then
        if text == "Aaaah..." then
          self.player.isUsingPotion = true
          schedule(950, function()
            self.player.isUsingPotion = false
          end)
        end
      end
    end)
  end
  
  return self
end

-- Get stand time (time since last movement)
function BotState:getStandTime()
  return (now or 0) - self.player.standTime
end

-- Player state accessors
function BotState:isUsingPotion()
  return self.player.isUsingPotion
end

function BotState:isUsing()
  return self.player.isUsing
end

function BotState:setUsing(value, duration)
  self.player.isUsing = value
  if value and duration then
    schedule(duration, function()
      self.player.isUsing = false
    end)
  end
end

-- Combat state accessors
function BotState:setTarget(target)
  local oldTarget = self.combat.currentTarget
  self.combat.currentTarget = target
  return oldTarget
end

function BotState:getTarget()
  return self.combat.currentTarget
end

function BotState:recordSpellCast(spellName, cooldown)
  self.combat.customCooldowns[spellName:lower()] = {
    time = now,
    cooldown = cooldown
  }
  self.combat.lastSpellTime = now
end

function BotState:canCastSpell(spellName, cooldown)
  local data = self.combat.customCooldowns[spellName:lower()]
  if not data then return true end
  return (now - data.time) > data.cooldown
end

-- CaveBot state accessors
function BotState:setLastLabel(label)
  self.cavebot.lastLabel = label
end

function BotState:getLastLabel()
  return self.cavebot.lastLabel
end

function BotState:incrementRound()
  self.cavebot.currentRound = self.cavebot.currentRound + 1
  return self.cavebot.currentRound
end

function BotState:getRound()
  return self.cavebot.currentRound
end

-- BotServer state accessors
function BotState:addBotServerMember(name, data)
  self.botServer.members[name] = data or {}
  self.botServer.lastSync = now
end

function BotState:removeBotServerMember(name)
  self.botServer.members[name] = nil
end

function BotState:getBotServerMembers()
  return self.botServer.members
end

function BotState:isBotServerMember(name)
  return self.botServer.members[name] ~= nil
end

-- Loot tracking
function BotState:addLootContainer(container)
  table.insert(self.loot.containers, container)
end

function BotState:getLootContainers()
  return self.loot.containers
end

function BotState:clearLootContainers()
  self.loot.containers = {}
end

function BotState:addLootItem(item, value)
  table.insert(self.loot.items, {item = item, value = value, time = now})
  self.loot.totalValue = self.loot.totalValue + (value or 0)
end

function BotState:getTotalLootValue()
  return self.loot.totalValue
end

-- Performance tracking
function BotState:recordTick(duration)
  self.performance.tickCount = self.performance.tickCount + 1
  self.performance.avgTickTime = (self.performance.avgTickTime + duration) / 2
end

function BotState:updateMemoryUsage()
  self.performance.memoryUsage = collectgarbage("count")
  return self.performance.memoryUsage
end

function BotState:getPerformanceStats()
  return {
    tickCount = self.performance.tickCount,
    avgTickTime = self.performance.avgTickTime,
    memoryUsage = self.performance.memoryUsage,
    uptime = os.time() - self.startTime
  }
end

-- Save/Load state for persistence
function BotState:serialize()
  return {
    cavebot = {
      lastLabel = self.cavebot.lastLabel,
      currentRound = self.cavebot.currentRound,
      roundData = self.cavebot.roundData
    },
    loot = {
      totalValue = self.loot.totalValue
    }
  }
end

function BotState:deserialize(data)
  if not data then return end
  
  if data.cavebot then
    self.cavebot.lastLabel = data.cavebot.lastLabel or ""
    self.cavebot.currentRound = data.cavebot.currentRound or 0
    self.cavebot.roundData = data.cavebot.roundData or {}
  end
  
  if data.loot then
    self.loot.totalValue = data.loot.totalValue or 0
  end
end

-- Reset all state
function BotState:reset()
  self.player.standTime = now
  self.player.isUsingPotion = false
  self.player.isUsing = false
  self.combat.currentTarget = nil
  self.combat.lastAttackTime = 0
  self.combat.customCooldowns = {}
  self.cavebot.lastLabel = ""
  self.loot.containers = {}
  self.loot.items = {}
  self.loot.totalValue = 0
end

return BotState
