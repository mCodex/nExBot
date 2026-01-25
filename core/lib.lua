-- nExBot Core Library
-- Contains utility functions and code shorteners
-- Refactored to use ClientService for cross-client compatibility

-- Global namespace initialization
nExBot = nExBot or {} -- global namespace for bot variables

-- Get ClientService reference (may not be loaded yet, lazy load in functions)
local function getClient()
  return ClientService
end
nExBot.standTime = now
nExBot.isUsingPotion = false
nExBot.isUsing = false
nExBot.customCooldowns = {}
nExBot.lastLabel = ""

--------------------------------------------------------------------------------
-- OBJECT POOL - Memory-efficient table reuse
-- Reduces garbage collection pressure for frequently created/destroyed tables
--------------------------------------------------------------------------------
local ObjectPool = {
  pools = {},      -- {poolName -> {objects}}
  maxSize = 100,   -- Max objects per pool
  stats = {
    hits = 0,
    misses = 0,
    returns = 0
  }
}

-- Get or create a table from pool
-- @param poolName: string identifier for the pool
-- @param initialData: optional table to copy values from
-- @return table
function nExBot.acquireTable(poolName, initialData)
  poolName = poolName or "default"
  local pool = ObjectPool.pools[poolName]
  
  local obj
  if pool and #pool > 0 then
    obj = table.remove(pool)
    ObjectPool.stats.hits = ObjectPool.stats.hits + 1
  else
    obj = {}
    ObjectPool.stats.misses = ObjectPool.stats.misses + 1
  end
  
  -- Copy initial data if provided
  if initialData then
    for k, v in pairs(initialData) do
      obj[k] = v
    end
  end
  
  return obj
end

