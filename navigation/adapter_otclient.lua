--[[
  navigation/adapter_otclient.lua — production ports adapter (T8).

  Implements the navigation/ports.lua contract against OTClient globals
  (g_map, g_game, player, g_clock, autoWalk, ...). This is the ONLY navigation
  file that touches OTClient globals. Every call is pcall-guarded and
  fail-closed: a missing capability returns nil/false, never success.

  STRICT path flags: findPath NEVER passes ignoreNonPathable/ignoreNonWalkable.
  Floor-changing is only requested explicitly for transition steps.
]]

local P = require("navigation.ports")

local adapter = {}

-- Path flags (Otc::PathFindFlags) — only the strict, non-permissive set.
local PF_ALLOW_NOT_SEEN = 1

local D_OFFSET = {
  [0] = { x = 0, y = -1 }, [1] = { x = 1, y = 0 }, [2] = { x = 0, y = 1 },
  [3] = { x = -1, y = 0 }, [4] = { x = 1, y = -1 }, [5] = { x = 1, y = 1 },
  [6] = { x = -1, y = 1 }, [7] = { x = -1, y = -1 },
}

local function tileOf(pos)
  local g = g_map
  if not g or not g.getTile then return nil end
  local ok, tile = pcall(g.getTile, pos)
  if not ok or not tile then return nil end
  return tile
end

local function methodOk(tile, name)
  if not tile then return nil end
  local fn = tile[name]
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, tile)
  if not ok then return nil end
  return v
end

local function tileHasCreature(tile)
  if not tile or not tile.getTopCreature then return nil end
  local ok, c = pcall(tile.getTopCreature, tile)
  if not ok then return nil end
  return c ~= nil
end

-- Item id probe that tolerates both item API shapes (`isType` on OTCv8,
-- `getId` elsewhere). Unknown capability => false.
local function itemIsType(item, id)
  if not item then return false end
  if type(item.isType) == "function" then
    local ok, v = pcall(item.isType, item, id)
    if ok then return v == true end
  end
  if type(item.getId) == "function" then
    local ok, v = pcall(item.getId, item)
    if ok then return v == id end
  end
  return false
end

-- Hazard detection is best-effort; unknown => treat as no hazard (the strict
-- path planner still refuses fields unless the edge explicitly allows them).
local function tileHazard(tile)
  if not tile or not tile.getGround then return nil end
  local ok, ground = pcall(tile.getGround, tile)
  if not ok or not ground then return nil end
  if itemIsType(ground, 1497) or itemIsType(ground, 1498) or itemIsType(ground, 1499) then
    return "FIRE_FIELD"
  end
  if itemIsType(ground, 1500) or itemIsType(ground, 1501) then return "POISON_FIELD" end
  if itemIsType(ground, 1502) or itemIsType(ground, 1503) then return "ENERGY_FIELD" end
  return nil
end

