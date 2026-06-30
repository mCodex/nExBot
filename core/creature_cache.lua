--[[
  CreatureCache compatibility shim
  Redirects to BotCore.Creatures (merged in Phase 3)
]]
CreatureCache = CreatureCache or {}

setmetatable(CreatureCache, {
  __index = function(_, key)
    return BotCore and BotCore.Creatures and BotCore.Creatures[key]
  end
})

return CreatureCache
