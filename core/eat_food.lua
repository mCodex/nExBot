--[[
  Eat Food Module - Ultra Simple
  
  Eats food every 3 minutes automatically.
  Searches all open containers for any food item.
]]

setDefaultTab("HP")

-- ═══════════════════════════════════════════════════════════════════════════
-- FOOD ITEMS
-- ═══════════════════════════════════════════════════════════════════════════

local FOOD_IDS = {
  3725,  -- Brown Mushroom
  3731,  -- Fire Mushroom  
  3723,  -- White Mushroom
  3726,  -- Orange Mushroom
  3728,  -- Dark Mushroom
  3582,  -- Ham
  3577,  -- Meat
  3585,  -- Cheese
  3600,  -- Bread
  3578,  -- Fish
  3607,  -- Mango
  3592,  -- Grape
  3601,  -- Banana
  3586,  -- Apple
}

-- O(1) lookup
local FOOD_LOOKUP = {}
for _, id in ipairs(FOOD_IDS) do
  FOOD_LOOKUP[id] = true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SIMPLE EAT FUNCTION
-- ═══════════════════════════════════════════════════════════════════════════

-- Find a food item in containers
local function findFood()
  -- Method 1: Search all open containers
  local containers = getContainers()
  if containers then
    for _, container in pairs(containers) do
      if container then
        local items = container:getItems()
        if items then
          for _, item in pairs(items) do
            if item and FOOD_LOOKUP[item:getId()] then
              return item
            end
          end
        end
      end
    end
  end
  return nil
end

-- Eat until full (regeneration time >= 10 minutes = 600 seconds)
-- This eats multiple pieces of food with small delays
local function eatUntilFull()
  local maxEats = 10  -- Safety limit to prevent infinite loop
  local eatCount = 0
  
  local function eatOnce()
    if eatCount >= maxEats then
      return -- Safety stop
    end
    
    -- Check regeneration time - stop if >= 10 minutes (600 seconds)
    local regenTime = regenerationTime and regenerationTime() or 0
    if regenTime >= 600 then
      return -- Already full enough
    end
    
    -- Find and eat food
    local food = findFood()
    if food then
      g_game.use(food)
      eatCount = eatCount + 1
      
      -- Schedule next eat after a small delay (to let the game process)
      schedule(200, eatOnce)
    else
      -- Try fallback method with use() by ID
      for _, foodId in ipairs(FOOD_IDS) do
        if itemAmount(foodId) > 0 then
          use(foodId)
          eatCount = eatCount + 1
          schedule(200, eatOnce)
          return
        end
      end
    end
  end
  
  -- Start eating
  eatOnce()
end

-- Simple single eat for compatibility
local function tryEat()
  local food = findFood()
  if food then
    g_game.use(food)
    return true
  end
  
  -- Fallback
  for _, foodId in ipairs(FOOD_IDS) do
    if itemAmount(foodId) > 0 then
      use(foodId)
      return true
    end
  end
  
  return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN MACRO - Every 3 minutes (180000 ms)
-- ═══════════════════════════════════════════════════════════════════════════

local eatFoodMacro = macro(180000, "Eat Food", function()
  eatUntilFull()
end)

-- Add tooltip explaining functionality
if eatFoodMacro and eatFoodMacro.button then
  eatFoodMacro.button:setTooltip("Automatically eats food until full (10+ min regen).\nRuns every 3 minutes and eats multiple pieces.\nSearches all open containers for supported food items.\nSupports: Brown Mushroom, Ham, Fish, Bread, Cheese, and more.")
end

-- Setup persistence with onEnable callback to eat immediately
BotDB.registerMacro(eatFoodMacro, "eatFood", function()
  eatUntilFull()
end)

UI.Separator()
