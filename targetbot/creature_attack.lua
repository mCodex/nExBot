local getClient = nExBot.Shared.getClient

TargetBot.Creature.attack = function(params, targets, isLooting)
  if not params or not params.creature or not params.config then return end
  if TargetBot.explicitlyDisabled then return end
  if TargetBot.isOn and not TargetBot.isOn() then return end

  local config = params.config
  local creature = params.creature
  local cpos = creature:getPosition()
  local pos = player and player:getPosition()
  if not cpos or not pos or cpos.z ~= pos.z then return end

  local dist = math.max(math.abs(cpos.x - pos.x), math.abs(cpos.y - pos.y))
  local chase = config.chase and not config.keepDistance

  -- Set chase mode once
  local Client = getClient()
  if Client and Client.setChaseMode then
    Client.setChaseMode(chase and 1 or 0)
  elseif g_game and g_game.setChaseMode then
    g_game.setChaseMode(chase and 1 or 0)
  end

  -- Keep distance: autoWalk to tile at keepRange from creature
  if config.keepDistance then
    local keepRange = config.keepDistanceRange or 4
    if dist < keepRange then
      local dx = pos.x - cpos.x
      local dy = pos.y - cpos.y
      local currentDist = math.max(1, math.max(math.abs(dx), math.abs(dy)))
      local scale = keepRange / currentDist
      local keepPos = { x = math.floor(cpos.x + dx * scale + 0.5), y = math.floor(cpos.y + dy * scale + 0.5), z = pos.z }
      TargetBot.walkTo(keepPos, 10, { precision = 1 })
    end
  elseif chase and dist > 1 then
    -- Chase: only autoWalk if a path exists (prevents silent stuck)
    local ok, path = pcall(findPath, pos, cpos, 12, {
      ignoreNonPathable = true, ignoreCreatures = true, ignoreCost = true,
    })
    if ok and path and #path > 0 then
      pcall(function() player:autoWalk(cpos) end)
    end
  end

  -- Face monster when adjacent or diagonal
  if config.faceMonster and dist <= 1 then
    local dx = cpos.x - pos.x
    local dy = cpos.y - pos.y
    if dx == 1 and pcall(function() return player:getDirection() ~= 1 end) then pcall(turn, 1)
    elseif dx == -1 and pcall(function() return player:getDirection() ~= 3 end) then pcall(turn, 3)
    elseif dy == 1 and pcall(function() return player:getDirection() ~= 2 end) then pcall(turn, 2)
    elseif dy == -1 and pcall(function() return player:getDirection() ~= 0 end) then pcall(turn, 0)
    end
  end
end

