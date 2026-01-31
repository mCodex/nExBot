-- Tools tab widgets and macros
setDefaultTab("Tools")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENT SERVICE HELPERS (Cross-client compatibility: OTCv8 / OpenTibiaBR)
-- ═══════════════════════════════════════════════════════════════════════════

-- ClientService helper for cross-client compatibility
local function getClient()
  return ClientService
end

-- Version check helper
local function getClientVersion()
  local Client = getClient()
  return (Client and Client.getClientVersion) and Client.getClientVersion() or (g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROFILE STORAGE INTEGRATION
-- All settings are stored per-profile using ProfileStorage from configs.lua
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper to get/set profile storage with fallback to old storage for compatibility
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

-- ═══════════════════════════════════════════════════════════════════════════
-- MONEY EXCHANGER - Auto-exchange 100 gold → platinum, 100 platinum → crystal
-- ═══════════════════════════════════════════════════════════════════════════

local EXCHANGEABLE_COINS = {
  [3031] = true,  -- Gold Coin
  [3035] = true,  -- Platinum Coin
}

local EXCHANGE_COUNT = 100  -- Stack of 100 triggers exchange

-- Pure function: Check if item is exchangeable
local function isExchangeable(item)
  if not item then return false end
  local id = item:getId()
  local count = item:getCount()
  return EXCHANGEABLE_COINS[id] == true and count == EXCHANGE_COUNT
end

-- Pure function: Find first exchangeable item in all containers
local function findExchangeableItem()
  local Client = getClient()
  local containers = (Client and Client.getContainers) and Client.getContainers() or (g_game and g_game.getContainers and g_game.getContainers()) or {}
  if not containers then return nil end
  
  for _, container in pairs(containers) do
    -- Skip loot containers to avoid interference
    if container and not container.lootContainer then
      local items = container:getItems()
      if items then
        for _, item in ipairs(items) do
          if isExchangeable(item) then
            return item
          end
        end
      end
    end
  end
  return nil
end

-- Side effect: Exchange a single item
local function exchangeItem(item)
  if not item then return false end
  local Client = getClient()
  if Client and Client.use then
    Client.use(item)
  elseif g_game and g_game.use then
    g_game.use(item)
  end
  return true
end

-- Cooldown state
local lastExchangeTime = 0
local EXCHANGE_COOLDOWN = 500  -- 500ms between exchanges for reliability

-- Main macro with persistence
local exchangeMoneyMacro = macro(200, "Exchange Money", function()
  -- Cooldown check
  if (now - lastExchangeTime) < EXCHANGE_COOLDOWN then return end
  
  -- Find and exchange
  local item = findExchangeableItem()
  if item then
    exchangeItem(item)
    lastExchangeTime = now
  end
end)
BotDB.registerMacro(exchangeMoneyMacro, "exchangeMoney")

UI.Separator()

-- Auto trade message --------------------------------------------------------
local autoTradeMessage = getProfileSetting("autoTradeMessage") or "nExBot is online!"

local autoTradeMacro = macro(60 * 1000, "Send message on trade", function()
  local trade = getChannelId("advertising") or getChannelId("trade")
  local message = autoTradeMessage or ""
  if trade and message:len() > 0 then
    sayChannel(trade, message)
  end
end)
BotDB.registerMacro(autoTradeMacro, "autoTradeMsg")

local tradeMessageEdit = UI.TextEdit(autoTradeMessage, function(widget, text)
  autoTradeMessage = text
  setProfileSetting("autoTradeMessage", text)
end)

UI.Separator()

UI.Label("Tools:")


-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO LEVITATE - Event-Driven with Z+1 Field Analysis (EventBus)
-- Analyzes Z+1 fields in movement direction to detect levitate opportunities
-- Works WITHOUT requiring walls - detects ground above adjacent tiles
-- Keeps character moving smoothly while detecting up/down opportunities
-- ═══════════════════════════════════════════════════════════════════════════

local autoLevitateEnabled = false
local lastLevCast = 0
local LEV_CD = 1950  -- Slightly under 2s for faster re-cast
local MIN_MANA = 50

-- Cached depth setting
local levDepth = BotDB.get("macros.autoLevitateDepth") or 1

-- All 8 directions with offsets
local DIRS = {
  {dx = 0, dy = -1},   -- 1: North
  {dx = 1, dy = 0},    -- 2: East
  {dx = 0, dy = 1},    -- 3: South
  {dx = -1, dy = 0},   -- 4: West
  {dx = 1, dy = -1},   -- 5: NE
  {dx = 1, dy = 1},    -- 6: SE
  {dx = -1, dy = 1},   -- 7: SW
  {dx = -1, dy = -1},  -- 8: NW
}

-- Player direction (0-7) to DIRS index (1-8)
local DIR_TO_IDX = {[0]=1, [1]=2, [2]=3, [3]=4, [4]=5, [5]=6, [6]=7, [7]=8}

-- Map key names to direction indices
local KEY_TO_DIR = {
  ["Up"] = 1, ["Numpad8"] = 1, ["W"] = 1,
  ["Right"] = 2, ["Numpad6"] = 2, ["D"] = 2,
  ["Down"] = 3, ["Numpad2"] = 3, ["S"] = 3,
  ["Left"] = 4, ["Numpad4"] = 4, ["A"] = 4,
  ["Numpad9"] = 5, ["Numpad3"] = 6, ["Numpad1"] = 7, ["Numpad7"] = 8,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Z+1 FIELD ANALYSIS - Core detection logic
-- ═══════════════════════════════════════════════════════════════════════════

-- Direct check for levitate opportunity in a specific direction (no caching)
-- Returns "up", "down", or nil
local function checkLevitateDirection(px, py, pz, dirIdx)
  local d = DIRS[dirIdx]
  if not d then return nil end
  
  local fx, fy = px + d.dx, py + d.dy
  
  -- CHECK UP: Is there ground at Z-1 (one level above the adjacent tile)?
  -- This works regardless of whether the current-level tile is walkable or not
  if pz > 0 then
    local Client = getClient()
    local aboveTile = (Client and Client.getTile) and Client.getTile({x = fx, y = fy, z = pz - 1}) or (g_map and g_map.getTile and g_map.getTile({x = fx, y = fy, z = pz - 1}))
    if aboveTile and aboveTile:getGround() then
      -- Ground exists above! This is ALWAYS a levitate-up opportunity
      return "up"
    end
    
    -- Check extra depth levels if configured
    for depth = 2, levDepth do
      local zcheck = pz - depth
      if zcheck < 0 then break end
      local aboveD = (Client and Client.getTile) and Client.getTile({x = fx, y = fy, z = zcheck}) or (g_map and g_map.getTile and g_map.getTile({x = fx, y = fy, z = zcheck}))
      if aboveD and aboveD:getGround() then
        return "up"
      end
    end
  end
  
  -- CHECK DOWN: No ground at current level + ground below
  local Client = getClient()
  local currentTile = (Client and Client.getTile) and Client.getTile({x = fx, y = fy, z = pz}) or (g_map and g_map.getTile and g_map.getTile({x = fx, y = fy, z = pz}))
  local hasCurrentGround = currentTile and currentTile:getGround()
  
  if not hasCurrentGround and pz < 15 then
    local belowTile = (Client and Client.getTile) and Client.getTile({x = fx, y = fy, z = pz + 1}) or (g_map and g_map.getTile and g_map.getTile({x = fx, y = fy, z = pz + 1}))
    if belowTile and belowTile:getGround() then
      return "down"
    end
  end
  
  return nil
end

-- Check if we're standing on a tile where we could levitate up
-- (checks the tile we're currently on, not adjacent)
local function checkCurrentTileLevitate(px, py, pz, dirIdx)
  local d = DIRS[dirIdx]
  if not d then return nil end
  
  local fx, fy = px + d.dx, py + d.dy
  
  -- Check if there's ground above the adjacent tile
  if pz > 0 then
    local Client = getClient()
    local aboveTile = (Client and Client.getTile) and Client.getTile({x = fx, y = fy, z = pz - 1}) or (g_map and g_map.getTile and g_map.getTile({x = fx, y = fy, z = pz - 1}))
    if aboveTile and aboveTile:getGround() then
      return "up"
    end
  end
  
  return nil
end

-- Cast levitate spell
local function castLev(levType)
  if levType == "up" then
    say("exani hur up")
  else
    say("exani hur down")
  end
  lastLevCast = now
end

-- Core levitate check - uses DIRECT check, no caching for immediate response
local function tryLevitate(px, py, pz, dirIdx)
  if not autoLevitateEnabled then return false end
  if (now - lastLevCast) < LEV_CD then return false end
  if mana() < MIN_MANA then return false end
  
  -- Direct check in the specified direction
  local levType = checkLevitateDirection(px, py, pz, dirIdx)
  
  if levType then
    -- Turn player to face the direction before casting
    local newDir = dirIdx - 1  -- Convert back to 0-7
    if turn then turn(newDir) end
    castLev(levType)
    return true
  end
  
  return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENT-DRIVEN TRIGGERS (EventBus)
-- ═══════════════════════════════════════════════════════════════════════════

-- TRIGGER 1: EventBus player:move - check from OLD position (before the move)
-- This catches cases where player walked onto a tile that had levitate above
if EventBus then
  EventBus.on("player:move", function(newPos, oldPos)
    if not autoLevitateEnabled then return end
    if not player then return end
    if (now - lastLevCast) < LEV_CD then return end
    if mana() < MIN_MANA then return end
    
    -- Calculate movement direction
    local moveDx = newPos.x - oldPos.x
    local moveDy = newPos.y - oldPos.y
    
    -- Find direction index from movement delta
    local dirIdx = nil
    for i, d in ipairs(DIRS) do
      if d.dx == moveDx and d.dy == moveDy then
        dirIdx = i
        break
      end
    end
    
    if not dirIdx then return end
    
    -- KEY FIX: Check from OLD position - this is where the levitate opportunity was
    local levType = checkLevitateDirection(oldPos.x, oldPos.y, oldPos.z, dirIdx)
    
    if levType then
      local newDir = dirIdx - 1
      if turn then turn(newDir) end
      castLev(levType)
      return
    end
    
    -- Also check if the NEW position has levitate opportunities in same direction
    -- (for chained levitate scenarios)
    local levType2 = checkLevitateDirection(newPos.x, newPos.y, newPos.z, dirIdx)
    if levType2 then
      local newDir = dirIdx - 1
      if turn then turn(newDir) end
      castLev(levType2)
    end
  end, 100)  -- High priority for instant response
end

-- TRIGGER 2: Key press - fires BEFORE movement, most reliable for wall-less levitate
onKeyDown(function(keys)
  if not autoLevitateEnabled then return end
  if (now - lastLevCast) < LEV_CD then return end
  
  local dirIdx = KEY_TO_DIR[keys]
  if not dirIdx then return end
  
  local p = player
  if not p then return end
  
  local pos = p:getPosition()
  if not pos then return end
  
  if mana() < MIN_MANA then return end
  
  -- Direct check - this fires BEFORE the walk happens
  local levType = checkLevitateDirection(pos.x, pos.y, pos.z, dirIdx)
  
  if levType then
    local newDir = dirIdx - 1
    if turn then turn(newDir) end
    castLev(levType)
  end
end)

-- TRIGGER 3: Lightweight backup macro (100ms) for held keys
-- Faster polling for continuous walking scenarios
local heldDirKeys = {}
local lastBackupCheck = 0

onKeyDown(function(keys)
  local dir = KEY_TO_DIR[keys]
  if dir then heldDirKeys[dir] = true end
end)

onKeyUp(function(keys)
  local dir = KEY_TO_DIR[keys]
  if dir then heldDirKeys[dir] = false end
end)

macro(100, function()
  if not autoLevitateEnabled then return end
  if (now - lastLevCast) < LEV_CD then return end
  if (now - lastBackupCheck) < 90 then return end
  lastBackupCheck = now
  
  -- Only check if a direction key is held
  local anyHeld = false
  for _, v in pairs(heldDirKeys) do
    if v then anyHeld = true break end
  end
  if not anyHeld then return end
  
  local p = player
  if not p then return end
  
  local pos = p:getPosition()
  if not pos then return end
  
  if mana() < MIN_MANA then return end
  
  -- Check all held directions with direct check
  for dirIdx = 1, 8 do
    if heldDirKeys[dirIdx] then
      local levType = checkLevitateDirection(pos.x, pos.y, pos.z, dirIdx)
      if levType then
        local newDir = dirIdx - 1
        if turn then turn(newDir) end
        castLev(levType)
        return
      end
    end
  end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- UI TOGGLE
-- ═══════════════════════════════════════════════════════════════════════════

local autoLevitateUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: autoLevitateToggle
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Auto Levitate')
    tooltip: Event-driven auto-levitate: triggers on movement and key presses for instant response
]])

autoLevitateUI.autoLevitateToggle.onClick = function(widget)
  autoLevitateEnabled = not autoLevitateEnabled
  widget:setOn(autoLevitateEnabled)
  BotDB.set("macros.autoLevitate", autoLevitateEnabled)
end

-- Restore state on load
if BotDB.get("macros.autoLevitate") == true then
  autoLevitateEnabled = true
  autoLevitateUI.autoLevitateToggle:setOn(true)
end

-- Ensure a default depth value exists (number of extra Z levels to consider for UP; default=1)
if BotDB.get("macros.autoLevitateDepth") == nil then
  BotDB.set("macros.autoLevitateDepth", 1)
end

-- Auto haste ---------------------------------------------------------------
local HASTE_SPELLS = {
  [1]  = { spell = "utani hur",      mana = 60  }, -- Knight
  [2]  = { spell = "utani hur",      mana = 60  }, -- Paladin
  [3]  = { spell = "utani gran hur", mana = 100 }, -- Sorcerer
  [4]  = { spell = "utani gran hur", mana = 100 }, -- Druid
  [11] = { spell = "utani hur",      mana = 60  },
  [12] = { spell = "utani hur",      mana = 60  },
  [13] = { spell = "utani gran hur", mana = 100 },
  [14] = { spell = "utani gran hur", mana = 100 },
}

local lastHasteCast = 0
local HASTE_CAST_COOLDOWN = 2000

-- Check if player is hasted (has speed buff)
local function isHasted()
  -- Use vLib hasHaste if available
  if hasHaste then
    return hasHaste()
  end
  
  -- Fallback: Check player speed vs base speed
  if player and player.getSpeed and player.getBaseSpeed then
    local currentSpeed = player:getSpeed() or 0
    local baseSpeed = player:getBaseSpeed() or 0
    return currentSpeed > baseSpeed
  end
  
  -- Can't determine, assume not hasted
  return false
end

local autoHasteMacro = macro(500, "Auto Haste", function()
  if not player then return end
  
  -- Cast cooldown
  if now - lastHasteCast < HASTE_CAST_COOLDOWN then return end
  
  local vocation = player:getVocation()
  local haste = HASTE_SPELLS[vocation]
  if not haste then return end
  
  -- Check if already hasted
  if isHasted() then return end
  
  -- Check mana
  if mana() < haste.mana then return end
  
  -- Check spell cooldown
  if getSpellCoolDown and getSpellCoolDown(haste.spell) then return end
  
  say(haste.spell)
  lastHasteCast = now
end)
BotDB.registerMacro(autoHasteMacro, "autoHaste")

-- Auto Mount ----------------------------------------------------------------
-- Automatically mounts player when outside of PZ
-- Uses the player's default mount from client settings
-- Does NOT attempt to mount in PZ (saves CPU/memory)
-- State persisted via BotDB.registerMacro

local lastMountAttempt = 0
local MOUNT_COOLDOWN = 2000 -- Don't spam mount attempts

local autoMountMacro = macro(500, "Auto Mount", function()
  if not player then return end
  
  -- Skip if in protection zone - saves CPU/memory
  if isInPz() then return end
  
  -- Cooldown to prevent spamming
  if (now - lastMountAttempt) < MOUNT_COOLDOWN then return end
  
  -- Check if already mounted
  local outfit = player:getOutfit()
  if outfit and outfit.mount and outfit.mount > 0 then
    return -- Already mounted
  end
  
  -- Check if player has any mount configured before trying to mount
  -- This prevents the outfit panel from opening
  if not outfit then return end
  
  -- Only try to mount if we're reasonably sure it won't open outfit dialog
  local Client = getClient()
  if Client and Client.mount then
    Client.mount()
    lastMountAttempt = now
  elseif g_game and g_game.mount then
    g_game.mount(true)
    lastMountAttempt = now
  end
end)
BotDB.registerMacro(autoMountMacro, "autoMount")

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO RANDOM OUTFIT COLORS - Ultra-fast automatic color cycling
-- Changes outfit colors every 0.2 seconds when enabled
-- Uses BotSwitch UI like fishing for consistency
-- ═══════════════════════════════════════════════════════════════════════════

-- Auto Random Outfit Colors
local autoRandomOutfitEnabled = false

local function randomizeOutfitColors()
  local Client = getClient()
  local player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not player then return end
  
  local currentOutfit = player:getOutfit()
  if not currentOutfit then return end
  
  -- Generate 4 unique random colors from the full valid Tibia color range (1-132)
  -- Color 0 is transparent/none, so we start from 1
  -- This ensures maximum variety and prevents duplicate colors in the same outfit
  local colors = {}
  local used = {}
  for i = 1, 4 do
    local c
    repeat
      c = math.random(1, 132)  -- Exclude 0 (transparent)
    until not used[c]
    used[c] = true
    colors[i] = c
  end
  
  local newOutfit = {
    type = currentOutfit.type,
    head = colors[1],
    body = colors[2],
    legs = colors[3],
    feet = colors[4],
    addons = currentOutfit.addons or 0
  }
  
  -- Preserve mount if present
  if currentOutfit.mount then
    newOutfit.mount = currentOutfit.mount
  end
  
  -- Apply the new outfit
  setOutfit(newOutfit)
end

local function autoRandomOutfitLoop()
  if autoRandomOutfitEnabled then
    randomizeOutfitColors()
    -- Schedule next change in 0.2 seconds (60% faster)
    schedule(200, autoRandomOutfitLoop)
  end
end

local autoRandomOutfitUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Auto Random Outfit Colors')
]])

