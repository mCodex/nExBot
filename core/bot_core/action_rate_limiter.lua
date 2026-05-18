--[[
  BotCore: Action Rate Limiter

  Small shared gate for outbound client actions. It prevents duplicate packets
  from tight retry loops without introducing queues or changing feature logic.
]]

local ActionRateLimiter = {}

local DEFAULT_INTERVALS = {
  default = 150,
  talk = 250,
  spell = 250,
  attack = 350,
  use = 200,
  useWith = 200,
  open = 300,
  move = 200,
  walk = 150,
  autoWalk = 300,
  stop = 250,
  path = 200,
  stash = 250,
}

local state = {
  last = {},
  sent = {},
  suppressed = {},
}

local function nowMs()
  if nExBot and nExBot.Shared and nExBot.Shared.nowMs then
    return nExBot.Shared.nowMs()
  end
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

local function normalizeKey(key)
  return tostring(key or "default")
end

local function getInterval(actionType, intervalMs)
  if intervalMs and intervalMs >= 0 then return intervalMs end
  return DEFAULT_INTERVALS[actionType or "default"] or DEFAULT_INTERVALS.default
end

local function bump(bucket, key)
  bucket[key] = (bucket[key] or 0) + 1
end

function ActionRateLimiter.getDefaultInterval(actionType)
  return getInterval(actionType, nil)
end

function ActionRateLimiter.isReady(key, intervalMs, actionType)
  key = normalizeKey(key)
  local interval = getInterval(actionType, intervalMs)
  local lastRun = state.last[key] or 0
  return (nowMs() - lastRun) >= interval
end

function ActionRateLimiter.allow(key, intervalMs, actionType)
  key = normalizeKey(key)
  local interval = getInterval(actionType, intervalMs)
  local t = nowMs()
  local lastRun = state.last[key] or 0

  if (t - lastRun) < interval then
    bump(state.suppressed, key)
    return false, interval - (t - lastRun)
  end

  state.last[key] = t
  bump(state.sent, key)
  return true, 0
end

function ActionRateLimiter.mark(key)
  key = normalizeKey(key)
  state.last[key] = nowMs()
  bump(state.sent, key)
end

function ActionRateLimiter.run(key, intervalMs, actionType, fn, ...)
  if type(fn) ~= "function" then return false end
  local ok = ActionRateLimiter.allow(key, intervalMs, actionType)
  if not ok then return false end
  fn(...)
  return true
end

function ActionRateLimiter.castSpell(spell, options)
  if not spell or spell == "" then return false end
  options = options or {}

  local cooldown = BotCore and BotCore.Cooldown
  if options.groupId and cooldown and cooldown.isGroupOnCooldown and cooldown.isGroupOnCooldown(options.groupId) then
    return false
  end

  local interval = options.interval or DEFAULT_INTERVALS.spell
  local globalKey = options.globalKey or "spell:global"
  local spellKey = "spell:" .. tostring(spell):lower()

  if not ActionRateLimiter.isReady(globalKey, interval, "spell") then
    bump(state.suppressed, globalKey)
    return false
  end
  if not ActionRateLimiter.isReady(spellKey, options.spellInterval or interval, "spell") then
    bump(state.suppressed, spellKey)
    return false
  end

  if say then
    say(spell)
    ActionRateLimiter.mark(globalKey)
    ActionRateLimiter.mark(spellKey)
    return true
  end

  return false
end

function ActionRateLimiter.getStats()
  return {
    sent = state.sent,
    suppressed = state.suppressed,
    last = state.last,
  }
end

function ActionRateLimiter.resetStats()
  state.sent = {}
  state.suppressed = {}
end

BotCore = BotCore or {}
BotCore.ActionRateLimiter = ActionRateLimiter
nExBot = nExBot or {}
nExBot.ActionRateLimiter = ActionRateLimiter

return ActionRateLimiter
