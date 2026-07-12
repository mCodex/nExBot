local SC = SafeCreature or {}
local Helpers = {}

function Helpers.cId(creature)
  return SC.getId(creature)
end

function Helpers.cHp(creature)
  return SC.getHealthPercent(creature) or 100
end

function Helpers.cDead(creature)
  return SC.isRemoved(creature) or SC.getHealthPercent(creature) == 0
end

function Helpers.cName(creature)
  return SC.getName(creature) or "unknown"
end

function Helpers.gameTarget()
  local Client = nExBot.Shared.getClient()
  if Client and Client.getAttackingCreature then
    return Client.getAttackingCreature()
  end
  if g_game and g_game.getAttackingCreature then
    return g_game.getAttackingCreature()
  end
  return nil
end

return Helpers
