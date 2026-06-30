-- Tools tab widgets and macros
setDefaultTab("Tools")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENT SERVICE HELPERS (Cross-client compatibility: OTCv8 / OpenTibiaBR)
-- ═══════════════════════════════════════════════════════════════════════════

local getClient = nExBot.Shared.getClient

-- Version check helper
local getClientVersion = nExBot.Shared.getClientVersion
local SC = SafeCreature

-- ═══════════════════════════════════════════════════════════════════════════
-- PROFILE STORAGE INTEGRATION
-- All settings are stored per-profile using ProfileStorage from configs.lua
-- ═══════════════════════════════════════════════════════════════════════════

local SharedHelpers = nExBot.SharedHelpers or {}
local getProfileSetting = SharedHelpers.getProfileSetting
local setProfileSetting = SharedHelpers.setProfileSetting

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
  local containers = nExBot.Shared.getContainers()
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
-- AUTO LEVITATE v2.0 — Event-Driven with Look-Ahead & CaveBot Integration
-- Analyzes Z±1 fields in movement direction to detect levitate opportunities
-- Supports look-ahead (1-2 sqm) for earlier detection
-- Integrates with CaveBot intended floor change system
-- ═══════════════════════════════════════════════════════════════════════════

local autoLevitateEnabled = false
local lastLevCast = 0
local LEV_CD = 1950  -- Slightly under 2s for faster re-cast
local MIN_MANA = 50
local _levHandledStep = 0  -- tick of last handled levitate (prevents triple-fire)
local LEV_DEDUP_MS = 300   -- dedup window for same-step triggers

-- Cached depth setting
local levDepth = BotDB.get("macros.autoLevitateDepth") or 1

