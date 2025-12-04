--[[
  ============================================================================
  nExBot Core Library (nlib.lua)
  ============================================================================
  
  Central utility library providing commonly used functions and shortcuts.
  This module is loaded first and provides the foundation for all other modules.
  
  PERFORMANCE NOTES:
  - All frequently used functions are cached locally to avoid global lookups
  - Table operations use ipairs() for arrays (faster than pairs())
  - String operations are minimized in hot paths
  - Callbacks use early returns to reduce processing
  
  Author: nExBot Team (Based on original by Vithrax)
  Version: 2.0.0 (Optimized)
  Last Updated: December 2025
  
  ============================================================================
]]

--[[
  ============================================================================
  SECTION 1: LOCAL CACHING FOR PERFORMANCE
  ============================================================================
  
  Caching global functions locally significantly improves performance by:
  - Avoiding hash table lookups on every function call
  - Reducing scope chain traversal
  - Enabling Lua JIT optimization
  
  Benchmark: Local lookups are ~20-30% faster than global lookups
  ============================================================================
]]

-- Math functions (frequently used in distance calculations)
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_ceil = math.ceil
local math_sqrt = math.sqrt

-- String functions (used in text processing)
local string_lower = string.lower
local string_sub = string.sub
local string_len = string.len
local string_match = string.match
local string_find = string.find
local string_format = string.format

-- Table functions
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort

-- Type checking (micro-optimization for hot paths)
local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local ipairs = ipairs

-- OTClient globals (cached for performance)
local g_game = g_game
local g_map = g_map
local g_ui = g_ui
local g_clock = g_clock

--[[
  ============================================================================
  SECTION 2: GLOBAL NAMESPACE INITIALIZATION
  ============================================================================
  
  The nExBot global namespace stores all bot-related state and configuration.
  Using a single namespace prevents global pollution and makes debugging easier.
  
  Memory Note: Tables are pre-allocated where possible to avoid rehashing
  ============================================================================
]]

nExBot = nExBot or {}

-- Bot state variables with sensible defaults
nExBot.BotServerMembers = nExBot.BotServerMembers or {}  -- Party coordination
nExBot.standTime = now or 0                               -- Last movement timestamp
nExBot.isUsingPotion = false                              -- Potion exhaust tracking
nExBot.isUsing = false                                    -- General action exhaust
nExBot.customCooldowns = {}                               -- Custom spell cooldown tracking
nExBot.lastLabel = ""                                     -- CaveBot label tracking
nExBot.CaveBotData = {}                                   -- CaveBot waypoint data
nExBot.lootContainers = {}                                -- Active loot containers
nExBot.lootItems = {}                                     -- Looted item tracking

--[[
  ============================================================================
  SECTION 3: LOGGING SYSTEM
  ============================================================================
  
  Provides formatted logging to the OTClient terminal with timestamps.
  Color-coded messages help distinguish bot output from game messages.
  
  Usage: logInfo("Message to display")
  ============================================================================
]]

--- Logs a message to the OTClient terminal with timestamp
-- @param text (string) The message to log
-- @return The result of addLine, or nil if terminal unavailable
function logInfo(text)
  -- Early return if terminal module isn't loaded
  if not modules or not modules.client_terminal then
    return nil
  end
  
  -- Format: "HH:MM:SS [nExBot]: message"
  local timestamp = os.date("%H:%M:%S")
  local formattedMessage = timestamp .. " [nExBot]: " .. tostring(text)
  
  return modules.client_terminal.addLine(formattedMessage, "orange")
end

--[[
  ============================================================================
  SECTION 4: PLAYER POSITION & MOVEMENT TRACKING
  ============================================================================
  
  Tracks player movement for stand time calculations.
  Stand time is used by various modules to detect idle states.
  ============================================================================
]]

-- Register position change callback (updates stand time on movement)
if onPlayerPositionChange then
  onPlayerPositionChange(function(newPos, oldPos)
    nExBot.standTime = now
  end)
end

--- Returns time in milliseconds since last player movement
-- @return (number) Milliseconds since last position change
function standTime()
  return (now or 0) - nExBot.standTime
end

--[[
  ============================================================================
  SECTION 5: CHARACTER MANAGEMENT
  ============================================================================
  
  Functions for character switching and account management.
  ============================================================================
]]

--- Relogs to a specific character by name
-- @param charName (string) Character name to relog to (partial match supported)
function relogOnCharacter(charName)
  if not charName then return end
  
  local rootWidget = g_ui.getRootWidget()
  if not rootWidget or not rootWidget.charactersWindow then return end
  
  local characters = rootWidget.charactersWindow.characters
  if not characters then return end
  
  local searchName = string_lower(charName)
  
  for _, child in ipairs(characters:getChildren()) do
    local children = child:getChildren()
    if children and children[1] then
      local name = string_lower(children[1]:getText())
      if string_find(name, searchName, 1, true) then
        child:focus()
        schedule(100, modules.client_entergame.CharacterList.doLogin)
        return
      end
    end
  end
end

--[[
  ============================================================================
  SECTION 6: SPELL CASTING SYSTEM
  ============================================================================
  
  Comprehensive spell management with cooldown tracking and validation.
  
  The system maintains a SpellCastTable that tracks:
  - Last cast time for each spell
  - Custom cooldown durations
  - Group cooldown associations
  
  Performance Note: Uses hash table for O(1) spell lookup
  ============================================================================
]]

