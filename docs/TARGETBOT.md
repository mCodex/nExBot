# 🎯 TargetBot

AI-powered creature targeting, combat positioning, and behavior prediction.

---

## 📖 Overview

TargetBot is the combat brain of nExBot. It decides **what** to attack, **when** to switch targets, and **how** to position your character — all while learning monster behavior in real time through the Monster Insights AI system.

Key capabilities:

- Intelligent target selection with 9-stage priority scoring
- Attack State Machine — sole attack issuer, eliminates attack conflicts
- Monster behavior learning (pattern recognition, spell tracking, wave prediction)
- Movement coordination (wave avoidance, AoE positioning, keep distance)
- Engagement lock system (anti-zigzag target switching)
- Scenario-aware combat (adapts to 1 monster vs. swarm)
- Looting with BFS container traversal
- Per-creature configurations
- Creature editor with pattern matching

---

## 🚀 Quick Start

1. Open the **Target** tab.
2. Click **+** to add a creature.
3. Enter monster name (e.g. `Dragon`), configure spells and behavior.
4. Toggle TargetBot **ON**.
5. TargetBot will automatically target and fight creatures.

---

## 🎯 Target Selection

### Pattern Matching

You can use patterns to match multiple creatures:

| Pattern | Matches |
|---------|---------|
| `Dragon` | Exact name "Dragon" |
| `Dragon*` | Dragon, Dragon Lord, Dragon Knight |
| `*Demon` | Demon, Grand Demon, Evil Demon |
| `*, !Dragon` | Everything except Dragons |
| `#100-#110` | Creature IDs 100–110 |

### 9-Stage Priority Scoring (TBI)

TBI stands for **TargetBot Integration** — the module that bridges Monster Insights AI data into TargetBot's priority system (`monster_tbi.lua`).

Each creature on screen receives a priority score through 9 sequential stages:

| Stage | Factor | Influence |
|-------|--------|-----------|
| 1 | **Distance** | Closer creatures get higher priority |
| 2 | **Health** | Low-health creatures get a bonus (finish kills) |
| 3 | **Tracker Data** | Learned danger from EWMA cooldown and DPS |
| 4 | **Wave Prediction** | Imminent wave attack adds urgency |
| 5 | **Classification** | Ranged, summoner, kiter types get priority boosts |
| 6 | **Movement** | Creatures charging toward you score higher |
| 7 | **Adaptive Weights** | Combat feedback adjusts stages 3–5 over time |
| 8 | **Telemetry** | Speed, casting signals from extended snapshots |
| 9 | **Clamp** | Final score normalized to [0, 1000] |

The creature with the highest score becomes the active target.

---

## ⚙️ Attack State Machine

All attacks in nExBot go through a single **AttackStateMachine** (ASM). No other module is allowed to call `g_game.attack()` directly — this eliminates the classic "attack once then stop" bug caused by competing attack issuers.

### State Flow

```text
IDLE → ACQUIRING → CONFIRMING → ATTACKING → RECOVERING → IDLE
```

| State | Description |
|-------|-------------|
| **IDLE** | No target. Waiting for `requestSwitch()`. |
| **ACQUIRING** | Target selected, `g_game.attack()` sent. |
| **CONFIRMING** | Waiting for server confirmation (up to 1000 ms). |
| **ATTACKING** | Server confirmed. Actively fighting. |
| **RECOVERING** | Target died or disappeared. Brief grace period before IDLE. |

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Reissue Interval | 1400 ms | Re-send attack if server didn't confirm |
| Confirm Timeout | 1000 ms | Wait time for server confirmation |
| Attack Cooldown | 300 ms | Minimum time between attack commands |
| Switch Cooldown | 5000 ms | Minimum time between target switches |
| Loss Grace | 450 ms | Grace period after losing target |

---

## 🧠 Monster Insights (AI System)

Monster Insights is a machine-learning subsystem made up of 12 specialized modules. It runs in the background, collecting data on every monster you encounter, and feeds its analysis into the targeting and movement systems.

### Pattern Recognition

Classifies each monster type into a behavior profile:

