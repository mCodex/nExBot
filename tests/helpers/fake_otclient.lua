-- tests/helpers/fake_otclient.lua
-- Deterministic fake OTClient for the Navigation context.
--
-- Explicit grid world (unknown tile == fail-safe nil), strict pathfinder
-- mirroring OTClient semantics, and a simulated player whose steps only
-- complete when the test advances the virtual clock. All state is trail-
-- free and reproducible; nothing depends on wall-clock time.
--
-- The fake does NOT depend on the navigation context. navigation/adapter_fake
-- maps this client to the ports the domain consumes.

local Fake = {}

local DirOffset = {
  [0] = { x = 0,  y = -1 },
  [1] = { x = 1,  y = 0  },
  [2] = { x = 0,  y = 1  },
  [3] = { x = -1, y = 0  },
  [4] = { x = 1,  y = -1 },
  [5] = { x = 1,  y = 1  },
  [6] = { x = -1, y = 1  },
  [7] = { x = -1, y = -1 },
}
local DiagDirs = { 4, 5, 6, 7 }
local DirNeighbors = {
  [0] = { 0, 1, 3 }, [1] = { 1, 0, 2 }, [2] = { 2, 1, 3 }, [3] = { 3, 0, 2 },
  [4] = { 4, 0, 1 }, [5] = { 5, 1, 2 }, [6] = { 6, 2, 3 }, [7] = { 7, 3, 0 },
}

Fake.STEP_DELAY_MS = 250

local function copyPos(p) return { x = p.x, y = p.y, z = p.z } end
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function posEquals(a, b) return a and b and a.x == b.x and a.y == b.y and a.z == b.z end

-- ── World ──────────────────────────────────────────────────────────────────

Fake.World = {}
Fake.World.__index = Fake.World

function Fake.newWorld()
  return setmetatable({
    tiles = {},      -- "x,y,z" -> raw tile def
    mapGen = 1,      -- bumped on every tile mutation (cache invalidation)
  }, Fake.World)
end

function Fake.World:key(p) return key(p) end
function Fake.World:tileAt(p) return self.tiles[key(p)] end

function Fake.World:mutate(p, def)
  local t = {}
  local raw = self.tiles[key(p)]
  if raw then for k, v in pairs(raw) do t[k] = v end end
  if def then for k, v in pairs(def) do t[k] = v end end
  self.tiles[key(p)] = t
  self.mapGen = self.mapGen + 1
  return t
end

-- Tile defs (all optional; omitted means "free"):
--   walkable (bool)      false = solid
--   creature (bool)      true  = occupied by a monster
--   hazard (string)      FIRE_FIELD|ENERGY_FIELD|POISON_FIELD|MAGIC_WALL|WILD_GROWTH
--   doorClosed (bool)    true  = closed door (blocks, but can be opened)
--   floorChange (bool)   true  = stairs/ladder/teleport entry tile

-- World methods use DOT syntax with explicit self so both `world:getTile(p)`
-- and the domain's plain `world.getTile(p)` call style work (g_map.getTile
-- in real OTClient is a plain function, not a method).

function Fake.World.freespaceRect(self, x0, y0, x1, y1, z)
  for x = x0, x1 do
    for y = y0, y1 do
      self.tiles[key({ x = x, y = y, z = z })] = { walkable = true }
    end
  end
  return self
end

function Fake.World.setWall(self, p) self:mutate(p, { walkable = false, pathable = false }) end
function Fake.World.setCreature(self, p) self:mutate(p, { creature = true }) end
function Fake.World.clearCreature(self, p) self:mutate(p, { creature = nil }) end
function Fake.World.setHazard(self, p, hazard) self:mutate(p, { hazard = hazard }) end
function Fake.World.setDoor(self, p, closed) self:mutate(p, { doorClosed = closed ~= false }) end
function Fake.World.setFloorChange(self, p) self:mutate(p, { floorChange = true }) end

-- Contract tile (what ports.world.getTile exposes). nil for void/unknown.
function Fake.World.getTile(self, p)
  local t = self.tiles[key(p)]
  if not t then return nil end
  return {
    walkable = t.walkable ~= false,
    pathable = t.pathable ~= false,
    hazard = t.hazard,
    floorChange = t.floorChange or false,
    doorClosed = t.doorClosed or false,
    bridgeBroken = t.bridgeBroken or false,
    unknown = false,
    creature = t.creature or false,
  }
end

function Fake.World.getMapGeneration(self) return self.mapGen end

