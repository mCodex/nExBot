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
  storage.foodItems = {3582, 3577}
end

local foodContainer = UI.Container(function(widget, items)
  storage.foodItems = items
end, true)
foodContainer:setHeight(35)
foodContainer:setItems(storage.foodItems)

-- Use food item - works even with closed backpack (hotkey-style)
local function eatFood(foodId)
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
  if player:getRegenerationTime() > 400 or not storage.foodItems[1] then return end
  
  -- Try each configured food item
  for _, foodItem in ipairs(storage.foodItems) do
    local foodId = type(foodItem) == "table" and foodItem.id or foodItem
    if foodId and eatFood(foodId) then
      return
    end
  end
end)
UI.Separator()