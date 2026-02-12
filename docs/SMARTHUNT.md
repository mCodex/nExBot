# Hunt Analyzer v3.0

> Real-time session analytics that track kills, damage, loot, supply usage,
> experience, and efficiency metrics while you hunt.

---

## Table of Contents

- [Overview](#overview)
- [Auto-Start Behaviour](#auto-start-behaviour)
- [Tracked Metrics](#tracked-metrics)
- [Insights Engine](#insights-engine)
- [API for Other Modules](#api-for-other-modules)
- [UI](#ui)
- [Troubleshooting](#troubleshooting)

---

## Overview

The Hunt Analyzer (`core/smart_hunt.lua`) is a lightweight analytics layer that
passively records events from native OTClient callbacks and the EventBus.
It maintains a per-session snapshot that can be viewed via the **Hunt Analyzer**
button on the Main tab.

Key design principles:

- **Zero-config** — starts automatically, no user action required
- **Passive** — never issues game actions; read-only observation
- **Low overhead** — callbacks are O(1); summary computed on-demand

---

## Auto-Start Behaviour

The Hunt Analyzer auto-starts a new session when **either**:

- **CaveBot** is turned on (`CaveBot.isOn()`)
- **TargetBot** is turned on (`TargetBot.isOn()`)

> **v3.0 change**: Previously only CaveBot triggered auto-start, so
> TargetBot-only players missed session data.

The background macro runs every 5 000 ms:

```lua
macro(5000, function()
  local caveBotOn  = CaveBot  and CaveBot.isOn  and CaveBot.isOn()
  local targetBotOn = TargetBot and TargetBot.isOn and TargetBot.isOn()
  if (caveBotOn or targetBotOn) and not isSessionActive() then
    startSession()
  end
  updateTracking()
end)
```

A second macro (`1 000 ms`) calls `updateTracking()` for finer resolution on
supply and health metrics.

---

## Tracked Metrics

| Metric | Source | Notes |
|--------|--------|-------|
| Kills | `onCreatureHealthPercentChange` | Monster health → 0 |
| Tiles walked | `onWalk` | Player movement |
| Spells cast | `onSpellCooldown` | Any spell with `duration > 0` |
| Runes used | `Analytics.trackRuneUse(name)` | Called by AttackBot |
| Potions used | `Analytics.trackPotionUse(name)` | Called by HealBot |
| Damage dealt | `HuntAnalytics.trackAttackSpell()` | Mana proxy |
| Session duration | `os.time()` delta | Wall-clock elapsed |
| Monster breakdown | `analytics.monsters[name]` | Per-creature-type kill count |

### Consumption Tracking API

Other modules report usage via the global `HuntAnalytics` alias:

```lua
HuntAnalytics.trackRuneUse("sudden death rune")
HuntAnalytics.trackPotionUse("great health potion")
HuntAnalytics.trackAttackSpell("exori vis", 0)  -- mana cost if known
```

---

## Insights Engine

The `buildInsights()` function computes derived metrics:

- **Kills/hour** — `kills / sessionHours`
- **Avg kill time** — from `MonsterAI.Telemetry.typeStats`
- **Top-killed monster** — highest count in `analytics.monsters`
- **Supply efficiency** — ratio of potions used per kill
- **Loot summary** — integrated with `core/analyzer.lua`

---

## API for Other Modules

```lua
-- Check if session is running
Analytics.isSessionActive()  -- boolean

-- Get current metrics snapshot
Analytics.getMetrics()       -- { kills, tilesWalked, spellsCast, ... }

-- Build human-readable summary string
Analytics.buildSummary()     -- multi-line text

-- Show analytics UI window
Analytics.showAnalytics()
```

---

## UI

Click **Hunt Analyzer** on the Main tab. The window shows:

- Session duration
- Total kills (with per-monster breakdown)
- Tiles walked
- Spells cast / Runes used / Potions used
- Insights section (kills/hour, efficiency)

If the UI fails to open (edge-case on some clients), the summary is printed
to the console as a fallback.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No data shown | Session never started | Turn on CaveBot _or_ TargetBot |
| Kill count = 0 | Monster health events not firing | Verify `onCreatureHealthPercentChange` works on your server |
| Analytics button missing | Module load error | Check `_Loader.lua` order; look for Lua errors in console |
| Duplicate kills | Multiple tracking sources | The native callback is the single source of truth; EventBus `creature:death` does _not_ double-count |