| Behavior | Description |
|----------|-------------|
| **Static** | Stays in place, doesn't chase |
| **Chaser** | Actively pursues the player |
| **Kiter** | Runs away, attacks from range |
| **Erratic** | Unpredictable, random movement |
| **Ranged** | Attacks from distance, prefers range |
| **Summoner** | Spawns other creatures |

Classification uses EWMA (Exponential Weighted Moving Average) on movement, attack frequency, and directional data.

### Spell Tracking

Records every observed spell and missile per monster type:

- Spell frequency and cooldown analysis
- Missile type identification
- Threat level assessment per creature

### Wave Prediction

Predicts when a monster is about to use a wave or beam attack:

- Monitors direction changes relative to player
- Tracks attack cooldowns with EWMA
- Outputs a confidence score (0–1)
- Movement coordinator uses this to dodge preemptively

### Combat Feedback

Tracks the accuracy of predictions vs. actual outcomes:

- Records prediction → result pairs
- Adjusts targeting weights adaptively
- Improves accuracy over multiple encounters

### Auto-Tuner

Automatically adjusts the danger rating of monster types:

- Classifies behavior from collected data
- Suggests danger adjustments to TargetBot config
- Can apply changes automatically or present suggestions

---

## 🚶 Movement Coordination

TargetBot uses an **intent-based voting system** for movement. Multiple subsystems can request movement, and the MovementCoordinator resolves conflicts:

### Movement Priorities

| Priority | Intent | Description |
|----------|--------|-------------|
| 1 | **Wave Avoidance** | Dodge predicted wave attacks |
| 2 | **Finish Kill** | Move into range of low-HP target |
| 3 | **Spell Position** | Optimal position for AoE spells |
| 4 | **Keep Distance** | Maintain range for ranged vocations |
| 5 | **Reposition** | Multi-factor tile scoring for safety |
| 6 | **Chase** | Close distance to target |
| 7 | **Face Monster** | Turn toward target |

Each intent carries a **confidence score**. Only the highest-confidence intent executes per tick. This prevents erratic movement from conflicting systems.

### Dynamic Scaling

Movement thresholds automatically scale based on nearby monster count:

| Monsters | Scale | Behavior |
|----------|-------|----------|
| 1–2 | 1.0x | Conservative (full thresholds) |
| 3–4 | 0.85x | Moderate reactivity |
| 5–6 | 0.70x | High reactivity |
| 7+ | 0.50x | Maximum reactivity |

---

## 🔒 Engagement Lock (Anti-Zigzag)

The Scenario Manager prevents the bot from rapidly switching between targets:

| Scenario | Monsters | Switch Cooldown | Stickiness |
|----------|----------|-----------------|------------|
| IDLE | 0 | 0 ms | 0 |
| SINGLE | 1 | 1000 ms | 80 |
| FEW | 2–3 | 5000 ms | 150 |
| MODERATE | 4–6 | 4000 ms | 100 |
| SWARM | 7–10 | 2500 ms | 60 |
| OVERWHELMING | 11+ | 1500 ms | 40 |

Once engaged with a target, the system won't allow switching until:
- The engaged creature dies or disappears
- The creature becomes unreachable
- The switch cooldown has elapsed AND the alternative has significantly higher priority

The engagement lock adds a **+1000 priority bonus** to the current target, making switches rare during active combat.

---

## 💰 Looting

TargetBot includes an integrated looting system:

- Automatic item pickup from dead creatures
- BFS (breadth-first search) container traversal for nested loot
- Configurable loot filters
- Loot-to-container assignment (loot goes to designated backpack)
- Integration with Hunt Analyzer for loot value tracking

### Eat Food from Corpses

TargetBot includes an optional **Eat Food** feature (`TargetBot.EatFood`) that consumes food items found inside corpses during normal looting. When enabled:

- Food items are identified via a centralized ID list from `constants/food_items.lua`.
- The system detects "You are full" server messages and pauses eating for 60 seconds.
- A legacy fallback reads from `storage.foodItems` if the centralized list has no match, but only when the toggle is on.
- Toggle the feature through the TargetBot UI or `TargetBot.EatFood.toggle()`.
- **Standalone mode**: Works even without loot items or loot containers configured — corpses are opened solely to eat food, then closed. The status bar shows "Eating" instead of "Looting".
- Nested containers inside corpses are skipped in eat-only mode (no loot items to find in sub-bags).

