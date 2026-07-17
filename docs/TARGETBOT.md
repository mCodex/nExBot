# TargetBot

AI-powered creature targeting, combat positioning, and behavior learning.

## Quick Start

1. Open **Target** tab
2. Click **+** → enter monster name → configure spells/behavior
3. Toggle **ON**

## Target Selection

### Pattern Matching

| Pattern | Matches |
|---------|---------|
| `Dragon` | Exact name |
| `Dragon*` | Dragon, Dragon Lord, Dragon Knight |
| `*Demon` | Demon, Grand Demon, Evil Demon |
| `*, !Dragon` | Everything except Dragons |
| `#100-#110` | Creature IDs 100–110 |

### 9-Stage Priority (TBI)

Each creature scored by:

| Stage | Factor |
|-------|--------|
| 1 | Distance — closer = higher |
| 2 | Health — low HP bonus (finish kills) |
| 3 | Tracker Data — learned danger from EWMA cooldown/DPS |
| 4 | Wave Prediction — imminent wave attack urgency |
| 5 | Classification — ranged, summoner, kiter boosts |
| 6 | Movement — charging toward you = higher |
| 7 | Adaptive Weights — combat feedback adjusts stages 3–5 |
| 8 | Telemetry — speed, casting signals |
| 9 | Clamp — normalized to [0, 1000] |

Highest score becomes active target.

### Proposal Arbitration

Both TargetBot selection loops submit the same normalized proposal. The intelligence Decision Engine checks generation, expiry, target validity, hard safety, priority, confidence, and utility before TargetBot requests an attack. Rejected proposals include a reason for replay and diagnostics.

`TargetReachability` owns reachable, temporarily unreachable, and hard-unreachable state. TargetBot can switch candidates after a bounded failure instead of remaining trapped on one creature.

## Attack State Machine

All attacks go through **AttackStateMachine** (ASM). No other module calls `g_game.attack()` directly.

```
IDLE → ENGAGING → LOCKED → IDLE
```

| State | Description |
|-------|-------------|
| IDLE | No target. Waiting for `requestAttack()`. |
| ENGAGING | Attack sent. Retries with exponential backoff (1.5s base, 1.5x growth, max 5). |
| LOCKED | Server confirmed. Actively fighting. |
| IDLE | Target killed/unreachable. Grace period before next. |

**SafeCreature:** All creature access via `SC.*` (single pcall wrapper).

**Persistence:** Attack sent once, server maintains state. ASM re-sends only when attack drops (nil game target). CaveBot blocked while ASM is ENGAGING or LOCKED.

### Parameters

| Parameter | Default |
|-----------|---------|
| Engage Backoff Base | 1500ms |
| Engage Backoff Growth | 1.5x |
| Engage Max Retries | 5 |
| Confirm Timeout | 1000ms |
| Attack Cooldown | 300ms |
| Switch Cooldown | 5000ms |
| Loss Grace | 450ms |

## Monster Insights

12-module AI subsystem. Runs in background, feeds targeting + movement.

### Behaviors

| Type | Description |
|------|-------------|
| Static | Stays in place |
| Chaser | Actively pursues |
| Kiter | Runs away, attacks from range |
| Erratic | Unpredictable movement |
| Ranged | Prefers distance |
| Summoner | Spawns creatures |

Classification via EWMA on movement, attack frequency, directional data.

### Spell Tracking

Records spell frequency, cooldown analysis, missile type, threat level per creature.

### Wave Prediction

Monitors direction changes + attack cooldowns. Outputs confidence 0–1. Movement coordinator dodges preemptively.

## Movement Coordination

Intent-based voting. Highest confidence intent executes per tick.

| Priority | Intent |
|----------|--------|
| 95 | Follow (party leader) |
| 90 | Wave Avoidance |
| 80 | Finish Kill |
| 70 | Spell Position (AoE) |
| 60 | Keep Distance |
| 50 | Reposition |
| 35 | Chase |
| 30 | Face Monster |