-- Connect UI switch to macro state
autoRandomOutfitUI.title.onClick = function(widget)
  autoRandomOutfitEnabled = not autoRandomOutfitEnabled
  widget:setOn(autoRandomOutfitEnabled)
  if autoRandomOutfitEnabled then
    -- Start the loop
    randomizeOutfitColors() -- Apply immediately
    schedule(500, autoRandomOutfitLoop)
    modules.game_textmessage.displayStatusMessage("Auto random outfit colors enabled!")
  else
    modules.game_textmessage.displayStatusMessage("Auto random outfit colors disabled!")
  end
end

UI.Separator()

-- ═══════════════════════════════════════════════════════════════════════════
-- FISHING - Random water tile selection + auto fish drop to water
-- ═══════════════════════════════════════════════════════════════════════════

-- Water tile IDs that can be fished
local WATER_TILES = {
  -- Standard water (most common)
  4597, 4598, 4599, 4600, 4601, 4602,
  4603, 4604, 4605, 4606, 4607, 4608,
  4609, 4610, 4611, 4612, 4613, 4614,
  4615, 4616, 4617, 4618, 4619, 4620,
  4621, 4622, 4623, 4624, 4625, 4626,
  4627, 4628, 4629, 4630, 4631, 4632,
  4633, 4634, 4635, 4636, 4637, 4638,
  4639, 4640, 4641, 4642, 4643, 4644,
  4645, 4646, 4647, 4648, 4649, 4650,
  4651, 4652, 4653, 4654, 4655, 4656,
  4657, 4658, 4659, 4660, 4661, 4662,
  4663, 4664, 4665, 4666,
  -- Fish in water
  7236,
  -- Swamp
  4691, 4692, 4693, 4694, 4695, 4696,
  4697, 4698, 4699, 4700, 4701, 4702,
  4703, 4704, 4705, 4706, 4707, 4708,
  4709, 4710, 4711, 4712, 4713, 4714,
  4715, 4716, 4717, 4718, 4719, 4720,
  4721, 4722, 4723, 4724, 4725, 4726,
}

