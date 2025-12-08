setDefaultTab("HP")
if voc() ~= 1 and voc() ~= 11 then
    if storage.foodItems then
        local t = {}
        for i, v in pairs(storage.foodItems) do
            if not table.find(t, v.id) then
                table.insert(t, v.id)
            end
        end
        local foodItems = { 3607, 3585, 3592, 3600, 3601 }
        for i, item in pairs(foodItems) do
            if not table.find(t, item) then
                table.insert(storage.foodItems, item)
            end
        end
    end
    macro(500, "Cast Food", function()
        if player:getRegenerationTime() <= 400 then
            cast("exevo pan", 5000)
        end
    end)
end

UI.Label("Eatable items:")
if type(storage.foodItems) ~= "table" then
  storage.foodItems = {3582, 3577, 3585, 3600, 3578}  -- ham, meat, apple, bread, fish
end

local foodContainer = UI.Container(function(widget, items)
  storage.foodItems = items
end, true)
foodContainer:setHeight(35)
foodContainer:setItems(storage.foodItems)

-- Use food item - works even with closed backpack (hotkey-style)
local function eatFood(foodId)
  if not foodId or foodId == 0 then return false end
  
  -- Method 1: Use inventory item directly (works without open backpack)
  if g_game.useInventoryItem then
    g_game.useInventoryItem(foodId)
    return true
  end
  
  -- Method 2: Fallback - find food in open containers
  local food = findItem(foodId)
  if food then
    g_game.use(food)
    return true
  end
  
  return false
end

macro(500, "Eat Food", function()
  if not player then return end
  if player:getRegenerationTime() > 400 then return end
  if not storage.foodItems then return end
  
  -- Handle both array and table formats
  local items = storage.foodItems
  if type(items) ~= "table" then return end
  
  -- Try each configured food item
  for k, foodItem in pairs(items) do
    local foodId = nil
    if type(foodItem) == "table" then
      foodId = foodItem.id or foodItem[1]
    elseif type(foodItem) == "number" then
      foodId = foodItem
    end
    if foodId and foodId > 0 then
      if eatFood(foodId) then
        return
      end
    end
  end
end)
UI.Separator()