-- Is the tile open for *moving into*, given traversal opts?
function Fake.World.isOpen(self, p, opts)
  local t = self.tiles[key(p)]
  if not t then return false end
  if t.walkable == false then return false end
  if t.creature and not (opts and opts.ignoreCreatures) then return false end
  if t.doorClosed then return false end
  return true
end

-- Bounded clearance: contiguous free tiles from p before the first blocker.
function Fake.World.getClearance(self, p, maxR)
  maxR = maxR or 4
  if not self:isOpen(p) then return 0 end
  local seen = { [key(p)] = true }
  local frontier = { copyPos(p) }
  local dist = 0
  while #frontier > 0 and dist < maxR do
    local next = {}
    for _, fp in ipairs(frontier) do
      for _, d in ipairs({ 0, 1, 2, 3 }) do
        local o = DirOffset[d]
        local q = { x = fp.x + o.x, y = fp.y + o.y, z = fp.z }
        if not self:isOpen(q) then return dist + 1 end
        if not seen[key(q)] then
          seen[key(q)] = true
          next[#next + 1] = q
        end
      end
    end
    frontier = next
    dist = dist + 1
  end
  return dist
end

-- Strict 8-direction BFS pathfinder (diagonals need both orthogonal sides).
-- Returns { directions, positions, cost } or nil.
function Fake.World.findPath(self, startPos, goalPos, opts)
  opts = opts or {}
  if not self:isOpen(goalPos, opts) then return nil end
  if posEquals(startPos, goalPos) then
    return { directions = {}, positions = { copyPos(startPos) }, cost = 0 }
  end
  if not self:isOpen(startPos, opts) then return nil end

  local maxSteps = opts.maxSteps or 100
  local startKey = key(startPos)
  local goalKey = key(goalPos)
  local cameFrom = { [startKey] = nil }
  local frontier = { copyPos(startPos) }
  local head = 1
  local steps = 0

  while head <= #frontier and steps < maxSteps do
    local cur = frontier[head]
    head = head + 1
    steps = steps + 1
    for d = 0, 7 do
      local o = DirOffset[d]
      local q = { x = cur.x + o.x, y = cur.y + o.y, z = cur.z }
      local qk = key(q)
      if cameFrom[qk] == nil and qk ~= startKey then
        -- Diagonal: both orthogonal corner tiles must be open too.
        if d >= 4 then
          local a = { x = cur.x + o.x, y = cur.y, z = cur.z }
          local b = { x = cur.x, y = cur.y + o.y, z = cur.z }
          if not self:isOpen(a, opts) or not self:isOpen(b, opts) then goto continue end
        end
        if not self:isOpen(q, opts) then goto continue end
        cameFrom[qk] = { from = cur, dir = d }
        if qk == goalKey then
          return self:_trace(startPos, q, cameFrom)
        end
        frontier[#frontier + 1] = q
      end
      ::continue::
    end
  end
  return nil
end

function Fake.World._trace(self, startPos, goalPos, cameFrom)
  local dirs = {}
  local node = goalPos
  local nodeKey = key(goalPos)
  while cameFrom[nodeKey] do
    local prev = cameFrom[nodeKey]
    dirs[#dirs + 1] = prev.dir
    node = prev.from
    nodeKey = key(node)
  end
  -- Reverse to start->goal.
  local rev = {}
  for i = #dirs, 1, -1 do rev[#rev + 1] = dirs[i] end

  local positions = { copyPos(startPos) }
  local p = copyPos(startPos)
  for i = 1, #rev do
    local o = DirOffset[rev[i]]
    p = { x = p.x + o.x, y = p.y + o.y, z = p.z }
    positions[#positions + 1] = p
  end
  return { directions = rev, positions = positions, cost = #rev }
end

-- ── Player / server simulation ─────────────────────────────────────────────

Fake.Player = {}
Fake.Player.__index = Fake.Player

-- Simulated server walk errors, sent to the client.
Fake.Player.WALK_ERROR = {}
Fake.Player.WALK_ERROR.SERVER_REJECTED = "SERVER_STEP_REJECTED"

function Fake.newPlayer(world, startPos)
  return setmetatable({
    world = world,
    pos = copyPos(startPos),
    pending = {},      -- queue of pending step directions
    owner = "NONE",
    clock = 0,         -- virtual ms
    frozen = false,    -- when true, pending steps never complete
    rejectNext = false,
    posCbs = {},
    zCbs = {},
    walkErrCbs = {},
    items = {},        -- itemId -> count
    useEffects = {},   -- itemId -> fn(player, fromPos, toPos, itemId)
  }, Fake.Player)
end

function Fake.Player:getPosition() return copyPos(self.pos) end
function Fake.Player:getClock() return self.clock end
function Fake.Player:isWalking() return #self.pending > 0 end

function Fake.Player:walk(dir)
  if type(dir) ~= "number" then return false end
  self.pending[#self.pending + 1] = dir
  return true
end

function Fake.Player:setAutoWalkPath(directions)
  for i = 1, #directions do self.pending[#self.pending + 1] = directions[i] end
  return true
end

function Fake.Player:autoWalk(destPos, chunkSize)
  local path = self.world:findPath(self.pos, destPos, { ignoreCreatures = false })
  if not path then return false end
  local n = math.min(chunkSize or #path.directions, #path.directions)
  for i = 1, n do self.pending[#self.pending + 1] = path.directions[i] end
  return true
end

function Fake.Player:stop() self.pending = {} end

-- Server simulation knobs.
function Fake.Player:freeze() self.frozen = true end
function Fake.Player:unfreeze() self.frozen = false end
function Fake.Player:rejectNextStep() self.rejectNext = true end

-- Advance the virtual clock; queued steps complete one per STEP_DELAY_MS.
-- Completing a step fires position/Z-change or walk-error callbacks.
function Fake.Player:advance(ms)
  if ms < 0 then ms = 0 end
  self.clock = self.clock + ms
  local budget = ms
  while #self.pending > 0 and budget >= Fake.STEP_DELAY_MS and not self.frozen do
    budget = budget - Fake.STEP_DELAY_MS
    self:_completeNextStep()
  end
end

function Fake.Player:_completeNextStep()
  local dir = table.remove(self.pending, 1)

  if self.rejectNext then
    self.rejectNext = false
    self.pending = {}
    self:_fireWalkError(Fake.Player.WALK_ERROR.SERVER_REJECTED)
    return
  end

  local o = DirOffset[dir]
  local target = { x = self.pos.x + o.x, y = self.pos.y + o.y, z = self.pos.z }
  -- Server refuses a move into a blocked tile.
  if not self.world:isOpen(target) then
    self.pending = {}
    self:_fireWalkError(Fake.Player.WALK_ERROR.SERVER_REJECTED)
    return
  end

  local old = copyPos(self.pos)
  self.pos = target
  if target.z ~= old.z then
    self:_fire(self.zCbs, target, old)
  else
    self:_fire(self.posCbs, target, old)
  end
end

function Fake.Player:_fire(cbs, ...)
  for _, cb in ipairs(cbs) do
    local ok, err = pcall(cb, ...)
    if not ok then error("fake callback error: " .. tostring(err)) end
  end
end

function Fake.Player:_fireWalkError(reason)
  for _, cb in ipairs(self.walkErrCbs) do
    local ok, err = pcall(cb, reason)
    if not ok then error("fake walk-error callback: " .. tostring(err)) end
  end
end

-- Ownership arbitration.
function Fake.Player:getOwner() return self.owner end
function Fake.Player:acquireOwnership(owner, _priority)
  if self.owner == "NONE" or self.owner == owner then
    self.owner = owner
    return true
  end
  return false
end
function Fake.Player:releaseOwnership(owner)
  if self.owner == owner then self.owner = "NONE" end
end

-- Item simulation (for action/obstacle tests).
function Fake.Player:addItem(itemId, n)
  self.items[itemId] = (self.items[itemId] or 0) + (n or 1)
end
function Fake.Player:hasItem(itemId) return (self.items[itemId] or 0) > 0 end
function Fake.Player:setUseEffect(itemId, fn) self.useEffects[itemId] = fn end
function Fake.Player:use(pos, itemId)
  if not self:hasItem(itemId) then return false end
  if self.useEffects[itemId] then
    return self.useEffects[itemId](self, copyPos(pos), nil, itemId) ~= false
  end
  return true
end
function Fake.Player:useOn(fromPos, itemId, toPos)
  if not self:hasItem(itemId) then return false end
  if self.useEffects[itemId] then
    return self.useEffects[itemId](self, copyPos(fromPos), copyPos(toPos), itemId) ~= false
  end
  return true
end

-- Event subscriptions (mirror the movement port's on* functions).
function Fake.Player:onPositionChange(cb)
  self.posCbs[#self.posCbs + 1] = cb
  return function() end
end
function Fake.Player:onZChange(cb)
  self.zCbs[#self.zCbs + 1] = cb
  return function() end
end
function Fake.Player:onWalkError(cb)
  self.walkErrCbs[#self.walkErrCbs + 1] = cb
  return function() end
end

return Fake