local FISHING_ROD_ID = 3483
local FISHING_RANGE = 3  -- Search radius for water tiles
local lastFishTime = 0
local lastDropTime = 0

-- Items to drop into water when fishing
local DROP_TO_WATER = {
  [3578] = true,  -- Fish
  [7159] = true,  -- Northern pike
  [3041] = true,  -- Blue gem (?)
  [1781] = true,  -- Unknown item
}

-- Find items to drop in containers
local function findItemsToDrop()
  for _, container in pairs(getContainers()) do
    if container then
      local items = container:getItems()
      if items then
        for _, item in ipairs(items) do
          if item and DROP_TO_WATER[item:getId()] then
            return item
          end
        end
      end
    end
  end
  return nil
end

-- Find water tile position for dropping
local function findWaterTilePos(playerPos)
  local Client = getClient()
  for dx = -FISHING_RANGE, FISHING_RANGE do
    for dy = -FISHING_RANGE, FISHING_RANGE do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
        local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
        if tile then
          local ground = tile:getGround()
          if ground then
            local groundId = ground:getId()
            for _, waterId in ipairs(WATER_TILES) do
              if groundId == waterId then
                return checkPos
              end
            end
          end
        end
      end
    end
  end
  return nil
end

-- Simple fishing macro (controlled by BotSwitch below)
local fishingEnabled = false
local fishingMacro = macro(1000, function()
  if not fishingEnabled then return end
  if not player then return end
  
  -- Get player position
  local ppos = player:getPosition()
  if not ppos then return end
  
  -- First: Drop fish/items to water (500ms cooldown)
  if now - lastDropTime >= 500 then
    local itemToDrop = findItemsToDrop()
    if itemToDrop then
      local waterPos = findWaterTilePos(ppos)
      if waterPos then
        local Client = getClient()
        if Client and Client.move then
          Client.move(itemToDrop, waterPos, itemToDrop:getCount())
        elseif g_game and g_game.move then
          g_game.move(itemToDrop, waterPos, itemToDrop:getCount())
        end
        lastDropTime = now
        return -- One action per tick
      end
    end
  end
  
  -- Second: Fish (1 second cooldown)
  if now - lastFishTime < 1000 then return end
  
  -- Find all water tiles nearby
  local waterTiles = {}
  local Client = getClient()
  
  for dx = -FISHING_RANGE, FISHING_RANGE do
    for dy = -FISHING_RANGE, FISHING_RANGE do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {x = ppos.x + dx, y = ppos.y + dy, z = ppos.z}
        local tile = (Client and Client.getTile) and Client.getTile(checkPos) or (g_map and g_map.getTile and g_map.getTile(checkPos))
        
        if tile then
          local ground = tile:getGround()
          if ground then
            local groundId = ground:getId()
            for _, waterId in ipairs(WATER_TILES) do
              if groundId == waterId then
                table.insert(waterTiles, ground)
                break
              end
            end
          end
        end
      end
    end
  end
  
  -- No water nearby
  if #waterTiles == 0 then return end
  
  -- Pick random water tile
  local target = waterTiles[math.random(1, #waterTiles)]
  
  -- Try to find fishing rod
  local rod = findItem(FISHING_ROD_ID)
  
  if rod then
    local Client = getClient()
    if Client and Client.useWith then
      Client.useWith(rod, target)
    elseif g_game and g_game.useWith then
      g_game.useWith(rod, target)
    end
    lastFishTime = now
  elseif getClientVersion() >= 780 then
    local Client = getClient()
    if Client and Client.useInventoryItemWith then
      Client.useInventoryItemWith(FISHING_ROD_ID, target, 0)
      lastFishTime = now
    elseif g_game and g_game.useInventoryItemWith then
      g_game.useInventoryItemWith(FISHING_ROD_ID, target, 0)
      lastFishTime = now
    end
  end
end)

-- Fishing UI Switch (same pattern as Dropper)
local fishingUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Fishing')
]])

