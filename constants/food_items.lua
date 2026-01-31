--[[
  Food Items Constants - Single Source of Truth
  
  Consolidates food item IDs and their regeneration values
  that were duplicated in eat_food.lua and looting.lua
  
  USAGE:
    dofile("constants/food_items.lua")  -- Loads FoodItems globally
    if FoodItems.isFood(itemId) then ... end
    local regen = FoodItems.getRegenTime(itemId)
]]

-- Declare as global (not local) so it's accessible after dofile
FoodItems = FoodItems or {}

-- ============================================================================
-- FOOD ITEMS WITH REGENERATION TIME (seconds)
-- Higher value = more filling
-- ============================================================================

FoodItems.FOODS = {
  -- ═══════════════════════════════════════════════════════════════════════
  -- BASIC FOODS (Low regen)
  -- ═══════════════════════════════════════════════════════════════════════
  [3577] = 60,    -- Meat
  [3578] = 60,    -- Fish
  [3582] = 60,    -- Ham
  [3600] = 30,    -- Cheese
  [3601] = 30,    -- Bread
  [3606] = 40,    -- Egg
  [3607] = 120,   -- Dragon Ham
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- FRUITS AND VEGETABLES
  -- ═══════════════════════════════════════════════════════════════════════
  [3584] = 60,    -- Carrot
  [3585] = 30,    -- Blueberry
  [3586] = 30,    -- Strawberry
  [3587] = 60,    -- Pumpkin
  [3593] = 60,    -- Coconut
  [3595] = 60,    -- Banana
  [3596] = 60,    -- Cherry
  [3597] = 60,    -- Grapes
  [3598] = 60,    -- Watermelon
  [3599] = 60,    -- Apple
  [3602] = 60,    -- Orange
  [8841] = 30,    -- Candy
  [9005] = 30,    -- Gingerbread Man
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- COOKED FOODS (Medium regen)
  -- ═══════════════════════════════════════════════════════════════════════
  [3581] = 180,   -- Cookie
  [3583] = 120,   -- Salmon
  [3588] = 60,    -- Fried Fish
  [3589] = 90,    -- Honeycomb
  [3590] = 120,   -- Cake
  [3591] = 144,   -- Birthday Cake
  [3592] = 144,   -- Wedding Cake
  [3594] = 60,    -- Roasted Meat
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- PREMIUM FOODS (High regen)
  -- ═══════════════════════════════════════════════════════════════════════
  [8844] = 360,   -- Roast Pork
  [8845] = 420,   -- Roasted Beef
  [8847] = 300,   -- Rice Ball
  [10454] = 300,  -- Roasted Dragon
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- SPECIAL FOODS
  -- ═══════════════════════════════════════════════════════════════════════
  [12540] = 600,  -- Anniversary Cake
  [12541] = 600,  -- Special Cake
  [8112] = 300,   -- Northern Pike
  [8113] = 300,   -- Green Perch
  [8114] = 300,   -- Rainbow Trout
  [11681] = 360,  -- Blessed Steak
  [11682] = 420,  -- Winter Wolf Loin
  
  -- ═══════════════════════════════════════════════════════════════════════
  -- BROWN MUSHROOMS AND OTHER
  -- ═══════════════════════════════════════════════════════════════════════
  [3725] = 144,   -- Brown Mushroom
  [3726] = 144,   -- White Mushroom
  [3727] = 144,   -- Red Mushroom
  [3728] = 144,   -- Orange Mushroom
  [3723] = 180,   -- Fire Mushroom
  [3724] = 180,   -- Green Mushroom
}

-- Simple lookup table for quick checks
FoodItems.FOOD_IDS = {}
for id, _ in pairs(FoodItems.FOODS) do
  FoodItems.FOOD_IDS[id] = true
end

-- ============================================================================
-- FOOD PRIORITY (what to eat first)
-- Higher priority = eat first (lower regen time foods first)
-- ============================================================================

local priorityCache = nil

local function buildPriorityCache()
  if priorityCache then return priorityCache end
  
  priorityCache = {}
  for id, regen in pairs(FoodItems.FOODS) do
    priorityCache[#priorityCache + 1] = { id = id, regen = regen }
  end
  
  -- Sort by regen time ascending (eat low-value food first)
  table.sort(priorityCache, function(a, b)
    return a.regen < b.regen
  end)
  
  return priorityCache
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
  Check if item ID is food
  @param itemId number
  @return boolean
]]
function FoodItems.isFood(itemId)
  return FoodItems.FOOD_IDS[itemId] == true
end

--[[
  Get regeneration time for food
  @param itemId number
  @return number seconds or nil
]]
function FoodItems.getRegenTime(itemId)
  return FoodItems.FOODS[itemId]
end

--[[
  Get all food IDs sorted by priority (eat order)
  @return array of {id, regen}
]]
function FoodItems.getPriorityList()
  return buildPriorityCache()
end

--[[
  Get food item IDs as simple array
  @return array of item IDs
]]
function FoodItems.getAllIds()
  local ids = {}
  for id, _ in pairs(FoodItems.FOOD_IDS) do
    ids[#ids + 1] = id
  end
  return ids
end

--[[
  Find best food to eat from container
  @param container Container object
  @return Item or nil, position
]]
function FoodItems.findBestFood(container)
  if not container then return nil, nil end
  
  local bestFood = nil
  local bestRegen = 999999
  local bestPos = nil
  
  local items = container:getItems()
  if not items then return nil, nil end
  
  for i, item in ipairs(items) do
    local id = item:getId()
    local regen = FoodItems.FOODS[id]
    if regen and regen < bestRegen then
      bestFood = item
      bestRegen = regen
      bestPos = i - 1  -- 0-indexed position
    end
  end
  
  return bestFood, bestPos
end

return FoodItems
