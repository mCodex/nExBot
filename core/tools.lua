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
  if g_game.mount then
    g_game.mount(true)
    lastMountAttempt = now
  end
end)
BotDB.registerMacro(autoMountMacro, "autoMount")

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

-- Connect UI switch to macro state using BotDB
fishingUI.title.onClick = function(widget)
  fishingEnabled = not fishingEnabled
  widget:setOn(fishingEnabled)
  BotDB.set("macros.fishing", fishingEnabled)
end

-- Restore fishing state on load (synchronous)
local savedFishingState = BotDB.get("macros.fishing") == true
if savedFishingState then
  fishingEnabled = true
  fishingUI.title:setOn(true)
end

UI.Separator()

-- ═══════════════════════════════════════════════════════════════════════════
-- FOLLOW PLAYER - Use OTClient's native follow system (like CTRL + Right Click)
-- ═══════════════════════════════════════════════════════════════════════════

-- Follow Player settings (stored per-profile)
local followPlayerConfig = getProfileSetting("followPlayer") or {
  enabled = false,
  playerName = ""
}

-- Forward decl for UI switch so helper can sync it
local followPlayerToggle = nil

local lastFollowCheck = 0
local FOLLOW_CHECK_COOLDOWN = 500  -- Check every 500ms

-- Helper: sync state, UI, and side effects
local function setFollowEnabled(state)
  followPlayerConfig.enabled = state
  setProfileSetting("followPlayer", followPlayerConfig)
  if followPlayerToggle then
    followPlayerToggle:setOn(state)
  end
  if not state then
    g_game.cancelFollow()
  end
end

-- Follow Player macro - Uses native OTClient follow system
local followPlayerMacro = macro(500, function()
  if not followPlayerConfig.enabled or not player then return end
  if not followPlayerConfig.playerName or followPlayerConfig.playerName == "" then return end
  
  -- Cooldown check
  if (now - lastFollowCheck) < FOLLOW_CHECK_COOLDOWN then return end
  lastFollowCheck = now

  -- If player started attacking, stop following and disable toggle
  if getTarget() then
    if followPlayerConfig.enabled then
      setFollowEnabled(false)
    end
    return
  end
  
  -- Find the target player
  local target = getCreatureByName(followPlayerConfig.playerName)
  
  if target then
    -- Start following the target (like CTRL + Right Click) only if not already
    local currentFollow = g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
    if not currentFollow or currentFollow:getId() ~= target:getId() then
      follow(target)
    end
  else
    -- Target not found, cancel follow if we were following someone
    g_game.cancelFollow()
  end
end)

BotDB.registerMacro(followPlayerMacro, "followPlayer")

-- Follow Player UI
UI.Label("Follow Player:")

local followPlayerNameEdit = UI.TextEdit(followPlayerConfig.playerName, function(widget, text)
  followPlayerConfig.playerName = text:trim()
  setProfileSetting("followPlayer", followPlayerConfig)
end)

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
local profileManaTraining = getProfileSetting("manaTraining") or { spell = "exura", minManaPercent = 80 }

-- Migrate legacy profile-level custom spell to per-character storage
if storage and not storage.manaTrainingSpell and profileManaTraining.spell and profileManaTraining.spell:lower() ~= "exura" then
  storage.manaTrainingSpell = profileManaTraining.spell
  -- reset profile default to avoid affecting other characters
  profileManaTraining.spell = "exura"
  setProfileSetting("manaTraining", profileManaTraining)
end

-- Build runtime manaTraining: profile defaults + per-character override for spell
local manaTraining = {
  spell = profileManaTraining.spell or "exura",
  minManaPercent = profileManaTraining.minManaPercent or 80
}
if storage and storage.manaTrainingSpell then
  manaTraining.spell = storage.manaTrainingSpell
end

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
  -- Save player-specific spell to character storage (do NOT overwrite profile default)
  if storage then storage.manaTrainingSpell = manaTraining.spell end
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

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO LEVITATE - Ultra-fast instant-cast for PVP
-- Moving: auto-levitates when running into wall/floor
-- Stopped: press direction key toward levitate point to turn & cast
-- ═══════════════════════════════════════════════════════════════════════════