-- Connect UI switch to macro state using CharacterDB (per-character)
fishingUI.title.onClick = function(widget)
  fishingEnabled = not fishingEnabled
  widget:setOn(fishingEnabled)
  -- Save to CharacterDB if available, otherwise BotDB
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("macros.fishing", fishingEnabled)
  else
    BotDB.set("macros.fishing", fishingEnabled)
  end
end

-- Restore fishing state on load (per-character via CharacterDB)
local function loadFishingState()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    return CharacterDB.get("macros.fishing") == true
  end
  return BotDB.get("macros.fishing") == true
end

local savedFishingState = loadFishingState()
if savedFishingState then
  fishingEnabled = true
  fishingUI.title:setOn(true)
end

UI.Separator()

-- ═══════════════════════════════════════════════════════════════════════════
-- FOLLOW PLAYER v4.0 - OpenTibiaBR Parallel Attack+Follow System
-- Enhanced for party hunting with TRUE parallel attack and follow
-- Features:
-- - PARALLEL ATTACK+FOLLOW: Walk toward leader while maintaining attack
-- - Manual path-based movement (doesn't cancel attack like native follow)
-- - Attack re-issue between walk steps to maintain target lock
-- - Smart distance tracking with path-based following
-- - TargetBot & MovementCoordinator integration
-- - EventBus for instant reaction to leader movements
-- - OpenTibiaBR forceWalk for reliable movement
-- - Combat window system with parallel execution
-- ═══════════════════════════════════════════════════════════════════════════

-- Load follow player settings from CharacterDB (per-character)
local function loadFollowPlayerConfig()
  local config = { 
    enabled = false, 
    playerName = "", 
    followWhileAttacking = true,
    maxDistance = 4,           -- Max distance before prioritizing follow over combat
    combatWindowMs = 1500,     -- Max time to finish a monster before forced follow
    smartFollow = true,        -- Use pathfinding when native follow fails
    aggressiveFollow = true    -- OpenTibiaBR: More aggressive re-follow
  }
  
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    local charConfig = CharacterDB.get("tools.followPlayer")
    if charConfig then
      config.enabled = charConfig.enabled or false
      config.playerName = charConfig.playerName or ""
      config.followWhileAttacking = charConfig.followWhileAttacking ~= false -- default true
      config.maxDistance = charConfig.maxDistance or 4
      config.combatWindowMs = charConfig.combatWindowMs or 1500
      config.smartFollow = charConfig.smartFollow ~= false
      config.aggressiveFollow = charConfig.aggressiveFollow ~= false
    end
    
    -- Migration from ProfileStorage
    local profileConfig = getProfileSetting("followPlayer")
    if profileConfig and profileConfig.playerName and config.playerName == "" then
      config.playerName = profileConfig.playerName
      CharacterDB.set("tools.followPlayer", config)
    end
  else
    -- Fallback to ProfileStorage
    local profileConfig = getProfileSetting("followPlayer")
    if profileConfig then
      config.enabled = profileConfig.enabled or false
      config.playerName = profileConfig.playerName or ""
      config.followWhileAttacking = profileConfig.followWhileAttacking ~= false
      config.maxDistance = profileConfig.maxDistance or 4
    end
  end
  
  return config
end

local followPlayerConfig = loadFollowPlayerConfig()

-- Forward decl for UI switch so helper can sync it
local followPlayerToggle = nil

-- State tracking (v4.0: Enhanced for parallel attack+follow)
local followState = {
  targetPlayerId = nil,
  targetPlayerCreature = nil,
  targetPlayerPosition = nil,
  lastFollowAttempt = 0,
  lastPathFollow = 0,
  lastNativeFollow = 0,        -- Track native follow attempts
  lastWalkStep = 0,            -- Track manual walk steps
  lastAttackReissue = 0,       -- NEW v4.0: Track attack re-issues
  combatStartTime = 0,
  pathToLeader = nil,
  pathTime = 0,
  lastLeaderDistance = 0,
  lostLeaderTime = 0,
  forceFollowMode = false,     -- When true, prioritize following over combat
  consecutiveFollowFails = 0,  -- Track native follow failures
  lastSuccessfulFollow = 0,    -- When native follow last worked
  walkingToLeader = false,     -- Currently path-walking to leader
  parallelMode = false,        -- NEW v4.0: Using parallel attack+follow
  currentAttackTarget = nil,   -- NEW v4.0: Current attack target creature
  currentAttackTargetId = nil, -- NEW v4.0: Current attack target ID
  pathIndex = 1,               -- NEW v4.0: Current position in path
}

-- v4.0: Tuned timings for parallel attack+follow
local FOLLOW_ATTEMPT_COOLDOWN = 50    -- Very fast checks
local PATH_RECALC_INTERVAL = 200      -- Path recalc interval
local NATIVE_FOLLOW_COOLDOWN = 200    -- Cooldown between native follow attempts
local WALK_STEP_COOLDOWN = 150        -- Cooldown between manual walk steps (slightly slower for stability)
local ATTACK_REISSUE_INTERVAL = 800   -- NEW v4.0: Re-issue attack every 800ms to maintain lock
local FORCE_FOLLOW_DISTANCE = 5       -- Distance at which we force follow over combat
local MAX_FOLLOW_FAILS = 3            -- After this many fails, switch to path-walking
local PATH_PARAMS = { ignoreCreatures = true, ignoreCost = true, allowNotSeenTiles = true }

-- Helper: save follow player settings
local function saveFollowPlayerConfig()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("tools.followPlayer", {
      enabled = followPlayerConfig.enabled,
      playerName = followPlayerConfig.playerName,
      followWhileAttacking = followPlayerConfig.followWhileAttacking,
      maxDistance = followPlayerConfig.maxDistance,
      combatWindowMs = followPlayerConfig.combatWindowMs,
      smartFollow = followPlayerConfig.smartFollow,
      aggressiveFollow = followPlayerConfig.aggressiveFollow
    })
  else
    setProfileSetting("followPlayer", followPlayerConfig)
  end
end

-- Safe creature getters
local function safeGetId(creature)
  if not creature then return nil end
  local ok, id = pcall(function() return creature:getId() end)
  return ok and id or nil
end

local function safeGetPosition(creature)
  if not creature then return nil end
  local ok, pos = pcall(function() return creature:getPosition() end)
  return ok and pos or nil
end

local function safeGetName(creature)
  if not creature then return nil end
  local ok, name = pcall(function() return creature:getName() end)
  return ok and name or nil
end

local function safeIsDead(creature)
  if not creature then return true end
  local ok, dead = pcall(function() return creature:isDead() end)
  return ok and dead or true
end

-- Calculate distance between positions (Chebyshev distance)
local function calcDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  if pos1.z ~= pos2.z then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Helper: Find player by name using OTClient's native functions for better performance
local function findPlayerByName(name)
  if not name or name == "" then return nil end

  -- First try exact match using OTClient helper (works for off-screen known creatures)
  local exact = SafeCall.getCreatureByName(name, true)
  if exact then
    local okPlayer, isPlayer = pcall(function() return exact:isPlayer() end)
    local okLocal, isLocal = pcall(function() return exact:isLocalPlayer() end)
    if okPlayer and isPlayer and (not okLocal or not isLocal) then
      return exact
    end
  end

  -- Fallback: Search through visible spectators for partial matches
  local lname = name:lower()
  local spectators = SafeCall.global("getSpectators") or {}

  for i, c in ipairs(spectators) do
    local okPlayer, isPlayer = pcall(function() return c and c:isPlayer() end)
    local okLocal, isLocal = pcall(function() return c and c:isLocalPlayer() end)
    if okPlayer and isPlayer and (not okLocal or not isLocal) then
      local cname = safeGetName(c)
      if cname and (cname:lower() == lname or cname:lower():find(lname, 1, true)) then
        return c
      end
    end
  end

  return nil
end

-- v3.0: Enhanced follow with OpenTibiaBR fallbacks
local function followStartCreature(creature)
  if not creature then return false end
  
  local currentTime = now or (os.time() * 1000)
  
  -- Store reference
  followState.targetPlayerId = safeGetId(creature)
  followState.targetPlayerCreature = creature
  followState.targetPlayerPosition = safeGetPosition(creature)
  followState.lastNativeFollow = currentTime
  
  -- Use native follow API with ClientService fallback
  local ok = pcall(function()
    local Client = getClient()
    -- Try multiple follow methods for OpenTibiaBR compatibility
    if Client and Client.follow then
      Client.follow(creature)
    elseif g_game and g_game.follow then
      g_game.follow(creature)
    elseif follow then
      follow(creature)
    else
      SafeCall.global("follow", creature)
    end
  end)
  
  if ok then
    followState.lastSuccessfulFollow = currentTime
    followState.consecutiveFollowFails = 0
  else
    followState.consecutiveFollowFails = followState.consecutiveFollowFails + 1
  end
  
  return ok
end

-- Follow manager: stop following
local function followStop()
  local Client = getClient()
  if Client and Client.cancelFollow then
    pcall(Client.cancelFollow)
  elseif g_game and g_game.cancelFollow then
    pcall(g_game.cancelFollow)
  end
  followState.targetPlayerId = nil
  followState.targetPlayerCreature = nil
  followState.targetPlayerPosition = nil
  followState.pathToLeader = nil
  followState.forceFollowMode = false
  followState.consecutiveFollowFails = 0
  followState.walkingToLeader = false
end

-- Check if we're currently following our target player
local function isFollowingTarget()
  if not followState.targetPlayerId then return false end
  local Client = getClient()
  local currentFollow = nil
  
  -- Try multiple methods for OpenTibiaBR
  if Client and Client.getFollowingCreature then
    currentFollow = Client.getFollowingCreature()
  elseif g_game and g_game.getFollowingCreature then
    currentFollow = g_game.getFollowingCreature()
  end
  
  if not currentFollow then return false end
  return safeGetId(currentFollow) == followState.targetPlayerId
end

-- v3.0: Enhanced path calculation with OpenTibiaBR g_map.findPath
local function getPathToLeader(leaderPos)
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer or not leaderPos then return nil, 999 end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return nil, 999 end
  
  -- Different floor = can't path
  if playerPos.z ~= leaderPos.z then return nil, 999 end
  
  -- Already adjacent = no path needed
  local dist = calcDistance(playerPos, leaderPos)
  if dist <= 1 then return {}, 0 end
  
  -- Try OpenTibiaBR native g_map.findPath first (most accurate)
  local path = nil
  local flags = 1 + 16  -- ALLOW_NOT_SEEN + IGNORE_CREATURES
  
  if g_map and g_map.findPath then
    local ok, result, _ = pcall(function()
      return g_map.findPath(playerPos, leaderPos, 50, flags)
    end)
    if ok and result and #result > 0 then
      path = result
    end
  end
  
  -- Fallback to bot's findPath
  if not path then
    if findPath then
      local ok, result = pcall(function() return findPath(playerPos, leaderPos, 20, PATH_PARAMS) end)
      if ok then path = result end
    elseif getPath then
      local ok, result = pcall(function() return getPath(playerPos, leaderPos, 20, PATH_PARAMS) end)
      if ok then path = result end
    end
  end
  
  local pathLen = path and #path or 999
  return path, pathLen
end

-- v3.0: Aggressive walking to leader (for when native follow fails)
local function walkStepToLeader(leaderPos)
  if not leaderPos then return false end
  
  local currentTime = now or (os.time() * 1000)
  if (currentTime - followState.lastWalkStep) < WALK_STEP_COOLDOWN then
    return false
  end
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer then return false end
  
  -- Don't walk while already walking
  local isWalking = localPlayer.isWalking and localPlayer:isWalking()
  if isWalking then return false end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return false end
  
  local path, pathLen = getPathToLeader(leaderPos)
  
  if path and pathLen > 0 then
    followState.pathToLeader = path
    followState.pathTime = currentTime
    followState.walkingToLeader = true
    
    -- Take the first step
    local nextDir = path[1]
    if nextDir then
      followState.lastWalkStep = currentTime
      
      -- Use native walk
      local walkOk = false
      if localPlayer.walk then
        walkOk = pcall(function() localPlayer:walk(nextDir) end)
      end
      if not walkOk and g_game and g_game.walk then
        walkOk = pcall(function() g_game.walk(nextDir) end)
      end
      if not walkOk and walk then
        walkOk = pcall(function() walk(nextDir) end)
      end
      
      return walkOk
    end
  end
  
  return false
end

-- v3.0: Smart walk with MovementCoordinator integration
local function smartWalkToLeader(leaderPos)
  if not leaderPos then return false end
  if not followPlayerConfig.smartFollow then return false end
  
  local currentTime = now or (os.time() * 1000)
  if (currentTime - followState.lastPathFollow) < PATH_RECALC_INTERVAL then
    return false
  end
  followState.lastPathFollow = currentTime
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer then return false end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return false end
  
  local path, pathLen = getPathToLeader(leaderPos)
  
  if path and pathLen > 0 and pathLen < 25 then
    followState.pathToLeader = path
    followState.pathTime = currentTime
    
    -- Use MovementCoordinator if available (integrates with TargetBot)
    if MovementCoordinator and MovementCoordinator.Intent then
      local confidence = 0.88  -- High priority for following leader
      if followState.forceFollowMode then
        confidence = 0.96  -- Very high when in force follow mode
      end
      
      MovementCoordinator.Intent.register(
        MovementCoordinator.CONSTANTS and MovementCoordinator.CONSTANTS.INTENT and 
          MovementCoordinator.CONSTANTS.INTENT.FOLLOW or "follow",
        leaderPos,
        confidence,
        "party_follow",
        { leader = followPlayerConfig.playerName, distance = pathLen }
      )
      return true
    end
    
    -- Fallback: Use autoWalk for multi-step paths
    if pathLen > 1 then
      local ok = false
      if localPlayer.autoWalk then
        ok = pcall(function() localPlayer:autoWalk(path) end)
      end
      if ok then
        followState.walkingToLeader = true
        return true
      end
    end
    
    -- Final fallback: Manual single step
    return walkStepToLeader(leaderPos)
  end
  
  return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PARALLEL ATTACK+FOLLOW SYSTEM v4.0
-- Walk toward leader while maintaining attack on current target
-- Key insight: Native follow() cancels attack, but walk() does not!
-- ═══════════════════════════════════════════════════════════════════════════

-- Re-issue attack command to maintain target lock
local function reissueAttack()
  if not followState.currentAttackTarget then return false end
  
  local currentTime = now or (os.time() * 1000)
  if (currentTime - followState.lastAttackReissue) < ATTACK_REISSUE_INTERVAL then
    return true -- Still within interval, attack should be active
  end
  
  -- Verify target is still valid
  local target = followState.currentAttackTarget
  if safeIsDead(target) then
    followState.currentAttackTarget = nil
    followState.currentAttackTargetId = nil
    followState.parallelMode = false
    return false
  end
  
  -- Re-issue attack command
  local Client = getClient()
  local attackOk = false
  
  if Client and Client.attack then
    attackOk = pcall(function() Client.attack(target) end)
  elseif g_game and g_game.attack then
    attackOk = pcall(function() g_game.attack(target) end)
  elseif attack then
    attackOk = pcall(function() attack(target) end)
  end
  
  if attackOk then
    followState.lastAttackReissue = currentTime
  end
  
  return attackOk
end

-- Get current attack target from game state
local function getCurrentAttackTarget()
  local Client = getClient()
  local target = nil
  
  if Client and Client.getAttackingCreature then
    target = Client.getAttackingCreature()
  elseif g_game and g_game.getAttackingCreature then
    target = g_game.getAttackingCreature()
  end
  
  return target
end

-- Walk one step toward leader using forceWalk (OpenTibiaBR) or regular walk
-- This does NOT cancel the attack!
local function parallelWalkStep(leaderPos)
  if not leaderPos then return false end
  
  local currentTime = now or (os.time() * 1000)
  if (currentTime - followState.lastWalkStep) < WALK_STEP_COOLDOWN then
    return false
  end
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer then return false end
  
  -- Check if we're currently walking
  local isWalking = localPlayer.isWalking and localPlayer:isWalking()
  if isWalking then return false end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return false end
  
  -- Calculate path to leader
  local path, pathLen = getPathToLeader(leaderPos)
  
  if not path or pathLen == 0 then
    -- Already adjacent or can't path
    return false
  end
  
  -- Get next direction to walk
  local nextDir = path[1]
  if not nextDir then return false end
  
  followState.lastWalkStep = currentTime
  followState.pathToLeader = path
  followState.pathIndex = 1
  
  -- Use OpenTibiaBR forceWalk if available (most reliable)
  local walkOk = false
  if g_game and g_game.forceWalk then
    walkOk = pcall(function() g_game.forceWalk(nextDir) end)
  end
  
  -- Fallback to regular walk
  if not walkOk then
    if localPlayer.walk then
      walkOk = pcall(function() localPlayer:walk(nextDir) end)
    end
    if not walkOk and g_game and g_game.walk then
      walkOk = pcall(function() g_game.walk(nextDir) end)
    end
    if not walkOk and walk then
      walkOk = pcall(function() walk(nextDir) end)
    end
  end
  
  return walkOk
end

-- Main parallel attack+follow execution
-- This runs when we're attacking AND need to follow the leader
local function executeParallelAttackFollow(leaderPos)
  if not leaderPos then return false end
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer then return false end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return false end
  
  local distance = calcDistance(playerPos, leaderPos)
  
  -- If we're close enough, no need to walk
  if distance <= 1 then
    followState.parallelMode = false
    return true
  end
  
  -- Track current attack target for re-issuing
  local currentTarget = getCurrentAttackTarget()
  if currentTarget then
    followState.currentAttackTarget = currentTarget
    followState.currentAttackTargetId = safeGetId(currentTarget)
  end
  
  -- Step 1: Re-issue attack to maintain target lock
  reissueAttack()
  
  -- Step 2: Take a walk step toward leader
  local walked = parallelWalkStep(leaderPos)
  
  -- Step 3: If we walked, re-issue attack again after a short delay
  -- This ensures we don't lose the attack when walking
  if walked and followState.currentAttackTarget then
    -- Schedule attack re-issue after walk step completes
    schedule(100, function()
      reissueAttack()
    end)
  end
  
  return walked
end

-- Check combat window - should we stop fighting to follow?
local function shouldForceFollow()
  if not followPlayerConfig.enabled then return false end
  if not followState.targetPlayerPosition then return false end
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer then return false end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return false end
  
  local leaderPos = followState.targetPlayerPosition
  local distance = calcDistance(playerPos, leaderPos)
  followState.lastLeaderDistance = distance
  
  -- Check if we're too far from leader
  if distance > FORCE_FOLLOW_DISTANCE then
    -- Check if we've been in combat too long
    local currentTime = now or (os.time() * 1000)
    if followState.combatStartTime > 0 then
      local combatDuration = currentTime - followState.combatStartTime
      if combatDuration > (followPlayerConfig.combatWindowMs or 1500) then
        return true
      end
    end
    
    -- Or if we're very far, force follow immediately
    if distance > (followPlayerConfig.maxDistance or 4) + 2 then
      return true
    end
  end
  
  return false
end

-- v4.0: Main follow logic - PARALLEL attack+follow for OpenTibiaBR
local function ensureFollowing()
  if not followPlayerConfig.enabled then return end
  
  local currentTime = now or (os.time() * 1000)
  if (currentTime - followState.lastFollowAttempt) < FOLLOW_ATTEMPT_COOLDOWN then return end
  followState.lastFollowAttempt = currentTime
  
  local name = followPlayerConfig.playerName and followPlayerConfig.playerName:trim() or ""
  if name == "" then return end
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  if not localPlayer then return end
  
  local playerPos = safeGetPosition(localPlayer)
  if not playerPos then return end
  
  -- Try to find the target player first
  local target = findPlayerByName(name)
  
  if target then
    -- Update our cached reference
    followState.targetPlayerId = safeGetId(target)
    followState.targetPlayerCreature = target
    followState.targetPlayerPosition = safeGetPosition(target)
    followState.lostLeaderTime = 0
    
    local leaderPos = followState.targetPlayerPosition
    local distance = calcDistance(playerPos, leaderPos)
    followState.lastLeaderDistance = distance
    
    -- Check if we're attacking
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    
    if isAttacking then
      if followState.combatStartTime == 0 then
        followState.combatStartTime = currentTime
      end
      
      -- ═══════════════════════════════════════════════════════════════════════
      -- v4.0 PARALLEL MODE: Walk toward leader while maintaining attack
      -- This is the key change - we DON'T cancel attack, we walk AND attack!
      -- ═══════════════════════════════════════════════════════════════════════
      
      -- Check if followWhileAttacking is enabled
      if followPlayerConfig.followWhileAttacking and distance > 1 then
        followState.parallelMode = true
        
        -- Use parallel attack+follow system
        executeParallelAttackFollow(leaderPos)
        
        -- Emit event for other modules to know we're in parallel mode
        if EventBus then
          pcall(function()
            EventBus.emit("followplayer/parallel_mode", leaderPos, distance, followState.currentAttackTargetId)
          end)
        end
        
        return -- Don't use native follow, we're walking manually
      end
      
      -- Check if we should force follow (only when followWhileAttacking is OFF)
      if not followPlayerConfig.followWhileAttacking and shouldForceFollow() then
        followState.forceFollowMode = true
        followState.parallelMode = false
        
        -- Cancel attack to follow leader (party survival priority)
        if Client and Client.cancelAttack then
          pcall(Client.cancelAttack)
        elseif g_game and g_game.cancelAttack then
          pcall(g_game.cancelAttack)
        end
        
        -- Emit event for TargetBot to know we're prioritizing follow
        if EventBus then
          pcall(function()
            EventBus.emit("followplayer/force_follow", leaderPos, distance)
          end)
        end
      elseif not followPlayerConfig.followWhileAttacking then
        return -- Don't follow while attacking if option is disabled
      end
    else
      -- Reset combat tracking when not attacking
      followState.combatStartTime = 0
      followState.forceFollowMode = false
      followState.parallelMode = false
      followState.currentAttackTarget = nil
      followState.currentAttackTargetId = nil
    end
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- NOT ATTACKING: Use native follow or smart walk
    -- ═══════════════════════════════════════════════════════════════════════
    if not isAttacking then
      -- Check if we're already following them
      local currentFollow = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
      local isFollowing = currentFollow and safeGetId(currentFollow) == followState.targetPlayerId
      
      if not isFollowing then
        -- Not following our target - try native follow first
        local isWalking = localPlayer:isWalking()
        
        if not isWalking then
          local followOk = followStartCreature(target)
          
          -- If native follow failed or we're far, use smart pathfinding
          if (not followOk or distance > 3) and followPlayerConfig.smartFollow then
            smartWalkToLeader(leaderPos)
          end
        end
      elseif distance > 5 and followPlayerConfig.smartFollow then
        -- We're "following" but still far - use smart walk to catch up
        smartWalkToLeader(leaderPos)
      end
    end
  else
    -- Player not visible
    if followState.lostLeaderTime == 0 then
      followState.lostLeaderTime = currentTime
    end
    
    -- Check if native follow is still tracking them
    local currentFollow = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
    if currentFollow and followState.targetPlayerId and safeGetId(currentFollow) == followState.targetPlayerId then
      -- Native follow is still tracking, update position
      followState.targetPlayerPosition = safeGetPosition(currentFollow)
      return
    end
    
    -- If we have last known position and haven't been lost long, walk there
    if followState.targetPlayerPosition and followPlayerConfig.smartFollow then
      local timeLost = currentTime - followState.lostLeaderTime
      if timeLost < 5000 then  -- Try for 5 seconds
        -- If attacking, use parallel mode
        local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
        if isAttacking and followPlayerConfig.followWhileAttacking then
          executeParallelAttackFollow(followState.targetPlayerPosition)
        else
          smartWalkToLeader(followState.targetPlayerPosition)
        end
      end
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENT-DRIVEN FOLLOW (High performance using EventBus)
-- Reacts instantly to player movements and combat state changes
-- ═══════════════════════════════════════════════════════════════════════════

if EventBus then
  -- v3.0: Aggressive creature:move handler for OpenTibiaBR
  -- When followed player moves, ensure we're still following them
  EventBus.on("creature:move", function(creature, oldPos)
    if not followPlayerConfig.enabled then return end
    
    -- Safe player check
    local okPlayer, isPlayer = pcall(function() return creature and creature:isPlayer() end)
    if not okPlayer or not isPlayer then return end
    if not followState.targetPlayerId then return end
    
    -- Check if this is our followed player
    local creatureId = safeGetId(creature)
    if creatureId ~= followState.targetPlayerId then return end
    
    -- Update last known position
    local newPos = safeGetPosition(creature)
    followState.targetPlayerPosition = newPos
    followState.targetPlayerCreature = creature
    
    -- Check distance
    local Client = getClient()
    local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
    if localPlayer then
      local playerPos = safeGetPosition(localPlayer)
      if playerPos and newPos then
        local distance = calcDistance(playerPos, newPos)
        followState.lastLeaderDistance = distance
        
        -- v3.0: More aggressive - if distance > 2, ensure we're moving
        if distance > 2 then
          -- Check if we're actually following
          local currentFollow = nil
          if Client and Client.getFollowingCreature then
            currentFollow = Client.getFollowingCreature()
          elseif g_game and g_game.getFollowingCreature then
            currentFollow = g_game.getFollowingCreature()
          end
          
          local isFollowing = currentFollow and safeGetId(currentFollow) == followState.targetPlayerId
          local isWalking = localPlayer.isWalking and localPlayer:isWalking()
          
          -- If not following and not walking, we're frozen - fix it!
          if not isFollowing and not isWalking then
            -- Immediate re-follow attempt
            followStartCreature(creature)
            
            -- Also try smart walk as backup
            if distance > 3 and followPlayerConfig.smartFollow then
              schedule(50, function()
                if followPlayerConfig.enabled then
                  smartWalkToLeader(newPos)
                end
              end)
            end
          elseif distance > 4 then
            -- Even if following, verify we're making progress
            schedule(25, ensureFollowing)
          end
        end
      end
    end
  end, 30)  -- Higher priority for party following
  
  -- When we stop attacking, immediately resume following
  EventBus.on("combat:end", function()
    if not followPlayerConfig.enabled then return end
    if not followState.targetPlayerId then return end
    
    followState.combatStartTime = 0
    followState.forceFollowMode = false
    
    -- Immediate follow resume
    schedule(50, ensureFollowing)
  end, 20)
  
  -- When we start attacking, track combat start time
  EventBus.on("combat:start", function(creature)
    if not followPlayerConfig.enabled then return end
    
    local currentTime = now or (os.time() * 1000)
    if followState.combatStartTime == 0 then
      followState.combatStartTime = currentTime
    end
  end, 15)
  
  -- When target changes (new attack target), manage combat window
  EventBus.on("combat:target", function(creature, oldCreature)
    if not followPlayerConfig.enabled then return end
    if not followPlayerConfig.followWhileAttacking then return end
    if not followState.targetPlayerId then return end
    
    local currentTime = now or (os.time() * 1000)
    
    if creature then
      -- Started attacking new target
      if oldCreature == nil then
        -- Fresh combat start
        followState.combatStartTime = currentTime
      end
      -- Continue following even while attacking
      schedule(100, ensureFollowing)
    else
      -- Stopped attacking
      followState.combatStartTime = 0
      followState.forceFollowMode = false
      schedule(50, ensureFollowing)
    end
  end, 15)
  
  -- When player moves (self), check if we need to catch up
  EventBus.on("player:move", function(newPos, oldPos)
    if not followPlayerConfig.enabled then return end
    if not followState.targetPlayerPosition then return end
    
    local distance = calcDistance(newPos, followState.targetPlayerPosition)
    followState.lastLeaderDistance = distance
    
    -- If we're getting close, native follow should work
    -- If we're still far, keep smart walking
    if distance > 5 then
      schedule(100, ensureFollowing)
    end
  end, 10)
  
  -- When followed player appears (comes into view), start following
  EventBus.on("creature:appear", function(creature)
    if not followPlayerConfig.enabled then return end
    
    -- Safe player check
    local okPlayer, isPlayer = pcall(function() return creature and creature:isPlayer() end)
    if not okPlayer or not isPlayer then return end
    
    local name = followPlayerConfig.playerName and followPlayerConfig.playerName:trim():lower() or ""
    if name == "" then return end
    
    local creatureName = safeGetName(creature)
    if creatureName then
      creatureName = creatureName:lower()
      if creatureName == name or creatureName:find(name, 1, true) then
        -- Our target player appeared! Start following
        followState.lostLeaderTime = 0
        followStartCreature(creature)
      end
    end
  end, 30)
  
  -- When followed player disappears, track lost time but don't clear state
  EventBus.on("creature:disappear", function(creature)
    if not creature then return end
    local creatureId = safeGetId(creature)
    if followState.targetPlayerId and creatureId == followState.targetPlayerId then
      -- Player went out of view
      followState.targetPlayerCreature = nil
      followState.lostLeaderTime = now or (os.time() * 1000)
      -- Keep targetPlayerId and targetPlayerPosition for recovery
    end
  end, 15)
  
  -- Integration with TargetBot: When TargetBot wants to move, coordinate
  EventBus.on("targetbot/movement_intent", function(intentType, targetPos, confidence)
    if not followPlayerConfig.enabled then return end
    if not followState.forceFollowMode then return end
    
    -- In force follow mode, reject low-confidence movement intents
    -- This helps prevent getting pulled away by TargetBot when we need to catch up
    if confidence and confidence < 0.80 then
      -- Emit that we're overriding
      pcall(function()
        EventBus.emit("followplayer/override_movement", intentType, "force_follow_active")
      end)
    end
  end, 5)  -- Very high priority to intercept
  
  -- Listen for TargetBot allowing CaveBot (we can piggyback on this)
  EventBus.on("targetbot/cavebot_allowed", function()
    if not followPlayerConfig.enabled then return end
    -- Good time to ensure following since TargetBot isn't busy
    schedule(25, ensureFollowing)
  end, 10)
end

-- v3.0: Faster backup macro for OpenTibiaBR responsiveness
-- Runs every 75ms instead of 200ms to prevent "freeze" issues
local followPlayerMacro = macro(75, function()
  ensureFollowing()
end)

-- Small status indicator (non-intrusive)
local followStatusLabel = UI.Label((followPlayerConfig.playerName and followPlayerConfig.playerName ~= "") and ("Target: "..followPlayerConfig.playerName) or "Target: -")
followStatusLabel:setId("followStatusLabel")
followStatusLabel:setTooltip("Shows current follow target, distance, and status")

-- Helper to update status label
local function updateFollowStatusLabel()
  local Client = getClient()
  local current = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
  local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
  local distance = followState.lastLeaderDistance or 0
  
  if current and followState.targetPlayerId and safeGetId(current) == followState.targetPlayerId then
    local suffix = ""
    if followState.forceFollowMode then
      suffix = " [CATCH UP!]"
    elseif isAttacking then
      suffix = " (attacking)"
    end
    followStatusLabel:setText("Following: " .. safeGetName(current) .. " [" .. distance .. "m]" .. suffix)
  elseif followState.targetPlayerId and followState.targetPlayerCreature then
    local name = safeGetName(followState.targetPlayerCreature) or "..."
    followStatusLabel:setText("Tracking: " .. name .. " [" .. distance .. "m]")
  else
    followStatusLabel:setText("Target: " .. (followPlayerConfig.playerName ~= "" and followPlayerConfig.playerName or "-"))
  end
end

-- Update label periodically
schedule(500, function()
  if followStatusLabel and followStatusLabel:isVisible() then 
    updateFollowStatusLabel() 
  end
end)

-- Initialize macro state based on config
if followPlayerConfig.enabled then
  followPlayerMacro:setOn()
else
  followPlayerMacro:setOff()
end

-- Helper: sync state, UI, and side effects
local function setFollowEnabled(state)
  followPlayerConfig.enabled = state
  saveFollowPlayerConfig()
  if followPlayerToggle then
    followPlayerToggle:setOn(state)
  end

  if followPlayerMacro then
    if state then
      pcall(function() followPlayerMacro:setOn() end)

      -- If we have a name set, attempt immediate follow
      if followPlayerConfig.playerName and followPlayerConfig.playerName ~= "" then
        local tgt = findPlayerByName(followPlayerConfig.playerName)
        if tgt then
          followStartCreature(tgt)
        end
      end
      
      -- Emit event for other modules
      if EventBus then
        pcall(function()
          EventBus.emit("followplayer/enabled", followPlayerConfig.playerName)
        end)
      end
    else
      pcall(function() followPlayerMacro:setOff() end)
      followStop()
      
      if EventBus then
        pcall(function()
          EventBus.emit("followplayer/disabled")
        end)
      end
    end
  end
end

-- Target input
UI.Label("Target:")

local followPlayerNameEdit = UI.TextEdit(followPlayerConfig.playerName, function(widget, text)
  followPlayerConfig.playerName = text:trim()
  saveFollowPlayerConfig()
  -- If enabled, attempt to follow immediately
  if followPlayerConfig.enabled and followPlayerConfig.playerName ~= "" then
    local tgt = findPlayerByName(followPlayerConfig.playerName)
    if tgt then
      followStartCreature(tgt)
    else
      followStop()
    end
  end
end)

-- Follow while attacking toggle
local followWhileAttackingUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: followWhileAttackingToggle
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Follow While Attacking')
    tooltip: Keep following player even when attacking monsters with TargetBot
]])

