--[[
  ═══════════════════════════════════════════════════════════════════════════
  FOOD MANAGEMENT MODULE
  Version: 2.0.0
  
  Features:
  1. Cast Food (Exevo Pan) - Auto-casts food spell every 2 minutes
  2. Eat Food - Optimized food eating with EventBus integration
  3. Eat from Corpses - Opens recent killed corpses to eat food inside
  
  Principles Applied:
  - SRP: Each feature is a separate, focused component
  - DRY: Shared food lookup, reusable helper functions
  - KISS: Simple, readable logic
  - SOLID: Open for extension, closed for modification
  
  OTClient API Used:
  - player:getRegenerationTime() - Check food buff duration
  - g_game.use(item) - Use food item
  - g_game.open(item) - Open corpse container
  - EventBus - Event-driven architecture for efficiency
  - onCreatureDisappear - Track killed monsters for corpse eating
  ═══════════════════════════════════════════════════════════════════════════
]]

setDefaultTab("HP")

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS (Single Source of Truth)
-- ═══════════════════════════════════════════════════════════════════════════

local FOOD_IDS = {
  -- Mushrooms (common hunting food)
  3725,  -- Brown Mushroom
  3731,  -- Fire Mushroom  
  3723,  -- White Mushroom
  3726,  -- Orange Mushroom
  3728,  -- Dark Mushroom
  -- Meat & Fish
  3582,  -- Ham
  3577,  -- Meat
  3578,  -- Fish
  -- Dairy & Bakery
  3585,  -- Cheese
  3600,  -- Bread
  3606,  -- Cake
  -- Fruits
  3607,  -- Mango
  3592,  -- Grape
  3601,  -- Banana
  3586,  -- Apple
  3595,  -- Pear
  3593,  -- Coconut
  3587,  -- Blueberry
  -- Other common food
  3583,  -- Dragon Ham
  3584,  -- Roasted Meat
  8838,  -- Hydra Tongue
}

-- Corpse IDs that may contain food (skinnable/lootable bodies)
local CORPSE_IDS = {
  -- Common monster corpses
  2920, 2921, 2922, 2923, 2924, 2925, 2926, 2927, 2928, 2929,
  2930, 2931, 2932, 2933, 2934, 2935, 2936, 2937, 2938, 2939,
  2940, 2941, 2942, 2943, 2944, 2945, 2946, 2947, 2948, 2949,
  2950, 2951, 2952, 2953, 2954, 2955, 2956, 2957, 2958, 2959,
  -- Dead bodies (general)
  3058, 3059, 3060, 3061, 3062, 3063, 3064, 3065,
  -- Specific monster corpses with food
  5995, 5996, 5997, 5998, 5999, -- Dragon corpses
  6014, 6015, 6016, 6017, -- Hydra corpses
  6079, 6080, 6081, 6082, -- Beast corpses
}

-- O(1) lookup tables
local FOOD_LOOKUP = {}
for _, id in ipairs(FOOD_IDS) do
  FOOD_LOOKUP[id] = true
end

local CORPSE_LOOKUP = {}
for _, id in ipairs(CORPSE_IDS) do
  CORPSE_LOOKUP[id] = true
end

