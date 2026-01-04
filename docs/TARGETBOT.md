# 🎯 TargetBot - Intelligent Combat System

![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![Status](https://img.shields.io/badge/status-Released-green.svg)

**AI-powered creature targeting with behavior prediction, movement optimization, and intelligent spell selection**

> Note: Casting of spells/runes and direct attack execution has been moved to the dedicated **AttackBot** module — TargetBot now focuses on target selection, positioning, movement coordination and tactical decisions.

---

## Table of Contents

- [Overview](#-overview)
- [Targeting System](#-targeting-system)
- [Monster AI](#-monster-behavior-ai)
- [Movement Coordination](#-movement-coordination)
- [Spell Optimization](#-spell-optimization)
- [Configuration](#-configuration)
- [Advanced Topics](#-advanced-topics)
- [Troubleshooting](#-troubleshooting)

---

## 🎯 Overview

TargetBot is the **combat intelligence system** that handles:

1. **Target Selection** - Weighted priority scoring decides which creature to attack
2. **Monster AI** - Pattern recognition learns creature behavior
3. **Movement** - Intent-based voting prevents erratic movement
4. **Spell Selection** - Optimizes positioning for area damage spells
5. **Combat Tactics** - Adapts to danger levels and group attacks

> [!TIP]
> TargetBot works seamlessly with CaveBot (pauses nav during combat) and HealBot (focused on survival). All systems share one unified event bus for coordinated decisions.

### Quick Architecture

```
Game Events (creature health, death, new spawn)
    │
    ├─→ Creature Priority Scoring (select target)
    │
    ├─→ Monster AI Analysis (predict behavior)
    │
    ├─→ Spell Optimizer (find best position)
    │
    ├─→ Movement Coordinator (vote on movement)
    │
    └─→ Combat Actions (spell/rune cast, walk)
         │
         └─→ Hunt Analyzer (track resource use)
```

---

## 🎯 Targeting System

### How TargetBot Chooses Targets

TargetBot uses **weighted scoring** to pick the best creature to attack:

```
PRIORITY SCORE = (Health Factor) + (Distance Factor) + (Danger Factor)
                + (Pattern Bonus) + (Size Bonus)
```

#### 1. Health Factor (Critical)

```
Dead Creatures:       Score = 0 (never target)
Dying (< 10% HP):     Score = +50 (highest priority!)
Critical (10-25%):    Score = +30
Low (25-50%):         Score = +15
Healthy (> 50%):      Score = -5 (deprioritized)

RATIONALE: Kill weakest enemies first to reduce incoming damage
```

**Example:**
```
Creature A: 15% HP remaining → +30 points (focus kill)
Creature B: 80% HP, closest → +0 points (skip this)
Creature C: Dead → 0 points (ignore)
Result: Attack Creature A first
```

#### 2. Distance Factor (Positioning)

```
Very Close (1-2 tiles):   Score = +20 (optimal range)
Close (3-5 tiles):        Score = +15 (good range)
Medium (6-10 tiles):      Score = +5  (can reach)
Far (11-15 tiles):        Score = -10 (inefficient)
Very Far (> 15 tiles):    Score = -25 (out of range)

RATIONALE: Closer = less movement waste, faster attacks
```

**Example with Distance:**
```
Creature A: 15% HP @ 2 tiles → 30 + 20 = 50 points ⭐ TARGET
Creature B: 80% HP @ 3 tiles → 0 + 15 = 15 points
```

#### 3. Danger Factor (Threat Assessment)

```
Creature Threat Levels:
├─ Safe (low damage):        Score = 0
├─ Threatening (medium):     Score = +5  (modest priority boost)
├─ Very Dangerous (high):    Score = +15 (serious threat)
└─ Extreme (one-shot risk):  Score = +25 (highest priority!)

RATIONALE: Kill threats before they kill you
```

**Real Example:**
```
Creature A: 15% HP, Safe danger    → 30 + 20 + 0 = 50 pts
Creature B: 80% HP, Extreme danger → 0 + 15 + 25 = 40 pts
Creature C: 60% HP, Threatening    → 0 + 10 + 5 = 15 pts

Analysis:
TargetBot focuses on Creature A (lowest threat+dying)
BUT if Creature B approaches very close, will switch
(threat factor grows as distance decreases)
```

#### 4. Pattern Matching (Special Rules)

You can use **patterns** to force specific targets:

```
PATTERN SYNTAX:
├─ Monster*       Matches any creature starting with "Monster"
├─ *Demon        Matches any creature ending with "Demon"
├─ *Evil*        Matches any creature containing "Evil"
├─ !Dragon       Exclude all Dragons
├─ Dragon, !Red  Include Drag*, exclude Red Dragons
├─ #100-#110     Target creature IDs 100-110
├─ ALL, !Knight  Target everything except Knights
└─ CORPSE        Target only corpses (looting)
```

**Examples:**

```
Pattern: "!, !Dragon"
├─ Targets: Every creature EXCEPT Dragons
└─ Score Adjustment: Matching = +100 (forced priority)

Pattern: "Demon"
├─ Targets: Demon, Demon Lord, Green Demon, etc.
└─ Score Adjustment: +100 boost

Pattern: "#100-#150"
├─ Targets: Creatures with IDs 100-150 (specific types)
└─ Use Case: Hunting specific monster levels
```

#### 5. Size Bonus (Area Optimization)

```
Group Size Modifier:
├─ Solo creature (1):      Score = +0
├─ Pair (2):               Score = +5  (double targets)
├─ Group (3-6):            Score = +10 (AoE effective)
├─ Large Group (7-10):     Score = +15 (very AoE effective)
└─ Swarm (> 10):           Score = +20 (AoE mandatory!)

RATIONALE: Group targets are better for area spells
```

### Priority Evaluation Order

TargetBot **re-evaluates** priorities every combat tick:

```
1. Check if current target still exists
   └─ If dead/gone → pick new target

2. Recalculate all creature scores
   └─ Health, distance, danger may have changed

3. If new target has > 20% higher score → switch targets
   └─ Prevents excessive target swapping

4. Execute attack on selected target
   └─ Spell or rune based on configuration
```

---

## 🧠 Monster Behavior AI

TargetBot learns and remembers how each monster **behaves** and **attacks**.

### Behavior Patterns

TargetBot classifies each monster into 4 behavior types:

#### 1. Static Pattern 🛑

```
Characteristics:
├─ Stays in one location
├─ Minimal movement
├─ Attacks when you're in range
├─ Predictable attack timing

Examples: Most spiders, wasps, bats in caves

Combat Tactics:
├─ Keep distance → they come to you
├─ Use AoE → they don't escape
├─ Time attacks → predictable windows
└─ Optimal: Stand & attack from range
```

**Confidence Scoring:**
```
Confidence 0.95 = Very predictable (perfect pattern match)
         0.85 = Reliable (mostly consistent)
         0.70 = Decent (some variation)
```

#### 2. Chase Pattern 🏃

```
Characteristics:
├─ Follows you aggressively
├─ Runs directly at you
├─ Closes distance quickly
├─ Doesn't retreat

Examples: Dragons, Demons, Most humanoids

Combat Tactics:
├─ They WILL reach you
├─ Prepare healing (high damage incoming)
├─ Use defensive spells (haste, shield)
├─ Kite or lure them away from others
└─ Optimal: Circle movement, heal as needed
```

#### 3. Kite Pattern 🔄

```
Characteristics:
├─ Keeps distance from you
├─ Runs away when you approach
├─ Attacks from range
├─ Slow to catch

Examples: Paladins, Rangers, Archers, some mages

Combat Tactics:
├─ Chase them down
├─ Don't waste time, they're slow
├─ AoE spells work well (big area)
├─ Ranged spells helpful
└─ Optimal: Direct approach, corner them
```

#### 4. Erratic Pattern 🌀

```
Characteristics:
├─ Unpredictable movement
├─ Sudden direction changes
├─ Random attack patterns
├─ Difficult to anticipate

Examples: Mutated creatures, possessed things, glitched behavior

Combat Tactics:
├─ More defensive (expect anything)
├─ Stay mobile
├─ Higher healing readiness
├─ Wider safety margins
└─ Optimal: Caution mode activated
```

### Behavior Learning Algorithm

```
┌─────────────────────────────────────────────────────────┐
│           MONSTER AI LEARNING PROCESS                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  STEP 1: Observe Creature Behavior                      │
│  └─ Track position changes over time                    │
│  └─ Record distance, direction, speed                   │
│  └─ Collect 10+ observations                            │
│                                                         │
│  STEP 2: Pattern Recognition                           │
│  └─ Analyze movement vectors                            │
│  └─ Classify into Static/Chase/Kite/Erratic            │
│  └─ Calculate pattern match % (0-1)                     │
│                                                         │
│  STEP 3: Confidence Scoring                             │
│  └─ High match % = high confidence                      │
│  └─ Conflicting data = lower confidence                 │
│  └─ More observations = higher confidence              │
│                                                         │
│  STEP 4: Store in Monster Database                      │
│  └─ Remember for future encounters                      │
│  └─ Tied to creature type ID                            │
│  └─ Persist across game sessions                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Prediction Engine

Once a pattern is learned, TargetBot **predicts future behavior**:

```
Example: "Dragon" behavior (Chase pattern, 0.92 confidence)

Current State:
├─ Dragon @ position (100, 200, 7)
├─ You @ position (102, 205, 7)
├─ Dragon running toward you

Prediction:
├─ In 3 seconds: Dragon will be ~4 tiles away
├─ In 5 seconds: Dragon will reach you (0-2 tiles)
├─ Attack incoming: Expected in 4 seconds

Action:
├─ Move away to prepare healing
├─ Pre-cast mana shield
├─ Ready greater health potion
└─ Wait for optimal counter-attack moment
```

### Wave Attack Detection 🌊

TargetBot predicts **group attacks** before they happen:

```
WAVE DETECTION: Monitors group creature behavior

Trigger Conditions:
├─ 3+ creatures approaching simultaneously
├─ Front-arc attack pattern (180° forward)
├─ Closing distance quickly
├─ Coordinated movement

When Detected:
├─ Movement Coordinator becomes VERY reactive
├─ Increases kiting distance
├─ Prioritizes movement over combat
├─ Notifies HealBot for heightened alert
└─ Result: Avoid taking group damage
```

**Example Wave Attack:**
```
Situation: 5 Dragons approach from corridor

Detection:
├─ Dragon 1 @ 3 tiles, Chase pattern
├─ Dragon 2 @ 4 tiles, Chase pattern
├─ Dragon 3 @ 5 tiles, Chase pattern
├─ Dragon 4 @ 6 tiles, Chase pattern
├─ Dragon 5 @ 7 tiles, Chase pattern
└─ WAVE DETECTED! (5 creatures, coordinated)

Response:
├─ Increase movement frequency 2x
├─ Widen position safety margin to 10 tiles
├─ Avoid being surrounded
└─ Switch to defensive combat
```

---

## 🚶 Movement Coordination

TargetBot uses **intent-based voting** to decide movements smoothly (no erratic running).

### Movement Coordinator Algorithm

```
┌─────────────────────────────────────────────────────────┐
│      MOVEMENT COORDINATOR - INTENT VOTING               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  INPUT: Multiple movement intents                       │
│  ├─ CaveBot: "Go to waypoint (100, 200)"               │
│  ├─ TargetBot Offense: "Approach target"               │
│  ├─ TargetBot Defense: "Maintain 5 tiles distance"     │
│  └─ TargetBot Safety: "Avoid getting cornered"         │
│                                                         │
│  VOTING PROCESS:                                        │
│  ├─ Each intent has weight (1-10)                       │
│  ├─ Weights change based on situation                   │
│  ├─ Safety intents have high weight when threatened     │
│  ├─ Navigation intent dominates when safe               │
│  └─ Calculate consensus movement                        │
│                                                         │
│  OUTPUT: One smooth movement decision                   │
│  └─ Prevents conflicting movements                      │
│  └─ Smooth trajectory instead of oscillation            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Dynamic Weight Adjustment

```
SITUATION: Safe (no nearby threats)
├─ CaveBot navigation:   Weight = 10 (HIGH)
├─ Combat movement:      Weight = 2  (LOW)
├─ Safety margin:        Weight = 1  (MINIMAL)
└─ RESULT: Follow waypoints normally

SITUATION: Single creature chasing (distance > 5 tiles)
├─ CaveBot navigation:   Weight = 6  (MEDIUM)
├─ Combat movement:      Weight = 7  (HIGH)
├─ Safety margin:        Weight = 3  (MODERATE)
└─ RESULT: Balanced hunting & navigation

SITUATION: Group wave attack (< 4 tiles)
├─ CaveBot navigation:   Weight = 1  (MINIMAL)
├─ Combat movement:      Weight = 2  (LOW)
├─ Safety margin:        Weight = 10 (CRITICAL!)
└─ RESULT: ESCAPE MODE - maximize distance

SITUATION: Multiple solo threats
├─ CaveBot navigation:   Weight = 2  (LOW)
├─ Combat movement:      Weight = 8  (HIGH)
├─ Safety margin:        Weight = 5  (MEDIUM)
└─ RESULT: Focused combat, stay mobile
```

### Tile Evaluation (5-Factor Scoring)

When deciding where to move, each potential tile is scored:

```
TILE SCORE = Safety + Offense + Navigation + Escape + Pressure

1. SAFETY (distance from threats)
   └─ Score × distance from nearest creature
   └─ Farther is safer

2. OFFENSE (ability to attack)
   └─ Score if in spell/melee range
   └─ Penalty if out of range

3. NAVIGATION (path toward waypoint)
   └─ Bonus if moving toward destination
   └─ Penalty if moving away

4. ESCAPE (exit route availability)
   └─ Bonus if tile has clear paths (escape routes)
   └─ Penalty if trapped or cornered

5. PRESSURE (how much incoming damage predicted)
   └─ High pressure = prioritize distance
   └─ Low pressure = prioritize offense

Example Tile Evaluation:
┌──────────────────────────────────┐
│   (100, 200) - NORTH TILE        │
├──────────────────────────────────┤
│ Safety:      +20 (3 tiles away)   │
│ Offense:     +10 (in spell range) │
│ Navigation:  +15 (toward waypoint)│
│ Escape:      +8 (2 exit routes)   │
│ Pressure:    +5 (low incoming)    │
├──────────────────────────────────┤
│ TOTAL SCORE: 58/100             │
│ STATUS: Good move ✓              │
└──────────────────────────────────┘
```

### Anti-Oscillation

TargetBot **prevents erratic movement** (bouncing back-and-forth):

```
OSCILLATION PREVENTION:
├─ Track movement history (last 3 moves)
├─ Detect back-and-forth patterns
├─ If detected: Stick with current move longer
├─ Threshold: Min 2-3 seconds per position
└─ Result: Smooth, predictable movement
```

---

## ⚡ Spell Optimization

TargetBot finds the **optimal position** for area-damage spells before casting.

### AoE Position Optimizer

```
GOAL: Maximize creature hits with area spell

PROCESS:
1. Get configured area spells (e.g., "Exori Con")
2. Get nearby creatures in combat
3. For each potential position in nearby tiles:
   a. Calculate damage coverage
   b. Count creatures in AoE radius
   c. Check if position is walkable
4. Pick position with most creature hits
5. Move there (if needed) and cast spell
```

### Coverage Calculation

```
AREA SPELL: "Exori Con" (5x5 tile area)
CREATURES:  Dragon @ (100, 200)
            Dragon @ (102, 201)
            Demon @ (105, 205) [too far]

Position Evaluation:
┌──────────────────────────────────────┐
│ If you stand @ (102, 200):           │
│ ├─ Dragon 1 @ (100,200): 2 tiles IN │
│ ├─ Dragon 2 @ (102,201): ADJACENT   │
│ └─ Demon @ (105,205): 6 tiles OUT   │
│ → 2 creatures hit ⭐⭐              │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ If you stand @ (101, 201):           │
│ ├─ Dragon 1 @ (100,200): ADJACENT   │
│ ├─ Dragon 2 @ (102,201): ADJACENT   │
│ └─ Demon @ (105,205): 6 tiles OUT   │
│ → 2 creatures hit ⭐⭐ (same)        │
│ But better centering! (more future) │
└──────────────────────────────────────┘
```

### Spell Selection

TargetBot automatically chooses spells based on situation:

```
Decision Tree:
├─ IF (7+ creatures) AND (AoE spell available)
│  └─ Use AoE spell (group damage)
│
├─ ELSE IF (target isolated) AND (high damage spell)
│  └─ Use single-target high damage
│
├─ ELSE IF (health < 40%) AND (support spell available)
│  └─ Use support spell (shield/haste)
│
└─ ELSE
   └─ Use default configured spell
```

---

## ⚙️ Configuration

### Creature Configuration File Format

Create a file in `targetbot_configs/MyMonsters.json`:

```json
{
  "creatures": [
    {
      "name": "Dragon",
      "patterns": ["Dragon", "Wyrm"],
      "spells": [
        {
          "name": "exori",
          "mana": 25,
          "damage": 240,
          "minDistance": 1,
          "maxDistance": 5
        },
        {
          "name": "exori con",
          "mana": 45,
          "damage": 320,
          "minDistance": 2,
          "maxDistance": 7,
          "isAoE": true
        }
      ],
      "runes": [
        {
          "name": "Sudden Death",
          "slot": 8,
          "damage": 650,
          "minDistance": 1,
          "maxDistance": 5
        }
      ],
      "supportSpells": [
        {
          "name": "utani hur",
          "triggers": "when_moving",
          "mana": 60
        }
      ]
    }
  ]
}
```

### Configuration UI

```
┌─────────────────────────────────────┐
│ TARGET BOT - CREATURE SETUP         │
├─────────────────────────────────────┤
│                                     │
│ Monster: Dragon                     │
│ Priority: [ ] High [ ] Medium [✓]   │
│                                     │
│ Patterns: Dragon, !Green Dragon     │
│                                     │
│ Spells:                             │
│ ├─ [✓] exori @ 25 mana             │
│ ├─ [✓] exori con @ 45 mana (AoE)   │
│ └─ [ ] exori gran @ 100 mana        │
│                                     │
│ Runes:                              │
│ ├─ [✓] Sudden Death (slot 8)        │
│ └─ [ ] Fireball Rune (slot 9)       │
│                                     │
│ Support:                            │
│ ├─ [✓] Haste (when moving)          │
│ └─ [ ] Shield (when below 50%)      │
│                                     │
│ [ DELETE ] [ ADD ] [ SAVE ]          │
│                                     │
└─────────────────────────────────────┘
```

---

## 🔮 Advanced Topics

### Custom Behavior Profiles

You can create custom behavior configs:

```lua
-- In targetbot config:
monsterBehaviors = {
  ["Dragon"] = {
    pattern = "CHASE",
    confidence = 0.95,
    dangerLevel = 10,
    recommendedDistance = 5,
    attackTiming = "when_approaching"
  }
}
```

### Spell Combo Sequences

```lua
-- Define attack combos:
spellCombos = {
  ["AoE_BURST"] = {
    -- Cast AoE to group, then single target strongest
    { spell = "exori con", wait = 500 },
    { spell = "exori", wait = 200 },
    { spell = "exori", wait = 200 }
  },

  ["SINGLE_TARGET"] = {
    -- Focus one target completely
    { spell = "exori gran", wait = 1000 },
    { spell = "exori gran", wait = 1000 }
  }
}
```

### Dynamic Danger Assessment

```lua
-- TargetBot calculates danger = sum of:
dangerLevel = function(creatures)
  local danger = 0
  danger += creatureCount * 5        -- More = more danger
  danger += avgMonsterDamage         -- Harder hitters
  danger -= avgPlayerDefense         -- Less defense = more danger
  return math.min(danger, 100)       -- Capped at 100
end
```

---

## 🆘 Troubleshooting

> [!WARNING]
> **TargetBot not attacking?**
> 1. Check if monsters are in range (spell maxDistance)
> 2. Verify mana is sufficient (required for spell)
> 3. Check if target is on cooldown (wait timer)
> 4. Enable debug: `targetbot.debug = true`

> [!TIP]
> **Erratic movement / bouncing around?**
> 1. Reduce number of active creatures (weight down some)
> 2. Increase safety distance threshold
> 3. Check for conflicting CaveBot waypoints
> 4. Disable AoE optimization temporarily

> [!WARNING]
> **Missing creatures / wrong targets?**
> 1. Verify creature names match exactly
> 2. Check patterns are correct (`Dragon` not `Drago`)
> 3. Use wildcard patterns: `Dragon*` for Dragonlord, etc.
> 4. Check creature ID range: `#100-#150`

> [!TIP]
> **Spell not being used?**
> 1. Check mana cost (enough mana available?)
> 2. Verify spell name capitalization matches
> 3. Check distance constraints (min/max range)
> 4. Ensure creature is in "active target" range

---

## 📚 See Also

- [CaveBot Guide](CAVEBOT.md) - Navigation system
- [HealBot Guide](HEALBOT.md) - Survival system
- [Hunt Analyzer](SMARTHUNT.md) - Combat analytics
- [Main README](README.md) - Overview

---

<div align="center">

**TargetBot v3.0** - Intelligent Combat AI 🎯

*Powered by nExBot - Adaptive Targeting & Behavior Learning*

</div>
