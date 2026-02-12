# TargetBot & Monster Insights v3.0

> **TargetBot** is the combat brain of nExBot. It decides _what_ to attack, _when_ to
> switch targets, and _how_ to position the player — all while learning monster
> behaviour in real time.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Attack Flow — AttackStateMachine](#attack-flow--attackstatemachine)
- [Monster Insights Modules](#monster-insights-modules)
- [9-Stage Priority Scoring (TBI)](#9-stage-priority-scoring-tbi)
- [Scenario Manager & Anti-Zigzag](#scenario-manager--anti-zigzag)
- [EventBus Wiring](#eventbus-wiring)
- [Configuration Reference](#configuration-reference)
- [Debugging & Diagnostics](#debugging--diagnostics)

---

## Architecture Overview

```
                ┌── EventBus ──┐
                │  creature:*  │
                │  player:*    │
                │  effect:*    │
                └──────┬───────┘
                       │ events
       ┌───────────────┤───────────────┐
       ▼               ▼               ▼
  monster_tracking  monster_spell   monster_prediction
  (EWMA learning)  _tracker        (wave anticipation)
       │               │               │
       └───────┬───────┴───────────────┘
               ▼
          monster_ai.lua  (orchestrator / glue)
          VolumeAdaptation · RealTime · Telemetry · Metrics
               │
       ┌───────┼───────────────────────┐
       ▼       ▼                       ▼
  auto_tuner  monster_scenario     monster_tbi
  (classify)  (engagement locks)   (9-stage priority)
               │                       │
               └──────────┬────────────┘
                          ▼
                   target.lua main loop
                          │
                ┌─────────▼──────────┐
                │ AttackStateMachine │  ← SOLE attack issuer
                │ IDLE → ACQUIRING → │
                │ CONFIRMING →       │
                │ ATTACKING →        │
                │ RECOVERING         │
                └────────────────────┘
```

### Loading Order (cavebot.lua)

All SRP modules are loaded **before** the orchestrator:

| # | File | Purpose |
|---|------|---------|
| 1 | `monster_ai_core.lua` | Namespace, helpers (`MonsterAI._helpers`), constants |
| 2 | `monster_patterns.lua` | Pattern CRUD, persistence to `UnifiedStorage` |
| 3 | `monster_tracking.lua` | Per-creature data, EWMA cooldown learning |
| 4 | `monster_prediction.lua` | Wave/beam prediction, confidence aggregation |
| 5 | `monster_combat_feedback.lua` | Tracks prediction accuracy, adjusts weights |
| 6 | `monster_spell_tracker.lua` | Spell/missile frequency & cooldown analysis |
| 7 | `auto_tuner.lua` | Behaviour classification + danger tuning |
| 8 | `monster_scenario.lua` | Scenario detection, engagement locks, anti-zigzag |
| 9 | `monster_reachability.lua` | Pathfinding cache + blocked-tile list |
| 10 | `monster_tbi.lua` | 9-stage priority scoring |
| 11 | **`monster_ai.lua`** | **Orchestrator** — EventBus wiring, `updateAll()`, public API |
| 12 | `attack_state_machine.lua` | Deterministic state machine for attacks |

---

## Attack Flow — AttackStateMachine

### The Problem (pre-v3.0)

Three modules (`target.lua`, `event_targeting.lua`, legacy fallbacks) all called
`g_game.attack()` independently, causing:

1. Attack issued by module A → server confirms
2. Module B issues _different_ attack → interrupts module A
3. Module A re-issues → attack-once-then-stop cycle

### The Solution

**`AttackStateMachine`** is the **sole** module allowed to call `g_game.attack()`.
All other modules call `AttackStateMachine.requestSwitch(creature, priority)`.

```
State Diagram
─────────────
  IDLE ──requestSwitch()──▶ ACQUIRING
    ▲                           │
    │                      g_game.attack()
    │                           │
    │                           ▼
  RECOVERING ◀──death/gone── ATTACKING ◀── CONFIRMING
    │ (350ms grace)             ▲          (900ms timeout)
    │                           │
    └───── re-confirm ──────────┘
```

| Config Key | Default | OpenTibiaBR | Description |
|------------|---------|-------------|-------------|
| `ATTACK_REISSUE_INTERVAL` | 1400 ms | 1500 ms | Re-send attack if server didn't confirm |
| `ATTACK_CONFIRM_TIMEOUT` | 1000 ms | 1200 ms | Time to wait for `getAttackingCreature` |
| `ATTACK_COOLDOWN` | 300 ms | 350 ms | Minimum time between attack commands |
| `ATTACK_LOSS_GRACE` | 450 ms | 800 ms | Grace after losing target before RECOVERING (must exceed ACL nil-report window) |
| `RECOVER_COOLDOWN` | 600 ms | 800 ms | Minimum time between recovery re-attack attempts |
| `STOP_START_DEBOUNCE` | 1000 ms | 1200 ms | IDLE hold-off time — prevents rapid stop→re-acquire loop on noisy clients |
| `SWITCH_COOLDOWN` | 5000 ms | 4000 ms | Minimum time between target switches |

### Rules

- `target.lua` main loop calls `requestSwitch()` (never `forceSwitch()`) and
  **only when ASM is in IDLE or RECOVERING** state.
- `event_targeting.lua` routes _all_ attacks through `AttackStateMachine`.
  The `g_game.attack()` / `Client.attack()` fallbacks have been **removed**.
- `TargetBot.attack(creature, force=true)` is the **only** path that may call
  `forceSwitch()`, reserved for explicit user-initiated overrides.

---

## Monster Insights Modules

### `monster_ai_core.lua`

Foundation namespace (`MonsterAI`), shared helpers, and the `CONSTANTS` table
(confidence thresholds, EWMA alphas, attack-type enum, movement-pattern enum,
damage correlation, event-driven thresholds).

### `monster_patterns.lua`

Persistent monster-type data (`knownMonsters` map).  
- `Patterns.get(name)` — returns pattern or safe empty table  
- `Patterns.register(name, data)` — merge & persist via `UnifiedStorage`  
- `Patterns.persist(name, partial)` — incremental update  

### `monster_tracking.lua`

Per-creature live tracking (`Tracker.monsters` map keyed by creature ID).  
- `Tracker.track(creature)` — initialise tracking entry  
- `Tracker.untrack(id)` — persist pattern data, cleanup  
- `Tracker.update(creature)` — position/movement/speed sampling  
- `Tracker.updateEWMA(data, observed)` — Welford EWMA for cooldown mean + variance  
- `Tracker.getDPS(id)` — DPS over configurable sliding window  

### `monster_prediction.lua`

Wave/beam prediction engine.  
- `Predictor.predictWaveAttack(creature)` — confidence-scored prediction  
- `Predictor.isFacingPosition(monsterPos, dir, targetPos)` — direction check  
- `Predictor.predictPositionDanger(pos)` — aggregate danger from all tracked monsters  
- `Confidence.aggregate(values)` — combine multiple confidence scores  
- `Confidence.shouldAct(score)` — threshold check  

### `monster_combat_feedback.lua`

Tracks wave predictions vs actual outcomes; adjusts targeting weights.  
- `CombatFeedback.recordPrediction(id, name, predictedTime, confidence)`  
- `CombatFeedback.recordDamage(amount, attributedId, attributedName)`  
- `CombatFeedback.getWeights()` — returns adaptive weight multipliers  

### `monster_spell_tracker.lua`

Records every observed spell/missile per monster type.  
- `SpellTracker.recordSpell(creatureId, spellType, srcPos, dstPos)`  
- `SpellTracker.getMonsterSpells(creatureId)` — per-instance data  
- `SpellTracker.getTypeSpellStats(name)` — aggregated type data  
- `SpellTracker.analyzeReactivity(creatureId)` — returns threat level  

### `auto_tuner.lua`

Behaviour classification + automatic danger tuning.  
- `Classifier.classify(name, data)` — static/chaser/kiter/erratic/ranged/summoner  
- `AutoTuner.suggestDanger(name)` — proposes TargetBot danger adjustment  
- `AutoTuner.applyDangerSuggestion(name)` — writes to TargetBot config  
- `AutoTuner.runPass()` — periodic sweep across all tracked types  

### `monster_scenario.lua`

Scenario detection and engagement lock system.

| Scenario | Monsters | Switch Cooldown | Stickiness |
|----------|----------|-----------------|------------|
| IDLE | 0 | 0 ms | 0 |
| SINGLE | 1 | 1 000 ms | 80 |
| FEW | 2–3 | 5 000 ms | 150 |
| MODERATE | 4–6 | 4 000 ms | 100 |
| SWARM | 7–10 | 2 500 ms | 60 |
| OVERWHELMING | 11+ | 1 500 ms | 40 |

**Key fix (v3.0)**: `endEngagement()` does **not** call `clearTargetLock()`.
Target lock persists so `shouldAllowTargetSwitch()` can evaluate properly
before allowing a new switch. `isEngaged()` validates via
`g_game.getAttackingCreature()` + 350 ms grace period.

### `monster_reachability.lua`

Caches path-finding results per creature ID with TTL.  
- `Reachability.isReachable(creature)` — pathfind + cache  
- `Reachability.filterReachable(creatures)` — batch filter  
- `Reachability.validateTarget(creature)` — full validation  

### `monster_tbi.lua`

9-stage weighted priority calculator.

### `monster_ai.lua` (orchestrator)

After v3.0 slimming (5 992 → 2 249 lines), this file contains:

- **VolumeAdaptation** — adjusts tick intervals by monster count
- **RealTime** — direction tracking, threat cache, prediction queue
- **Telemetry** — OTClient extended creature snapshots
- **Metrics** — centralised aggregator across all subsystems
- **EventBus wiring** — connects native callbacks → subsystem methods
- **`updateAll()`** — periodic tick entry-point (500 ms via UnifiedTick)
- **Public API** — `getStatsSummary()`, `isPositionDangerous()`, etc.

---

## 9-Stage Priority Scoring (TBI)

Each creature receives a priority score through 9 sequential stages:

| Stage | Weight | Input |
|-------|--------|-------|
| 1. Distance | `-dist * 3` | Chebyshev distance to player |
| 2. Health | `(100 - hp%) * 0.5` | Finish low-health targets |
| 3. Tracker data | EWMA cooldown, DPS | Learned danger from live data |
| 4. Wave prediction | `confidence * 40` | Imminent wave attack bonus |
| 5. Classification | behaviour category bonus | Ranged/summoner get +20–35 |
| 6. Movement / Trajectory | facing player, closing speed | +25 if charging toward player |
| 7. Adaptive weights | `CombatFeedback.getWeights()` | Scales stages 3–5 |
| 8. Telemetry | snapshot enrichments | Speed multiplier, casting signals |
| 9. Final clamp | `[0, 1000]` | Normalise result |

---

## Scenario Manager & Anti-Zigzag

### Engagement Lock

Once `Scenario.startEngagement(id, hp)` is called, the system:

1. Sets `isEngaged = true`, `engagementLockId = id`
2. `shouldAllowTargetSwitch()` returns `false` for _any other_ creature
   while the engaged creature is alive and reachable
3. Target lock adds a +1 000 priority bonus to the engaged creature
4. `endEngagement()` is called **only** when the creature dies, is removed,
   or becomes unreachable — it does **not** call `clearTargetLock()`

### Zigzag Detection

The `movementHistory` buffer (last 10 positions) is analysed for direction
reversals. If ≥ 50 % of movements reverse direction and average switch time
is below 5 s, the system forces the current target lock.

---

## EventBus Wiring

All event connections are in the `if EventBus then … end` block of
`monster_ai.lua`. Key hooks:

| Event | Handler |
|-------|---------|
| `monster:appear` | `Tracker.track()` + init RealTime direction |
| `monster:disappear` | `Tracker.untrack()` + cleanup prediction queue |
| `creature:move` | Direction change → `RealTime.onDirectionChange()` |
| `monster:health` | `Tracker.update()` + activity timestamp |
| `player:damage` | Damage correlation → EWMA update → CombatFeedback |
| `effect:missile` / `onMissle` | SpellTracker + wave observation |
| `onCreatureTurn` | Native turn callback → immediate threat detection |
| `creature:death` | Kill stats → classification → AutoTuner suggestion |

---

## Configuration Reference

### TargetBot Creature Configs

```lua
{
  name = "Dragon Lord",
  priority = 3,          -- Base weight (×1000 internally)
  danger = 8,            -- AutoTuner may adjust this
  keepDistance = true,
  keepDistanceRange = 4,
  avoidWaves = true,
  lureCount = 0,
  attackSpells = { "exori gran vis", "exori vis" },
  attackRunes = { 3161 },  -- sudden death
}
```

### Runtime Flags

| Flag | Default | Description |
|------|---------|-------------|
| `MonsterAI.COLLECT_ENABLED` | `true` | Master switch for data collection |
| `MonsterAI.AUTO_TUNE_ENABLED` | `true` | Enable danger auto-tuning |
| `MonsterAI.DEBUG` | `false` | Verbose console output |
| `MonsterAI.COLLECT_EXTENDED` | `true` | Full OTClient telemetry snapshots |

---

## Debugging & Diagnostics

```lua
-- Print full stats summary
print(MonsterAI.getStatsSummary())

-- Check classification for a monster type
print(MonsterAI.getClassification("Dragon Lord"))

-- Check current scenario
print(MonsterAI.Scenario.getStats())

-- Inspect ASM state
print(AttackStateMachine.getState(), AttackStateMachine.getTargetId())

-- View TBI breakdown for a creature
local c = g_game.getAttackingCreature()
if c then print(MonsterAI.TargetBot.debugCreature(c)) end

-- Enable verbose logging
MonsterAI.DEBUG = true
```