-- Configuration
local CONFIG = {
  CAST_FOOD_INTERVAL = 120000,    -- 2 minutes in ms
  CAST_FOOD_THRESHOLD = 60,       -- Cast when regen time < 60 seconds
  EAT_FOOD_INTERVAL = 500,        -- Check every 500ms
  EAT_FOOD_THRESHOLD = 400,       -- Eat when regen time < 400 deciseconds (40s)
  MAX_REGEN_TIME = 600,           -- Stop eating at 600 deciseconds (60s)
  CORPSE_SCAN_RANGE = 3,          -- Range to scan for corpses
  CORPSE_OPEN_DELAY = 300,        -- Delay between corpse operations
  CORPSE_EAT_DELAY = 200,         -- Delay after opening corpse to eat
  MAX_CORPSE_AGE_MS = 10000,      -- Max age of tracked corpse (10s)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE MANAGEMENT (Module-private)
-- ═══════════════════════════════════════════════════════════════════════════

local State = {
  lastCastFood = 0,
  lastEatFood = 0,
  lastCorpseCheck = 0,
  recentKills = {},        -- { pos, timestamp } of recently killed monsters
  openedCorpses = {},      -- { ["x,y,z"] = timestamp } of already opened corpses
  corpseContainerOpen = false,
  waitingForCorpse = nil,
  lastEat = 0,             -- Last time we ate food
}

-- Helper to create position key for tracking
local function posKey(pos)
  if not pos then return nil end
  return string.format("%d,%d,%d", pos.x or 0, pos.y or 0, pos.z or 0)
end

-- Check if corpse at position was already opened
local function wasCorpseOpened(pos)
  local key = posKey(pos)
  if not key then return true end  -- If no valid pos, consider it opened
  return State.openedCorpses[key] ~= nil
end

-- Mark corpse as opened
local function markCorpseOpened(pos)
  local key = posKey(pos)
  if not key then return end
  State.openedCorpses[key] = now or 0
end

-- Cleanup old opened corpse entries (older than 30 seconds)
local function cleanupOpenedCorpses()
  local nowMs = now or 0
  local OPENED_CORPSE_EXPIRY = 30000  -- 30 seconds
  for key, timestamp in pairs(State.openedCorpses) do
    if (nowMs - timestamp) > OPENED_CORPSE_EXPIRY then
      State.openedCorpses[key] = nil
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS (DRY: Reusable utilities)
-- ═══════════════════════════════════════════════════════════════════════════

-- Get player's current regeneration time in deciseconds
local function getRegenTime()
  if player and player.getRegenerationTime then
    local ok, regen = pcall(function() return player:getRegenerationTime() end)
    if ok then return regen end
  end
  -- Fallback to player:regeneration()
  if player and player.regeneration then
    local ok, regen = pcall(function() return player:regeneration() end)
    if ok then return regen end
  end
  -- Fallback to global function if available
  if regenerationTime then
    local ok, regen = pcall(regenerationTime)
    if ok then return regen end
  end
  return 0
end

-- Check if player can cast spells (not exhausted, has mana)
local function canCastSpell(spell, manaCost)
  if not player then return false end
  
  -- Check mana
  local playerMana = 0
  if player.getMana then
    local ok, m = pcall(function() return player:getMana() end)
    if ok then playerMana = m end
  elseif mana then
    playerMana = mana()
  end
  
  if playerMana < (manaCost or 50) then return false end
  
  -- Check if canCast function exists and spell is ready
  if canCast then
    local ok, result = pcall(canCast, spell)
    if ok and result then return true end
  end
  
  return true  -- Default to allowing cast
end

-- Get player vocation (1=EK, 2=RP, 3=MS, 4=ED + promoted)
local function getVocation()
  if voc then
    local ok, v = pcall(voc)
    if ok then return v end
  end
  if player and player.getVocation then
    local ok, v = pcall(function() return player:getVocation() end)
    if ok then return v end
  end
  return 0
end

-- Check if vocation can use Exevo Pan (not knights - voc 1/11)
local function canUseFoodSpell()
  local v = getVocation()
  return v ~= 1 and v ~= 11  -- Knights can't cast exevo pan
end

-- Find food item in all open containers
local function findFoodInContainers()
  local containers = getContainers and getContainers() or (g_game and g_game.getContainers and g_game.getContainers())
  if not containers then return nil end
  
  for _, container in pairs(containers) do
    if container then
      local items = container.getItems and container:getItems()
      if items then
        for _, item in pairs(items) do
          if item and item.getId then
            local id = item:getId()
            if FOOD_LOOKUP[id] then
              return item
            end
          end
        end
      end
    end
  end
  return nil
end

-- Find food by ID using itemAmount (fallback)
local function findFoodById()
  for _, foodId in ipairs(FOOD_IDS) do
    if itemAmount and itemAmount(foodId) > 0 then
      return foodId
    end
  end
  return nil
end

-- Clean up old kill records
local function cleanupRecentKills()
  local nowMs = (now or 0)
  local cleaned = {}
  for _, kill in ipairs(State.recentKills) do
    if (nowMs - kill.timestamp) < CONFIG.MAX_CORPSE_AGE_MS then
      table.insert(cleaned, kill)
    end
  end
  State.recentKills = cleaned
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CAST FOOD FEATURE (Exevo Pan)
-- Only for non-knight vocations
-- ═══════════════════════════════════════════════════════════════════════════

local castFoodMacro = nil

if canUseFoodSpell() then
  castFoodMacro = macro(CONFIG.CAST_FOOD_INTERVAL, "Cast Food", function()
    -- Check regeneration time (in deciseconds)
    local regenTime = getRegenTime()
    
    -- Only cast if regen time is low (< 60 seconds = 600 deciseconds)
    if regenTime > CONFIG.CAST_FOOD_THRESHOLD * 10 then
      return
    end
    
    -- Check if we can cast the spell
    if not canCastSpell("exevo pan", 50) then
      return
    end
    
    -- Cast the food spell
    if cast then
      cast("exevo pan", 5000)  -- 5 second exhaust
    elseif say then
      say("exevo pan")
    end
    
    State.lastCastFood = now
  end)
  
  -- Add tooltip
  if castFoodMacro and castFoodMacro.button then
    castFoodMacro.button:setTooltip(
      "Automatically casts 'Exevo Pan' to create food.\n" ..
      "Runs every 2 minutes when regeneration < 60 seconds.\n" ..
      "Requires 50 mana and support spell cooldown.\n" ..
      "Not available for Knights."
    )
  end
  
  -- Register with BotDB for persistence
  if BotDB and BotDB.registerMacro then
    BotDB.registerMacro(castFoodMacro, "castFood")
  end
  
  UI.Separator()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EAT FOOD FEATURE (Optimized with EventBus)
-- ═══════════════════════════════════════════════════════════════════════════

-- Event-driven eating: React to regeneration changes
local function setupRegenEventListener()
  if not EventBus then return end
  
  -- Listen for regeneration time changes (if available)
  EventBus.on("player:regen", function(newRegen, oldRegen)
    -- Only trigger eating when regen drops below threshold
    if newRegen < CONFIG.EAT_FOOD_THRESHOLD and oldRegen >= CONFIG.EAT_FOOD_THRESHOLD then
      schedule(50, function()
        tryEat()
      end)
    end
  end, 50)
end

-- Eat food until full
local function eatUntilFull()
  local maxEats = 10
  local eatCount = 0
  
  local function eatOnce()
    if eatCount >= maxEats then return end
    
    -- Check regeneration time
    local regenTime = getRegenTime()
    if regenTime >= CONFIG.MAX_REGEN_TIME then
      return  -- Already full
    end
    
    -- Find and eat food
    local food = findFoodInContainers()
    if food then
      g_game.use(food)
      eatCount = eatCount + 1
      schedule(CONFIG.EAT_FOOD_INTERVAL - 300, eatOnce)  -- Continue eating
      return
    end
    
    -- Fallback: Use by ID
    local foodId = findFoodById()
    if foodId then
      if use then use(foodId) end
      eatCount = eatCount + 1
      schedule(CONFIG.EAT_FOOD_INTERVAL - 300, eatOnce)
    end
  end
  
  eatOnce()
end

-- Simple single eat (for macro polling)
local function tryEat()
  -- Cooldown to prevent spam eating
  if now - State.lastEat < 10000 then  -- 10 seconds cooldown
    return false
  end
  
  local regenTime = getRegenTime()
  if regenTime >= CONFIG.EAT_FOOD_THRESHOLD then
    return false
  end
  
  local food = findFoodInContainers()
  if food then
    g_game.use(food)
    State.lastEat = now
    return true
  end
  
  local foodId = findFoodById()
  if foodId and use then
    use(foodId)
    State.lastEat = now
    return true
  end
  
  return false
end

-- Main eat food macro
local eatFoodMacro = macro(CONFIG.EAT_FOOD_INTERVAL, "Eat Food", function()
  local regenTime = getRegenTime()
  
  -- Skip if regeneration is sufficient
  if regenTime >= CONFIG.EAT_FOOD_THRESHOLD then
    return
  end
  
  -- Eat food
  tryEat()
end)

-- Add tooltip
if eatFoodMacro and eatFoodMacro.button then
  eatFoodMacro.button:setTooltip(
    "Automatically eats food when regeneration < 40 seconds.\n" ..
    "Runs every 500ms and eats one piece at a time.\n" ..
    "Searches all open containers for supported food items.\n" ..
    "Uses EventBus for optimized performance.\n" ..
    "10 second cooldown between eats to prevent spam."
  )
end

-- Register with BotDB for persistence, eat immediately on enable
if BotDB and BotDB.registerMacro then
  BotDB.registerMacro(eatFoodMacro, "eatFood", function()
    schedule(100, tryEat)
  end)
end

-- Setup event listener for reactive eating
setupRegenEventListener()

UI.Separator()

-- ═══════════════════════════════════════════════════════════════════════════
-- EAT FROM CORPSES FEATURE
-- Opens recently killed monster corpses and eats food from them
-- Uses monster:killed event which fires when monster health reaches 0%
-- This is more reliable than monster:disappear as it captures the exact death position
-- ═══════════════════════════════════════════════════════════════════════════

-- Track monster deaths using EventBus monster:killed event
local function setupCorpseTracking()
  if not EventBus then 
    warn("[EatFood] EventBus not available, corpse tracking disabled")
    return 
  end
  
  -- PRIMARY: Listen for monster:killed event (health dropped to 0%)
  -- This is the most reliable way to track kills - fires at exact moment of death
  EventBus.on("monster:killed", function(creature, creaturePos, creatureName)
    if not creaturePos then return end
    
    local killPos = { x = creaturePos.x, y = creaturePos.y, z = creaturePos.z }
    
    -- Skip if this position was already opened
    if wasCorpseOpened(killPos) then
      return
    end
    
    -- Record the kill position
    table.insert(State.recentKills, {
      pos = killPos,
      timestamp = now or 0,
      name = creatureName or "Unknown"
    })
    
    -- Limit queue size
    while #State.recentKills > 20 do
      table.remove(State.recentKills, 1)
    end
  end, 20)  -- Priority 20
  
  -- FALLBACK: Also check EventBus.getKilledMonsters() for direct access
  -- This provides redundancy if event subscription fails
end

-- Find corpse on tile - improved detection
local function findCorpseOnTile(tilePos)
  if not g_map then return nil end
  
  local tile = nil
  if g_map.getTile then
    tile = g_map.getTile(tilePos)
  end
  if not tile then return nil end
  
  -- Method 1: Get top usable thing (most reliable for corpses)
  local thing = nil
  if tile.getTopUseThing then
    local ok, t = pcall(function() return tile:getTopUseThing() end)
    if ok then thing = t end
  end
  
  -- Method 2: Fallback to top thing
  if not thing and tile.getTopThing then
    local ok, t = pcall(function() return tile:getTopThing() end)
    if ok then thing = t end
  end
  
  if not thing then return nil end
  
  local id = 0
  if thing.getId then
    local ok, i = pcall(function() return thing:getId() end)
    if ok then id = i end
  end
  
  -- Check if it's a container (corpses are containers)
  if thing.isContainer then
    local ok, isContainer = pcall(function() return thing:isContainer() end)
    if ok and isContainer then
      return thing
    end
  end
  
  -- Check against known corpse IDs
  if CORPSE_LOOKUP[id] then
    return thing
  end
  
  -- Method 3: Check all items on the tile for containers/corpses
  if tile.getItems then
    local ok, items = pcall(function() return tile:getItems() end)
    if ok and items then
      for _, item in pairs(items) do
        if item and item.isContainer then
          local okC, isC = pcall(function() return item:isContainer() end)
          if okC and isC then
            return item
          end
        end
        if item and item.getId then
          local okId, itemId = pcall(function() return item:getId() end)
          if okId and CORPSE_LOOKUP[itemId] then
            return item
          end
        end
      end
    end
  end
  
  return nil
end

-- Handle container open event to eat food
local function onCorpseContainerOpen(container)
  if not State.corpseContainerOpen then return end
  
  -- Check if this is a corpse container
  if not container then return end
  
  local items = container.getItems and container:getItems()
  if not items then return end
  
  -- Look for food in the corpse
  for _, item in pairs(items) do
    if item and item.getId then
      local id = item:getId()
      if FOOD_LOOKUP[id] then
        -- Eat the food
        schedule(CONFIG.CORPSE_EAT_DELAY, function()
          g_game.use(item)
          State.corpseContainerOpen = false
          
          -- Close the corpse container after eating
          schedule(200, function()
            pcall(function() g_game.close(container) end)
          end)
        end)
        return
      end
    end
  end
  
  -- No food found, close container
  State.corpseContainerOpen = false
  schedule(100, function()
    pcall(function() g_game.close(container) end)
  end)
end

-- Main corpse eating function
local function tryEatFromCorpse()
  -- Check if we need food
  local regenTime = getRegenTime()
  if regenTime >= CONFIG.EAT_FOOD_THRESHOLD then
    return false  -- Don't need food
  end
  
  -- Cleanup old kills and opened corpses
  cleanupRecentKills()
  cleanupOpenedCorpses()
  
  -- Also merge in kills from EventBus.getKilledMonsters() as fallback
  if EventBus and EventBus.getKilledMonsters then
    local ebKills = EventBus.getKilledMonsters()
    if ebKills then
      for id, data in pairs(ebKills) do
        -- Skip if this corpse was already opened
        if data.pos and wasCorpseOpened(data.pos) then
          -- Already handled this corpse, skip
        else
          -- Check if this kill is already in our list (by position)
          local found = false
          for _, k in ipairs(State.recentKills) do
            if k.pos and data.pos and 
               k.pos.x == data.pos.x and 
               k.pos.y == data.pos.y and 
               k.pos.z == data.pos.z then
              found = true
              break
            end
          end
          if not found and data.pos then
            table.insert(State.recentKills, {
              pos = data.pos,
              timestamp = data.timestamp,
              name = data.name
            })
          end
        end
      end
    end
  end
  
  if #State.recentKills == 0 then
    return false  -- No recent kills
  end
  
  -- Get player position
  local playerPos = nil
  if player and player.getPosition then
    local ok, p = pcall(function() return player:getPosition() end)
    if ok then playerPos = p end
  elseif pos then
    local ok, p = pcall(pos)
    if ok then playerPos = p end
  end
  if not playerPos and g_game and g_game.getLocalPlayer then
    local ok, lp = pcall(g_game.getLocalPlayer)
    if ok and lp then
      local okP, p = pcall(function() return lp:getPosition() end)
      if okP then playerPos = p end
    end
  end
  
  if not playerPos then return false end
  
  -- Find nearest corpse from recent kills
  for i = #State.recentKills, 1, -1 do
    local kill = State.recentKills[i]
    if kill and kill.pos then
      -- Skip if this corpse was already opened
      if wasCorpseOpened(kill.pos) then
        table.remove(State.recentKills, i)
      elseif kill.pos.z == playerPos.z then
        -- Check distance
        local dist = math.max(
          math.abs(kill.pos.x - playerPos.x),
          math.abs(kill.pos.y - playerPos.y)
        )
        
        if dist <= CONFIG.CORPSE_SCAN_RANGE then
          -- Create position object for tile lookup
          local tilePos = { x = kill.pos.x, y = kill.pos.y, z = kill.pos.z }
          
          -- Try to find corpse on this tile
          local corpse = findCorpseOnTile(tilePos)
          if corpse then
            -- Mark this corpse as opened BEFORE opening it
            markCorpseOpened(tilePos)
            
            -- Open the corpse
            State.corpseContainerOpen = true
            State.waitingForCorpse = tilePos
            
            local openOk = pcall(function() g_game.open(corpse) end)
            if not openOk then
              -- Try alternative method
              pcall(function() g_game.use(corpse) end)
            end
            
            -- Remove from queue
            table.remove(State.recentKills, i)
            
            return true
          else
            -- Corpse gone or not found, mark as opened anyway and remove
            markCorpseOpened(kill.pos)
            table.remove(State.recentKills, i)
          end
        end
      end
    end
  end
  
  return false
end

-- Setup container open listener for corpse eating
local function setupCorpseContainerListener()
  if onContainerOpen then
    onContainerOpen(function(container, previousContainer)
      if State.corpseContainerOpen then
        onCorpseContainerOpen(container)
      end
    end)
  end
end

-- Eat from corpses macro
local eatFromCorpsesMacro = macro(1000, "Eat from Corpses", function()
  -- Skip if not needed
  local regenTime = getRegenTime()
  if regenTime >= CONFIG.EAT_FOOD_THRESHOLD then
    return
  end
  
  -- Skip if already waiting for corpse
  if State.corpseContainerOpen then
    return
  end
  
  -- Try to eat from corpse
  tryEatFromCorpse()
end)

-- Add tooltip
if eatFromCorpsesMacro and eatFromCorpsesMacro.button then
  eatFromCorpsesMacro.button:setTooltip(
    "Opens recently killed monster corpses to eat food inside.\n" ..
    "Tracks monster deaths using EventBus.\n" ..
    "Only opens corpses within " .. CONFIG.CORPSE_SCAN_RANGE .. " tiles.\n" ..
    "Automatically closes corpse after eating."
  )
end

-- Register with BotDB for persistence
if BotDB and BotDB.registerMacro then
  BotDB.registerMacro(eatFromCorpsesMacro, "eatFromCorpses")
end

-- Setup tracking and listeners
setupCorpseTracking()
setupCorpseContainerListener()

UI.Separator()

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORTS (For other modules to use)
-- ═══════════════════════════════════════════════════════════════════════════

nExBot = nExBot or {}
nExBot.Food = {
  getRegenTime = getRegenTime,
  findFood = findFoodInContainers,
  eatUntilFull = eatUntilFull,
  tryEat = tryEat,
  tryEatFromCorpse = tryEatFromCorpse,
  FOOD_IDS = FOOD_IDS,
  FOOD_LOOKUP = FOOD_LOOKUP,
}
