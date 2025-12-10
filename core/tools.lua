-- Tools tab widgets and macros
setDefaultTab("Tools")

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
-- MONEY EXCHANGER (Optimized)
-- Automatically exchanges 100 gold → platinum, 100 platinum → crystal
-- Works on all open containers including nested backpacks
-- ═══════════════════════════════════════════════════════════════════════════

--[[
  Money Exchange System
  
  Pure function design:
  - isExchangeable(item) → boolean (pure)
  - findExchangeableItem(containers) → item or nil (pure)
  - exchangeItem(item) → void (side effect, isolated)
  
  Coin IDs:
  - 3031 = Gold Coin (100 → 1 Platinum)
  - 3035 = Platinum Coin (100 → 1 Crystal)
  - 3043 = Crystal Coin (no exchange)
]]

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
  local containers = g_game.getContainers()
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
  g_game.use(item)
  return true
end

-- Cooldown state
local lastExchangeTime = 0
local EXCHANGE_COOLDOWN = 500  -- 500ms between exchanges for reliability

-- Main macro
macro(200, "Exchange Money", function()
  -- Cooldown check
  if (now - lastExchangeTime) < EXCHANGE_COOLDOWN then return end
  
  -- Find and exchange
  local item = findExchangeableItem()
  if item then
    exchangeItem(item)
    lastExchangeTime = now
  end
end)

UI.Separator()

-- Auto trade message --------------------------------------------------------
local autoTradeMessage = getProfileSetting("autoTradeMessage") or "nExBot is online!"

macro(60 * 1000, "Send message on trade", function()
  local trade = getChannelId("advertising") or getChannelId("trade")
  local message = autoTradeMessage or ""
  if trade and message:len() > 0 then
    sayChannel(trade, message)
  end
end)

local tradeMessageEdit = UI.TextEdit(autoTradeMessage, function(widget, text)
  autoTradeMessage = text
  setProfileSetting("autoTradeMessage", text)
end)

UI.Separator()

UI.Label("Tools:")

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

macro(500, "Auto Haste", function()
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

-- Auto Mount ----------------------------------------------------------------
-- Automatically mounts player when outside of PZ
-- Uses the player's default mount from client settings
-- Does NOT attempt to mount in PZ (saves CPU/memory)
-- State is saved PER CHARACTER using storage

local lastMountAttempt = 0
local MOUNT_COOLDOWN = 2000 -- Don't spam mount attempts
local autoMountInitialized = false -- Prevent running before state is loaded

-- Helper to get character-specific storage key
local function getCharStorageKey(key)
  local charName = player and name() or "unknown"
  storage.charSettings = storage.charSettings or {}
  storage.charSettings[charName] = storage.charSettings[charName] or {}
  return storage.charSettings[charName], key
end

-- Load/save per-character Auto Mount state
local function getAutoMountState()
  local charStorage, key = getCharStorageKey("autoMount")
  return charStorage[key] == true
end

local function setAutoMountState(enabled)
  local charStorage, key = getCharStorageKey("autoMount")
  charStorage[key] = enabled
end

-- Create the macro (starts OFF, state will be loaded from per-char storage)
local autoMountMacro = macro(500, "Auto Mount", function()
  -- Don't run until per-character state has been loaded
  if not autoMountInitialized then return end
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
  if g_game.mount then
    g_game.mount(true)
    lastMountAttempt = now
  end
end)

-- Start with macro OFF to prevent premature execution
autoMountMacro.setOff()

-- Handle state changes and persist per-character
autoMountMacro.onSwitch = function(m, enabled)
  if autoMountInitialized then
    setAutoMountState(enabled)
  end
end

-- Restore per-character state on load (after a delay to ensure player is ready)
schedule(1000, function()
  if player then
    local savedState = getAutoMountState()
    autoMountMacro.setOn(savedState)
  end
  autoMountInitialized = true
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- FISHING (Optimized with Random Spot Selection + Auto Fish Drop)
-- Automatically fishes on random water tiles within range
-- Drops caught fish to random water tiles
-- Uses per-character state persistence like Auto Mount
-- ═══════════════════════════════════════════════════════════════════════════

--[[
  Fishing System - Pure Function Architecture
  
  Design Principles:
  - SRP: Each function has one responsibility
  - DRY: Reusable utility functions
  - KISS: Simple, focused logic
  - Pure Functions: No side effects in detection functions
  
  Features:
  - Simple and reliable implementation
  - Uses g_game.useWith() directly
  - Random water tile selection
  - Respects exhausted cooldown
]]

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
local fishingInitialized = false
local fishingDebug = false -- Set to true to enable debug messages

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
  for dx = -FISHING_RANGE, FISHING_RANGE do
    for dy = -FISHING_RANGE, FISHING_RANGE do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
        local tile = g_map.getTile(checkPos)
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
        g_game.move(itemToDrop, waterPos, itemToDrop:getCount())
        lastDropTime = now
        return -- One action per tick
      end
    end
  end
  
  -- Second: Fish (1 second cooldown)
  if now - lastFishTime < 1000 then return end
  
  -- Find all water tiles nearby
  local waterTiles = {}
  
  for dx = -FISHING_RANGE, FISHING_RANGE do
    for dy = -FISHING_RANGE, FISHING_RANGE do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {x = ppos.x + dx, y = ppos.y + dy, z = ppos.z}
        local tile = g_map.getTile(checkPos)
        
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
    g_game.useWith(rod, target)
    lastFishTime = now
  elseif g_game.getClientVersion() >= 780 and g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(FISHING_ROD_ID, target, 0)
    lastFishTime = now
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

-- Load saved state from ProfileStorage
local savedFishingState = getProfileSetting("fishingEnabled")
if savedFishingState == true then
  fishingEnabled = true
  fishingUI.title:setOn(true)
end

-- Handle click - toggle and save
fishingUI.title.onClick = function(widget)
  fishingEnabled = not fishingEnabled
  widget:setOn(fishingEnabled)
  setProfileSetting("fishingEnabled", fishingEnabled)
end

UI.Separator()

-- NOTE: Low Power Mode removed - OTClient v8 bot API does not expose FPS control
-- FPS is managed at the client level (Options > Graphics), not through bot scripts

-- Mana training -------------------------------------------------------------
local manaTraining = getProfileSetting("manaTraining") or {
  spell = "exura",
  minManaPercent = 80
}

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

UI.Label("Mana Training:")

UI.Label("Spell to cast (default: exura):")
UI.TextEdit(manaTraining.spell or "exura", function(widget, text)
  manaTraining.spell = sanitizeSpell(text)
  setProfileSetting("manaTraining", manaTraining)
end)

UI.Label("Min mana % to train (10-100):")
UI.TextEdit(tostring(manaTraining.minManaPercent or 80), function(widget, text)
  local value = tonumber(text)
  if not value then return end
  if value < 10 then value = 10 end
  if value > 100 then value = 100 end
  manaTraining.minManaPercent = value
  setProfileSetting("manaTraining", manaTraining)
end)

-- Mana Training macro with built-in toggle (like Hold Target)
local lastTrainCast = 0
local TRAIN_COOLDOWN = 1000

macro(500, "Mana Training", function()
  if not player then return end
  if (now - lastTrainCast) < TRAIN_COOLDOWN then return end

  local manaPercent = getManaPercent()
  if manaPercent < (manaTraining.minManaPercent or 80) then return end

  local spell = sanitizeSpell(manaTraining.spell)
  if not spell or spell == "" then return end

  say(spell)
  lastTrainCast = now
end)

UI.Separator()