-- Return a table to the pool for reuse
-- @param poolName: string identifier for the pool
-- @param obj: the table to return
function nExBot.releaseTable(poolName, obj)
  if not obj then return end
  
  poolName = poolName or "default"
  local pool = ObjectPool.pools[poolName]
  
  if not pool then
    pool = {}
    ObjectPool.pools[poolName] = pool
  end
  
  -- Clear the table for reuse
  for k in pairs(obj) do
    obj[k] = nil
  end
  
  -- Only keep up to maxSize objects
  if #pool < ObjectPool.maxSize then
    pool[#pool + 1] = obj
    ObjectPool.stats.returns = ObjectPool.stats.returns + 1
  end
end

-- Get pool statistics
function nExBot.getPoolStats()
  local totalPooled = 0
  for _, pool in pairs(ObjectPool.pools) do
    totalPooled = totalPooled + #pool
  end
  
  return {
    hits = ObjectPool.stats.hits,
    misses = ObjectPool.stats.misses,
    returns = ObjectPool.stats.returns,
    totalPooled = totalPooled,
    hitRate = ObjectPool.stats.hits / math.max(1, ObjectPool.stats.hits + ObjectPool.stats.misses)
  }
end

-- Alias for common position table acquisition
function nExBot.acquirePos(x, y, z)
  local p = nExBot.acquireTable("position")
  p.x = x or 0
  p.y = y or 0
  p.z = z or 0
  return p
end

-- Release position table
function nExBot.releasePos(p)
  nExBot.releaseTable("position", p)
end

--------------------------------------------------------------------------------
-- MEMOIZATION - Cache function results for pure functions
--------------------------------------------------------------------------------
local MemoCache = {}

function logInfo(text)
    local timestamp = os.date("%H:%M:%S")
    text = tostring(text)
    local start = timestamp.." [nExBot]: "

    return modules.client_terminal.addLine(start..text, "orange") 
end

-- scripts / functions
onPlayerPositionChange(function(x,y)
    nExBot.standTime = now
end)

function standTime()
    return now - nExBot.standTime
end

function castSpell(text)
    if canCast(text) then
        say(text)
    end
end

local dmgTable = {}
local lastDmgMessage = now
onTextMessage(function(mode, text)
    if not text:lower():find("you lose") or not text:lower():find("due to") then
        return
    end
    local dmg = string.match(text, "%d+")
    if #dmgTable > 0 then
        for k, v in ipairs(dmgTable) do
            if now - v.t > 3000 then table.remove(dmgTable, k) end
        end
    end
    lastDmgMessage = now
    table.insert(dmgTable, {d = dmg, t = now})
    schedule(3050, function()
        if now - lastDmgMessage > 3000 then dmgTable = {} end
    end)
end)

-- based on data collected by callback calculates per second damage
-- returns number
function burstDamageValue()
    local d = 0
    local time = 0
    if #dmgTable > 1 then
        for i, v in ipairs(dmgTable) do
            if i == 1 then time = v.t end
            d = d + v.d
        end
    end
    return math.ceil(d / ((now - time) / 1000))
end

function statusMessage(text, logInConsole)
    return not logInConsole and modules.game_textmessage.displayFailureMessage(text) or modules.game_textmessage.displayStatusMessage(text)
end

-- returns first number in string, already formatted as number
-- returns number or nil
function getFirstNumberInText(text)
    local n = nil
    if string.match(text, "%d+") then n = tonumber(string.match(text, "%d+")) end
    return n
end

-- position is a special table, impossible to compare with normal one
-- this is translator from x,y,z to proper position value
-- returns position table
function getPos(x, y, z)
    if not x or not y or not z then return nil end
    local pos = pos()
    pos.x = x
    pos.y = y
    pos.z = z

    return pos
end

-- check's whether container is full
-- c has to be container object
-- returns boolean
function containerIsFull(c)
    if not c then return false end

    if c:getCapacity() > #c:getItems() then
        return false
    else
        return true
    end

end

function dropItem(idOrObject)
    if type(idOrObject) == "number" then
        idOrObject = findItem(idOrObject)
    end
    if not idOrObject then return end

    local Client = getClient()
    if Client and Client.move then
        Client.move(idOrObject, pos(), idOrObject:getCount())
    elseif g_game and g_game.move then
        g_game.move(idOrObject, pos(), idOrObject:getCount())
    end
end

-- not perfect function to return whether character has utito tempo buff
-- known to be bugged if received debuff (ie. roshamuul)
-- TODO: simply a better version
-- returns boolean
function isBuffed()
    local var = false
    if not hasPartyBuff() then return var end

    local skillId = 0
    for i = 1, 4 do
        if player:getSkillBaseLevel(i) > player:getSkillBaseLevel(skillId) then
            skillId = i
        end
    end

    local premium = (player:getSkillLevel(skillId) - player:getSkillBaseLevel(skillId))
    local base = player:getSkillBaseLevel(skillId)
    if (premium / 100) * 305 > base then
        var = true
    end
    return var
end

-- if using index as table element, this can be used to properly assign new idex to all values
-- table needs to contain "index" as value
-- if no index in tables, it will create one
function reindexTable(t)
    if not t or type(t) ~= "table" then return end

    local i = 0
    for _, e in pairs(t) do
        i = i + 1
        e.index = i
    end
end

-- supports only new tibia, ver 10+
-- returns how many kills left to get next skull - can be red skull, can be black skull!
-- reutrns number
function killsToRs()
    local Client = getClient()
    local points = Client and Client.getUnjustifiedPoints and Client.getUnjustifiedPoints() or 
                   (g_game and g_game.getUnjustifiedPoints and g_game.getUnjustifiedPoints()) or {}
    return math.min(points.killsDayRemaining or 999,
                    points.killsWeekRemaining or 999,
                    points.killsMonthRemaining or 999)
end

-- calculates exhaust for potions based on "Aaaah..." message
-- changes state of nExBot variable, can be used in other scripts
-- already used in pushmax, healbot, etc

onTalk(function(name, level, mode, text, channelId, pos)
    if name ~= player:getName() then return end
    if mode ~= 34 then return end

    if text == "Aaaah..." then
        nExBot.isUsingPotion = true
        schedule(950, function() nExBot.isUsingPotion = false end)
    end
end)

-- [[ canCast and cast functions ]] --
-- callback connected to cast and canCast function
-- detects if a given spell was in fact casted based on player's text messages 
-- Cast text and message text must match
-- checks only spells inserted in SpellCastTable by function cast
SpellCastTable = {}
onTalk(function(name, level, mode, text, channelId, pos)
    if name ~= player:getName() then return end
    text = text:lower()

    if SpellCastTable[text] then SpellCastTable[text].t = now end
end)

-- if delay is nil or delay is lower than 100 then this function will act as a normal say function
-- checks or adds a spell to SpellCastTable and updates cast time if exist
function cast(text, delay)
    text = text:lower()
    if type(text) ~= "string" then return end
    if not delay or delay < 100 then
        return say(text) -- if not added delay or delay is really low then just treat it like casual say
    end
    if not SpellCastTable[text] or SpellCastTable[text].d ~= delay then
        SpellCastTable[text] = {t = now - delay, d = delay}
        return say(text)
    end
    local lastCast = SpellCastTable[text].t
    local spellDelay = SpellCastTable[text].d
    if now - lastCast > spellDelay then return say(text) end
end

-- canCast is a base for AttackBot and HealBot
-- checks if spell is ready to be casted again
-- ignoreRL - if true, aparat from cooldown will also check conditions inside gamelib SpellInfo table
-- ignoreCd - it true, will ignore cooldown
-- returns boolean
local Spells = modules.gamelib.SpellInfo['Default']
function canCast(spell, ignoreRL, ignoreCd)
    if type(spell) ~= "string" then return end
    spell = spell:lower()
    if SpellCastTable[spell] then
        if now - SpellCastTable[spell].t > SpellCastTable[spell].d or ignoreCd then
            return true
        else
            return false
        end
    end
    if getSpellData(spell) then
        if (ignoreCd or not getSpellCoolDown(spell)) and
            (ignoreRL or level() >= getSpellData(spell).level and mana() >=
                getSpellData(spell).mana) then
            return true
        else
            return false
        end
    end
    -- if no data nor spell table then return true
    return true
end

local lastPhrase = ""
onTalk(function(name, level, mode, text, channelId, pos)
    if name == player:getName() then
        lastPhrase = text:lower()
    end
end)

if onSpellCooldown and onGroupSpellCooldown then
    onSpellCooldown(function(iconId, duration)
        schedule(40, function()
            if not nExBot.customCooldowns[lastPhrase] then
                nExBot.customCooldowns[lastPhrase] = {id = iconId}
            end
        end)
    end)

    onGroupSpellCooldown(function(iconId, duration)
        schedule(40, function()
            if nExBot.customCooldowns[lastPhrase] then
                nExBot.customCooldowns[lastPhrase] = {id = nExBot.customCooldowns[lastPhrase].id, group = {[iconId] = duration}}
            end
        end)
    end)
else
    warn("Outdated OTClient! update to newest version to take benefits from all scripts!")
end

-- exctracts data about spell from gamelib SpellInfo table
-- returns table
-- ie:['Spell Name'] = {id, words, exhaustion, premium, type, icon, mana, level, soul, group, vocations}
-- cooldown detection module
function getSpellData(spell)
    if not spell then return false end
    spell = spell:lower()
    local t = nil
    local c = nil
    for k, v in pairs(Spells) do
        if v.words == spell then
            t = k
            break
        end
    end
    if not t then
        for k, v in pairs(nExBot.customCooldowns) do
            if k == spell then
                c = {id = v.id, mana = 1, level = 1, group = v.group}
                break
            end
        end
    end
    if t then
        return Spells[t]
    elseif c then
        return c
    else
        return false
    end
end

-- based on info extracted by getSpellData checks if spell is on cooldown
-- returns boolean
function getSpellCoolDown(text)
    if not text then return nil end
    text = text:lower()
    local data = getSpellData(text)
    if not data then return false end
    
    local Client = getClient()
    local icon = false
    local group = false
    
    if Client and Client.isCooldownActive then
        icon = Client.isCooldownActive(data.id)
    elseif modules and modules.game_cooldown then
        icon = modules.game_cooldown.isCooldownIconActive(data.id)
    end
    
    if data.group then
        for groupId, duration in pairs(data.group) do
            local groupActive = false
            if Client and Client.isGroupCooldownActive then
                groupActive = Client.isGroupCooldownActive(groupId)
            elseif modules and modules.game_cooldown then
                groupActive = modules.game_cooldown.isGroupCooldownIconActive(groupId)
            end
            if groupActive then
                group = true
                break
            end
        end
    end
    
    return icon or group
end

-- global var to indicate that player is trying to do something
-- prevents action blocking by scripts
-- below callbacks are triggers to changing the var state
local isUsingTime = now
macro(100, function()
    nExBot.isUsing = now < isUsingTime and true or false
end)
onUse(function(pos, itemId, stackPos, subType)
    if pos.x > 65000 then return end
    if getDistanceBetween(player:getPosition(), pos) > 1 then return end
    local tile = g_map.getTile(pos)
    if not tile then return end

    local topThing = tile:getTopUseThing()
    if topThing:isContainer() then return end

    isUsingTime = now + 1000
end)
onUseWith(function(pos, itemId, target, subType)
    if pos.x < 65000 then isUsingTime = now + 1000 end
end)

-- returns first word in string 
function string.starts(String, Start)
    return string.sub(String, 1, string.len(Start)) == Start
end

-- Optimized friend/enemy caching system with periodic cache invalidation
-- Cache structure with TTL (time-to-live) for entries
CachedFriends = {}
CachedEnemies = {}
local friendCacheByName = {}  -- Secondary index by name for O(1) lookup
local enemyCacheByName = {}
local cacheLastClear = now
local CACHE_TTL = 30000  -- Clear cache every 30 seconds

-- Periodic cache cleanup to prevent stale data
local function checkCacheTTL()
    if now - cacheLastClear > CACHE_TTL then
        CachedFriends = {}
        CachedEnemies = {}
        friendCacheByName = {}
        enemyCacheByName = {}
        cacheLastClear = now
    end
end

-- Pre-build friend list lookup table for O(1) access
local friendListLookup = {}
local lastFriendListBuild = 0
local function buildFriendListLookup()
    if now - lastFriendListBuild > 5000 then  -- Rebuild every 5 seconds
        friendListLookup = {}
        if storage.playerList and storage.playerList.friendList then
            for _, name in ipairs(storage.playerList.friendList) do
                friendListLookup[name] = true
            end
        end
        lastFriendListBuild = now
    end
end

function isFriend(c)
    checkCacheTTL()
    buildFriendListLookup()
    
    local name, creature
    if type(c) == "string" then
        name = c
        -- Check name cache first
        if friendCacheByName[name] then return true end
        if enemyCacheByName[name] then return false end
    else
        if c == player then return true end
        if c:isLocalPlayer() then return true end
        -- Check creature cache first
        if CachedFriends[c] then return true end
        if CachedEnemies[c] then return false end
        name = c:getName()
        creature = c
        -- Also check name cache
        if friendCacheByName[name] then return true end
    end

    -- O(1) lookup instead of table.find O(n)
    if friendListLookup[name] then
        if creature then CachedFriends[creature] = true end
        friendCacheByName[name] = true
        return true
    end
    
    -- Party member check
    if storage.playerList and storage.playerList.groupMembers then
        local p = creature
        if not p and type(c) == "string" then
            p = SafeCall.getCreatureByName(c, true)
        end
        if p and p:isPlayer() and p:isPartyMember() then
            CachedFriends[p] = true
            friendCacheByName[name] = true
            return true
        end
    end
    
    return false
end

-- Pre-build enemy list lookup table for O(1) access
local enemyListLookup = {}
local lastEnemyListBuild = 0
local function buildEnemyListLookup()
    if now - lastEnemyListBuild > 5000 then  -- Rebuild every 5 seconds
        enemyListLookup = {}
        if storage.playerList and storage.playerList.enemyList then
            for _, name in ipairs(storage.playerList.enemyList) do
                enemyListLookup[name] = true
            end
        end
        lastEnemyListBuild = now
    end
end

-- Optimized isEnemy with O(1) lookups and caching
function isEnemy(c)
    checkCacheTTL()
    buildEnemyListLookup()
    
    local name, p
    if type(c) == "string" then
        name = c
        if enemyCacheByName[name] then return true end
        if friendCacheByName[name] then return false end
    else
        if c == player or c:isLocalPlayer() then return false end
        if CachedEnemies[c] then return true end
        if CachedFriends[c] then return false end
        name = c:getName()
        p = c
        if enemyCacheByName[name] then return true end
    end
    
    if not name then return false end
    
    if not p then
        p = SafeCall.getCreatureByName(name, true)
    end
    if not p then return false end
    if p:isLocalPlayer() then return false end

    -- O(1) lookup instead of table.find O(n)
    local isEnemyResult = false
    if p:isPlayer() then
        if enemyListLookup[name] then
            isEnemyResult = true
        elseif storage.playerList and storage.playerList.marks and not isFriend(name) then
            isEnemyResult = true
        elseif p:getEmblem() == 2 then
            isEnemyResult = true
        end
    end
    
    if isEnemyResult then
        CachedEnemies[p] = true
        enemyCacheByName[name] = true
    end
    
    return isEnemyResult
end

function getPlayerDistribution()
    local friends = {}
    local neutrals = {}
    local enemies = {}
    for i, spec in ipairs(SafeCall.global("getSpectators") or {}) do
        if spec:isPlayer() and not spec:isLocalPlayer() then
            if isFriend(spec) then
                table.insert(friends, spec)
            elseif isEnemy(spec) then
                table.insert(enemies, spec)
            else
                table.insert(neutrals, spec)
            end
        end
    end

    return friends, neutrals, enemies
end

function getFriends()
    local friends, neutrals, enemies = getPlayerDistribution()

    return friends
end

function getNeutrals()
    local friends, neutrals, enemies = getPlayerDistribution()

    return neutrals
end

function getEnemies()
    local friends, neutrals, enemies = getPlayerDistribution()

    return enemies
end

-- based on first word in string detects if text is a offensive spell
-- returns boolean
function isAttSpell(expr)
    if string.starts(expr, "exori") or string.starts(expr, "exevo") then
        return true
    else
        return false
    end
end

-- returns dressed-up item id based on not dressed id
-- returns number
function getActiveItemId(id)
    if not id then return false end

    if id == 3049 then
        return 3086
    elseif id == 3050 then
        return 3087
    elseif id == 3051 then
        return 3088
    elseif id == 3052 then
        return 3089
    elseif id == 3053 then
        return 3090
    elseif id == 3091 then
        return 3094
    elseif id == 3092 then
        return 3095
    elseif id == 3093 then
        return 3096
    elseif id == 3097 then
        return 3099
    elseif id == 3098 then
        return 3100
    elseif id == 16114 then
        return 16264
    elseif id == 23531 then
        return 23532
    elseif id == 23533 then
        return 23534
    elseif id == 23544 then
        return 23528
    elseif id == 23529 then
        return 23530
    elseif id == 30343 then -- Sleep Shawl
        return 30342
    elseif id == 30344 then -- Enchanted Pendulet
        return 30345
    elseif id == 30403 then -- Enchanted Theurgic Amulet
        return 30402
    elseif id == 31621 then -- Blister Ring
        return 31616
    elseif id == 32621 then -- Ring of Souls
        return 32635
    else
        return id
    end
end

-- returns not dressed item id based on dressed-up id
-- returns number
function getInactiveItemId(id)
    if not id then return false end

    if id == 3086 then
        return 3049
    elseif id == 3087 then
        return 3050
    elseif id == 3088 then
        return 3051
    elseif id == 3089 then
        return 3052
    elseif id == 3090 then
        return 3053
    elseif id == 3094 then
        return 3091
    elseif id == 3095 then
        return 3092
    elseif id == 3096 then
        return 3093
    elseif id == 3099 then
        return 3097
    elseif id == 3100 then
        return 3098
    elseif id == 16264 then
        return 16114
    elseif id == 23532 then
        return 23531
    elseif id == 23534 then
        return 23533
    elseif id == 23530 then
        return 23529
    elseif id == 30342 then -- Sleep Shawl
        return 30343
    elseif id == 30345 then -- Enchanted Pendulet
        return 30344
    elseif id == 30402 then -- Enchanted Theurgic Amulet
        return 30403
    elseif id == 31616 then -- Blister Ring
        return 31621
    elseif id == 32635 then -- Ring of Souls
        return 32621
    else
        return id
    end
end

-- returns amount of monsters within the range of position
-- does not include summons (new tibia)
-- returns number
function getMonstersInRange(pos, range)
    if not pos or not range then return false end
    local monsters = 0
    local Client = getClient()
    local clientVersion = getClientVersion()
    for i, spec in pairs(SafeCall.global("getSpectators") or {}) do
        if spec:isMonster() and
            (clientVersion < 960 or spec:getType() < 3) and
            getDistanceBetween(pos, spec:getPosition()) < range then
            monsters = monsters + 1
        end
    end
    return monsters
end

-- shortcut in calculating distance from local player position
-- needs only one argument
-- returns number
function distanceFromPlayer(coords)
    if not coords then return false end
    return getDistanceBetween(pos(), coords)
end

-- Cache client version check (doesn't change during session)
local function getClientVersion()
    local Client = getClient()
    if Client and Client.getClientVersion then
        return Client.getClientVersion()
    end
    return g_game and g_game.getClientVersion and g_game.getClientVersion() or 1200
end
local isOldTibia = getClientVersion() < 960

--------------------------------------------------------------------------------
-- ADVANCED MONSTER COUNTING SYSTEM
-- Supports multiple mathematical shapes for accurate counting:
-- - SQUARE: Chebyshev distance (max(dx, dy)) - default, fastest
-- - CIRCLE: Euclidean distance (sqrt(dx² + dy²)) - most accurate
-- - DIAMOND: Manhattan distance (dx + dy) - cross pattern
-- - CROSS: Only cardinal directions (N/E/S/W)
-- - CONE: Directional cone in front of player
--------------------------------------------------------------------------------

-- Shape type enum for cleaner code
local SHAPE = {
  SQUARE = 1,   -- Chebyshev distance (default Tibia range)
  CIRCLE = 2,   -- Euclidean distance (true circle)
  DIAMOND = 3,  -- Manhattan distance (rotated square)
  CROSS = 4,    -- Cardinal directions only
  CONE = 5      -- Directional cone
}

-- Export shape constants
nExBot.SHAPE = SHAPE

-- Pre-computed direction vectors for cone calculations
local CONE_DIRECTIONS = {
  [0] = {x = 0, y = -1},  -- North
  [1] = {x = 1, y = 0},   -- East
  [2] = {x = 0, y = 1},   -- South
  [3] = {x = -1, y = 0}   -- West
}

-- Pure function: Check if position is within shape
-- @param dx: x distance from center
-- @param dy: y distance from center
-- @param range: maximum range
-- @param shape: shape type (SHAPE enum)
-- @param direction: player direction (0-3) for cone shape
-- @param coneAngle: cone half-angle in tiles (default 1)
-- @return boolean
local function isInShape(dx, dy, range, shape, direction, coneAngle)
  shape = shape or SHAPE.SQUARE
  
  if shape == SHAPE.SQUARE then
    -- Chebyshev distance: max(|dx|, |dy|) <= range
    return math.max(dx, dy) <= range
    
  elseif shape == SHAPE.CIRCLE then
    -- Euclidean distance: sqrt(dx² + dy²) <= range
    -- Use squared comparison to avoid sqrt
    return (dx * dx + dy * dy) <= (range * range)
    
  elseif shape == SHAPE.DIAMOND then
    -- Manhattan distance: |dx| + |dy| <= range
    return (dx + dy) <= range
    
  elseif shape == SHAPE.CROSS then
    -- Only cardinal directions (exactly on X or Y axis)
    return (dx == 0 or dy == 0) and math.max(dx, dy) <= range
    
  elseif shape == SHAPE.CONE then
    -- Cone in front of player
    direction = direction or 0
    coneAngle = coneAngle or 1
    
    local dir = CONE_DIRECTIONS[direction]
    if not dir then return false end
    
    -- Check if in front (positive dot product with direction)
    local dotX = dx * dir.x
    local dotY = dy * dir.y
    
    -- For North/South, check Y direction and X spread
    -- For East/West, check X direction and Y spread
    if dir.y ~= 0 then
      -- North (y = -1) or South (y = 1)
      local inFront = (dy * dir.y) > 0  -- Moving in correct direction
      local withinSpread = dx <= coneAngle
      local withinRange = dy <= range
      return inFront and withinSpread and withinRange
    else
      -- East (x = 1) or West (x = -1)
      local inFront = (dx * dir.x) > 0
      local withinSpread = dy <= coneAngle
      local withinRange = dx <= range
      return inFront and withinSpread and withinRange
    end
  end
  
  return false
end

-- Advanced monster counting with shape support
-- @param range: maximum range (default 10)
-- @param shape: shape type from SHAPE enum (default SQUARE)
-- @param options: optional table {multifloor, direction, coneAngle, center, filter}
-- @return number of monsters
function getMonstersAdvanced(range, shape, options)
  range = range or 10
  shape = shape or SHAPE.SQUARE
  options = options or {}
  
  local multifloor = options.multifloor
  local direction = options.direction or (player and player:getDirection())
  local coneAngle = options.coneAngle or 1
  local center = options.center or (player and player:getPosition())
  local filter = options.filter  -- Optional filter function(creature) -> boolean
  
  if not center then return 0 end
  
  local mobs = 0
  local px, py = center.x, center.y
  
  for _, spec in pairs(getSpectators(multifloor)) do
    if spec:isMonster() and (isOldTibia or spec:getType() < 3) then
      -- Apply custom filter if provided
      if not filter or filter(spec) then
        local specPos = spec:getPosition()
        local dx = math.abs(specPos.x - px)
        local dy = math.abs(specPos.y - py)
        
        if isInShape(dx, dy, range, shape, direction, coneAngle) then
          mobs = mobs + 1
        end
      end
    end
  end
  
  return mobs
end

-- Optimized getMonsters with cached version check and pre-fetched player position
-- Backward compatible - uses SQUARE shape (Chebyshev distance)
function getMonsters(range, multifloor)
    range = range or 10
    local mobs = 0
    local playerPos = player:getPosition()
    local px, py, pz = playerPos.x, playerPos.y, playerPos.z
    
    for _, spec in pairs(getSpectators(multifloor)) do
        if spec:isMonster() and (isOldTibia or spec:getType() < 3) then
            local specPos = spec:getPosition()
            -- Inline distance calculation (faster than function call)
            local dx = math.abs(specPos.x - px)
            local dy = math.abs(specPos.y - py)
            if math.max(dx, dy) <= range then
                mobs = mobs + 1
            end
        end
    end
    return mobs
end

-- Get monsters in a circular area (true distance)
function getMonstersCircle(range, multifloor)
  return getMonstersAdvanced(range, SHAPE.CIRCLE, {multifloor = multifloor})
end

-- Get monsters in diamond/cross pattern
function getMonstersDiamond(range, multifloor)
  return getMonstersAdvanced(range, SHAPE.DIAMOND, {multifloor = multifloor})
end

-- Get monsters in cone in front of player
function getMonstersCone(range, spread, multifloor)
  return getMonstersAdvanced(range, SHAPE.CONE, {
    multifloor = multifloor,
    coneAngle = spread or 1
  })
end

-- Export isInShape for other modules
nExBot.isInShape = isInShape

-- Optimized getPlayers with reduced function calls
function getPlayers(range, multifloor)
    range = range or 10
    local specs = 0
    local playerPos = player:getPosition()
    local px, py = playerPos.x, playerPos.y
    
    for _, spec in pairs(getSpectators(multifloor)) do
        if spec:isPlayer() and not spec:isLocalPlayer() then
            local specPos = spec:getPosition()
            local dx = math.abs(specPos.x - px)
            local dy = math.abs(specPos.y - py)
            if math.max(dx, dy) <= range then
                local shield = spec:getShield()
                local emblem = spec:getEmblem()
                if not ((shield ~= 1 and spec:isPartyMember()) or emblem == 1) then
                    specs = specs + 1
                end
            end
        end
    end
    return specs
end

-- this is multifloor function
-- checks if player added in "Anti RS list" in player list is within the given range
-- returns boolean
function isBlackListedPlayerInRange(range)
    if #storage.playerList.blackList == 0 then return end
    if not range then range = 10 end
    local found = false
    for _, spec in pairs(getSpectators(true)) do
        local specPos = spec:getPosition()
        local pPos = player:getPosition()
        if spec:isPlayer() then
            if math.abs(specPos.z - pPos.z) <= 2 then
                if specPos.z ~= pPos.z then specPos.z = pPos.z end
                if distanceFromPlayer(specPos) < range then
                    if table.find(storage.playerList.blackList, spec:getName()) then
                        found = true
                    end
                end
            end
        end
    end
    return found
end

-- checks if there is non-friend player withing the range
-- padding is only for multifloor
-- returns boolean
function isSafe(range, multifloor, padding)
    local onSame = 0
    local onAnother = 0
    if not multifloor and padding then
        multifloor = false
        padding = false
    end

    for _, spec in pairs(getSpectators(multifloor)) do
        if spec:isPlayer() and not spec:isLocalPlayer() and
            not isFriend(spec:getName()) then
            if spec:getPosition().z == posz() and
                distanceFromPlayer(spec:getPosition()) <= range then
                onSame = onSame + 1
            end
            if multifloor and padding and spec:getPosition().z ~= posz() and
                distanceFromPlayer(spec:getPosition()) <= (range + padding) then
                onAnother = onAnother + 1
            end
        end
    end

    if onSame + onAnother > 0 then
        return false
    else
        return true
    end
end

-- returns amount of players within the range of local player position
-- can also check multiple floors
-- returns number
function getAllPlayers(range, multifloor)
    if not range then range = 10 end
    local specs = 0;
    for _, spec in pairs(getSpectators(multifloor)) do
        specs = not spec:isLocalPlayer() and spec:isPlayer() and
                    distanceFromPlayer(spec:getPosition()) <= range and specs +
                    1 or specs;
    end
    return specs;
end

-- returns amount of NPC's within the range of local player position
-- can also check multiple floors
-- returns number
function getNpcs(range, multifloor)
    if not range then range = 10 end
    local npcs = 0;
    for _, spec in pairs(getSpectators(multifloor)) do
        npcs =
            spec:isNpc() and distanceFromPlayer(spec:getPosition()) <= range and
                npcs + 1 or npcs;
    end
    return npcs;
end

-- main function for calculatin item amount in all visible containers
-- also considers equipped items
-- returns number
function itemAmount(id)
    return player:getItemsCount(id)
end

-- self explanatory
-- a is item to use on 
-- b is item to use a on
function useOnInvertoryItem(a, b)
    local item = findItem(b)
    if not item then return end

    return SafeCall.useWith(a, item)
end

-- Pre-computed direction offsets (static, never changes)
local NEAR_TILE_DIRS = {
    {-1, 1}, {0, 1}, {1, 1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}
}
local NEAR_TILE_COUNT = 8

-- Reusable position table to reduce garbage collection
local nearTilePos = { x = 0, y = 0, z = 0 }

-- Optimized getNearTiles with reduced allocations
function getNearTiles(pos)
    if type(pos) ~= "table" then pos = pos:getPosition() end

    local tiles = {}
    local tileCount = 0
    local baseX, baseY, baseZ = pos.x, pos.y, pos.z
    local Client = getClient()
    
    for i = 1, NEAR_TILE_COUNT do
        local dir = NEAR_TILE_DIRS[i]
        nearTilePos.x = baseX - dir[1]
        nearTilePos.y = baseY - dir[2]
        nearTilePos.z = baseZ
        
        local tile = (Client and Client.getTile) and Client.getTile(nearTilePos) or (g_map and g_map.getTile(nearTilePos))
        if tile then
            tileCount = tileCount + 1
            tiles[tileCount] = tile
        end
    end

    return tiles
end

-- self explanatory
-- use along with delay, it will only call action
function useGroundItem(id)
    if not id then return false end

    local dest = nil
    local Client = getClient()
    local tiles = (Client and Client.getTiles) and Client.getTiles(posz()) or (g_map and g_map.getTiles(posz())) or {}
    for i, tile in ipairs(tiles) do
        for j, item in ipairs(tile:getItems()) do
            if item:getId() == id then
                dest = item
                break
            end
        end
    end

    if dest then
        return use(dest)
    else
        return false
    end
end

-- self explanatory
-- use along with delay, it will only call action
function reachGroundItem(id)
    if not id then return false end

    local dest = nil
    local iPos = nil
    local Client = getClient()
    local tiles = (Client and Client.getTiles) and Client.getTiles(posz()) or (g_map and g_map.getTiles(posz())) or {}
    for i, tile in ipairs(tiles) do
        for j, item in ipairs(tile:getItems()) do
            iPos = item:getPosition()
            local iId = item:getId()
            if iId == id then
                if findPath(pos(), iPos, 20,
                            {ignoreNonPathable = true, precision = 1}) then
                    dest = item
                    break
                end
            end
        end
    end

    if dest and iPos then
        return autoWalk(iPos, 20, {ignoreNonPathable = true, precision = 1})
    else
        return false
    end
end

-- self explanatory
-- returns object
function findItemOnGround(id)
    local Client = getClient()
    local tiles = (Client and Client.getTiles) and Client.getTiles(posz()) or (g_map and g_map.getTiles(posz())) or {}
    for i, tile in ipairs(tiles) do
        for j, item in ipairs(tile:getItems()) do
            if item:getId() == id then return item end
        end
    end
end

-- self explanatory
-- use along with delay, it will only call action
function useOnGroundItem(a, b)
    if not b then return false end
    local item = findItem(a)
    if not item then return false end

    local dest = nil
    local Client = getClient()
    local tiles = (Client and Client.getTiles) and Client.getTiles(posz()) or (g_map and g_map.getTiles(posz())) or {}
    for i, tile in ipairs(tiles) do
        for j, tileItem in ipairs(tile:getItems()) do
            if tileItem:getId() == b then
                dest = tileItem
                break
            end
        end
    end

    if dest then
        return SafeCall.useWith(item, dest)
    else
        return false
    end
end

-- returns target creature
function target()
    local Client = getClient()
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    if not isAttacking then
        return nil
    end
    return (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature and g_game.getAttackingCreature())
end

-- returns target creature
function getTarget() return target() end

-- dist is boolean
-- returns target position/distance from player
function targetPos(dist)
    local Client = getClient()
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    if not isAttacking then return end
    local t = target()
    if not t then return end
    if dist then
        return distanceFromPlayer(t:getPosition())
    else
        return t:getPosition()
    end
end

-- for gunzodus/ezodus only
-- it will reopen loot bag, necessary for depositer
function reopenPurse()
    local Client = getClient()
    local containers = (Client and Client.getContainers) and Client.getContainers() or getContainers()
    for i, c in pairs(containers) do
        if c:getName():lower() == "loot bag" or c:getName():lower() ==
            "store inbox" then 
            if Client and Client.close then
                Client.close(c)
            elseif g_game and g_game.close then
                g_game.close(c)
            end
        end
    end
    schedule(100, function()
        local Client = getClient()
        local player = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer())
        if player then
            local purseItem = player:getInventoryItem(InventorySlotPurse)
            if purseItem then
                if Client and Client.use then
                    Client.use(purseItem)
                elseif g_game and g_game.use then
                    g_game.use(purseItem)
                end
            end
        end
    end)
    schedule(1400, function()
        local Client = getClient()
        local containers = (Client and Client.getContainers) and Client.getContainers() or getContainers()
        for i, c in pairs(containers) do
            if c:getName():lower() == "store inbox" then
                for _, item in pairs(c:getItems()) do
                    if item:getId() == 23721 then
                        if Client and Client.open then
                            Client.open(item, c)
                        elseif g_game and g_game.open then
                            g_game.open(item, c)
                        end
                    end
                end
            end
        end
    end)
    return CaveBot.delay(1500)
end

-- getSpectator patterns
-- param1 - pos/creature
-- param2 - pattern
-- param3 - type of return
-- 1 - everyone, 2 - monsters, 3 - players
-- returns number
function getCreaturesInArea(param1, param2, param3)
    local specs = 0
    local monsters = 0
    local players = 0
    local clientVersion = getClientVersion()
    for i, spec in pairs(getSpectators(param1, param2)) do
        if spec ~= player then
            specs = specs + 1
            if spec:isMonster() and
                (clientVersion < 960 or spec:getType() < 3) then
                monsters = monsters + 1
            elseif spec:isPlayer() and not isFriend(spec:getName()) then
                players = players + 1
            end
        end
    end

    if param3 == 1 then
        return specs
    elseif param3 == 2 then
        return monsters
    else
        return players
    end
end

-- can be improved
-- TODO in future
-- uses getCreaturesInArea, specType
-- returns number
function getBestTileByPatern(pattern, specType, maxDist, safe)
    if not pattern or not specType then return end
    if not maxDist then maxDist = 4 end

    local bestTile = nil
    local best = nil
    local Client = getClient()
    local tiles = (Client and Client.getTiles) and Client.getTiles(posz()) or (g_map and g_map.getTiles(posz())) or {}
    for _, tile in pairs(tiles) do
        if distanceFromPlayer(tile:getPosition()) <= maxDist then
            local tilePos = tile:getPosition()
            local minimapColor = (Client and Client.getMinimapColor) and Client.getMinimapColor(tilePos) or (g_map and g_map.getMinimapColor(tilePos)) or 0
            local stairs = (minimapColor >= 210 and minimapColor <= 213)
            if tile:canShoot() and tile:isWalkable() then
                if getCreaturesInArea(tilePos, pattern, specType) > 0 then
                    if (not safe or
                        getCreaturesInArea(tilePos, pattern, 3) == 0) then
                        local candidate =
                            {
                                pos = tile,
                                count = getCreaturesInArea(tilePos,
                                                           pattern, specType)
                            }
                        if not best or best.count <= candidate.count then
                            best = candidate
                        end
                    end
                end
            end
        end
    end

    bestTile = best

    if bestTile then
        return bestTile
    else
        return false
    end
end

-- returns container object based on name
function getContainerByName(name, notFull)
    if type(name) ~= "string" then return nil end

    local d = nil
    for i, c in pairs(getContainers()) do
        if c:getName():lower() == name:lower() and (not notFull or not containerIsFull(c)) then
            d = c
            break
        end
    end
    return d
end

-- returns container object based on container ID
function getContainerByItem(id, notFull)
    if type(id) ~= "number" then return nil end

    local d = nil
    for i, c in pairs(getContainers()) do
        if c:getContainerItem():getId() == id and (not notFull or not containerIsFull(c)) then
            d = c
            break
        end
    end
    return d
end

-- [[ ready to use getSpectators patterns ]] --
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
