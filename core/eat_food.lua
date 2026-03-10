--[[
  ═══════════════════════════════════════════════════════════════════════════
  FOOD MANAGEMENT MODULE
  Version: 2.1.0
  
  Features:
  1. Cast Food (Exevo Pan) - Auto-casts food spell every 2 minutes
  2. Eat Food - Optimized food eating with EventBus integration
  
  Note: "Eat from Corpses" is handled exclusively by TargetBot (Target tab).
  
  Principles Applied:
  - SRP: Each feature is a separate, focused component
  - DRY: Shared food lookup from constants/food_items.lua, reusable helper functions
  - KISS: Simple, readable logic
  - SOLID: Open for extension, closed for modification
  
  OTClient API Used:
  - player:getRegenerationTime() - Check food buff duration
  - g_game.use(item) - Use food item
  - EventBus - Event-driven architecture for efficiency
  ═══════════════════════════════════════════════════════════════════════════
]]

setDefaultTab("HP")

-- Use centralized constants (dofile loads FoodItems globally)
if not FoodItems then
  dofile("constants/food_items.lua")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS (Use centralized FoodItems)
-- ═══════════════════════════════════════════════════════════════════════════

-- Get food IDs array from FoodItems
local FOOD_IDS = {}
for id, _ in pairs(FoodItems.FOODS) do
  FOOD_IDS[#FOOD_IDS + 1] = id
end

-- O(1) lookup table (FOOD_LOOKUP uses FoodItems.FOOD_IDS directly)
local FOOD_LOOKUP = FoodItems.FOOD_IDS

-- Configuration
local CONFIG = {
  CAST_FOOD_INTERVAL = 120000,    -- 2 minutes in ms
  CAST_FOOD_THRESHOLD = 60,       -- Cast when regen time < 60 seconds
  EAT_FOOD_INTERVAL = 500,        -- Check every 500ms
  EAT_FOOD_THRESHOLD = 400,       -- Eat when regen time < 400 deciseconds (40s)
  MAX_REGEN_TIME = 600,           -- Stop eating at 600 deciseconds (60s)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE MANAGEMENT (Module-private)
-- ═══════════════════════════════════════════════════════════════════════════

local State = {
  lastCastFood = 0,
  lastEatFood = 0,
  lastEat = 0,             -- Last time we ate food
}

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

-- ═══════════════════════════════════════════════════════════════════════════
-- CAST FOOD FEATURE (Exevo Pan)
-- Only for non-knight vocations
-- ═══════════════════════════════════════════════════════════════════════════

-- Food Management heading
setupUI([[
NxBotSection
  height: 24
  margin-top: 10

  NxHeading
    id: heading
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    !text: tr('Food')
]])

local castFoodEnabled = false

if canUseFoodSpell() then
  local castFoodMacro = macro(CONFIG.CAST_FOOD_INTERVAL, function()
    if not castFoodEnabled then return end
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

  local castFoodUI = setupUI([[
NxBotSection
  height: 30

  NxSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    margin-top: 0
    !text: tr('Cast Food')
]])

  castFoodUI.title.onClick = function(widget)
    castFoodEnabled = not castFoodEnabled
    widget:setOn(castFoodEnabled)
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
      CharacterDB.set("macros.castFood", castFoodEnabled)
    else
      BotDB.set("macros.castFood", castFoodEnabled)
    end
  end

  local savedCastFoodState = (function()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
      return CharacterDB.get("macros.castFood") == true
    end
    return BotDB.get("macros.castFood") == true
  end)()
  if savedCastFoodState then
    castFoodEnabled = true
    castFoodUI.title:setOn(true)
  end
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

-- Eat food handler function (shared by UnifiedTick and fallback macro)
local function eatFoodHandler()
  local regenTime = getRegenTime()
  
  -- Skip if regeneration is sufficient
  if regenTime >= CONFIG.EAT_FOOD_THRESHOLD then
    return
  end
  
  -- Eat food
  tryEat()
end

-- Main eat food - use UnifiedTick if available
local eatFoodEnabled = false
if UnifiedTick and UnifiedTick.register then
  -- Register with UnifiedTick for consolidated tick management
  UnifiedTick.register("eat_food", {
    interval = CONFIG.EAT_FOOD_INTERVAL,
    priority = UnifiedTick.Priority.LOW,
    handler = eatFoodHandler,
    group = "tools"
  })
  -- Start disabled; state restored below
  UnifiedTick.setEnabled("eat_food", false)
else
  -- Fallback: nameless macro guarded by enabled flag
  macro(CONFIG.EAT_FOOD_INTERVAL, function()
    if not eatFoodEnabled then return end
    eatFoodHandler()
  end)
end

local eatFoodUI = setupUI([[
NxBotSection
  height: 30

  NxSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    margin-top: 0
    !text: tr('Eat Food')
]])

eatFoodUI.title.onClick = function(widget)
  eatFoodEnabled = not eatFoodEnabled
  widget:setOn(eatFoodEnabled)
  if UnifiedTick then
    UnifiedTick.setEnabled("eat_food", eatFoodEnabled)
  end
  if eatFoodEnabled then
    schedule(100, tryEat)
  end
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("macros.eatFood", eatFoodEnabled)
  else
    BotDB.set("macros.eatFood", eatFoodEnabled)
  end
end

local savedEatFoodState = (function()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    return CharacterDB.get("macros.eatFood") == true
  end
  return BotDB.get("macros.eatFood") == true
end)()
if savedEatFoodState then
  eatFoodEnabled = true
  eatFoodUI.title:setOn(true)
  if UnifiedTick then
    UnifiedTick.setEnabled("eat_food", true)
  end
  schedule(100, tryEat)
end

-- Setup event listener for reactive eating
setupRegenEventListener()

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORTS (For other modules to use)
-- ═══════════════════════════════════════════════════════════════════════════

nExBot = nExBot or {}
nExBot.Food = {
  getRegenTime = getRegenTime,
  findFood = findFoodInContainers,
  eatUntilFull = eatUntilFull,
  tryEat = tryEat,
  FOOD_IDS = FOOD_IDS,
  FOOD_LOOKUP = FOOD_LOOKUP,
}