-- Cardinal directions only (diagonals can't levitate in Tibia)
local CARDINAL_DIRS = {
  {dx = 0, dy = -1},   -- 1: North
  {dx = 1, dy = 0},    -- 2: East
  {dx = 0, dy = 1},    -- 3: South
  {dx = -1, dy = 0},   -- 4: West
}

-- Full 8 directions for key mapping
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

-- Map key names to direction indices (cardinal only for levitate)
local KEY_TO_DIR = {
  ["Up"] = 1, ["Numpad8"] = 1, ["W"] = 1,
  ["Right"] = 2, ["Numpad6"] = 2, ["D"] = 2,
  ["Down"] = 3, ["Numpad2"] = 3, ["S"] = 3,
  ["Left"] = 4, ["Numpad4"] = 4, ["A"] = 4,
  -- Diagonals intentionally excluded: levitate spell only works cardinally
}

-- DRY helper: get tile at position
local function _getTile(x, y, z)
  local Client = getClient()
  if Client and Client.getTile then
    return Client.getTile({x = x, y = y, z = z})
  end
  if g_map and g_map.getTile then
    return g_map.getTile({x = x, y = y, z = z})
  end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Z+1 FIELD ANALYSIS — Core detection logic (DRY refactored)
-- ═══════════════════════════════════════════════════════════════════════════

-- Direct check for levitate opportunity in a specific direction
-- Returns "up", "down", or nil
local function checkLevitateDirection(px, py, pz, dirIdx)
  local d = DIRS[dirIdx]
  if not d then return nil end
  -- Only cardinal directions can levitate
  if dirIdx > 4 then return nil end

  local fx, fy = px + d.dx, py + d.dy

  -- CHECK UP: Is there ground at Z-1 above the adjacent tile?
  if pz > 0 then
    local aboveTile = _getTile(fx, fy, pz - 1)
    if aboveTile and aboveTile:getGround() then
      return "up"
    end
    -- Check extra depth levels if configured
    for depth = 2, levDepth do
      local zcheck = pz - depth
      if zcheck < 0 then break end
      local aboveD = _getTile(fx, fy, zcheck)
      if aboveD and aboveD:getGround() then
        return "up"
      end
    end
  end

  -- CHECK DOWN: No ground at current level + ground below
  local currentTile = _getTile(fx, fy, pz)
  local hasCurrentGround = currentTile and currentTile:getGround()

  if not hasCurrentGround and pz < 15 then
    local belowTile = _getTile(fx, fy, pz + 1)
    if belowTile and belowTile:getGround() then
      return "down"
    end
  end

  return nil
end

-- Look-ahead: check 1-2 sqm ahead of current position for upcoming levitate
-- Returns nil or {distance, levType, dirIdx}
local function lookAheadLevitate(px, py, pz, dirIdx)
  local d = DIRS[dirIdx]
  if not d or dirIdx > 4 then return nil end

  for ahead = 1, 2 do
    local ax, ay = px + d.dx * ahead, py + d.dy * ahead
    local result = checkLevitateDirection(ax, ay, pz, dirIdx)
    if result then
      return {distance = ahead, levType = result, dirIdx = dirIdx}
    end
  end
  return nil
end

-- Cast levitate spell with CaveBot integration
local function castLev(levType, dirIdx)
  if levType == "up" then
    say("exani hur up")
  else
    say("exani hur down")
  end
  lastLevCast = now
  _levHandledStep = now
  -- Z-change is handled universally by cavebot.lua main loop Z-handler
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENT-DRIVEN TRIGGERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Common guard: returns true if we should skip this trigger
local function shouldSkipLevitate()
  if not autoLevitateEnabled then return true end
  if (now - lastLevCast) < LEV_CD then return true end
  if (now - _levHandledStep) < LEV_DEDUP_MS then return true end
  if mana() < MIN_MANA then return true end
  return false
end

-- TRIGGER 1: EventBus player:move — check from OLD position
if EventBus then
  EventBus.on("player:move", function(newPos, oldPos)
    if shouldSkipLevitate() then return end
    if not player then return end

    -- Calculate movement direction
    local moveDx = newPos.x - oldPos.x
    local moveDy = newPos.y - oldPos.y

    local dirIdx = nil
    for i = 1, 4 do  -- cardinal only
      local d = DIRS[i]
      if d.dx == moveDx and d.dy == moveDy then
        dirIdx = i
        break
      end
    end
    if not dirIdx then return end

    -- Check from OLD position first
    local levType = checkLevitateDirection(oldPos.x, oldPos.y, oldPos.z, dirIdx)
    if levType then
      local newDir = dirIdx - 1
      if turn then turn(newDir) end
      castLev(levType, dirIdx)
      return
    end

    -- Check from NEW position + look-ahead for chained levitate
    local levType2 = checkLevitateDirection(newPos.x, newPos.y, newPos.z, dirIdx)
    if levType2 then
      local newDir = dirIdx - 1
      if turn then turn(newDir) end
      castLev(levType2, dirIdx)
    end
  end, 100)
end

-- TRIGGER 2: Key press — fires BEFORE movement for instant response
onKeyDown(function(keys)
  if shouldSkipLevitate() then return end

  local dirIdx = KEY_TO_DIR[keys]
  if not dirIdx then return end

  local p = player
  if not p then return end
  local pos = p:getPosition()
  if not pos then return end

  -- Direct check at current position
  local levType = checkLevitateDirection(pos.x, pos.y, pos.z, dirIdx)
  if levType then
    local newDir = dirIdx - 1
    if turn then turn(newDir) end
    castLev(levType, dirIdx)
    return
  end

  -- Look-ahead: detect upcoming levitate 1-2 sqm ahead
  local ahead = lookAheadLevitate(pos.x, pos.y, pos.z, dirIdx)
  if ahead and ahead.distance == 1 then
    -- Only pre-cast if 1 sqm away (2 sqm ahead is just informational)
    local newDir = dirIdx - 1
    if turn then turn(newDir) end
    castLev(ahead.levType, dirIdx)
  end
end)

-- TRIGGER 3: Backup macro (60ms) for held keys — faster than v1's 100ms
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

macro(60, function()
  if shouldSkipLevitate() then return end
  if (now - lastBackupCheck) < 55 then return end
  lastBackupCheck = now

  local anyHeld = false
  for _, v in pairs(heldDirKeys) do
    if v then anyHeld = true break end
  end
  if not anyHeld then return end

  local p = player
  if not p then return end
  local pos = p:getPosition()
  if not pos then return end

  for dirIdx = 1, 4 do  -- cardinal only
    if heldDirKeys[dirIdx] then
      local levType = checkLevitateDirection(pos.x, pos.y, pos.z, dirIdx)
      if levType then
        local newDir = dirIdx - 1
        if turn then turn(newDir) end
        castLev(levType, dirIdx)
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
  [5]  = { spells = { { spell = "utani gran hur", mana = 100 }, { spell = "utani hur", mana = 60 } } }, -- Monk
  [11] = { spell = "utani hur",      mana = 60  },
  [12] = { spell = "utani hur",      mana = 60  },
  [13] = { spell = "utani gran hur", mana = 100 },
  [14] = { spell = "utani gran hur", mana = 100 },
  [15] = { spells = { { spell = "utani gran hur", mana = 100 }, { spell = "utani hur", mana = 60 } } }, -- Monk
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

local function resolveHasteSpell(vocation, currentMana)
  local haste = HASTE_SPELLS[vocation]
  if not haste then return nil end

  if haste.spells then
    for _, entry in ipairs(haste.spells) do
      if currentMana >= entry.mana then
        return entry
      end
    end
    return nil
  end

  if currentMana >= haste.mana then
    return haste
  end

  return nil
end

local autoHasteMacro = macro(500, "Auto Haste", function()
  if not player then return end
  
  -- Cast cooldown
  if now - lastHasteCast < HASTE_CAST_COOLDOWN then return end
  
  local vocation = player:getVocation()
  local currentMana = mana()
  local haste = resolveHasteSpell(vocation, currentMana)
  if not haste then return end
  
  -- Check if already hasted
  if isHasted() then return end
  
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
-- FOLLOW PLAYER — Party hunt companion
-- ═══════════════════════════════════════════════════════════════════════════

local Follow = nil
do
  local ok, result = pcall(dofile, "/core/follow.lua")
  if ok then
    Follow = result
  end
  if not Follow then Follow = nExBot.Follow end
  if not Follow then print("[Follow] Failed to load: dofile returned nil and nExBot.Follow not set") end
end
if Follow and Follow.loadConfig then
  Follow.loadConfig()
end

local followPlayerMacro = macro(75, "Follow Player", function()
  if Follow and Follow.tick then
    Follow.tick()
  end
end)

if Follow then
  local lastMacroState = nil
  schedule(500, function()
    local macroOn = followPlayerMacro:isOn()
    if macroOn ~= lastMacroState then
      lastMacroState = macroOn
      Follow.setEnabled(macroOn)
      Follow.saveConfig()
    end
  end)
  if Follow.getConfig and Follow.getConfig().enabled then
    followPlayerMacro:setOn()
  else
    followPlayerMacro:setOff()
  end
end

if Follow then
  UI.Label("Auto Follow")

  UI.Label("Target:")
  local followPlayerNameEdit = UI.TextEdit(Follow.getConfig().playerName, function(widget, text)
    Follow.setPlayerName(text:trim())
    Follow.saveConfig()
  end)

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

  followWhileAttackingUI.followWhileAttackingToggle:setOn(Follow.getConfig().followWhileAttacking)
  followWhileAttackingUI.followWhileAttackingToggle.onClick = function(widget)
    local cfg = Follow.getConfig()
    cfg.followWhileAttacking = not cfg.followWhileAttacking
    widget:setOn(cfg.followWhileAttacking)
    Follow.saveConfig()
  end
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