followWhileAttackingUI.followWhileAttackingToggle:setOn(followPlayerConfig.followWhileAttacking)
followWhileAttackingUI.followWhileAttackingToggle.onClick = function(widget)
  followPlayerConfig.followWhileAttacking = not followPlayerConfig.followWhileAttacking
  widget:setOn(followPlayerConfig.followWhileAttacking)
  saveFollowPlayerConfig()
end

local followToggleUI = setupUI([[
Panel
  height: 19

  BotSwitch
    id: followPlayerToggle
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Follow')
]])

followPlayerToggle = followToggleUI.followPlayerToggle
followPlayerToggle:setOn(followPlayerConfig.enabled)
followPlayerToggle.onClick = function(widget)
  setFollowEnabled(not followPlayerConfig.enabled)
end

UI.Separator()

-- ═══════════════════════════════════════════════════════════════════════════
-- MANA TRAINING - Per-character settings via CharacterDB
-- ═══════════════════════════════════════════════════════════════════════════

-- Load mana training settings from CharacterDB (per-character) with fallbacks
local function loadManaTrainingSettings()
  local settings = { spell = "exura", minManaPercent = 80 }
  
  -- Try CharacterDB first (per-character)
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    local charSettings = CharacterDB.get("tools.manaTraining")
    if charSettings then
      settings.spell = charSettings.spell or "exura"
      settings.minManaPercent = charSettings.minManaPercent or 80
    end
    
    -- Migration from legacy storage
    if storage and storage.manaTrainingSpell and settings.spell == "exura" then
      settings.spell = storage.manaTrainingSpell
      CharacterDB.set("tools.manaTraining", settings)
    end
  else
    -- Fallback to legacy storage
    if storage and storage.manaTrainingSpell then
      settings.spell = storage.manaTrainingSpell
    end
    -- Profile-level fallback
    local profileSettings = getProfileSetting("manaTraining")
    if profileSettings then
      if not storage or not storage.manaTrainingSpell then
        settings.spell = profileSettings.spell or "exura"
      end
      settings.minManaPercent = profileSettings.minManaPercent or 80
    end
  end
  
  return settings