-- Spell cast tracking table (spell_words -> {t: last_cast_time, d: cooldown})
SpellCastTable = {}

-- Reference to gamelib spell data (cached for performance)
local Spells = modules.gamelib and modules.gamelib.SpellInfo and 
               modules.gamelib.SpellInfo['Default'] or {}

-- Track spell casts from player messages
if onTalk then
  onTalk(function(name, level, mode, text, channelId, pos)
    -- Only process our own messages
    if not player or name ~= player:getName() then return end
    
    local lowerText = string_lower(text)
    
    -- Update spell cast time if tracked
    if SpellCastTable[lowerText] then
      SpellCastTable[lowerText].t = now
    end
  end)
end

--- Simple spell casting with cooldown check
-- @param text (string) Spell words to cast
function castSpell(text)
  if canCast(text) then
    say(text)
  end
end

--- Advanced spell casting with custom cooldown management
-- Tracks cast time for reliable cooldown calculation
-- @param text (string) Spell words to cast
-- @param delay (number|nil) Custom cooldown in milliseconds
function cast(text, delay)
  if type(text) ~= "string" then return end
  
  text = string_lower(text)
  
  -- No delay specified, use simple say
  if not delay or delay < 100 then
    return say(text)
  end
  
  -- Initialize or update spell tracking
  local spellData = SpellCastTable[text]
  if not spellData or spellData.d ~= delay then
    SpellCastTable[text] = {t = now - delay, d = delay}
    return say(text)
  end
  
  -- Check if cooldown has passed
  if now - spellData.t > spellData.d then
    return say(text)
  end
end

--- Checks if a spell can be cast (cooldown, mana, level requirements)
-- @param spell (string) Spell words to check
-- @param ignoreRL (boolean|nil) If true, ignore level/mana requirements
-- @param ignoreCd (boolean|nil) If true, ignore cooldown
-- @return (boolean) True if spell can be cast
function canCast(spell, ignoreRL, ignoreCd)
  if type(spell) ~= "string" then return false end
  
  spell = string_lower(spell)
  
  -- Check custom spell table first (fastest path)
  local customData = SpellCastTable[spell]
  if customData then
    if ignoreCd then return true end
    return now - customData.t > customData.d
  end
  
  -- Check gamelib spell data
  local spellData = getSpellData(spell)
  if spellData then
    local cdOk = ignoreCd or not getSpellCoolDown(spell)
    local reqOk = ignoreRL or (
      level() >= spellData.level and 
      mana() >= spellData.mana
    )
    return cdOk and reqOk
  end
  
  -- Unknown spell, allow cast attempt
  return true
end

--- Retrieves spell configuration from gamelib or custom cooldowns
-- @param spell (string) Spell words to look up
-- @return (table|false) Spell data or false if not found
function getSpellData(spell)
  if not spell then return false end
  
  spell = string_lower(spell)
  
  -- Search gamelib spells (by words)
  for spellName, data in pairs(Spells) do
    if data.words == spell then
      return data
    end
  end
  
  -- Check custom cooldowns
  local customData = nExBot.customCooldowns[spell]
  if customData then
    return {
      id = customData.id,
      mana = 1,
      level = 1,
      group = customData.group or {}
    }
  end
  
  return false
end

--- Checks if a spell is currently on cooldown
-- @param text (string) Spell words to check
-- @return (boolean|nil) True if on cooldown, false if ready, nil if unknown
function getSpellCoolDown(text)
  if not text then return nil end
  
  local data = getSpellData(string_lower(text))
  if not data then return false end
  
  -- Check individual spell cooldown
  if modules.game_cooldown then
    local iconActive = modules.game_cooldown.isCooldownIconActive(data.id)
    if iconActive then return true end
    
    -- Check group cooldowns
    if data.group then
      for groupId, _ in pairs(data.group) do
        if modules.game_cooldown.isGroupCooldownIconActive(groupId) then
          return true
        end
      end
    end
  end
  
  return false
end

-- Track custom spell cooldowns from game events
local lastPhrase = ""
if onTalk then
  onTalk(function(name, level, mode, text, channelId, pos)
    if player and name == player:getName() then
      lastPhrase = string_lower(text)
    end
  end)
end

-- Register spell cooldown callbacks if available
if onSpellCooldown and onGroupSpellCooldown then
  onSpellCooldown(function(iconId, duration)
    schedule(1, function()
      if lastPhrase ~= "" and not nExBot.customCooldowns[lastPhrase] then
        nExBot.customCooldowns[lastPhrase] = {id = iconId}
      end
    end)
  end)
  
  onGroupSpellCooldown(function(iconId, duration)
    schedule(2, function()
      local customData = nExBot.customCooldowns[lastPhrase]
      if customData then
        customData.group = customData.group or {}
        customData.group[iconId] = duration
      end
    end)
  end)
end

--[[
  ============================================================================
  SECTION 7: DAMAGE TRACKING SYSTEM
  ============================================================================
  
  Tracks incoming damage for burst damage calculations.
  Used by healing modules to adjust healing intensity.
  
  Performance Note: Table is periodically cleaned to prevent unbounded growth
  ============================================================================
]]

