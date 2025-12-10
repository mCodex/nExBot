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

macro(100, "Auto Haste", function()
  if not player then return end
  local vocation = player:getVocation()
  local haste = HASTE_SPELLS[vocation]
  if not haste then return end
  if hasHaste and hasHaste() then return end
  if mana() < haste.mana then return end
  if getSpellCoolDown and getSpellCoolDown(haste.spell) then return end
  say(haste.spell)
end)

UI.Separator()

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