end

local manaTraining = loadManaTrainingSettings()

local function sanitizeSpell(text)
  text = text or ""
  text = text:match("^%s*(.-)%s*$")
  if text == "" then
    return "exura"
  end
  return text
end

local function getManaPercent()
  if not player then return 0 end
  local current = player.getMana and player:getMana() or 0
  local maximum = player.getMaxMana and player:getMaxMana() or 0
  if maximum <= 0 then return 0 end
  return (current / maximum) * 100
end

-- Helper to save mana training settings to CharacterDB
local function saveManaTrainingSettings()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("tools.manaTraining", {
      spell = manaTraining.spell,
      minManaPercent = manaTraining.minManaPercent
    })
  else
    -- Fallback to legacy storage
    if storage then storage.manaTrainingSpell = manaTraining.spell end
  end
end

UI.Label("Mana Training:")

UI.Label("Spell to cast (default: exura):")
UI.TextEdit(manaTraining.spell or "exura", function(widget, text)
  manaTraining.spell = sanitizeSpell(text)
  saveManaTrainingSettings()
end)

UI.Label("Min mana % to train (10-100):")
UI.TextEdit(tostring(manaTraining.minManaPercent or 80), function(widget, text)
  local value = tonumber(text)
  if not value then return end
  if value < 10 then value = 10 end
  if value > 100 then value = 100 end
  manaTraining.minManaPercent = value
  saveManaTrainingSettings()
end)

-- Mana Training macro with built-in toggle (like Hold Target)
local lastTrainCast = 0
local TRAIN_COOLDOWN = 1000

local manaTrainingMacro = macro(500, "Mana Training", function()
  if not player then return end
  if (now - lastTrainCast) < TRAIN_COOLDOWN then return end

  local manaPercent = getManaPercent()
  if manaPercent < (manaTraining.minManaPercent or 80) then return end

  local spell = sanitizeSpell(manaTraining.spell)
  if not spell or spell == "" then return end

  say(spell)
  lastTrainCast = now
end)
BotDB.registerMacro(manaTrainingMacro, "manaTraining")

UI.Separator()
