local dest = nil
local params = nil

TargetBot.walkTo = function(_dest, _maxDist, _params)
  dest = _dest
  params = _params or {}
end

TargetBot.walk = function()
  if not dest then return end
  local walking = player and pcall(function() return player:isWalking() end)
  if walking then return end
  local pos = player and player:getPosition()
  if not pos or pos.z ~= dest.z then dest = nil; return end
  local dist = math.max(math.abs(pos.x - dest.x), math.abs(pos.y - dest.y))
  if params.precision and dist <= params.precision then dest = nil; return end
  if player and player.autoWalk then
    pcall(function() player:autoWalk(dest) end)
  end
end

TargetBot.clearWalk = function()
  dest = nil
end
