--[[
  nExBot Food System
  Intelligent food and potion management with event-driven architecture
  
  Features:
  - Event-driven food consumption
  - Subscribes to health/mana change events
  - Emits food consumed events
  
  Author: nExBot Team
  Version: 1.0.0
]]

local EatFood = {
  lastEatTime = 0,
  eatCooldown = 1000,
  enabled = false,
  healthThreshold = 50,
  manaThreshold = 40,
  subscriptions = {}
}

-- Food database with type and regeneration value
local FOOD_DATA = {
  -- Potions
  [268] = { name = "mana potion", type = "mana", value = 60 },
  [269] = { name = "strong mana potion", type = "mana", value = 150 },
  [7590] = { name = "great mana potion", type = "mana", value = 200 },
  [23373] = { name = "ultimate mana potion", type = "mana", value = 250 },
  [266] = { name = "health potion", type = "health", value = 125 },
  [267] = { name = "strong health potion", type = "health", value = 250 },
  [7591] = { name = "great health potion", type = "health", value = 500 },
  [7588] = { name = "ultimate health potion", type = "health", value = 800 },
  [7618] = { name = "supreme health potion", type = "health", value = 1000 },
  
  -- Regular food
  [3577] = { name = "meat", type = "food", value = 180 },
  [3578] = { name = "fish", type = "food", value = 144 },
  [3582] = { name = "ham", type = "food", value = 360 },
  [3583] = { name = "dragon ham", type = "food", value = 720 },
  [3585] = { name = "cheese", type = "food", value = 108 },
  [3586] = { name = "bread", type = "food", value = 84 },
  [3587] = { name = "roll", type = "food", value = 36 },
  [3592] = { name = "grape", type = "food", value = 72 },
  [3593] = { name = "apple", type = "food", value = 60 },
  [3595] = { name = "banana", type = "food", value = 72 },
  [3596] = { name = "cherry", type = "food", value = 18 },
  [3597] = { name = "mango", type = "food", value = 120 },
  [3598] = { name = "banana", type = "food", value = 72 },
  [3599] = { name = "blueberry", type = "food", value = 18 },
  [3600] = { name = "strawberry", type = "food", value = 36 },
  [3601] = { name = "orange", type = "food", value = 84 },
  [3607] = { name = "brown mushroom", type = "food", value = 108 },
  [3723] = { name = "white mushroom", type = "food", value = 72 },
  [3725] = { name = "fire mushroom", type = "food", value = 216 }
}

function EatFood:new()
  local instance = {
    lastEatTime = 0,
    eatCooldown = 1000,
    enabled = false,
    healthThreshold = 50,
    manaThreshold = 40,
    subscriptions = {}
  }
  setmetatable(instance, { __index = self })
  return instance
end

function EatFood:initialize()
  self.enabled = true
  
  -- Subscribe to health/mana change events if EventBus available
  if nExBot and nExBot.EventBus then
    local eventBus = nExBot.EventBus
    
    -- Subscribe to health changes
    self.subscriptions.health = eventBus:subscribe(
      eventBus.Events.PLAYER_HEALTH_CHANGED,
      function(newHealth, oldHealth)
        if self.enabled and self:shouldEatHealth() then
          self:eat()
        end
      end,
      10 -- Priority
    )
    
    -- Subscribe to mana changes
    self.subscriptions.mana = eventBus:subscribe(
      eventBus.Events.PLAYER_MANA_CHANGED,
      function(newMana, oldMana)
        if self.enabled and self:shouldEatMana() then
          self:eat()
        end
      end,
      10
    )
  end
end

function EatFood:destroy()
  -- Unsubscribe from events
  if nExBot and nExBot.EventBus and self.subscriptions then
    for _, subId in pairs(self.subscriptions) do
      nExBot.EventBus:unsubscribe(subId)
    end
  end
  self.subscriptions = {}
end

function EatFood:canEat()
  if not self.enabled then return false end
  
  local currentTime = now or os.time() * 1000
  if (currentTime - self.lastEatTime) < self.eatCooldown then
    return false
  end
  
  return true
end

function EatFood:shouldEatHealth()
  local healthPercent = hppercent()
  if not healthPercent then return false end
  
  return healthPercent <= self.healthThreshold
end

function EatFood:shouldEatMana()
  local manaPercent = manapercent()
  if not manaPercent then return false end
  
  return manaPercent <= self.manaThreshold
end

function EatFood:findFoodInInventory(foodType)
  local bestFood = nil
  local bestValue = 0
  
  for itemId, foodInfo in pairs(FOOD_DATA) do
    if not foodType or foodInfo.type == foodType then
      local count = itemAmount(itemId)
      if count and count > 0 then
        if foodInfo.value > bestValue then
          bestValue = foodInfo.value
          bestFood = {
            id = itemId,
            name = foodInfo.name,
            type = foodInfo.type,
            value = foodInfo.value
          }
        end
      end
    end
  end
  
  return bestFood
end

function EatFood:findBestFood()
  local healthPercent = hppercent() or 100
  local manaPercent = manapercent() or 100
  
  -- Priority: Critical health
  if healthPercent < 20 then
    return self:findFoodInInventory("health")
  end
  
  -- Priority: Health below threshold
  if self:shouldEatHealth() then
    return self:findFoodInInventory("health")
  end
  
  -- Priority: Mana below threshold
  if self:shouldEatMana() then
    return self:findFoodInInventory("mana")
  end
  
  -- Default: regular food for regeneration
  return self:findFoodInInventory("food")
end

function EatFood:eat()
  if not self:canEat() then
    return false
  end
  
  local food = self:findBestFood()
  if not food then
    return false
  end
  
  -- Use the food item
  local item = findItem(food.id)
  if item then
    use(item)
    self.lastEatTime = now or os.time() * 1000
    
    -- Emit food consumed event
    if nExBot and nExBot.EventBus then
      nExBot.EventBus:emit("food:consumed", food.type, food.name, food.value)
    end
    
    return true
  end
  
  return false
end

function EatFood:setHealthThreshold(percentage)
  self.healthThreshold = math.max(10, math.min(90, percentage))
end

function EatFood:setManaThreshold(percentage)
  self.manaThreshold = math.max(10, math.min(90, percentage))
end

function EatFood:toggle()
  self.enabled = not self.enabled
  return self.enabled
end

function EatFood:isEnabled()
  return self.enabled
end

function EatFood:getFoodCount(foodType)
  local total = 0
  
  for itemId, foodInfo in pairs(FOOD_DATA) do
    if not foodType or foodInfo.type == foodType then
      local count = itemAmount(itemId)
      if count then
        total = total + count
      end
    end
  end
  
  return total
end

return EatFood