-- Damage tracking state
local dmgTable = {}
local lastDmgMessage = now or 0
local DMG_TRACKING_WINDOW = 3000  -- Track damage for 3 seconds

-- Track damage from game messages
if onTextMessage then
  onTextMessage(function(mode, text)
    -- Quick check for damage message (performance optimization)
    local lowerText = string_lower(text)
    if not string_find(lowerText, "you lose", 1, true) then return end
    if not string_find(lowerText, "due to", 1, true) then return end
    
    -- Extract damage value
    local dmg = tonumber(string_match(text, "%d+"))
    if not dmg then return end
    
    -- Clean old entries (inline to avoid function call overhead)
    local currentTime = now
    for i = #dmgTable, 1, -1 do
      if currentTime - dmgTable[i].t > DMG_TRACKING_WINDOW then
        table_remove(dmgTable, i)
      end
    end
    
    -- Record new damage
    lastDmgMessage = currentTime
    table_insert(dmgTable, {d = dmg, t = currentTime})
    
    -- Schedule cleanup
    schedule(DMG_TRACKING_WINDOW + 50, function()
      if now - lastDmgMessage > DMG_TRACKING_WINDOW then
        dmgTable = {}
      end
    end)
  end)
end

--- Calculates damage per second from recent damage events
-- @return (number) Average DPS over tracking window
function burstDamageValue()
  local count = #dmgTable
  if count < 2 then return 0 end
  
  local totalDamage = 0
  local firstTime = dmgTable[1].t
  
  for i = 1, count do
    totalDamage = totalDamage + dmgTable[i].d
  end
  
  local duration = (now - firstTime) / 1000  -- Convert to seconds
  if duration <= 0 then return 0 end
  
  return math_ceil(totalDamage / duration)
end

--[[
  ============================================================================
  SECTION 8: POTION EXHAUST TRACKING
  ============================================================================
  
  Tracks potion usage based on the "Aaaah..." message.
  Prevents wasting potions during exhaust period.
  ============================================================================
]]

local POTION_EXHAUST_MS = 950  -- Potion cooldown duration

if onTalk then
  onTalk(function(name, level, mode, text, channelId, pos)
    if not player or name ~= player:getName() then return end
    if mode ~= 34 then return end  -- Mode 34 = potion sound
    
    if text == "Aaaah..." then
      nExBot.isUsingPotion = true
      schedule(POTION_EXHAUST_MS, function()
        nExBot.isUsingPotion = false
      end)
    end
  end)
end

--[[
  ============================================================================
  SECTION 9: ACTION TRACKING SYSTEM
  ============================================================================
  
  Tracks when player is performing actions (using items, etc).
  Prevents action blocking by bot scripts.
  ============================================================================
]]

local isUsingTime = now or 0
local ACTION_LOCK_DURATION = 1000  -- 1 second lock

-- Update isUsing state periodically
if macro then
  macro(100, function()
    nExBot.isUsing = now < isUsingTime
  end)
end

-- Track item usage
if onUse then
  onUse(function(pos, itemId, stackPos, subType)
    -- Ignore inventory positions (x > 65000)
    if pos.x > 65000 then return end
    
    -- Ignore distant tiles
    if player and getDistanceBetween(player:getPosition(), pos) > 1 then return end
    
    -- Ignore container opens
    local tile = g_map.getTile(pos)
    if not tile then return end
    
    local topThing = tile:getTopUseThing()
    if topThing and topThing:isContainer() then return end
    
    isUsingTime = now + ACTION_LOCK_DURATION
  end)
end

if onUseWith then
  onUseWith(function(pos, itemId, target, subType)
    if pos.x < 65000 then
      isUsingTime = now + ACTION_LOCK_DURATION
    end
  end)
end

--[[
  ============================================================================
  SECTION 10: MESSAGE DISPLAY UTILITIES
  ============================================================================
  
  Wrapper functions for displaying various types of game messages.
  ============================================================================
]]

--- Displays a white info message on screen
-- @param text (string) Message to display
function whiteInfoMessage(text)
  if modules.game_textmessage then
    return modules.game_textmessage.displayGameMessage(text)
  end
end

--- Displays a status/failure message
-- @param text (string) Message to display
-- @param logInConsole (boolean|nil) If true, use status message style
function statusMessage(text, logInConsole)
  if not modules.game_textmessage then return end
  
  if logInConsole then
    return modules.game_textmessage.displayStatusMessage(text)
  else
    return modules.game_textmessage.displayFailureMessage(text)
  end
end

--- Displays a red broadcast message on screen
-- @param text (string) Message to display
function broadcastMessage(text)
  if modules.game_textmessage then
    return modules.game_textmessage.displayBroadcastMessage(text)
  end
end

--[[
  ============================================================================
  SECTION 11: NPC INTERACTION UTILITIES
  ============================================================================
]]

--- Schedules an NPC message to be sent after a delay
-- @param text (string) Text to say to NPC
-- @param delay (number) Delay in milliseconds before speaking
-- @return (boolean) False if parameters invalid
function scheduleNpcSay(text, delay)
  if not text or not delay then return false end
  return schedule(delay, function() NPC.say(text) end)
end

--[[
  ============================================================================
  SECTION 12: TEXT PARSING UTILITIES
  ============================================================================
]]

