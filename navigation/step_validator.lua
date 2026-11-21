--[[
  navigation/step_validator.lua — THE authoritative single-step validator.

  P0.1 / P0.2 / P0.3 fixes live here:
    * canWalkDirection contract: unknown capability == reject (never `true`).
    * validate(fromPos, dir, policy): destination + diagonal corner semantics.
    * Smoothing is never navigation authority: callers must pass the exact
      suggested step here before issuing any command.

  Pure Lua; depends only on navigation.domain and the world port.
]]

local domain = require("navigation.domain")
local D = domain

local StepValidator = {}

local DEFAULT_POLICY = {
  ignoreCreatures = false,     -- unknown-creature state => reject (fail safe)
  allowFields = false,         -- never cross a field unless explicitly allowed
  allowFloorChange = false,    -- never enter a transition tile by accident
  strictCorners = true,        -- diagonal requires BOTH orthogonal sides clear
  ignoreHazards = false,
}

local function tileBlocked(world, pos, policy)
  local tile = world.getTile and world.getTile(pos)
  if tile == nil then
    -- Void or unknown tile.
    return true, D.OBSTACLE.VOID_OR_MISSING_TILE
  end
  if tile.unknown then
    return true, D.OBSTACLE.UNKNOWN_MAP
  end
  if not tile.walkable then
    if tile.doorClosed then return true, D.OBSTACLE.CLOSED_DOOR end
    if tile.bridgeBroken then return true, D.OBSTACLE.BROKEN_BRIDGE end
    if tile.lockedDoor then return true, D.OBSTACLE.LOCKED_DOOR end
    return true, D.OBSTACLE.STATIC_UNWALKABLE
  end
  if not policy.ignoreCreatures and tile.creature then
    return true, D.OBSTACLE.TEMPORARY_CREATURE
  end
  if tile.hazard and not policy.allowFields and not policy.ignoreHazards then
    return true, tile.hazard  -- FIRE_FIELD, ENERGY_FIELD, POISON_FIELD, MAGIC_WALL, WILD_GROWTH
  end
  if tile.floorChange and not policy.allowFloorChange then
    return true, "FLOOR_CHANGE_TILE"
  end
  if policy.ignoreCreatures and tile.floorChange and not policy.allowFloorChange then
    return true, "FLOOR_CHANGE_TILE"
  end
  return false, nil
end

-- Resolve the end tile of a move and validate it.
-- returns: ok(bool), resultPos(table|nil), blockReason(string|nil)
function StepValidator.validate(fromPos, dir, opts)
  if type(dir) ~= "number" then
    return false, nil, "INVALID_DIRECTION"
  end
  local off = D.offsetOf(dir)
  if not off then
    return false, nil, "INVALID_DIRECTION"
  end
  local policy = {}
  for k, v in pairs(DEFAULT_POLICY) do policy[k] = v end
  if opts then for k, v in pairs(opts) do policy[k] = v end end

  local world = policy.world
  if not world or not world.getTile then
    -- Unknown capability must NOT default to success.
    return false, nil, "NO_MAP"
  end

  local destPos = D.addOffset(fromPos, off)

  local blocked, reason = tileBlocked(world, destPos, policy)
  if blocked then
    return false, nil, reason
  end

  if D.isDiagonal(dir) and policy.strictCorners then
    -- Corner semantics: both orthogonal side tiles must also be clear under
    -- the same policy. A single blocked corner clips the tile.
    local sideA = { x = fromPos.x + off.x, y = fromPos.y, z = fromPos.z }
    local sideB = { x = fromPos.x, y = fromPos.y + off.y, z = fromPos.z }
    local aBlocked, aReason = tileBlocked(world, sideA, policy)
    if aBlocked then
      return false, nil, "DIAGONAL_CORNER_REJECTED:" .. tostring(aReason)
    end
    local bBlocked, bReason = tileBlocked(world, sideB, policy)
    if bBlocked then
      return false, nil, "DIAGONAL_CORNER_REJECTED:" .. tostring(bReason)
    end
  end

  return true, destPos, nil
