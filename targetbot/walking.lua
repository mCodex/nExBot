--[[
  TargetBot Walking Module - Strict Movement
  
  Routes all walkTo/walk movement through the unified PathStrategy engine
  (same strict, wall-safe pathfinding CaveBot uses) + StepValidator, instead
  of the old permissive bare getPath which let chase paths cut through walls.
]]

-- Unified strict movement engine (same as CaveBot): PathStrategy does strict,
-- wall-safe pathfinding + smoothing; StepValidator validates each step
-- fail-closed.
local PS = (nExBot and nExBot.PathStrategy) or PathStrategy
local StepValidator = (nExBot and nExBot.Nav and nExBot.Nav["navigation.step_validator"])
local function getStepValidator()
  if StepValidator then return StepValidator end
  if not StepValidator then
    local ok, mod = pcall(require, "navigation.step_validator")
    if ok and mod then StepValidator = mod end
  end
  return StepValidator
end

local getClient = nExBot.Shared.getClient

local dest = nil
local maxDist = nil
local params = nil

TargetBot.walkTo = function(_dest, _maxDist, _params)
  dest = _dest
  maxDist = _maxDist
  params = _params or {}
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NATIVE CHASE MODE CHECK
  -- When OTClient native chase mode is active (setChaseMode(1) + attacking),
  -- skip custom pathfinding - let the client handle walking automatically.
  -- This prevents interference with the native chase behavior.
  -- ═══════════════════════════════════════════════════════════════════════════
  if TargetBot.usingNativeChase then
    -- Check if we're actually attacking (native chase only works when attacking)
    local Client = getClient()
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    if isAttacking then
      -- Verify chase mode is still set correctly
      local chaseMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode()) or 0
      if chaseMode == 1 then
        -- Native chase is active and working, skip custom walking
        dest = nil
        return true  -- Return true to indicate chase is handling movement
      end
    end
  end
  
  -- Check if following a player (for "Follow While Attacking" feature)
  -- We don't skip pathfinding for monsters anymore since we use custom pathfinding for chase
  local Client = getClient()
  local currentFollow = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
  if currentFollow then
    if currentFollow:isPlayer() and not currentFollow:isLocalPlayer() then
      -- Check if following a player with "Follow While Attacking" enabled
      local shouldKeepFollow = false
      if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        local followConfig = CharacterDB.get("tools.followPlayer")
        if followConfig and followConfig.enabled and followConfig.followWhileAttacking then
          local targetName = followConfig.playerName and followConfig.playerName:trim():lower() or ""
          local followName = currentFollow:getName():lower()
          if targetName ~= "" and (followName == targetName or followName:find(targetName, 1, true)) then
            shouldKeepFollow = true
          end
        end
      end
      
      if shouldKeepFollow then
        -- Following a player, skip custom pathfinding
        dest = nil
        return
      else
        -- Not a configured follow target, cancel and use custom pathfinding
        if Client and Client.cancelFollow then
          Client.cancelFollow()
        elseif g_game and g_game.cancelFollow then
          g_game.cancelFollow()
        end
      end
    end
  end
  
  -- IMMEDIATE WALK: Execute first step right away instead of waiting for next tick
  -- This fixes the timing issue where TargetBot.walk() was called before walkTo()
  if dest and not player:isWalking() then
    return TargetBot.walk()
  end
  return true
end

-- Called every 100ms if targeting or looting is active
TargetBot.walk = function()
  if not dest then return end
  if player:isWalking() then return end
  if not PS then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  if playerPos.z ~= dest.z then 
    dest = nil
    return 
  end
  
  -- Calculate distance
  local distX = math.abs(playerPos.x - dest.x)
  local distY = math.abs(playerPos.y - dest.y)
  local dist = math.max(distX, distY)
  
  -- Check precision
  if params.precision and params.precision >= dist then 
    dest = nil
    return 
  end
  
  -- Check margin range
  if params.marginMin and params.marginMax then
    if dist >= params.marginMin and dist <= params.marginMax then 
      dest = nil
      return
    end
  end

  -- STRICT pathfinding via the shared engine (PathStrategy). It never paths
  -- through non-pathable/wall tiles (no ignoreNonPathable) and validates every
  -- step against floor-change tiles, so chases stop cutting through walls.
  -- Path recomputed each idle tick from the observed position (bounded short
  -- chase paths); no hand-rolled cache to go stale.
  local path = PS.findPath(playerPos, dest, {
    maxSteps = math.min(maxDist or 10, 50),
    ignoreCreatures = (params and params.ignoreCreatures) or false,
    precision = (params and params.precision) or 1,
  })
  if not path or #path == 0 then
    dest = nil
    return false
  end

  -- Validate + smooth the first step (same fail-closed accuracy path as CaveBot).
  local dir = path[1]
  local smoothed = PS.smoothDirection(dir) or dir
  local validator = getStepValidator()
  local vctx = { player = player, world = g_map, getPosition = function() return player:getPosition() end }
  if validator and validator.canWalkDirection then
    if validator.canWalkDirection(smoothed, vctx) then
      PS.walkStep(smoothed)
      dest = nil
      return true
    end
    if smoothed ~= dir and validator.canWalkDirection(dir, vctx) then
      PS.walkStep(dir)
      dest = nil
      return true
    end
  else
    -- No validator available (shouldn't happen): fall back to the raw step.
    local moved = walk(dir) ~= false
    dest = nil
    return moved
  end
  
  dest = nil
  return false
end

-- Clear walking state
TargetBot.clearWalk = function()
  dest = nil
end