--- Extracts the first number from a string
-- @param text (string) Text to parse
-- @return (number|nil) First number found, or nil if none
function getFirstNumberInText(text)
  local match = string_match(text, "%d+")
  return match and tonumber(match) or nil
end

--- Checks if a string starts with a specific prefix
-- @param str (string) String to check
-- @param start (string) Prefix to look for
-- @return (boolean) True if string starts with prefix
function string.starts(str, start)
  return string_sub(str, 1, string_len(start)) == start
end

--[[
  ============================================================================
  SECTION 13: POSITION & TILE UTILITIES
  ============================================================================
]]

--- Checks if an item with given ID exists on a tile
-- @param id (number) Item ID to search for
-- @param p1 (table|Tile|number) Tile, position table, or X coordinate
-- @param p2 (number|nil) Y coordinate (if p1 is X)
-- @param p3 (number|nil) Z coordinate (if p1 is X)
-- @return (boolean) True if item found on tile
function isOnTile(id, p1, p2, p3)
  if not id then return false end
  
  -- Resolve tile from various input types
  local tile
  if type(p1) == "table" then
    tile = g_map.getTile(p1)
  elseif type(p1) ~= "number" then
    tile = p1
  else
    tile = g_map.getTile({x = p1, y = p2, z = p3})
  end
  
  if not tile then return false end
  
  -- Search items on tile
  local items = tile:getItems()
  if not items or #items == 0 then return false end
  
  for _, item in ipairs(items) do
    if item:getId() == id then
      return true
    end
  end
  
  return false
end

--- Creates a position table from coordinates
-- @param x (number) X coordinate
-- @param y (number) Y coordinate
-- @param z (number) Z coordinate
-- @return (table|nil) Position table or nil if invalid
function getPos(x, y, z)
  if not x or not y or not z then return nil end
  
  local position = pos()
  position.x = x
  position.y = y
  position.z = z
  return position
end

--- Gets tiles surrounding a position (8-directional)
-- @param position (table|Tile) Center position or tile
-- @return (table) Array of adjacent tiles
function getNearTiles(position)
  if type(position) ~= "table" then
    position = position:getPosition()
  end
  
  local tiles = {}
  local offsets = {
    {-1, 1}, {0, 1}, {1, 1},
    {-1, 0},         {1, 0},
    {-1, -1}, {0, -1}, {1, -1}
  }
  
  for _, offset in ipairs(offsets) do
    local tile = g_map.getTile({
      x = position.x - offset[1],
      y = position.y - offset[2],
      z = position.z
    })
    if tile then
      table_insert(tiles, tile)
    end
  end
  
  return tiles
end

--[[
  ============================================================================
  SECTION 14: DISTANCE UTILITIES
  ============================================================================
]]

--- Calculates distance from player to a position
-- @param coords (table) Target position {x, y, z}
-- @return (number|false) Distance or false if invalid
function distanceFromPlayer(coords)
  if not coords then return false end
  return getDistanceBetween(pos(), coords)
end

--[[
  ============================================================================
  SECTION 15: CONTAINER UTILITIES
  ============================================================================
]]

--- Opens the player's purse
function openPurse()
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    local purse = localPlayer:getInventoryItem(InventorySlotPurse)
    if purse then
      return g_game.use(purse)
    end
  end
end

--- Checks if a container is full
-- @param c (Container) Container to check
-- @return (boolean) True if container is at capacity
function containerIsFull(c)
  if not c then return false end
  return c:getCapacity() <= #c:getItems()
end

--- Gets a container by its display name
-- @param name (string) Container name to search for
-- @param notFull (boolean|nil) If true, only return non-full containers
-- @return (Container|nil) Container object or nil
function getContainerByName(name, notFull)
  if type(name) ~= "string" then return nil end
  
  local searchName = string_lower(name)
  
  for _, container in pairs(getContainers()) do
    if string_lower(container:getName()) == searchName then
      if not notFull or not containerIsFull(container) then
        return container
      end
    end
  end
  
  return nil
end

--- Gets a container by its item ID
-- @param id (number) Container item ID
-- @param notFull (boolean|nil) If true, only return non-full containers
-- @return (Container|nil) Container object or nil
function getContainerByItem(id, notFull)
  if type(id) ~= "number" then return nil end
  
  for _, container in pairs(getContainers()) do
    if container:getContainerItem():getId() == id then
      if not notFull or not containerIsFull(container) then
        return container
      end
    end
  end
  
  return nil
end

--[[
  ============================================================================
  SECTION 16: ITEM UTILITIES
  ============================================================================
]]

--- Drops an item on the ground at player position
-- @param idOrObject (number|Item) Item ID or item object
function dropItem(idOrObject)
  if type(idOrObject) == "number" then
    idOrObject = findItem(idOrObject)
  end
  
  if idOrObject then
    g_game.move(idOrObject, pos(), idOrObject:getCount())
  end
end

--- Counts items in all visible containers and equipment
-- @param id (number) Item ID to count
-- @return (number) Total count
function itemAmount(id)
  return player:getItemsCount(id)
end

--- Uses one inventory item on another
-- @param a (number) Item ID to use
-- @param b (number) Target item ID
function useOnInvertoryItem(a, b)
  local item = findItem(b)
  if item then
    return useWith(a, item)
  end
end