end

-- Legacy-safe client walkability probe (P0.1 contract).
--
-- Razors:
--   * nil direction                          -> false, "INVALID_DIRECTION"
--   * player:canWalk(dir) == true            -> true,  "PLAYER_CONFIRMED"
--   * player:canWalk(dir) explicit false     -> false, "PLAYER_REJECTED"
--   * player.canWalk missing / throws        -> StepValidator.validate
--   * still unknown                          -> false, "UNKNOWN_WALKABILITY"
function StepValidator.canWalkDirection(dir, ctx)
  if type(dir) ~= "number" then
    return false, "INVALID_DIRECTION"
  end
  local player = ctx and ctx.player
  if player and type(player.canWalk) == "function" then
    local ok, result = pcall(player.canWalk, player, dir)
    if ok then
      if result == true then
        return true, "PLAYER_CONFIRMED"
      end
      return false, "PLAYER_REJECTED"
    end
  end
  -- No reliable client signal: fall back to map-validated step.
  local world = (ctx and ctx.world) or (ctx and ctx.ports and ctx.ports.world)
  if world and ctx and ctx.player then
    local pos = ctx.getPosition and ctx.getPosition()
    if pos then
      local okV, _, reason = StepValidator.validate(pos, dir, {
        world = world,
        ignoreCreatures = false,
        allowFloorChange = false,
      })
      if okV then return true, "MAP_CONFIRMED" end
      return false, reason or "UNKNOWN_WALKABILITY"
    end
  end
  -- Unknown capability must not default to success.
  return false, "UNKNOWN_WALKABILITY"
end

-- Validate a direction sequence position-by-position from `startPos`.
-- Returns ok(bool), endPos, firstBadIndex.
function StepValidator.validatePath(startPos, directions, opts)
  local pos = D.copyPos(startPos)
  local policy = { world = opts and opts.world }
  if opts then
    for k, v in pairs(opts) do
      if k ~= "world" then policy[k] = v end
    end
  end
  for i = 1, #directions do
    local ok, nextPos, reason = StepValidator.validate(pos, directions[i], policy)
    if not ok then
      return false, pos, i, reason
    end
    pos = nextPos
  end
  return true, pos, nil
end

-- Validate diagonal corner semantics from a `from`->`to` L-shape merge.
-- Returns ok(bool), reason.
function StepValidator.canMergeDiagonal(fromPos, dirA, dirB, world, policy)
  local offA = D.offsetOf(dirA)
  local offB = D.offsetOf(dirB)
  if not offA or not offB or D.isDiagonal(dirA) or D.isDiagonal(dirB) then
    return false, "NOT_CARDINAL_PAIR"
  end
  -- The two cardinal steps must be perpendicular (an L-shape).
  if offA.x * offB.x + offA.y * offB.y ~= 0 then
    return false, "NOT_L_SHAPE"
  end
  policy = policy or {}
  local p = D.copyPos(fromPos)
  local corner = { x = p.x + offA.x, y = p.y + offA.y, z = p.z }
  local otherSide = { x = p.x + offB.x, y = p.y + offB.y, z = p.z }
  local diag = { x = p.x + offA.x + offB.x, y = p.y + offA.y + offB.y, z = p.z }
  -- Both orthogonal sides and the diagonal must be clear.
  local blocked, reason = tileBlocked(world, corner, policy)
  if blocked then return false, "CORNER_TILE_BLOCKED:" .. tostring(reason) end
  blocked, reason = tileBlocked(world, otherSide, policy)
  if blocked then return false, "CORNER_TILE_BLOCKED:" .. tostring(reason) end
  blocked, reason = tileBlocked(world, diag, policy)
  if blocked then return false, "DIAGONAL_TILE_BLOCKED:" .. tostring(reason) end
  return true, nil
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.step_validator"] = StepValidator end
return StepValidator
