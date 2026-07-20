local HuntMetrics = {}
HuntMetrics.__index = HuntMetrics

local UnifiedStorage = nExBot.UnifiedStorage
local EventBus = EventBus

local DEFAULT_METRICS = {
  xpGained = 0,
  xpPerHour = 0,
  kills = 0,
  killsPerHour = 0,
  combatUptime = 0,
  tilesWalked = 0,
  tilesPerKill = 0,
  damageTaken = 0,
  healingDone = 0,
  survivabilityIndex = 0,
  nearDeathCount = 0,
  hpPotionsUsed = 0,
  manaPotionsUsed = 0,
  runesUsed = 0,
  healSpellsCast = 0,
  attackSpellsCast = 0,
  manaSpent = 0,
  potionsPerHour = 0,
  runesPerHour = 0,
  manaSpentPerHour = 0,
}

local function nowMs()
  return nExBot.Shared and nExBot.Shared.nowMs and nExBot.Shared.nowMs() or os.time() * 1000
end

local function deepCopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local result = {}
  for k, v in pairs(tbl) do
    result[k] = deepCopy(v)
  end
  return result
end

function HuntMetrics.new()
  local self = setmetatable({
    metrics = {},
    trends = {},
    sessionStartMs = nowMs(),
    lastSnapshotMs = 0,
    snapshotIntervalMs = 60000,
    loaded = false,
  }, HuntMetrics)
  return self
end

function HuntMetrics:load()
  if self.loaded then return end
  if UnifiedStorage and UnifiedStorage.isReady and UnifiedStorage.isReady() then
    local stored = UnifiedStorage.get("huntMetrics")
    if stored then
      self.metrics = stored.metrics or {}
      self.trends = stored.trends or {}
      self.sessionStartMs = stored.sessionStartMs or self.sessionStartMs
    end
  end
  self:applyDefaults()
  self.loaded = true
end

function HuntMetrics:applyDefaults()
  for k, v in pairs(DEFAULT_METRICS) do
    if self.metrics[k] == nil then
      self.metrics[k] = v
    end
  end
end

function HuntMetrics:save()
  if not UnifiedStorage or not UnifiedStorage.isReady or not UnifiedStorage.isReady() then return end
  UnifiedStorage.set("huntMetrics", {
    metrics = self.metrics,
    trends = self.trends,
    sessionStartMs = self.sessionStartMs,
  })
end

function HuntMetrics:reset()
  self.metrics = {}
  self.trends = {}
  self.sessionStartMs = nowMs()
  self:applyDefaults()
  self:save()
end

function HuntMetrics:isActive()
  return true
end

function HuntMetrics:getElapsed()
  return self:getElapsedMs()
end

function HuntMetrics:getMetrics()
  self:load()
  return deepCopy(self.metrics)
end

function HuntMetrics:getTrends()
  self:load()
  return deepCopy(self.trends)
end

function HuntMetrics:getElapsed()
  self:load()
  return nowMs() - self.sessionStartMs
end

function HuntMetrics:isActive()
  return true
end

function HuntMetrics:recordXp(amount)
  self:load()
  self.metrics.xpGained = (self.metrics.xpGained or 0) + (amount or 0)
  self:updateRates()
  self:save()
end

function HuntMetrics:recordKill()
  self:load()
  self.metrics.kills = (self.metrics.kills or 0) + 1
  self:updateRates()
  self:save()
end

function HuntMetrics:recordCombat(active)
  self:load()
  -- combatUptime tracked separately via session
  self:save()
end

function HuntMetrics:recordResource(resourceType, amount)
  self:load()
  local key = resourceType .. "Used"
  if key == "hpPotionsUsed" or key == "manaPotionsUsed" or key == "runesUsed" then
    self.metrics[key] = (self.metrics[key] or 0) + (amount or 1)
  elseif key == "healSpellsCast" or key == "attackSpellsCast" then
    self.metrics[key] = (self.metrics[key] or 0) + (amount or 1)
  elseif key == "manaSpent" then
    self.metrics.manaSpent = (self.metrics.manaSpent or 0) + (amount or 0)
  end
  self:updateRates()
  self:save()
end

function HuntMetrics:recordDamageTaken(amount)
  self:load()
  self.metrics.damageTaken = (self.metrics.damageTaken or 0) + (amount or 0)
  self:save()
end

function HuntMetrics:recordHealingDone(amount)
  self:load()
  self.metrics.healingDone = (self.metrics.healingDone or 0) + (amount or 0)
  self:save()
end

function HuntMetrics:recordTilesWalked(amount)
  self:load()
  self.metrics.tilesWalked = (self.metrics.tilesWalked or 0) + (amount or 0)
  self:save()
end

function HuntMetrics:recordNearDeath()
  self:load()
  self.metrics.nearDeathCount = (self.metrics.nearDeathCount or 0) + 1
  self:save()
end

function HuntMetrics:updateRates()
  local elapsedHours = self:getElapsed() / 3600000
  if elapsedHours > 0 then
    self.metrics.xpPerHour = (self.metrics.xpGained or 0) / elapsedHours
    self.metrics.killsPerHour = (self.metrics.kills or 0) / elapsedHours
    self.metrics.potionsPerHour = ((self.metrics.hpPotionsUsed or 0) + (self.metrics.manaPotionsUsed or 0)) / elapsedHours
    self.metrics.runesPerHour = (self.metrics.runesUsed or 0) / elapsedHours
    self.metrics.manaSpentPerHour = (self.metrics.manaSpent or 0) / elapsedHours
    if (self.metrics.kills or 0) > 0 then
      self.metrics.tilesPerKill = (self.metrics.tilesWalked or 0) / self.metrics.kills
    end
  end
end

if EventBus then
  EventBus.on("player:logout", function()
    if HuntMetrics.instance then
      HuntMetrics.instance:save()
    end
  end)
end

nExBot = nExBot or {}
local instance = HuntMetrics.new()
HuntMetrics.instance = instance
nExBot.HuntMetrics = instance

return instance