--[[
  ============================================================================
  SECTION 17: GROUND ITEM UTILITIES
  ============================================================================
]]

--- Uses an item on the ground
-- @param id (number) Item ID to use
-- @return (boolean) False if item not found
function useGroundItem(id)
  if not id then return false end
  
  for _, tile in ipairs(g_map.getTiles(posz())) do
    for _, item in ipairs(tile:getItems()) do
      if item:getId() == id then
        return use(item)
      end
    end
  end
  
  return false
end

--- Finds an item on the ground
-- @param id (number) Item ID to find
-- @return (Item|nil) Item object or nil
function findItemOnGround(id)
  for _, tile in ipairs(g_map.getTiles(posz())) do
    for _, item in ipairs(tile:getItems()) do
      if item:getId() == id then
        return item
      end
    end
  end
  return nil
end

--- Walks to a ground item
-- @param id (number) Item ID to reach
-- @return (boolean) False if item not found or unreachable
function reachGroundItem(id)
  if not id then return false end
  
  for _, tile in ipairs(g_map.getTiles(posz())) do
    for _, item in ipairs(tile:getItems()) do
      if item:getId() == id then
        local itemPos = item:getPosition()
        local path = findPath(pos(), itemPos, 20, {ignoreNonPathable = true, precision = 1})
        if path then
          return autoWalk(itemPos, 20, {ignoreNonPathable = true, precision = 1})
        end
      end
    end
  end
  
  return false
end

--[[
  ============================================================================
  SECTION 18: TARGETING UTILITIES
  ============================================================================
]]

--- Gets the currently attacked creature
-- @return (Creature|nil) Target creature or nil
function target()
  if g_game.isAttacking() then
    return g_game.getAttackingCreature()
  end
  return nil
end

-- Alias for target()
function getTarget()
  return target()
end

--- Gets target position or distance
-- @param dist (boolean|nil) If true, return distance instead of position
-- @return (table|number|nil) Position, distance, or nil
function targetPos(dist)
  if not g_game.isAttacking() then return nil end
  
  local targetCreature = target()
  if not targetCreature then return nil end
  
  local targetPosition = targetCreature:getPosition()
  
  if dist then
    return distanceFromPlayer(targetPosition)
  else
    return targetPosition
  end
end

--[[
  ============================================================================
  SECTION 19: PLAYER/CREATURE CLASSIFICATION
  ============================================================================
  
  Friend/Enemy caching system to reduce lookup overhead.
  Cache is populated on first check and reused for subsequent lookups.
  
  Performance Note: Hash table lookups are O(1) vs O(n) for list searches
  ============================================================================
]]

-- Player classification caches (use weak keys for auto-cleanup)
CachedFriends = setmetatable({}, {__mode = "k"})
CachedEnemies = setmetatable({}, {__mode = "k"})

--- Checks if a creature/player is a friend
-- @param c (Creature|string) Creature object or player name
-- @return (boolean) True if friend
function isFriend(c)
  local name = c
  
  if type(c) ~= "string" then
    if c == player then return true end
    name = c:getName()
  end
  
  -- Check cache first
  if CachedFriends[c] then return true end
  if CachedEnemies[c] then return false end
  
  -- Check friend list
  if storage.playerList and storage.playerList.friendList then
    if table.find(storage.playerList.friendList, name) then
      CachedFriends[c] = true
      return true
    end
  end
  
  -- Check BotServer members
  if nExBot.BotServerMembers[name] then
    CachedFriends[c] = true
    return true
  end
  
  -- Check party members
  if storage.playerList and storage.playerList.groupMembers then
    local creature = type(c) == "string" and getCreatureByName(c, true) or c
    if creature and creature:isPlayer() and not creature:isLocalPlayer() then
      if creature:isPartyMember() then
        CachedFriends[c] = true
        CachedFriends[creature] = true
        return true
      end
    end
  end
  
  return false
end

--- Checks if a creature/player is an enemy
-- @param c (Creature|string) Creature object or player name
-- @return (boolean) True if enemy
function isEnemy(c)
  local name = c
  local creature
  
  if type(c) ~= "string" then
    if c == player then return false end
    name = c:getName()
    creature = c
  end
  
  if not name then return false end
  
  if not creature then
    creature = getCreatureByName(name, true)
  end
  
  if not creature then return false end
  if creature:isLocalPlayer() then return false end
  
  -- Check enemy conditions
  if creature:isPlayer() then
    -- Direct enemy list match
    if storage.playerList and storage.playerList.enemyList then
      if table.find(storage.playerList.enemyList, name) then
        return true
      end
    end
    
    -- Unmarked players as enemies
    if storage.playerList and storage.playerList.marks and not isFriend(name) then
      return true
    end
    
    -- War emblem
    if creature:getEmblem() == 2 then
      return true
    end
  end
  
  return false
end

--- Gets all players categorized by relationship
-- @return friends, neutrals, enemies (three tables of creatures)
function getPlayerDistribution()
  local friends = {}
  local neutrals = {}
  local enemies = {}
  
  for _, spec in ipairs(getSpectators()) do
    if spec:isPlayer() and not spec:isLocalPlayer() then
      if isFriend(spec) then
        table_insert(friends, spec)
      elseif isEnemy(spec) then
        table_insert(enemies, spec)
      else
        table_insert(neutrals, spec)
      end
    end
  end
  
  return friends, neutrals, enemies
