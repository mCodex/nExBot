local targetbotMacro = nil
local config = nil
local lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true
local dangerValue = 0
local looterStatus = ""

-- Pull System state (shared with CaveBot)
TargetBot = TargetBot or {}
TargetBot.smartPullActive = false  -- When true, CaveBot pauses waypoint walking

-- Use TargetBotCore if available (DRY principle)
local Core = TargetCore or {}

-- Creature type constants for clarity
local CREATURE_TYPE = {
  PLAYER = 0,
  MONSTER = 1,      -- Targetable monster
  NPC = 2,
  SUMMON = 3        -- Non-targetable (other player's summons)
}

-- Pre-allocated constants for pathfinding (PERFORMANCE: avoid table creation in loop)
local PATH_PARAMS = {
  ignoreLastCreature = true,
  ignoreNonPathable = true,
  ignoreCost = true,
  ignoreCreatures = true
}

-- Pre-allocated status strings (PERFORMANCE: avoid string concatenation)
local STATUS_ATTACKING = "Attacking"
local STATUS_ATTACKING_LURE_OFF = "Attacking (luring off)"
local STATUS_PULLING = "Pulling (using CaveBot)"
local STATUS_WAITING = "Waiting"
local STATUS_ATTACK_PREFIX = "Attack & "

--------------------------------------------------------------------------------
-- PERFORMANCE: Optimized Creature Cache
-- Uses event-driven updates with LRU eviction and TargetCore integration
--------------------------------------------------------------------------------
local CreatureCache = {
  monsters = {},          -- {id -> {creature, path, params, lastUpdate, priority}}
  monsterCount = 0,
  bestTarget = nil,
  bestPriority = 0,
  totalDanger = 0,
  dirty = true,           -- Flag to recalculate on next tick
  lastFullUpdate = 0,
  FULL_UPDATE_INTERVAL = 400,  -- Reduced for faster adaptation
  PATH_TTL = 250,         -- Path cache valid for 250ms (faster invalidation)
  lastCleanup = 0,
  CLEANUP_INTERVAL = 1500,
  -- LRU eviction
  accessOrder = {},       -- Array of IDs in access order
  maxSize = 50            -- Max cached creatures
}

-- Mark cache as dirty (needs recalculation)
local function invalidateCache()
  CreatureCache.dirty = true
end

-- LRU eviction helper: move ID to end of access order
local function touchCreature(id)
  local order = CreatureCache.accessOrder
  -- Remove existing position
  for i = #order, 1, -1 do
    if order[i] == id then
      table.remove(order, i)
      break
    end
  end
  -- Add to end (most recently used)
  order[#order + 1] = id
end

-- LRU eviction: remove oldest entries when over capacity
local function evictOldestCreatures()
  local order = CreatureCache.accessOrder
  while #order > CreatureCache.maxSize do
    local oldestId = table.remove(order, 1)
    if CreatureCache.monsters[oldestId] then
      CreatureCache.monsters[oldestId] = nil
      CreatureCache.monsterCount = CreatureCache.monsterCount - 1
    end
  end
end

-- Clean up stale cache entries (improved with LRU)
local function cleanupCache()
  if now - CreatureCache.lastCleanup < CreatureCache.CLEANUP_INTERVAL then
    return
  end
  
  local cutoff = now - 3000  -- Reduced from 5s to 3s for faster cleanup
  local newMonsters = {}
  local newOrder = {}
  local count = 0
  
  -- Keep only recent entries in access order
  for i = 1, #CreatureCache.accessOrder do
    local id = CreatureCache.accessOrder[i]
    local data = CreatureCache.monsters[id]
    if data and data.lastUpdate > cutoff and data.creature and not data.creature:isDead() then
      newMonsters[id] = data
      newOrder[#newOrder + 1] = id
      count = count + 1
    end
  end
  
  CreatureCache.monsters = newMonsters
  CreatureCache.accessOrder = newOrder
  CreatureCache.monsterCount = count
  CreatureCache.lastCleanup = now
  invalidateCache()
end

-- Update a single creature in cache (called on events)
-- Improved with LRU tracking and distance-based filtering
local function updateCreatureInCache(creature)
  if not creature or creature:isDead() then
    local id = creature and creature:getId()
    if id and CreatureCache.monsters[id] then
      CreatureCache.monsters[id] = nil
      CreatureCache.monsterCount = CreatureCache.monsterCount - 1
      -- Remove from access order
      for i = #CreatureCache.accessOrder, 1, -1 do
        if CreatureCache.accessOrder[i] == id then
          table.remove(CreatureCache.accessOrder, i)
          break
        end
      end
    end
    invalidateCache()
    return
  end
  
  if not creature:isMonster() then return end
  
  local id = creature:getId()
  local pos = player:getPosition()
  local cpos = creature:getPosition()
  
  -- Use TargetBotCore distance if available, otherwise calculate
  local dist
  if Core.Geometry and Core.Geometry.chebyshevDistance then
    dist = Core.Geometry.chebyshevDistance(pos, cpos)
  else
    dist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
  end
  
  -- Skip if too far (reduced from 10 to 8 for better performance)
  if dist > 8 then
    if CreatureCache.monsters[id] then
      CreatureCache.monsters[id] = nil
      CreatureCache.monsterCount = CreatureCache.monsterCount - 1
      for i = #CreatureCache.accessOrder, 1, -1 do
        if CreatureCache.accessOrder[i] == id then
          table.remove(CreatureCache.accessOrder, i)
          break
        end
      end
    end
    return
  end
  
  local entry = CreatureCache.monsters[id]
  if not entry then
    entry = { 
      creature = creature, 
      lastUpdate = now,
      distance = dist
    }
    CreatureCache.monsters[id] = entry
    CreatureCache.monsterCount = CreatureCache.monsterCount + 1
    touchCreature(id)
    -- Check if we need to evict
    evictOldestCreatures()
  else
    entry.creature = creature
    entry.lastUpdate = now
    entry.distance = dist
    touchCreature(id)
  end
  
  -- Recalculate path if needed
  if not entry.path or now - (entry.pathTime or 0) > CreatureCache.PATH_TTL then
    entry.path = findPath(pos, cpos, 10, PATH_PARAMS)
    entry.pathTime = now
  end
  
  invalidateCache()
end

-- Remove creature from cache (with LRU cleanup)
local function removeCreatureFromCache(creature)
  if not creature then return end
  local id = creature:getId()
  if CreatureCache.monsters[id] then
    CreatureCache.monsters[id] = nil
    CreatureCache.monsterCount = CreatureCache.monsterCount - 1
    -- Remove from LRU order
    for i = #CreatureCache.accessOrder, 1, -1 do
      if CreatureCache.accessOrder[i] == id then
        table.remove(CreatureCache.accessOrder, i)
        break
      end
    end
    invalidateCache()
  end
end

--------------------------------------------------------------------------------
-- EventBus Integration for Event-Driven Targeting
--------------------------------------------------------------------------------
if EventBus then
  -- Monster appears - add to cache
  EventBus.on("monster:appear", function(creature)
    updateCreatureInCache(creature)
  end, 50)
  
  -- Monster disappears - remove from cache
  EventBus.on("monster:disappear", function(creature)
    removeCreatureFromCache(creature)
  end, 50)
  
  -- Monster health changes - update priority (high priority for targeting decisions)
  EventBus.on("monster:health", function(creature, percent)
    if percent <= 0 then
      removeCreatureFromCache(creature)
    else
      -- Invalidate to recalculate priority for wounded monsters
      invalidateCache()
    end
  end, 80)
  
  -- Player moves - need to recalculate paths
  EventBus.on("player:move", function(newPos, oldPos)
    -- Invalidate all paths on player movement
    for id, data in pairs(CreatureCache.monsters) do
      data.path = nil
      data.pathTime = nil
    end
    invalidateCache()
  end, 60)
  
  -- Target changes
  EventBus.on("combat:target", function(creature, oldCreature)
    invalidateCache()
  end, 70)
end

-- PERFORMANCE: Path cache for backward compatibility (optimized)
local PathCache = {
  paths = {},
  TTL = 500,
  lastCleanup = 0,
  cleanupInterval = 2000,
  size = 0,
  maxSize = 100
}

-- Pre-allocated cache entry to reduce GC
local cacheEntryPool = {}

local function acquireCacheEntry()
  local entry = table.remove(cacheEntryPool)
  return entry or { path = nil, timestamp = 0 }
end

local function releaseCacheEntry(entry)
  if #cacheEntryPool < 20 then
    entry.path = nil
    entry.timestamp = 0
    cacheEntryPool[#cacheEntryPool + 1] = entry
  end
end

local function getCachedPath(creatureId, fromPos, toPos)
  local cached = PathCache.paths[creatureId]
  if cached and (now - cached.timestamp) < PathCache.TTL then
    return cached.path
  end
  return nil
end

local function setCachedPath(creatureId, path)
  local existing = PathCache.paths[creatureId]
  if existing then
    existing.path = path
    existing.timestamp = now
  else
    if PathCache.size >= PathCache.maxSize then
      -- Evict oldest entry
      local oldest, oldestId = now, nil
      for id, data in pairs(PathCache.paths) do
        if data.timestamp < oldest then
          oldest = data.timestamp
          oldestId = id
        end
      end
      if oldestId then
        releaseCacheEntry(PathCache.paths[oldestId])
        PathCache.paths[oldestId] = nil
        PathCache.size = PathCache.size - 1
      end
    end
    local entry = acquireCacheEntry()
    entry.path = path
    entry.timestamp = now
    PathCache.paths[creatureId] = entry
    PathCache.size = PathCache.size + 1
  end
end

local function cleanupPathCache()
  if now - PathCache.lastCleanup < PathCache.cleanupInterval then
    return
  end
  
  local cutoff = now - PathCache.TTL
  for id, data in pairs(PathCache.paths) do
    if data.timestamp < cutoff then
      releaseCacheEntry(data)
      PathCache.paths[id] = nil
      PathCache.size = PathCache.size - 1
    end
  end
  PathCache.lastCleanup = now
end

-- ui
local configWidget = UI.Config()
local ui = UI.createWidget("TargetBotPanel")

ui.list = ui.listPanel.list -- shortcut
TargetBot.targetList = ui.list
TargetBot.Looting.setup()

-- Setup eat food feature if available
if TargetBot.EatFood and TargetBot.EatFood.setup then
  TargetBot.EatFood.setup()
end

ui.status.left:setText("Status:")
ui.status.right:setText("Off")
ui.target.left:setText("Target:")
ui.target.right:setText("-")
ui.config.left:setText("Config:")
ui.config.right:setText("-")
ui.danger.left:setText("Danger:")
ui.danger.right:setText("0")

ui.editor.debug.onClick = function()
  local on = ui.editor.debug:isOn()
  ui.editor.debug:setOn(not on)
  if on then
    local specs = getSpectators()
    for i = 1, #specs do
      specs[i]:clearText()
    end
  end
end

local oldTibia = g_game.getClientVersion() < 960

-- config, its callback is called immediately, data can be nil
config = Config.setup("targetbot_configs", configWidget, "json", function(name, enabled, data)
  -- Save character's profile preference when profile changes (multi-client support)
  if enabled and name and name ~= "" and setCharacterProfile then
    setCharacterProfile("targetbotProfile", name)
  end

  if not data then
    ui.status.right:setText("Off")
    if targetbotMacro and targetbotMacro.setOff then
      return targetbotMacro.setOff() 
    end
    return
  end
  TargetBot.Creature.resetConfigs()
  for _, value in ipairs(data["targeting"] or {}) do
    TargetBot.Creature.addConfig(value)
  end
  TargetBot.Looting.update(data["looting"] or {})

  -- add configs
  if enabled then
    ui.status.right:setText("On")
  else
    ui.status.right:setText("Off")
  end

  if targetbotMacro and targetbotMacro.setOn then
    targetbotMacro.setOn(enabled)
    targetbotMacro.delay = nil
  end
  lureEnabled = true
end)

-- Setup UI tooltips
ui.editor.buttons.add:setTooltip("Add a new creature targeting configuration.\nDefine which creatures to attack and how.")
ui.editor.buttons.edit:setTooltip("Edit the selected creature targeting configuration.\nModify priority, distance, and behavior settings.")
ui.editor.buttons.remove:setTooltip("Remove the selected creature targeting configuration.\nThis action cannot be undone.")
ui.editor.debug:setTooltip("Show priority values on creatures in-game.\nUseful for debugging targeting decisions.")
ui.configButton:setTooltip("Show/hide the target editor panel.\nUse to add, edit, or remove creature configurations.")

-- setup ui
ui.editor.buttons.add.onClick = function()
  TargetBot.Creature.edit(nil, function(newConfig)
    TargetBot.Creature.addConfig(newConfig, true)
    TargetBot.save()
  end)
end

ui.editor.buttons.edit.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  TargetBot.Creature.edit(entry.value, function(newConfig)
    entry:setText(newConfig.name)
    entry.value = newConfig
    TargetBot.Creature.resetConfigsCache()
    TargetBot.save()
  end)
end

ui.editor.buttons.remove.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  entry:destroy()
  TargetBot.Creature.resetConfigsCache()
  TargetBot.save()
end

-- public function, you can use them in your scripts
TargetBot.isActive = function() -- return true if attacking or looting takes place
  return lastAction + 300 > now
end

TargetBot.isCaveBotActionAllowed = function()
  return cavebotAllowance > now
end

TargetBot.setStatus = function(text)
  return ui.status.right:setText(text)
end

TargetBot.getStatus = function()
  return ui.status.right:getText()
end

TargetBot.isOn = function()
  if not config or not config.isOn then return false end
  return config.isOn()
end

TargetBot.isOff = function()
  if not config or not config.isOff then return true end
  return config.isOff()
end

TargetBot.setOn = function(val)
  if val == false then  
    return TargetBot.setOff(true)
  end
  config.setOn()
end

TargetBot.setOff = function(val)
  if val == false then  
    return TargetBot.setOn(true)
  end
  config.setOff()
end

TargetBot.getCurrentProfile = function()
  return storage._configs.targetbot_configs.selected
end

-- Use shared BotConfigName from configs.lua (DRY)
local botConfigName = BotConfigName or modules.game_bot.contentsPanel.config:getCurrentOption().text
TargetBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/targetbot_configs/"..name..".json") then
    return warn("there is no targetbot profile with that name!")
  end
  TargetBot.setOff()
  storage._configs.targetbot_configs.selected = name
  -- Save character's profile preference for multi-client support
  if setCharacterProfile then
    setCharacterProfile("targetbotProfile", name)
  end
  TargetBot.setOn()
end

TargetBot.delay = function(value)
  targetbotMacro.delay = now + value
end

TargetBot.save = function()
  local data = {targeting={}, looting={}}
  for _, entry in ipairs(ui.list:getChildren()) do
    table.insert(data.targeting, entry.value)
  end
  TargetBot.Looting.save(data.looting)
  config.save(data)
end

TargetBot.allowCaveBot = function(time)
  cavebotAllowance = now + time
end

TargetBot.disableLuring = function()
  lureEnabled = false
end

TargetBot.enableLuring = function()
  lureEnabled = true
end

TargetBot.Danger = function()
  return dangerValue
end

TargetBot.lootStatus = function()
  return looterStatus
end


-- attacks
local lastSpell = 0
local lastAttackSpell = 0

TargetBot.saySpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 500 end
  if g_game.getProtocolVersion() < 1090 then
    lastAttackSpell = now -- pause attack spells, healing spells are more important
  end
  if lastSpell + delay < now then
    say(text)
    lastSpell = now
    return true
  end
  return false
end

TargetBot.sayAttackSpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 2000 end
  if lastAttackSpell + delay < now then
    say(text)
    lastAttackSpell = now
    return true
  end
  return false
end

local lastItemUse = 0
local lastRuneAttack = 0

-- Use item on target like hotkey (doesn't require open backpack)
-- Uses BotCore.Items for consolidated item usage with fallback
local function useItemOnTargetLikeHotkey(item, target, subType)
  -- Use BotCore.Items if available (handles all client compatibility)
  if BotCore and BotCore.Items and BotCore.Items.useOn then
    return BotCore.Items.useOn(item, target, subType)
  end
  
  -- Fallback: direct implementation
  local thing = g_things.getThingType(item)
  if not thing or not thing:isFluidContainer() then
    subType = g_game.getClientVersion() >= 860 and 0 or 1
  end
  
  if g_game.getClientVersion() >= 780 then
    if g_game.useInventoryItemWith then
      g_game.useInventoryItemWith(item, target, subType)
      return true
    end
  end
  
  local tmpItem = g_game.findPlayerItem(item, subType)
  if tmpItem then
    g_game.useWith(tmpItem, target, subType)
    return true
  end
  
  return false
end

TargetBot.useItem = function(item, subType, target, delay)
  if not delay then delay = 200 end
  if lastItemUse + delay < now then
    if useItemOnTargetLikeHotkey(item, target, subType) then
      lastItemUse = now
      return true
    end
  end
  return false
end

TargetBot.useAttackItem = function(item, subType, target, delay)
  if not delay then delay = 2000 end
  if lastRuneAttack + delay < now then
    if useItemOnTargetLikeHotkey(item, target, subType) then
      lastRuneAttack = now
      return true
    end
  end
  return false
end

TargetBot.canLure = function()
  return lureEnabled
end

-- Helper function to check if creature is targetable
local function isTargetableCreature(creature)
  if not creature or creature:isDead() then
    return false
  end
  
  if not creature:isMonster() then
    return false
  end
  
  -- Old Tibia clients don't have creature types
  if oldTibia then
    return true
  end
  
  local creatureType = creature:getType()
  -- Target monsters (type 1) and some summons (type < 3)
  return creatureType < 3
end

--------------------------------------------------------------------------------
-- Optimized Main TargetBot Loop
-- Uses EventBus-driven cache for reduced CPU usage and better accuracy
-- Only recalculates when cache is dirty (events occurred)
--------------------------------------------------------------------------------

-- Recalculate best target from cache
local function recalculateBestTarget()
  local pos = player:getPosition()
  if not pos then return end
  
  local bestTarget = nil
  local bestPriority = 0
  local totalDanger = 0
  local targetCount = 0
  local debugEnabled = ui.editor.debug:isOn()
  
  -- Use cached creatures if available, otherwise fetch fresh
  local useCache = CreatureCache.monsterCount > 0 and not CreatureCache.dirty
  
  if useCache and now - CreatureCache.lastFullUpdate < CreatureCache.FULL_UPDATE_INTERVAL then
    -- Fast path: use cached data
    for id, data in pairs(CreatureCache.monsters) do
      local creature = data.creature
      if creature and not creature:isDead() and isTargetableCreature(creature) then
        local path = data.path
        if not path then
          local cpos = creature:getPosition()
          path = findPath(pos, cpos, 10, PATH_PARAMS)
          data.path = path
          data.pathTime = now
        end
        
        if path then
          local params = TargetBot.Creature.calculateParams(creature, path)
          
          if params.config then
            targetCount = targetCount + 1
            totalDanger = totalDanger + (params.danger or 0)
            
            if debugEnabled then
              creature:setText(tostring(math.floor(params.priority * 10) / 10))
            end
            
            if params.priority > bestPriority then
              bestPriority = params.priority
              bestTarget = params
            end
          end
        end
      end
    end
  else
    -- Slow path: full refresh from getSpectators
    local creatures = g_map.getSpectatorsInRange(pos, false, 10, 10)
    
    -- Clear and rebuild cache
    CreatureCache.monsters = {}
    CreatureCache.monsterCount = 0
    
    if creatures then
      for i = 1, #creatures do
        local creature = creatures[i]
        if isTargetableCreature(creature) then
          local id = creature:getId()
          local cpos = creature:getPosition()
          local path = findPath(pos, cpos, 10, PATH_PARAMS)
          
          -- Add to cache
          CreatureCache.monsters[id] = {
            creature = creature,
            path = path,
            pathTime = now,
            lastUpdate = now
          }
          CreatureCache.monsterCount = CreatureCache.monsterCount + 1
          
          if path then
            local params = TargetBot.Creature.calculateParams(creature, path)
            
            if params.config then
              targetCount = targetCount + 1
              totalDanger = totalDanger + (params.danger or 0)
              
              if debugEnabled then
                creature:setText(tostring(math.floor(params.priority * 10) / 10))
              end
              
              if params.priority > bestPriority then
                bestPriority = params.priority
                bestTarget = params
              end
            end
          end
        end
      end
    end
    
    CreatureCache.lastFullUpdate = now
  end
  
  -- Update cache state
  CreatureCache.bestTarget = bestTarget
  CreatureCache.bestPriority = bestPriority
  CreatureCache.totalDanger = totalDanger
  CreatureCache.dirty = false
  
  return bestTarget, targetCount, totalDanger
end

-- Main TargetBot loop - optimized with EventBus caching
targetbotMacro = macro(100, function()
  if not config or not config.isOn or not config.isOn() then
    return
  end
  
  local pos = player:getPosition()
  if not pos then return end
  
  -- Periodic cache cleanup
  cleanupCache()
  cleanupPathCache()
  
  -- Handle walking if destination is set
  TargetBot.walk()
  
  -- Check for looting first
  local lootResult = TargetBot.Looting.process()
  if lootResult then
    lastAction = now
    looterStatus = TargetBot.Looting.getStatus and TargetBot.Looting.getStatus() or "Looting"
    return
  else
    looterStatus = ""
  end
  
  -- Get best target (uses cache when possible)
  local bestTarget, targetCount, totalDanger = recalculateBestTarget()
  
  if not bestTarget then
    ui.target.right:setText("-")
    ui.danger.right:setText("0")
    ui.config.right:setText("-")
    dangerValue = 0
    cavebotAllowance = now + 100
    ui.status.right:setText(STATUS_WAITING)
    return
  end
  
  -- Update danger value
  dangerValue = totalDanger
  ui.danger.right:setText(tostring(totalDanger))
  
  -- Attack best target
  if bestTarget.creature and bestTarget.config then
    lastAction = now
    ui.target.right:setText(bestTarget.creature:getName())
    ui.config.right:setText(bestTarget.config.name or "-")
    
    -- Pass lure status for status display
    local isLooting = false
    TargetBot.Creature.attack(bestTarget, targetCount, isLooting)
    
    -- Update status
    if lureEnabled then
      ui.status.right:setText(STATUS_ATTACKING)
    else
      ui.status.right:setText(STATUS_ATTACKING_LURE_OFF)
    end
  else
    ui.target.right:setText("-")
    ui.config.right:setText("-")
    
    -- No target, allow cavebot
    cavebotAllowance = now + 100
    ui.status.right:setText(STATUS_WAITING)
  end
end)

-- Note: Profile restoration is handled early in configs.lua
-- before Config.setup() is called, so the dropdown loads correctly