### Loot Lock

The looting system uses a **Loot Lock** protocol to prevent the Container Panel's "Force Open" feature from fighting with corpse windows:

- **ACTIVE** phase: acquired when a corpse window is opened or being processed. The Container Panel suppresses all `sortingMacro` triggers and `forceOpen` re-opens.
- **GRACE** phase: after the corpse is closed, an 800 ms cooldown keeps the lock held so any queued container events settle before `forceOpen` resumes.
- Exposed via `TargetBot.Looting.isLocked()` and `TargetBot.Looting.isActive()`.

---

## ✏️ Creature Editor

The creature editor lets you configure per-monster behavior:

| Setting | Description |
|---------|-------------|
| **Name** | Monster name or pattern |
| **Priority** | Base weight for targeting |
| **Danger** | Danger rating (auto-tuned by AI) |
| **Keep Distance** | Enable ranged positioning |
| **Distance Range** | How far to stay |
| **Avoid Waves** | Dodge wave attacks |
| **Lure Count** | Pull this many before fighting |
| **Attack Spells** | Spells to use against this creature |
| **Attack Runes** | Runes to use against this creature |

---

## 📍 Reachability System

TargetBot caches pathfinding results per creature to avoid repeated expensive calculations:

- `isReachable(creature)` — pathfind with caching
- `filterReachable(creatures)` — batch filter
- Unreachable creatures are deprioritized
- Cache entries expire on a TTL to handle changing terrain

---

## 📣 Exeta Res (Challenge)

The Exeta Res module automatically casts `exeta res` (challenge) to attract monsters to you. Useful for knights who need to maintain aggro during team hunts:

- Configurable monster count threshold
- Cooldown management
- Only casts when monsters are in range

---

## ⚙️ Configuration

### Creature Configs

Stored as JSON files in `targetbot_configs/`:

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

### Runtime Flags

| Flag | Default | Description |
|------|---------|-------------|
| `MonsterAI.COLLECT_ENABLED` | true | Master data-collection switch |
| `MonsterAI.AUTO_TUNE_ENABLED` | true | Enable danger auto-tuning |
| `MonsterAI.DEBUG` | false | Verbose console output |

---

## 🔍 Monster Inspector

The Monster Inspector UI shows live data from Monster Insights:

- Behavior classification for each tracked creature
- Pattern confidence scores
- Spell/attack history
- EWMA cooldown data
- Movement pattern visualization

Open it from the Target tab to see what the AI is learning about each monster type.

---

## 🐛 Debugging

```lua
-- Print full stats summary
print(MonsterAI.getStatsSummary())

-- Check classification for a monster type
print(MonsterAI.getClassification("Dragon Lord"))

-- Check current scenario
print(MonsterAI.Scenario.getStats())

-- Inspect ASM state
print(AttackStateMachine.getState(), AttackStateMachine.getTargetId())

-- Enable verbose logging
MonsterAI.DEBUG = true
```

---

## ❓ Troubleshooting

### TargetBot not attacking

1. Is TargetBot **enabled** (green toggle)?
2. Are there creatures configured in the creature list?
3. Are matching monsters on screen?
4. Do you have mana for attack spells?
5. Check ASM state — it should be ATTACKING when a target is present.

### Target keeps switching (zigzag)

- This should be rare with engagement locks. Check the scenario:
  - FEW monsters (2–3) has a 5-second switch cooldown
  - Ensure creature priorities are configured properly
  - Enable `MonsterAI.DEBUG` to see why switches occur

### Not attacking after target dies

- The ASM enters RECOVERING state for 350–600 ms after a kill
- This is normal — it prevents attacking the wrong creature during the transition
- If it seems stuck, check for `STOP_START_DEBOUNCE` timing

### Monsters not being looted

- Verify looting is enabled in the Target tab
- Check that loot containers are open
- Make sure the creature died within looting range