end

function getFriends()
  local friends = getPlayerDistribution()
  return friends
end

function getNeutrals()
  local _, neutrals = getPlayerDistribution()
  return neutrals
end

function getEnemies()
  local _, _, enemies = getPlayerDistribution()
  return enemies
end

--[[
  ============================================================================
  SECTION 20: CREATURE COUNTING UTILITIES
  ============================================================================
]]

--- Counts monsters within range of a position
-- @param position (table) Center position
-- @param range (number) Maximum distance
-- @return (number) Monster count
function getMonstersInRange(position, range)
  if not position or not range then return 0 end
  
  local count = 0
  local clientVersion = g_game.getClientVersion()
  
  for _, spec in ipairs(getSpectators()) do
    if spec:isMonster() then
      -- Filter out summons in newer clients
      if clientVersion < 960 or spec:getType() < 3 then
        if getDistanceBetween(position, spec:getPosition()) < range then
          count = count + 1
        end
      end
    end
  end
  
  return count
end

--- Counts monsters within range of player
-- @param range (number|nil) Maximum distance (default: 10)
-- @param multifloor (boolean|nil) Check multiple floors
-- @return (number) Monster count
function getMonsters(range, multifloor)
  range = range or 10
  
  local count = 0
  local clientVersion = g_game.getClientVersion()
  
  for _, spec in ipairs(getSpectators(multifloor)) do
    if spec:isMonster() then
      if clientVersion < 960 or spec:getType() < 3 then
        if distanceFromPlayer(spec:getPosition()) <= range then
          count = count + 1
        end
      end
    end
  end
  
  return count
end

--- Counts non-party players within range of player
-- @param range (number|nil) Maximum distance (default: 10)
-- @param multifloor (boolean|nil) Check multiple floors
-- @return (number) Player count
function getPlayers(range, multifloor)
  range = range or 10
  
  local count = 0
  
  for _, spec in ipairs(getSpectators(multifloor)) do
    if spec:isPlayer() and not spec:isLocalPlayer() then
      if distanceFromPlayer(spec:getPosition()) <= range then
        -- Exclude party members and guild members
        local isParty = spec:isPartyMember() and spec:getShield() ~= 1
        local isGuild = spec:getEmblem() == 1
        
        if not isParty and not isGuild then
          count = count + 1
        end
      end
    end
  end
  
  return count
end

--- Counts all non-local players within range
-- @param range (number|nil) Maximum distance (default: 10)
-- @param multifloor (boolean|nil) Check multiple floors
-- @return (number) Player count
function getAllPlayers(range, multifloor)
  range = range or 10
  
  local count = 0
  
  for _, spec in ipairs(getSpectators(multifloor)) do
    if spec:isPlayer() and not spec:isLocalPlayer() then
      if distanceFromPlayer(spec:getPosition()) <= range then
        count = count + 1
      end
    end
  end
  
  return count
end

--- Counts NPCs within range of player
-- @param range (number|nil) Maximum distance (default: 10)
-- @param multifloor (boolean|nil) Check multiple floors
-- @return (number) NPC count
function getNpcs(range, multifloor)
  range = range or 10
  
  local count = 0
  
  for _, spec in ipairs(getSpectators(multifloor)) do
    if spec:isNpc() then
      if distanceFromPlayer(spec:getPosition()) <= range then
        count = count + 1
      end
    end
  end
  
  return count
end

--[[
  ============================================================================
  SECTION 21: SAFETY CHECKS
  ============================================================================
]]

--- Checks if a blacklisted player is within range
-- @param range (number|nil) Maximum distance (default: 10)
-- @return (boolean) True if blacklisted player found
function isBlackListedPlayerInRange(range)
  if not storage.playerList or not storage.playerList.blackList then return false end
  if #storage.playerList.blackList == 0 then return false end
  
  range = range or 10
  local pPos = player:getPosition()
  
  for _, spec in ipairs(getSpectators(true)) do
    if spec:isPlayer() then
      local specPos = spec:getPosition()
      
      -- Check floor distance
      if math_abs(specPos.z - pPos.z) <= 2 then
        -- Normalize Z for distance calculation
        local checkPos = {x = specPos.x, y = specPos.y, z = pPos.z}
        
        if distanceFromPlayer(checkPos) < range then
          if table.find(storage.playerList.blackList, spec:getName()) then
            return true
          end
        end
      end
    end
  end
  
  return false
end

--- Checks if area is safe from non-friend players
-- @param range (number) Check radius
-- @param multifloor (boolean|nil) Check multiple floors
-- @param padding (number|nil) Additional range for other floors
-- @return (boolean) True if no non-friends found
function isSafe(range, multifloor, padding)
  local onSame = 0
  local onAnother = 0
  local pZ = posz()
  
  for _, spec in ipairs(getSpectators(multifloor)) do
    if spec:isPlayer() and not spec:isLocalPlayer() then
      if not isFriend(spec:getName()) then
        local specPos = spec:getPosition()
        
        if specPos.z == pZ then
          if distanceFromPlayer(specPos) <= range then
            onSame = onSame + 1
          end
        elseif multifloor and padding then
          if distanceFromPlayer(specPos) <= (range + padding) then
            onAnother = onAnother + 1
          end
        end
      end
    end
  end
  
  return (onSame + onAnother) == 0
