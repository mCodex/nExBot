--[[
  nExBot - Eat Food from Corpses (TargetBot Integration)
  
  Automatically opens recently killed monster corpses and eats food inside.
  This feature ONLY handles eating from monster corpses while TargetBot is active.
  
  For eating food from inventory, use the "Eat Food" macro in the HP tab.
  
  Features:
  - Uses looting system's monster death tracking
  - Opens corpses automatically
  - Eats food from any opened container (corpses)
  - Uses comprehensive food item list
  - Cooldown to prevent spam eating
  - Toggle switch in TargetBot Looting panel
]]

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

--------------------------------------------------------------------------------
-- CLIENTSERVICE HELPERS (cross-client compatibility)
--------------------------------------------------------------------------------
local function getClient()
  return ClientService
end

local function getClientVersion()
  local Client = getClient()
  return (Client and Client.getClientVersion) and Client.getClientVersion() or (g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200
end

TargetBot.EatFood = {}

-- Food item IDs
local FOOD_IDS = {
  -- Meats
  [3577] = true,  -- meat
  [3582] = true,  -- ham
  [3583] = true,  -- dragon ham
  
  -- Fish
  [3578] = true,  -- fish
  [6984] = true,  -- fish (variant)
  [7885] = true,  -- fish (variant)
  [10245] = true, -- fish (variant)
  
  -- Fruits
  [3584] = true,  -- pear
  [3585] = true,  -- red apple
  [3586] = true,  -- orange
  [3587] = true,  -- banana
  [3588] = true,  -- blueberry
  [3589] = true,  -- coconut
  [3590] = true,  -- cherry
  [3591] = true,  -- strawberry
  [3593] = true,  -- melon
  [5096] = true,  -- mango
  [8011] = true,  -- plum
  [8012] = true,  -- raspberry
  [8013] = true,  -- lemon
  
  -- Vegetables
  [3594] = true,  -- pumpkin
  [3595] = true,  -- carrot
  [8015] = true,  -- onion
  [15634] = true, -- carrot (variant)
  [15636] = true, -- carrot (variant)
  
  -- Baked goods
  [3598] = true,  -- cookie
  [3600] = true,  -- bread
  [3602] = true,  -- brown bread
  
  -- Other
  [3606] = true,  -- egg
  [3607] = true,  -- cheese
  [3723] = true,  -- white mushroom
  [3725] = true,  -- brown mushroom
  [15700] = true, -- mushroom
  [6277] = true,  -- cake
  [6278] = true,  -- cake (variant)
  [12147] = true, -- cake (variant)
  [3592] = true,  -- grape
}

-- State variables
local eatFromCorpsesEnabled = false
local lastEatTime = 0
local lastOpenTime = 0
local foodCorpseQueue = {}     -- Independent corpse queue for food
local EAT_COOLDOWN = 1000      -- 1 second between eating
local OPEN_COOLDOWN = 200      -- 0.2 seconds between opening corpses
local MAX_CORPSE_QUEUE = 30    -- Queue up to 30 corpses
local CORPSE_MAX_AGE = 30000   -- Remove corpses older than 30 seconds
local CORPSE_RANGE = 2         -- Must be within 2 tiles to open
local CORPSE_WALK_RANGE = 6    -- Max distance to walk to corpse
local FULL_REGEN_TIME = 600    -- Consider player full if regen > 10 minutes (600 seconds)
local processedContainers = {} -- Track containers we've checked for food
local walkingToCorpse = nil    -- Currently walking to this corpse

-- "You are full" detection state
local isPlayerFull = false           -- Flag set when server says we're full
local fullDetectedTime = 0           -- When we detected player is full
local FULL_COOLDOWN = 60000          -- Don't retry eating for 60 seconds after "You are full"
local FULL_MESSAGES = {              -- Server messages indicating player is full (case insensitive)
  "you are full",
  "you're full", 
  "voce esta cheio",                 -- Portuguese
  "estas lleno",                     -- Spanish
}

-- Pure function: Check if text contains a "full" message
local function isFullMessage(text)
  if not text then return false end
  local lowerText = text:lower()
  for _, pattern in ipairs(FULL_MESSAGES) do
    if lowerText:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

-- Listen for server messages to detect "You are full"
onTextMessage(function(mode, text)
  if not eatFromCorpsesEnabled then return end
  if isFullMessage(text) then
    isPlayerFull = true
    fullDetectedTime = now
    -- Clear the corpse queue since we can't eat anyway
    foodCorpseQueue = {}
    walkingToCorpse = nil
  end
end)

-- Pure function: Check if "full" cooldown has expired
local function hasFullCooldownExpired()
  return (now - fullDetectedTime) > FULL_COOLDOWN
end

-- Profile storage helpers
local function getProfileSetting(key)
  if ProfileStorage then
    return ProfileStorage.get(key)
  end
  return storage[key]
end

local function setProfileSetting(key, value)
  if ProfileStorage then
    ProfileStorage.set(key, value)
  else
    storage[key] = value
  end
end

-- Initialize from profile storage
eatFromCorpsesEnabled = getProfileSetting("eatFromCorpses") or false

-- Check if enabled
TargetBot.EatFood.isEnabled = function()
  return eatFromCorpsesEnabled
end

-- Set enabled state
TargetBot.EatFood.setEnabled = function(enabled)
  eatFromCorpsesEnabled = enabled
  setProfileSetting("eatFromCorpses", enabled)
end

-- Toggle state
TargetBot.EatFood.toggle = function()
  eatFromCorpsesEnabled = not eatFromCorpsesEnabled
  setProfileSetting("eatFromCorpses", eatFromCorpsesEnabled)
  return eatFromCorpsesEnabled
end

-- Get food IDs table
TargetBot.EatFood.getFoodIds = function()
  return FOOD_IDS
end

-- Check if item is food
TargetBot.EatFood.isFood = function(itemId)
  return FOOD_IDS[itemId] == true
end

-- Add custom food ID
TargetBot.EatFood.addFoodId = function(itemId)
  FOOD_IDS[itemId] = true
end

-- Remove food ID  
TargetBot.EatFood.removeFoodId = function(itemId)
  FOOD_IDS[itemId] = nil
end

-- Check if player is marked as full (server said "You are full")
TargetBot.EatFood.isPlayerFull = function()
  return isPlayerFull and not hasFullCooldownExpired()
end

-- Reset the "full" flag (useful if player takes damage and loses regen)
TargetBot.EatFood.resetFullStatus = function()
  isPlayerFull = false
  fullDetectedTime = 0
end

-- Get remaining cooldown time in seconds
TargetBot.EatFood.getFullCooldownRemaining = function()
  if not isPlayerFull then return 0 end
  local remaining = FULL_COOLDOWN - (now - fullDetectedTime)
  return remaining > 0 and math.floor(remaining / 1000) or 0
end

-- Check distance to position
local function getDistance(pos1, pos2)
  if pos1.z ~= pos2.z then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Check if player needs food (not full)
local function needsFood()
  if not player then return false end
  
  -- If server told us we're full, respect the cooldown
  if isPlayerFull then
    if hasFullCooldownExpired() then
      -- Cooldown expired, reset the flag and try again
      isPlayerFull = false
    else
      -- Still in cooldown, don't try to eat
      return false
    end
  end
  
  -- Get regeneration time in seconds
  -- Player:getRegenerationTime() returns seconds of regeneration remaining
  local regenTime = 0
  if player.getRegenerationTime then
    regenTime = player:getRegenerationTime() or 0
  elseif player.regeneration then
    regenTime = player:regeneration() or 0
  end
  -- Only eat if regeneration time is below threshold (not full)
  return regenTime < FULL_REGEN_TIME
end

-- Clean old corpses from queue
local function cleanCorpseQueue()
  local currentTime = now
  for i = #foodCorpseQueue, 1, -1 do
    if currentTime - foodCorpseQueue[i].time > CORPSE_MAX_AGE then
      table.remove(foodCorpseQueue, i)
    end
  end
end

-- Add corpse to food queue
local function addCorpseToQueue(pos, name)
  -- Check if already in queue
  for _, corpse in ipairs(foodCorpseQueue) do
    if corpse.pos.x == pos.x and corpse.pos.y == pos.y and corpse.pos.z == pos.z then
      return
    end
  end
  
  if #foodCorpseQueue >= MAX_CORPSE_QUEUE then
    -- Remove oldest done/failed corpse first, otherwise remove oldest
    local removed = false
    for i = 1, #foodCorpseQueue do
      if foodCorpseQueue[i].state == "done" or foodCorpseQueue[i].state == "failed" then
        table.remove(foodCorpseQueue, i)
        removed = true
        break
      end
    end
    if not removed then
      table.remove(foodCorpseQueue, 1)
    end
  end
  
  table.insert(foodCorpseQueue, {
    pos = {x = pos.x, y = pos.y, z = pos.z},
    name = name,
    time = now,
    state = "pending",  -- pending, opening, checking, done, failed
    tries = 0,
    containerIndex = nil
  })
end

-- Find nearest corpse to open (within open range)
local function findNearestCorpse()
  local playerPos = player:getPosition()
  local nearest = nil
  local nearestDist = 999
  local nearestIndex = nil
  
  for i, corpse in ipairs(foodCorpseQueue) do
    -- Only process pending corpses that haven't failed too many times
    if corpse.state == "pending" and corpse.tries < 3 then
      local dist = getDistance(playerPos, corpse.pos)
      if dist <= CORPSE_RANGE and dist < nearestDist then
        nearestDist = dist
        nearest = corpse
        nearestIndex = i
      end
    end
  end
  
  return nearest, nearestIndex
end

-- Find nearest corpse to walk to (within walk range but outside open range)
local function findCorpseToWalkTo()
  local playerPos = player:getPosition()
  local nearest = nil
  local nearestDist = 999
  local nearestIndex = nil
  
  for i, corpse in ipairs(foodCorpseQueue) do
    -- Only walk to pending corpses
    if corpse.state == "pending" and corpse.tries < 3 then
      local dist = getDistance(playerPos, corpse.pos)
      -- Must be within walk range but outside open range
      if dist > CORPSE_RANGE and dist <= CORPSE_WALK_RANGE and dist < nearestDist then
        nearestDist = dist
        nearest = corpse
        nearestIndex = i
      end
    end
  end
  
  return nearest, nearestIndex
end

-- Walk to a corpse position
local function walkToCorpse(corpse)
  if not corpse then return false end
  if not player then return false end
  
  local playerPos = player:getPosition()
  local dist = getDistance(playerPos, corpse.pos)
  
  -- Already close enough
  if dist <= CORPSE_RANGE then
    walkingToCorpse = nil
    return false
  end
  
  -- Use autoWalk if available
  if autoWalk then
    autoWalk(corpse.pos, 20, { ignoreNonPathable = true, precision = 1 })
    walkingToCorpse = corpse
    return true
  end
  
  -- Fallback: use g_game.walk
  local Client = getClient()
  if (Client and Client.walk) or (g_game and g_game.walk) then
    -- Calculate direction to walk
    local dx = corpse.pos.x - playerPos.x
    local dy = corpse.pos.y - playerPos.y
    local dir = nil
    
    if math.abs(dx) >= math.abs(dy) then
      dir = dx > 0 and East or West
    else
      dir = dy > 0 and South or North
    end
    
    if dir then
      if Client and Client.walk then
        Client.walk(dir)
      elseif g_game and g_game.walk then
        g_game.walk(dir)
      end
      walkingToCorpse = corpse
      return true
    end
  end
  
  return false
end

-- Eat food directly from player's inventory/backpacks (not corpses)
local function eatFromInventory()
  if (now - lastEatTime) < EAT_COOLDOWN then return false end
  
  -- Try findItem first (searches all open containers including backpacks)
  local Client = getClient()
  for foodId, _ in pairs(FOOD_IDS) do
    local food = SafeCall.findItem(foodId)
    if food then
      if Client and Client.use then
        Client.use(food)
      elseif g_game and g_game.use then
        g_game.use(food)
      end
      lastEatTime = now
      return true
    end
  end
  
  -- Fallback: use itemAmount and use() by ID
  if itemAmount and use then
    for foodId, _ in pairs(FOOD_IDS) do
      if itemAmount(foodId) > 0 then
        use(foodId)
        lastEatTime = now
        return true
      end
    end
  end
  
  return false
end

-- Eat food from any opened container (corpse containers)
local function eatFromOpenContainers()
  if (now - lastEatTime) < EAT_COOLDOWN then return false end
  
  local Client = getClient()
  local containers = (Client and Client.getContainers) and Client.getContainers() or (g_game and g_game.getContainers and g_game.getContainers())
  for index, container in pairs(containers) do
    -- Only check corpse containers (not backpacks)
    local containerItem = container:getContainerItem()
    if containerItem then
      local itemId = containerItem:getId()
      -- Corpse IDs are typically in certain ranges - we check all containers for now
      -- and rely on the fact that player's loot containers won't have food
      for _, item in ipairs(container:getItems()) do
        if FOOD_IDS[item:getId()] then
          if Client and Client.use then
            Client.use(item)
          elseif g_game and g_game.use then
            g_game.use(item)
          end
          lastEatTime = now
          -- Mark container for tracking
          if not processedContainers[index] then
            processedContainers[index] = true
            -- Close corpse after a delay if not a backpack
            schedule(500, function()
              if container and not container:isClosed() then
                -- Check if it's likely a corpse (single container, not linked to others)
                local items = container:getItems()
                local hasFood = false
                for _, itm in ipairs(items) do
                  if FOOD_IDS[itm:getId()] then
                    hasFood = true
                    break
                  end
                end
                -- Close if no more food
                if not hasFood then
                  local Client2 = getClient()
                  if Client2 and Client2.close then
                    Client2.close(container)
                  elseif g_game and g_game.close then
                    g_game.close(container)
                  end
                  processedContainers[index] = nil
                end
              end
            end)
          end
          return true
        end
      end
    end
  end
  -- If no food in open containers, try inventory-based eating (closed BP friendly)
  if eatFromInventory() then
    return true
  end
  return false
end

-- Open a nearby corpse
local function openNearbyCorpse()
  if (now - lastOpenTime) < OPEN_COOLDOWN then return false end
  
  local corpse, index = findNearestCorpse()
  if not corpse then return false end
  
  local Client = getClient()
  local tile = (Client and Client.getTile) and Client.getTile(corpse.pos) or (g_map and g_map.getTile and g_map.getTile(corpse.pos))
  if not tile then
    foodCorpseQueue[index].tries = foodCorpseQueue[index].tries + 1
    if foodCorpseQueue[index].tries >= 3 then
      foodCorpseQueue[index].state = "failed"
    end
    return false
  end
  
  -- Find the top usable thing (corpse container)
  local topThing = tile:getTopUseThing()
  if not topThing then
    foodCorpseQueue[index].tries = foodCorpseQueue[index].tries + 1
    if foodCorpseQueue[index].tries >= 3 then
      foodCorpseQueue[index].state = "failed"
    end
    return false
  end
  
  -- Check if it's a container
  if not topThing:isContainer() then
    foodCorpseQueue[index].tries = foodCorpseQueue[index].tries + 1
    if foodCorpseQueue[index].tries >= 3 then
      foodCorpseQueue[index].state = "failed"
    end
    return false
  end
  
  -- Open the corpse
  if Client and Client.open then
    Client.open(topThing)
  elseif g_game and g_game.open then
    g_game.open(topThing)
  end
  foodCorpseQueue[index].state = "opening"
  lastOpenTime = now
  
  -- Schedule to mark as done after a delay (to allow container to open and food to be eaten)
  local corpseIndex = index
  schedule(1500, function()
    if foodCorpseQueue[corpseIndex] and foodCorpseQueue[corpseIndex].state == "opening" then
      foodCorpseQueue[corpseIndex].state = "done"
    end
  end)
  
  return true
end

-- Process: Open corpses and eat food
TargetBot.EatFood.process = function()
  if not eatFromCorpsesEnabled then return false end
  if not player then return false end
  if SafeCall.isInPz() then return false end
  if not TargetBot.isOn() then return false end
  
  -- Clean old corpses
  cleanCorpseQueue()
  
  -- Check if player needs food (not full)
  if not needsFood() then
    walkingToCorpse = nil
    return false
  end
  
  -- First, try to eat from already opened containers
  if eatFromOpenContainers() then
    return true
  end
  
  -- Count pending corpses
  local pendingCount = 0
  for _, corpse in ipairs(foodCorpseQueue) do
    if corpse.state == "pending" then
      pendingCount = pendingCount + 1
    end
  end
  
  -- If no pending corpses, nothing to do
  if pendingCount == 0 then
    return false
  end
  
  -- Try to open a nearby corpse (works in parallel with combat)
  if openNearbyCorpse() then
    return true
  end
  
  -- If no corpse nearby, walk to one if available
  -- Only walk to corpses if not actively in combat
  local currentTarget = target and target() or nil
  if not currentTarget then
    local corpseToWalk, walkIndex = findCorpseToWalkTo()
    if corpseToWalk then
      if walkToCorpse(corpseToWalk) then
        return true
      end
    end
  end
  
  return false
end

-- Hook: Track monster deaths for food corpses
onCreatureDisappear(function(creature)
  if not eatFromCorpsesEnabled then return end
  if not player then return end
  if SafeCall.isInPz() then return end
  if not TargetBot.isOn() then return end
  if not creature:isMonster() then return end
  
  local playerPos = player:getPosition()
  local mpos = creature:getPosition()
  
  -- Check if on same floor
  if playerPos.z ~= mpos.z then return end
  
  -- Check if within reasonable range  
  local dist = getDistance(playerPos, mpos)
  if dist > 8 then return end
  
  -- Schedule to allow corpse to appear on tile
  schedule(100, function()
    if not player then return end
    
    local Client = getClient()
    local tile = (Client and Client.getTile) and Client.getTile(mpos) or (g_map and g_map.getTile and g_map.getTile(mpos))
    if not tile then return end
    
    local topThing = tile:getTopUseThing()
    if not topThing then return end
    if not topThing:isContainer() then return end
    
    -- Add to corpse queue for food checking
    addCorpseToQueue(mpos, creature:getName())
  end)
end)

-- Also react to direct tile adds (faster / more robust than only relying on disappear schedule)
if EventBus and nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
  local addCorpseDebounced = nExBot.EventUtil.debounce(100, function(tile, thing)
    -- Only containers are interesting for corpses
    if not thing or not thing:isContainer() then return end
    local pos = tile:getPosition()
    -- Only consider nearby positions
    local p = player and player:getPosition()
    if not p or p.z ~= pos.z then return end
    if getDistance(p, pos) > 8 then return end
    schedule(50, function()
      local topThing = tile:getTopUseThing()
      if topThing and topThing:isContainer() then
        addCorpseToQueue(pos, "")
      end
    end)
  end)

  EventBus.on("tile:add", function(tile, thing)
    addCorpseDebounced(tile, thing)
  end, 10)
end

-- Macro to process corpse eating (runs every 200ms)
-- NOTE: For eating food from inventory, use the "Eat Food" macro in the HP tab
macro(200, function()
  if not eatFromCorpsesEnabled then return end
  if not TargetBot or not TargetBot.isOn or not TargetBot.isOn() then return end
  if SafeCall.isInPz() then return end
  if not player then return end
  
  -- Process corpse eating
  TargetBot.EatFood.process()
end)