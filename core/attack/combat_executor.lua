local M = {}

function M.useRuneOnTarget(runeId, target, deps)
  if deps.useWith and target then
    local ok = pcall(deps.useWith, runeId, target)
    if ok then return true end
  end

  if deps.g_game and deps.g_game.useInventoryItemWith then
    local ok = pcall(deps.g_game.useInventoryItemWith, runeId, target)
    if ok then return true end
  end

  if deps.SafeCall and deps.SafeCall.findItem then
    local rune = deps.SafeCall.findItem(runeId)
    if rune then
      if deps.Client and deps.Client.useWith then
        local ok = pcall(deps.Client.useWith, rune, target)
        if ok then return true end
      elseif deps.g_game and deps.g_game.useWith then
        local ok = pcall(deps.g_game.useWith, rune, target)
        if ok then return true end
      end
    end
  end

  return false
end

function M.attemptSpellCast(entry, context, deps)
  local spellKey = deps.getSpellKey(entry)
  if spellKey == "" then return false end

  local state = deps.getSpellState(spellKey)
  local cdMs = deps.toCooldownMs(entry.cooldown)

  if context.settings.Cooldown and state and deps.nowMs() < state.nextReadyAt then
    return false
  end

  local canCastCaller = deps.SafeCall.getCachedCaller("canCast")
  if canCastCaller then
    local ok = canCastCaller(spellKey, not context.settings.ignoreMana, not context.settings.Cooldown)
    if ok == false then return false end
  end

  local beforeTs = deps.SpellCastTable and deps.SpellCastTable[spellKey] and deps.SpellCastTable[spellKey].t or 0
  if state then state.lastAttemptAt = deps.nowMs() end

  deps.cast(spellKey, math.max(cdMs, 100))

  local globalBackoff = deps.GLOBAL_CAST_BACKOFF or 250
  local failedBackoff = deps.FAILED_CAST_BACKOFF or 350

  deps.confirmSpellCast(spellKey, beforeTs, function()
    if state then
      state.nextReadyAt = deps.nowMs() + cdMs
    end
    deps.applyGlobalBackoff(globalBackoff)
    deps.recordAttackAction(entry.category, entry.spell)
  end, function()
    if context.settings.Cooldown and state then
      state.nextReadyAt = math.max(state.nextReadyAt or 0, deps.nowMs() + failedBackoff)
    end
    deps.applyGlobalBackoff(failedBackoff)
  end)

  return true
end

function M.executeAttack(entry, context, deps)
  if deps.isSpellCategory(entry.category) then
    return M.attemptSpellCast(entry, context, deps)
  end

  local stampKey = entry.key or tostring(entry.itemId or entry.spell)
  local actionId = entry.itemId > 100 and entry.itemId or entry.spell

  if entry.category == 3 then
    local okTargeted = M.useRuneOnTarget(entry.itemId, context.target, deps)
    if okTargeted then
      if deps.stamp then deps.stamp(stampKey) end
      deps.recordAttackAction(entry.category, actionId)
      if context and context._attackCache then context._attackCache.rotationAttempts = 0 end
      return true
    end
    return false
  elseif entry.category == 2 then
    local pat = deps.spellPatterns[entry.patternCategory] and deps.spellPatterns[entry.patternCategory][entry.pattern]
    local pKey = deps.buildPatternKey(entry, context.settings.PvpSafe)
    local cache = context._attackCache and context._attackCache.bestTileByPattern
    local data = cache and cache[pKey]
    if not data then
      data = deps.getBestTileByPattern(
        pat, entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters
      )
    end
    if data and data.pos then
      local Client = deps.Client
      local tile = (Client and Client.getTile) and Client.getTile(data.pos)
      if tile then
        local okArea = M.useRuneOnTarget(entry.itemId, tile:getTopUseThing(), deps)
        if okArea then
          if deps.stamp then deps.stamp(stampKey) end
          deps.recordAttackAction(entry.category, actionId)
          if context and context._attackCache then context._attackCache.rotationAttempts = 0 end
          return true
        end
      end
    end
    return false
  end

  return true
end

CombatExecutor = M
return M