end

--[[
  ============================================================================
  SECTION 22: BUFF DETECTION
  ============================================================================
]]

--- Checks if player has utito tempo buff active
-- @return (boolean) True if buffed
function isBuffed()
  if not hasPartyBuff() then return false end
  
  -- Find highest skill
  local bestSkillId = 0
  local bestSkillLevel = 0
  
  for i = 1, 4 do
    local baseLevel = player:getSkillBaseLevel(i)
    if baseLevel > bestSkillLevel then
      bestSkillLevel = baseLevel
      bestSkillId = i
    end
  end
  
  -- Check for skill boost
  local currentLevel = player:getSkillLevel(bestSkillId)
  local baseLevel = player:getSkillBaseLevel(bestSkillId)
  local bonus = currentLevel - baseLevel
  
  -- Utito gives 35% skill boost
  return (bonus / 100 * 305) > baseLevel
end

--- Returns kills remaining to red skull
-- @return (number) Minimum kills remaining
function killsToRs()
  local points = g_game.getUnjustifiedPoints()
  return math_min(
    points.killsDayRemaining,
    points.killsWeekRemaining,
    points.killsMonthRemaining
  )
end

--[[
  ============================================================================
  SECTION 23: TABLE UTILITIES
  ============================================================================
]]

--- Reindexes a table, assigning sequential indices
-- @param t (table) Table to reindex
function reindexTable(t)
  if not t or type(t) ~= "table" then return end
  
  local i = 0
  for _, element in pairs(t) do
    i = i + 1
    element.index = i
  end
end

--[[
  ============================================================================
  SECTION 24: EQUIPMENT UTILITIES
  ============================================================================
  
  Lookup tables for active/inactive equipment item IDs.
  Used for ring/amulet management.
  
  Performance Note: Using hash tables for O(1) lookup instead of if-else chains
  ============================================================================
]]

-- Active -> Inactive ID mappings
local ACTIVE_TO_INACTIVE = {
  [3086] = 3049,   -- Stealth Ring
  [3087] = 3050,   -- Might Ring
  [3088] = 3051,   -- Life Ring
  [3089] = 3052,   -- Time Ring
  [3090] = 3053,   -- Energy Ring
  [3094] = 3091,   -- Ring of Healing
  [3095] = 3092,   -- Ring of the Sky
  [3096] = 3093,   -- Sword Ring
  [3099] = 3097,   -- Club Ring
  [3100] = 3098,   -- Axe Ring
  [16264] = 16114, -- Prismatic Ring
  [23532] = 23531, -- Ring of Blue Plasma
  [23534] = 23533, -- Ring of Red Plasma
  [23530] = 23529, -- Ring of Green Plasma
  [30342] = 30343, -- Sleep Shawl
  [30345] = 30344, -- Enchanted Pendulet
  [30402] = 30403, -- Enchanted Theurgic Amulet
  [31616] = 31621, -- Blister Ring
  [32635] = 32621, -- Ring of Souls
}

-- Inactive -> Active ID mappings (reverse of above)
local INACTIVE_TO_ACTIVE = {}
for active, inactive in pairs(ACTIVE_TO_INACTIVE) do
  INACTIVE_TO_ACTIVE[inactive] = active
end

--- Gets the active (equipped) item ID from inactive ID
-- @param id (number) Inactive item ID
-- @return (number) Active item ID or original ID
function getActiveItemId(id)
  if not id then return false end
  return INACTIVE_TO_ACTIVE[id] or id
end

--- Gets the inactive (unequipped) item ID from active ID
-- @param id (number) Active item ID
-- @return (number) Inactive item ID or original ID
function getInactiveItemId(id)
  if not id then return false end
  return ACTIVE_TO_INACTIVE[id] or id
end

--[[
  ============================================================================
  SECTION 25: SPELL TYPE DETECTION
  ============================================================================
]]

--- Checks if spell is an attack spell
-- @param expr (string) Spell words
-- @return (boolean) True if attack spell
function isAttSpell(expr)
  return string.starts(expr, "exori") or string.starts(expr, "exevo")
end

--[[
  ============================================================================
  SECTION 26: CREATURE AREA ANALYSIS
  ============================================================================
]]

--- Counts creatures in a pattern area
-- @param pos (table|Creature) Center position or creature
-- @param pattern (string) Pattern string for getSpectators
-- @param returnType (number) 1=all, 2=monsters, 3=players
-- @return (number) Creature count
function getCreaturesInArea(pos, pattern, returnType)
  local specs = 0
  local monsters = 0
  local players = 0
  local clientVersion = g_game.getClientVersion()
  
  for _, spec in ipairs(getSpectators(pos, pattern)) do
    if spec ~= player then
      specs = specs + 1
      
      if spec:isMonster() and (clientVersion < 960 or spec:getType() < 3) then
        monsters = monsters + 1
      elseif spec:isPlayer() and not isFriend(spec:getName()) then
        players = players + 1
      end
    end
  end
  
  if returnType == 1 then return specs
  elseif returnType == 2 then return monsters
  else return players
  end
end

