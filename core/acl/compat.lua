--[[
  nExBot ACL — Compatibility Shim v2.0

  Minimal shim kept for _Loader.lua load order compatibility.
  The old GameWrapper/MapWrapper/proxy factories are removed.
  SafeCall enhancements that depend on ClientService are preserved.
]]

local Client = ClientService

-- =========================================================================
-- SAFECALL ENHANCEMENTS (kept — these are used by other modules)
-- =========================================================================

if SafeCall then
  local origUseWith = SafeCall.useWith
  local origGetCreature = SafeCall.getCreatureByName

  function SafeCall.useWith(item, target, subType)
    if Client and Client.useWith then
      local ok, r = pcall(Client.useWith, item, target)
      if ok then return r end
    end
    if origUseWith then return origUseWith(item, target, subType) end
    if g_game and g_game.useWith then return g_game.useWith(item, target, subType) end
  end

  function SafeCall.getCreatureByName(name, caseSensitive)
    if Client and Client.getCreatureByName then
      local ok, r = pcall(Client.getCreatureByName, name, caseSensitive)
      if ok then return r end
    end
    if origGetCreature then return origGetCreature(name, caseSensitive) end
    return nil
  end
end

-- =========================================================================
-- EXPORT (empty — no GameWrapper/MapWrapper needed)
-- =========================================================================

local Compat = {}
ACLCompat = Compat
return Compat