local function worldLayer()
  return {
    getMapGeneration = function()
      if g_map and g_map.revision then return g_map.revision() end
      if g_map and g_map.getMapRevision then return g_map.getMapRevision() end
      return nil
    end,
    getTile = function(pos)
      local tile = tileOf(pos)
      if not tile then return nil end
      local walkable = methodOk(tile, "isWalkable")
      local pathable = methodOk(tile, "isPathable")
      -- Unknown capability => treat the tile as unknown, never walkable.
      if walkable == nil then return { unknown = true } end
      if pathable == nil then pathable = walkable end
      return {
        walkable = walkable,
        pathable = pathable,
        hazard = tileHazard(tile),
        -- Floor-change detection is wired by the legacy bridge (which knows
        -- the client's stairs/teleport ids); fail closed here.
        floorChange = false,
        doorClosed = false,
        bridgeBroken = false,
        creature = tileHasCreature(tile) or false,
        unknown = false,
      }
    end,
    getTileBlockReason = function(pos)
      local tile = tileOf(pos)
      if not tile then return "VOID_OR_MISSING_TILE" end
      local walkable = methodOk(tile, "isWalkable")
      if walkable == false then return "STATIC_UNWALKABLE" end
      if tileHasCreature(tile) then return "TEMPORARY_CREATURE" end
      return nil
    end,
    getClearance = function(pos)
      local open = 0
      for dx = -1, 1 do
        for dy = -1, 1 do
          local t = tileOf({ x = pos.x + dx, y = pos.y + dy, z = pos.z })
          local w = t and methodOk(t, "isWalkable")
          if w then open = open + 1 end
        end
      end
      return open
    end,
    getMinimapColor = function() return nil end,
    isField = function() return false end,
    fieldAgeMs = function() return nil end,
  }
end

local function pathLayer()
  return {
    findPath = function(startPos, goalPos, opts)
      opts = opts or {}
      local g = g_map
      if not g or not g.findPath then return nil end
      local flags = PF_ALLOW_NOT_SEEN
      if opts.ignoreCreatures then flags = flags + 16 end -- PF_IGNORE_CREATURES
      -- STRICT: ignoreNonPathable / ignoreNonWalkable are NEVER set.
      local maxSteps = math.min(opts.maxSteps or 120, 127)
      local ok, result = pcall(g.findPath, startPos, goalPos, maxSteps, flags)
      if not ok or type(result) ~= "table" or #result == 0 then return nil end
      -- OTClient returns a flat direction array; build positions from it.
      local positions = { { x = startPos.x, y = startPos.y, z = startPos.z } }
      local px, py = startPos.x, startPos.y
      for _, dir in ipairs(result) do
        local off = D_OFFSET[dir]
        if off then
          px, py = px + off.x, py + off.y
          positions[#positions + 1] = { x = px, y = py, z = startPos.z }
        end
      end
      return { directions = result, positions = positions, cost = #result }
    end,
  }
end

local owner = "NONE"
local ownerPriority = 0

local function movementLayer()
  return {
    walk = function(dir)
      if g_game and g_game.walk then
        local ok, v = pcall(g_game.walk, dir, true)
        return ok and v ~= false
      end
      return false
    end,
    autoWalk = function(destPos, chunkSize)
      if autoWalk then
        local ok, v = pcall(autoWalk, destPos, chunkSize)
        return ok and v ~= false
      end
      if g_game and g_game.autoWalk then
        local ok, v = pcall(g_game.autoWalk, destPos, chunkSize)
        return ok and v ~= false
      end
      return false
    end,
    stopAutoWalk = function()
      if g_game and g_game.stop then pcall(g_game.stop) end
      if autoWalk then pcall(autoWalk, nil) end
    end,
    isWalking = function()
      local p = player
      if p and p.isWalking then
        local ok, v = pcall(p.isWalking, p)
        if ok then return v end
      end
      return false
    end,
    acquireOwnership = function(newOwner, priority)
      if owner ~= "NONE" and owner ~= newOwner and priority <= ownerPriority then
        return false
      end
      owner, ownerPriority = newOwner, priority or 0
      return true
    end,
    releaseOwnership = function(relOwner)
      if owner == relOwner then owner, ownerPriority = "NONE", 0 end
    end,
    getOwner = function() return owner end,
    onPositionChange = function(cb)
      local ok = onPlayerPositionChange and pcall(onPlayerPositionChange, cb)
      if ok and onPlayerPositionChange then return function() end end
      return function() end
    end,
    onZChange = function(cb)
      local ok = onPlayerZChange and pcall(onPlayerZChange, cb)
      if ok and onPlayerZChange then return function() end end
      return function() end
    end,
    onWalkError = function(cb)
      local ok = onPlayerWalkError and pcall(onPlayerWalkError, cb)
      if ok and onPlayerWalkError then return function() end end
      return function() end
    end,
  }
end

local function actionLayer()
  return {
    use = function(pos, itemId)
      if g_game and g_game.use and pos then
        local ok, v = pcall(g_game.use, itemId, pos)
        return ok and v ~= false
      end
      return false
    end,
    useWith = function(pos, itemId, targetPos)
      if g_game and g_game.useWith and pos and targetPos then
        local ok, v = pcall(g_game.useWith, itemId, pos, targetPos)
        return ok and v ~= false
      end
      return false
    end,
    hasItem = function(itemId)
      if g_items and g_items.getItemsCount then
        local ok, n = pcall(g_items.getItemsCount, itemId)
        if ok and n and n > 0 then return true end
      end
      return false
    end,
  }
end

local function timeLayer()
  if g_clock and g_clock.millis then
    return { nowMs = function() return g_clock.millis() end }
  end
  return { nowMs = function() return now or (os.time() * 1000) end }
end

--- Create the production port. Optional overrides for testing / partial wiring.
function adapter.create(overrides)
  local port = P.create({
    world = worldLayer(),
    path = pathLayer(),
    movement = movementLayer(),
    action = actionLayer(),
    time = timeLayer(),
  })
  if overrides then
    for layer, tbl in pairs(overrides) do
      if type(tbl) == "table" then
        for k, v in pairs(tbl) do port[layer][k] = v end
      else
        port[layer] = tbl
      end
    end
  end
  return port
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.adapter_otclient"] = adapter end
return adapter