Dynamic scaling with monster count (1–2: 1.0x, 3–4: 0.85x, 5–6: 0.70x, 7+: 0.50x).

MovementCoordinator owns autonomous movement arbitration. `ChaseController` writes the native chase mode, while the TargetBot walker executes approved paths. Loot repositioning, keep-distance, chase, lure, pull, and wave avoidance use the same intent boundary.

## Dynamic Lure and Pull

Dynamic Lure uses target counts, configured minimums and maximums, delay, confidence, and current route generation. Its state machine moves through collection, holding, completion, or abort without issuing movement itself.

Pull selects one participant, applies distance and timeout hysteresis, and pauses CaveBot through the shared route state. CaveBot resumes through an explicit transition when the pull completes or aborts.

## Wave and Beam Avoidance

Wave observations combine direction, timing, and confidence. The state machine waits for its entry threshold, keeps the avoidance state through a lower exit threshold, and rejects unsafe tiles. Approved safe-tile proposals go through MovementCoordinator. Outcomes feed replay and calibration.

## Learning Modes

TargetBot models start in `SHADOW`. They record target utility, switching, monster behavior, lure safety, pull continuation, and wave outcomes without affecting combat. Configured monster priority ranks first. Route and monster context needs 30 outcomes and 0.7 confidence before it can adjust a candidate within a 10 percent bound. It cannot change chase, keep-distance, lure, reachability, or safety configuration. Promotion to `ACTIVE` requires evidence, confidence, calibration, performance, safety, XP, path-failure, and target-thrashing gates.

See [Adaptive Intelligence](INTELLIGENCE.md) for model controls and diagnostics.

## Engagement Lock

| Scenario | Monsters | Switch Cooldown | Stickiness |
|----------|----------|-----------------|------------|
| IDLE | 0 | 0ms | 0 |
| SINGLE | 1 | 1000ms | 80 |
| FEW | 2–3 | 5000ms | 150 |
| MODERATE | 4–6 | 4000ms | 100 |
| SWARM | 7–10 | 2500ms | 60 |
| OVERWHELMING | 11+ | 1500ms | 40 |

+1000 priority bonus to current target. Switch only when creature dies/disappears, becomes unreachable, or cooldown elapsed AND alternative has significantly higher priority.

## Looting

- BFS container traversal for nested loot
- Configurable loot filters
- Loot-to-container assignment
- Hunt Analyzer integration

**Eat Food:** Consumes food from corpses. "You are full" → pause 60s. Standalone mode (no loot items needed).

**Loot Lock:** Prevents Container Panel "Force Open" from fighting corpse windows. ACTIVE phase during processing, 800ms GRACE after close.

## Configuration

```json
{
  "name": "Dragon Lord",
  "priority": 3,
  "danger": 8,
  "keepDistance": true,
  "keepDistanceRange": 4,
  "avoidWaves": true,
  "lureCount": 0,
  "attackSpells": ["exori gran vis", "exori vis"],
  "attackRunes": [3161]
}
```

| Flag | Default | Description |
|------|---------|-------------|
| `MonsterAI.COLLECT_ENABLED` | true | Data collection |
| `MonsterAI.AUTO_TUNE_ENABLED` | true | Danger auto-tuning |
| `MonsterAI.DEBUG` | false | Verbose output |

## Debugging

```lua
print(MonsterAI.getStatsSummary())
print(MonsterAI.getClassification("Dragon Lord"))
print(MonsterAI.Scenario.getStats())
print(AttackStateMachine.getState(), AttackStateMachine.getTargetId())
print(nExBot.Intelligence.models:get("TargetUtilityModel").mode)
MonsterAI.DEBUG = true
```

## Troubleshooting

**Not attacking:** Enabled? Creatures configured? On screen? Mana? ASM state should be LOCKED.

**Attack stops after one hit:** ASM re-sends on nil game target. Check no other module calls `g_game.attack()`.

**Zigzag switching:** Check scenario (FEW = 5s cooldown). Enable `MonsterAI.DEBUG`.

**Not looting:** Enabled? Containers open? Creature in range?
