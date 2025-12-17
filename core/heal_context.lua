-- Shared heal/combat context for coordinated safety-first decisions
-- Captures per-tick snapshot and exposes flags used by HealBot, FriendHealer,
-- Attack/Target bots, and EQ safety. Keep this module lightweight.

HealContext = {
  snapshot = nil,
  lastSnapshotTime = 0,
  SNAPSHOT_INTERVAL = 100, -- ms; do not over-sample
  critical = false,
  dangerFlag = false,
  thresholds = {
    hpCritical = 35,
    dangerCritical = 50,
  }
}

storage.healThresholds = storage.healThresholds or { hpCritical = 35, dangerCritical = 50 }
HealContext.thresholds = {
  hpCritical = storage.healThresholds.hpCritical or 35,
  dangerCritical = storage.healThresholds.dangerCritical or 50,
}

local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

local function getTargetNameLower()
  local t = target()
  return t and t:getName():lower() or nil
end

local function snapshotOnce()
  local nowTime = nowMs()
  if (nowTime - HealContext.lastSnapshotTime) < HealContext.SNAPSHOT_INTERVAL and HealContext.snapshot then
    return HealContext.snapshot
  end

  -- Get current mana (absolute value) for spell cost checks
  local currentMana = 0
  if mana then 
    currentMana = mana() or 0
  elseif player and player.getMana then 
    currentMana = player:getMana() or 0 
  end

  local snap = {
    hp = hppercent(),
    mp = manapercent(),
    currentMana = currentMana,  -- CRITICAL: Absolute mana value for spell cost checks
    monsters = getMonsters(),
    players = getPlayers(),
    inPz = isInPz(),
    paralyzed = isParalyzed(),
    burning = isBurning and isBurning() or false,
    poisoned = isPoisoned and isPoisoned() or false,
    targetName = getTargetNameLower(),
    danger = (TargetBot and TargetBot.Danger and TargetBot.Danger()) or 0,
    cavebotOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
    targetbotOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
  }

  snap.hp = snap.hp or 0
  snap.mp = snap.mp or 0
  snap.danger = snap.danger or 0

  HealContext.snapshot = snap
  HealContext.lastSnapshotTime = nowTime

  local crit = (snap.hp <= HealContext.thresholds.hpCritical) or (snap.danger >= HealContext.thresholds.dangerCritical and not snap.inPz)
  HealContext.critical = crit
  HealContext.dangerFlag = snap.danger >= HealContext.thresholds.dangerCritical

  return snap
end

function HealContext.get()
  return snapshotOnce()
end

function HealContext.isCritical()
  snapshotOnce()
  return HealContext.critical
end

function HealContext.isDanger()
  snapshotOnce()
  return HealContext.dangerFlag
end

function HealContext.setThresholds(opts)
  if not opts then return end
  if opts.hpCritical then HealContext.thresholds.hpCritical = opts.hpCritical end
  if opts.dangerCritical then HealContext.thresholds.dangerCritical = opts.dangerCritical end
  storage.healThresholds.hpCritical = HealContext.thresholds.hpCritical
  storage.healThresholds.dangerCritical = HealContext.thresholds.dangerCritical
end

return HealContext