local autoLevitateEnabled = false
local lastLevCast = 0
local LEV_CD = 1950  -- Slightly under 2s for faster re-cast

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

-- Track which direction keys are currently held down
local heldDirKeys = {}

-- Map key names to direction indices
local KEY_TO_DIR = {}
KEY_TO_DIR["Up"] = 1
KEY_TO_DIR["Numpad8"] = 1
KEY_TO_DIR["W"] = 1
KEY_TO_DIR["Right"] = 2
KEY_TO_DIR["Numpad6"] = 2
KEY_TO_DIR["D"] = 2
KEY_TO_DIR["Down"] = 3
KEY_TO_DIR["Numpad2"] = 3
KEY_TO_DIR["S"] = 3
KEY_TO_DIR["Left"] = 4
KEY_TO_DIR["Numpad4"] = 4
KEY_TO_DIR["A"] = 4
KEY_TO_DIR["Numpad9"] = 5
KEY_TO_DIR["Numpad3"] = 6
KEY_TO_DIR["Numpad1"] = 7
KEY_TO_DIR["Numpad7"] = 8

-- Track key presses using bot callbacks
onKeyDown(function(keys)
  local dir = KEY_TO_DIR[keys]
  if dir then
    heldDirKeys[dir] = true
  end
end)

onKeyUp(function(keys)
  local dir = KEY_TO_DIR[keys]
  if dir then
    heldDirKeys[dir] = false
  end
end)

-- Check levitate opportunity at adjacent position
local function getLevType(px, py, pz, dx, dy)
  local fx, fy = px + dx, py + dy
  local tile = g_map.getTile({x = fx, y = fy, z = pz})
  
  -- Check UP: blocked tile + ground above
  if tile then
    local blocked = false
    if tile.isWalkable then
      blocked = not tile:isWalkable()
    else
      blocked = not tile:getGround()
    end
    if blocked and pz > 0 then
      local above = g_map.getTile({x = fx, y = fy, z = pz - 1})
      if above and above:getGround() then
        return "up"
      end
    end
  end
  
  -- Check DOWN: no ground in front + ground below
  if not tile or not tile:getGround() then
    if pz < 15 then
      local below = g_map.getTile({x = fx, y = fy, z = pz + 1})
      if below and below:getGround() then
        return "down"
      end
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

-- Track movement state
local lastPx, lastPy = 0, 0

-- Ultra-fast 2ms polling
macro(2, function()
  if not autoLevitateEnabled then return end
  
  local p = player
  if not p then return end
  
  -- Fast cooldown check first
  if (now - lastLevCast) < LEV_CD then return end
  
  -- Mana check
  if mana() < 50 then return end
  
  local pos = p:getPosition()
  if not pos then return end
  
  local px, py, pz = pos.x, pos.y, pos.z
  
  -- Detect if player moved this tick
  local justMoved = (px ~= lastPx or py ~= lastPy)
  lastPx, lastPy = px, py
  
  -- PRIORITY 1: Check all directions for held key (works when trapped/stopped)
  for dirIdx = 1, 8 do
    if heldDirKeys[dirIdx] then
      local d = DIRS[dirIdx]
      local levType = getLevType(px, py, pz, d.dx, d.dy)
      if levType then
        -- Turn player to face the direction before casting
        local newDir = dirIdx - 1  -- Convert back to 0-7
        if turn then turn(newDir) end
        castLev(levType)
        return
      end
    end
  end
  
  -- PRIORITY 2: If moving, also auto-levitate in facing direction
  if justMoved then
    local playerDir = p:getDirection()
    local facingIdx = DIR_TO_IDX[playerDir] or 1
    local fd = DIRS[facingIdx]
    if fd then
      local levType = getLevType(px, py, pz, fd.dx, fd.dy)
      if levType then
        castLev(levType)
        return
      end
    end
  end
end)

-- Single UI Toggle for Auto Levitate
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

UI.Separator()
