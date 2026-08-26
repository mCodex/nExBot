---@diagnostic disable: undefined-global
local zChanging = nExBot.zChanging or function() return false end
local panelName = "pushmax"
if not storage[panelName] then
  storage[panelName] = {
    enabled = true,
    pushDelay = 1060,
    pushMaxRuneId = 3188,
    mwallBlockId = 2128,
    pushMaxKey = "PageUp"
  }
end

local config = storage[panelName]
PushMax = {
  config = config,
  isOn = function() return config.enabled == true end,
  setOn = function() config.enabled = true end,
  setOff = function() config.enabled = false end,
  toggle = function() config.enabled = not config.enabled return config.enabled end,
  getConfig = function() return config end,
  setConfig = function(key, value) config[key] = value end
}

PushMax.show = function() end

-- variables for config
local fieldTable = {2118, 105, 2122}
local cleanTile = nil

-- scripts 

local targetTile
local pushTarget

local resetData = function()
  for i, tile in pairs(g_map.getTiles(posz())) do
    if tile:getText() == "TARGET" or tile:getText() == "DEST" or tile:getText() == "CLEAR" then
      tile:setText('')
    end
  end
  pushTarget = nil
  targetTile = nil
  cleanTile = nil
end

local getCreatureById = function(id)
  for i, spec in ipairs(SafeCall.global("getSpectators") or {}) do
    if spec:getId() == id then
      return spec
    end
  end
  return false
end

local isNotOk = function(t,tile)
  local tileItems = {}

  for i, item in pairs(tile:getItems()) do
    table.insert(tileItems, item:getId())
  end
  for i, field in ipairs(t) do
    if table.find(tileItems, field) then
      return true
    end
  end
  return false
end

local isOk = function(a,b)
  return getDistanceBetween(a,b) == 1
end

-- to mark
local hold = 0
onKeyDown(function(keys)
  if not config.enabled then return end
  if keys ~= config.pushMaxKey then return end
  hold = now
  local tile = getTileUnderCursor()
  if not tile then return end
  if pushTarget and targetTile then
    resetData()
    return
  end
  local creature = tile:getCreatures()[1]
  if not pushTarget and creature then
    pushTarget = creature
    if pushTarget then
      tile:setText('TARGET')
      pushTarget:setMarked('#00FF00')
    end
  elseif not targetTile and pushTarget then
    if pushTarget and getDistanceBetween(tile:getPosition(),pushTarget:getPosition()) ~= 1 then
      resetData()
      return
    else
      tile:setText('DEST')
      targetTile = tile
    end
  end
end)

-- mark tile to throw anything from it
onKeyPress(function(keys)
  if not config.enabled then return end
  if keys ~= config.pushMaxKey then return end
  local tile = getTileUnderCursor()
  if not tile then return end

  if (hold - now) < -2500 then
    if cleanTile and tile ~= cleanTile then
      resetData()
    elseif not cleanTile then
      cleanTile = tile
      tile:setText("CLEAR")
    end
  end
  hold = 0
end)

onCreaturePositionChange(function(creature, newPos, oldPos)
  if not config.enabled then return end
  if zChanging() then return end
  if creature == player then
    resetData()
  end
  if not pushTarget or not targetTile then return end
  if creature == pushTarget and newPos == targetTile then
    resetData()
  end
end)

-- Non-blocking cooldown state
local lastPushTime = 0
local PUSH_COOLDOWN = 2000

-- Push handler function (shared by UnifiedTick and fallback macro)
local function pushHandler()
  if not config.enabled then return end
  if not pushTarget or not targetTile then return end
  if now - lastPushTime < PUSH_COOLDOWN then return end
  
  -- Verify target still exists and is valid
  local creature = pushTarget
  if not creature or not creature:getPosition() then
    resetData()
    return
  end
  
  local creaturePos = creature:getPosition()
  local targetPos = targetTile:getPosition()
  
  -- Check if we can push (adjacent)
  if not isOk(creaturePos, targetPos) then
    resetData()
    return
  end
  
  -- Check if target tile is walkable and not blocked
  local hasCreature = targetTile and targetTile.hasCreature and targetTile:hasCreature()
  if isNotOk(fieldTable, targetTile) or hasCreature then
    return -- Wait for tile to be clear
  end
  
  -- Execute the push
  if config.pushMaxRuneId and config.pushMaxRuneId > 0 then
    local rune = findItem(config.pushMaxRuneId)
    if rune then
      g_game.useWith(rune, creature)
      lastPushTime = now
    end
  end
end

-- Clear tile handler function
local function clearTileHandler()
  if not config.enabled then return end
  if not cleanTile then return end
  
  local items = cleanTile:getItems()
  if not items or #items == 0 then
    cleanTile:setText('')
    cleanTile = nil
    return
  end
  
  -- Move the top item
  local topItem = items[#items]
  if topItem and topItem:isMoveable() then
    local playerPos = player:getPosition()
    g_game.move(topItem, playerPos, topItem:getCount())
  end
end

-- Use UnifiedTick if available, fallback to standalone macros
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("pushmax_push", {
    interval = 200,
    priority = UnifiedTick.Priority.NORMAL,
    handler = pushHandler,
    group = "combat"
  })
  UnifiedTick.register("pushmax_clear", {
    interval = 300,
    priority = UnifiedTick.Priority.LOW,
    handler = clearTileHandler,
    group = "combat"
  })
else
  macro(200, pushHandler)
  macro(300, clearTileHandler)
end
