-- TargetBot Attack Spells Module
-- Spell/rune usage and targeting

local lastSpell = 0
local lastAttackSpell = 0
local lastItemUse = 0
local lastRuneAttack = 0

local getClient = nExBot.Shared.getClient

local function doSay(text)
  if type(text) ~= 'string' or text:len() < 1 then return false end
  local SafeCall = SafeCall or require("core.safe_call")
  if type(say) == 'function' then
    local ok, res = SafeCall.call(say, text)
    if ok then return true end
    warn("[TargetBot] doSay: say(...) failed")
    return false
  end
  if g_game and type(g_game.say) == 'function' then
    local ok, res = SafeCall.call(g_game.say, text)
    if ok then return true end
    warn("[TargetBot] doSay: g_game.say(...) failed")
    return false
  end
  if g_game and type(g_game.talk) == 'function' then
    local ok, res = SafeCall.call(g_game.talk, text)
    if ok then return true end
    warn("[TargetBot] doSay: g_game.talk(...) failed")
    return false
  end
  if g_game and type(g_game.talkLocal) == 'function' then
    local ok, res = SafeCall.call(g_game.talkLocal, text)
    if ok then return true end
    warn("[TargetBot] doSay: g_game.talkLocal(...) failed")
    return false
  end
  return false
end

TargetBot.saySpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return false end
  if not delay then delay = 500 end
  if lastSpell + delay < now then
    if not doSay(text) then
      warn("[TargetBot] no suitable say/talk method; cannot cast: " .. tostring(text))
      return false
    end
    lastSpell = now
    return true
  end
  return false
end

TargetBot.sayAttackSpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 2000 end
  if BotCore and BotCore.AttackSystem and BotCore.AttackSystem.isEnabled and BotCore.AttackSystem.isEnabled() then
    return BotCore.AttackSystem.executeSingleSpell(text, delay)
  end
  if lastAttackSpell + delay < now then
    doSay(text)
    lastAttackSpell = now
    if HuntAnalytics and HuntAnalytics.trackAttackSpell then
      HuntAnalytics.trackAttackSpell(text, 0)
    end
    return true
  end
  return false
end

TargetBot.useItem = function(item, subType, target, delay)
  if AttackBot and type(AttackBot.useItem) == 'function' then
    return AttackBot.useItem(item, subType, target, delay)
  end
  if not delay then delay = 200 end
  if lastItemUse + delay < now then
    warn("[TargetBot] useItem called but AttackBot.useItem not available; item=" .. tostring(item))
    lastItemUse = now
  end
  return false
end

TargetBot.useAttackItem = function(item, subType, target, delay)
  if AttackBot and type(AttackBot.useAttackItem) == 'function' then
    return AttackBot.useAttackItem(item, subType, target, delay)
  end
  if not delay then delay = 2000 end
  if BotCore and BotCore.AttackSystem and BotCore.AttackSystem.isEnabled and BotCore.AttackSystem.isEnabled() then
    return BotCore.AttackSystem.executeSingleRune(item, target, delay)
  end
  if lastRuneAttack + delay < now then
    warn("[TargetBot] useAttackItem called but AttackBot.useAttackItem not available; item=" .. tostring(item))
    lastRuneAttack = now
  else
    warn("[TargetBot] Rune on cooldown: last=" .. tostring(lastRuneAttack) .. ", now=" .. tostring(now) .. ", delay=" .. tostring(delay))
  end
  return false
end
