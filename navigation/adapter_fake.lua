--[[
  navigation/adapter_fake.lua — deterministic adapter (fake client -> ports).

  Bridges tests/helpers/fake_otclient.lua to the port contract in
  navigation/ports.lua. Used by unit specs and by the replay/soak harness.
  Mirrors navigation/adapter_otclient.lua 1:1 (same mapping rules).
]]

local domain = require("navigation.domain")
local D = domain
local ports = require("navigation.ports")

local AdapterFake = {}

local HAZARD_TO_OBSTACLE = {
  FIRE_FIELD = D.OBSTACLE.FIRE_FIELD,
  ENERGY_FIELD = D.OBSTACLE.ENERGY_FIELD,
  POISON_FIELD = D.OBSTACLE.POISON_FIELD,
  MAGIC_WALL = D.OBSTACLE.MAGIC_WALL,
  WILD_GROWTH = D.OBSTACLE.WILD_GROWTH,
}

-- Diagnosis of why a tile blocks movement (raw client state -> domain terms).
function AdapterFake.blockReason(world, pos, opts)
  local t = world:tileAt(pos)
  if not t then return D.OBSTACLE.VOID_OR_MISSING_TILE end
  if t.creature and not (opts and opts.ignoreCreatures) then return D.OBSTACLE.TEMPORARY_CREATURE end
  if t.doorClosed then return D.OBSTACLE.CLOSED_DOOR end
  if t.hazard then return HAZARD_TO_OBSTACLE[t.hazard] or D.OBSTACLE.STATIC_UNWALKABLE end
  if t.bridgeBroken then return D.OBSTACLE.BROKEN_BRIDGE end
  if t.walkable == false then return D.OBSTACLE.STATIC_UNWALKABLE end
  return nil
end

--- Build the ports table for one fake client.
-- @param world  Fake.World
-- @param player Fake.Player
-- @param opts   { onEvent = function(event, payload) }  (bus listener)
-- @return ports table
function AdapterFake.create(world, player, opts)
  opts = opts or {}
  local p = ports.create()

  p.world.getMapGeneration = function() return world:getMapGeneration() end
  p.world.getTile = function(pos) return world:getTile(pos) end
  p.world.getTileBlockReason = function(pos, o) return AdapterFake.blockReason(world, pos, o) end
  p.world.getClearance = function(pos, maxR) return world:getClearance(pos, maxR) end
  p.world.isField = function(pos)
    local t = world:getTile(pos)
    return t ~= nil and t.hazard ~= nil
  end
  p.world.fieldAgeMs = function(pos)
    local t = world:tileAt(pos)
    return t and t.fieldAgeMs or nil
  end
  p.world.getMinimapColor = function() return 0 end

  p.path.findPath = function(startPos, goalPos, o)
    return world:findPath(startPos, goalPos, o)
  end

  p.movement.walk = function(dir) return player:walk(dir) end
  p.movement.autoWalk = function(destPos, chunkSize) return player:autoWalk(destPos, chunkSize) end
  p.movement.stopAutoWalk = function() player:stop() end
  p.movement.isWalking = function() return player:isWalking() end
  p.movement.acquireOwnership = function(owner, priority) return player:acquireOwnership(owner, priority) end
  p.movement.releaseOwnership = function(owner) player:releaseOwnership(owner) end
  p.movement.getOwner = function() return player:getOwner() end
  p.movement.onPositionChange = function(cb) return player:onPositionChange(cb) end
  p.movement.onZChange = function(cb) return player:onZChange(cb) end
  p.movement.onWalkError = function(cb) return player:onWalkError(cb) end

  p.action.use = function(pos, itemId) return player:use(pos, itemId) end
  p.action.useWith = function(pos, itemId, targetPos) return player:useOn(pos, itemId, targetPos) end
  p.action.hasItem = function(itemId) return player:hasItem(itemId) end

  p.time.nowMs = function() return player:getClock() end

  if opts.onEvent then
    p.bus.emit = opts.onEvent
  end

  return p
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.adapter_fake"] = AdapterFake end
return AdapterFake