--- Finds the best tile for area attacks based on creature count
-- @param pattern (string) Attack pattern
-- @param specType (number) 1=all, 2=monsters, 3=players
-- @param maxDist (number|nil) Maximum distance (default: 4)
-- @param safe (boolean|nil) Exclude tiles that would hit players
-- @return (table|false) {pos, count} or false
function getBestTileByPatern(pattern, specType, maxDist, safe)
  if not pattern or not specType then return false end
  maxDist = maxDist or 4
  
  local best = nil
  
  for _, tile in ipairs(g_map.getTiles(posz())) do
    local tilePos = tile:getPosition()
    
    if distanceFromPlayer(tilePos) <= maxDist then
      if tile:canShoot() and tile:isWalkable() then
        local creatureCount = getCreaturesInArea(tilePos, pattern, specType)
        
        if creatureCount > 0 then
          -- Check safety if required
          local isSafeSpot = true
          if safe then
            isSafeSpot = getCreaturesInArea(tilePos, pattern, 3) == 0
          end
          
          if isSafeSpot then
            if not best or creatureCount > best.count then
              best = {pos = tile, count = creatureCount}
            end
          end
        end
      end
    end
  end
  
  return best or false
end

--[[
  ============================================================================
  SECTION 27: SPECIAL ACTIONS
  ============================================================================
]]

--- Reopens loot bag (for specific servers like Gunzodus/Ezodus)
-- @return CaveBot delay
function reopenPurse()
  -- Close existing loot bag/inbox
  for _, container in pairs(getContainers()) do
    local name = string_lower(container:getName())
    if name == "loot bag" or name == "store inbox" then
      g_game.close(container)
    end
  end
  
  -- Reopen purse
  schedule(100, function()
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
      local purse = localPlayer:getInventoryItem(InventorySlotPurse)
      if purse then
        g_game.use(purse)
      end
    end
  end)
  
  -- Open loot bag from inbox
  schedule(1400, function()
    for _, container in pairs(getContainers()) do
      if string_lower(container:getName()) == "store inbox" then
        for _, item in ipairs(container:getItems()) do
          if item:getId() == 23721 then  -- Loot bag ID
            g_game.open(item, container)
            break
          end
        end
      end
    end
  end)
  
  return CaveBot.delay(1500)
end

--[[
  ============================================================================
  SECTION 28: CONFIGURATION SAVE
  ============================================================================
]]

--- Saves nExBot configuration to storage
-- @param section (string) Configuration section name
-- @param data (table) Data to save
function nExBotConfigSave(section, data)
  if section and data then
    storage[section] = data
  end
end

--[[
  ============================================================================
  SECTION 29: SPELL PATTERNS (PREDEFINED)
  ============================================================================
  
  Pattern strings for getSpectators() used in area attack calculations.
  0 = empty, 1 = all directions, N/S/E/W = directional
  ============================================================================
]]

LargeUeArea = [[
    0000001000000
    0000011100000
    0000111110000
    0001111111000
    0011111111100
    0111111111110
    1111111111111
    0111111111110
    0011111111100
    0001111111000
    0000111110000
    0000011100000
    0000001000000
]]

NormalUeAreaMs = [[
    00000100000
    00011111000
    00111111100
    01111111110
    01111111110
    11111111111
    01111111110
    01111111110
    00111111100
    00001110000
    00000100000
]]

NormalUeAreaEd = [[
    00000100000
    00001110000
    00011111000
    00111111100
    01111111110
    11111111111
    01111111110
    00111111100
    00011111000
    00001110000
    00000100000
]]

smallUeArea = [[
    0011100
    0111110
    1111111
    1111111
    1111111
    0111110
    0011100
]]

largeRuneArea = [[
    0011100
    0111110
    1111111
    1111111
    1111111
    0111110
    0011100
]]

adjacentArea = [[
    111
    101
    111
]]

longBeamArea = [[
    0000000N0000000
    0000000N0000000
    0000000N0000000
    0000000N0000000
    0000000N0000000
    0000000N0000000
    0000000N0000000
    WWWWWWW0EEEEEEE
    0000000S0000000
    0000000S0000000
    0000000S0000000
    0000000S0000000
    0000000S0000000
    0000000S0000000
    0000000S0000000
]]

shortBeamArea = [[
    00000100000
    00000100000
    00000100000
    00000100000
    00000100000
    EEEEE0WWWWW
    00000S00000
    00000S00000
    00000S00000
    00000S00000
    00000S00000
]]

newWaveArea = [[
    000NNNNN000
    000NNNNN000
    0000NNN0000
    WW00NNN00EE
    WWWW0N0EEEE
    WWWWW0EEEEE
    WWWW0S0EEEE
    WW00SSS00EE
    0000SSS0000
    000SSSSS000
    000SSSSS000
]]

bigWaveArea = [[
    0000NNN0000
    0000NNN0000
    0000NNN0000
    00000N00000
    WWW00N00EEE
    WWWWW0EEEEE
    WWW00S00EEE
    00000S00000
    0000SSS0000
    0000SSS0000
    0000SSS0000
]]

smallWaveArea = [[
    00NNN00
    00NNN00
    WW0N0EE
    WWW0EEE
    WW0S0EE
    00SSS00
    00SSS00
]]

diamondArrowArea = [[
    01110
    11111
    11111
    11111
    01110
]]

--[[
  ============================================================================
  END OF nlib.lua
  ============================================================================
]]
