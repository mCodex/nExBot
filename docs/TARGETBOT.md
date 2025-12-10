# 🎯 TargetBot Documentation v1.0

**Intelligent creature targeting and combat automation**

---

## 📖 Overview

TargetBot is the combat brain of nExBot. It automatically:
- Selects the best target based on weighted priority scoring
- Manages positioning during combat with coordinated movement
- Coordinates with CaveBot for luring
- Avoids wave attacks from monsters with prediction
- Optimizes position for AoE spells and runes
- Uses behavior analysis to predict monster attacks
- **Dynamic reactivity** based on monster count (more reactive when surrounded)
- Prevents erratic movement with adaptive confidence thresholds

---

## ⚙️ Configuration Options

### Basic Settings

| Setting | Description | Default |
|---------|-------------|---------|
| **Priority** | Target selection priority (1-10) | 5 |
| **Danger** | Danger level for this creature | 0 |
| **Max Distance** | Maximum targeting range | 10 |

### Movement Options

<details>
<summary><b>🏃 Chase</b></summary>

Walks towards the target until adjacent (1 tile away).

> [!TIP]
> Best for melee characters (Knights)

**When to use:**
- Melee combat
- When you need to be adjacent to attack
- When using melee spells like `exori`

</details>

<details>
<summary><b>📏 Keep Distance</b></summary>

Maintains a specific distance from the target.

**Settings:**
- `Keep Distance Range`: The distance to maintain (1-10 tiles)

> [!TIP]
> Best for ranged characters (Paladins, Mages)

**When to use:**
- Ranged combat with bows/crossbows
- Mage hunting with runes
- Avoiding melee damage from monsters

</details>

<details>
<summary><b>⚓ Anchor</b></summary>

Stays within a radius of your initial position.

**Settings:**
- `Anchor Range`: Maximum distance from anchor point (1-10 tiles)

> [!WARNING]
> If you move too far, the anchor resets to your new position.

**When to use:**
- Box hunting (staying in one spot)
- Preventing the bot from running too far
- Defending a specific area

</details>

---

## 🔄 Combat Features

### 🧲 Pull System

Pauses waypoint walking when you have fewer monsters than desired.

**Settings:**
- `Pull Range`: Detection radius (1-10 tiles)
- `Pull Min`: Minimum monsters needed
- `Pull Shape`: Detection shape

**Shapes:**
| Shape | Description | Best For |
|-------|-------------|----------|
| ⬛ Square | Box pattern | General use |
| 🔵 Circle | Round pattern | AoE spells |
| 💎 Diamond | Diagonal pattern | Melee combat |
| ✚ Cross | Cardinal only | Beam spells |

> [!IMPORTANT]
> Pull **pauses** CaveBot walking - it won't run to the next waypoint and lose your respawn!

**Safeguard:** Pull only activates when there are monsters on screen!
```lua
-- First checks if ANY monsters are visible (range 7)
local screenMonsters = getMonsters(7)
if screenMonsters == 0 then
  -- No monsters? Don't pause, let CaveBot walk!
  TargetBot.pullActive = false
else
  -- Monsters exist - check pull range and minimum
  if nearbyMonsters < pullMin then
    TargetBot.pullActive = true  -- Pause waypoints
  end
end
```

```
When pullMin = 3 and you have 2 monsters:
1. CaveBot PAUSES waypoint walking
2. You stay and fight current monsters
3. Only continues when monsters >= 3 OR all dead
```

### 🌊 Wave Attack Avoidance

Automatically dodges monster wave attacks using pattern prediction.

> [!TIP]
> Works best against monsters with directional attacks like:
> - Dragons (fire wave)
> - Demons (energy wave)
> - Hydras (wave attack)

**How it works:**
1. Monster analyzer checks facing direction and attack patterns
2. Calculates danger zones using front arc detection (90° cone)
3. Scores safe tiles based on:
   - Distance from danger zones
   - Path walkability
   - Anchor constraints
   - AoE spell potential (via SpellOptimizer)
4. MovementCoordinator evaluates with 0.50 confidence threshold
5. Uses anti-oscillation to prevent jittering

**Features:**
- Attack timing prediction based on monster cooldowns
- Confidence scoring for danger assessment
- Integration with SpellOptimizer for retreat positions

### 🔄 Reposition

Moves to tiles with better tactical advantage using multi-factor scoring.

**Scoring factors:**
| Factor | Points | Description |
|--------|--------|-------------|
| Escape routes | +10 each | Walkable adjacent tiles |
| Danger zones | -15 each | In front of monster |
| Target distance | +20/+10 | Adjacent/Close range |
| Movement cost | -3 each | Tiles to move |
| Cardinal direction | +5 | Easier pathing |
| AoE potential | +25 | Good spell position (via SpellOptimizer) |
| Monster concentration | +15 | Multiple targets in range |

**Features:**
- Dynamic thresholds based on monster count
- SpellOptimizer integration for AoE considerations
- LRU creature config cache (50 entries max)
- Pure function scoring via TargetCore
- More reactive when surrounded, conservative when safe

---

## 🎮 Priority System

TargetBot uses a coordinated movement system with **dynamic confidence thresholds** that scale based on monster count:

```
╔═══════════════════════════════════════════════════════════════════════════╗
║         MOVEMENT COORDINATOR - Dynamic Scaling                            ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  MONSTER COUNT SCALING:                                                   ║
║  ├─ 1-2 monsters: Conservative (scale = 1.0)                             ║
║  ├─ 3-4 monsters: Moderate (scale = 0.85)                                ║
║  ├─ 5-6 monsters: Reactive (scale = 0.70)                                ║
║  └─ 7+ monsters:  Very Reactive (scale = 0.50)                           ║
║                                                                           ║
║  Intent Type        Base → With 7+ Monsters    Purpose                    ║
║  ────────────────────────────────────────────────────────────────────────║
║  EMERGENCY          0.45 → 0.23               Critical danger evasion     ║
║  WAVE_AVOID         0.70 → 0.35               Predicted attack dodge      ║
║  FINISH_KILL        0.65 → 0.33               Low-health target chase     ║
║  SPELL_POSITION     0.80 → 0.56               Optimal AoE positioning     ║
║  CHASE              0.60 → 0.51               Close distance to target    ║
║  KEEP_DISTANCE      0.65 → 0.46               Maintain range              ║
║                                                                           ║
║  Anti-Oscillation: 3 moves in 2.5s = movement blocked                     ║
║  Dynamic Hysteresis: Less sticky when many monsters nearby                ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

> [!NOTE]
> The system automatically becomes more reactive when surrounded by many monsters, and more conservative when there are few. This prevents standing still when taking heavy damage, while avoiding erratic movement in safer situations.

---

## 🧠 Behavior Modules

### Monster Behavior Analysis

Tracks monster behavior patterns to predict attacks:

```lua
-- Automatic behavior recording
MonsterBehavior.recordBehavior(creature)

-- Attack prediction with confidence
local prediction = MonsterBehavior.predictAttack(creature)
-- Returns: { willAttack = true, confidence = 0.85, timeToAttack = 1.2 }
```

**Tracked Patterns:**
| Pattern | Description |
|---------|-------------|
| **Movement** | static, chase, kite, erratic |
| **Attack Timing** | Wave cooldown estimation |
| **Direction** | Facing direction history |
| **Distance Preference** | Melee vs ranged behavior |

### SpellOptimizer - Position Optimization

Finds optimal positions for AoE spells and runes:

```lua
-- Find best position for spell type
local bestPos = SpellOptimizer.findBestPosition("wave", monsters, playerPos)

-- Score a specific position
local score = SpellOptimizer.scorePosition(pos, "greatFireball", monsters)
```

**AoE Patterns:**
| Type | Shape | Description |
|------|-------|-------------|
| wave | 3-wide cone | Dragon breath, exori gran |
| beam | 1-wide line | Energy beam |
| circle | radius=3 | Great fireball, thunderstorm |
| square | 3x3 | UE spells |

### MovementCoordinator - Unified Movement

Prevents conflicting movement decisions with confidence voting:

```lua
-- Register movement intent
MovementCoordinator.registerIntent("wave_avoid", safeTile, 0.85, "Dragon wave incoming")
MovementCoordinator.registerIntent("chase", targetPos, 0.60, "Chase low target")

-- Execute best intent
MovementCoordinator.tick()  -- Evaluates all intents, moves to highest confidence
```

**Anti-Oscillation Features:**
- Consecutive move tracking (max 3 to same tile)
- Position stickiness window (500ms)
- Cooldown between movement decisions

---

## 📋 Creature Configuration

### Adding Creatures

1. Open TargetBot panel
2. Click **Add**
3. Enter creature name (or `*` for all)
4. Configure settings
5. Click **Save**

### Exclusion Patterns

Use `!` prefix to exclude specific creatures:

```
*              → Attack all monsters
*, !Dragon     → Attack all except Dragons
*, !Dragon, !Demon → Exclude Dragons and Demons
Dragon, Dragon Lord → Only attack Dragons
```

---

## 💡 Tips & Tricks

<details>
<summary><b>Best settings for Knights</b></summary>

- ✅ Chase: ON
- ✅ Face Monster: ON
- ✅ Reposition: ON (Amount: 5)
- ❌ Keep Distance: OFF
- ✅ Avoid Attacks: ON

</details>

<details>
<summary><b>Best settings for Paladins</b></summary>

- ❌ Chase: OFF
- ✅ Keep Distance: ON (Range: 4-5)
- ✅ Anchor: ON (Range: 5)
- ✅ Pull System: ON
- ✅ Avoid Attacks: ON

</details>

<details>
<summary><b>Best settings for Mages</b></summary>

- ❌ Chase: OFF
- ✅ Keep Distance: ON (Range: 3-4)
- ✅ Anchor: ON (Range: 4)
- ✅ Avoid Attacks: ON
- ✅ Reposition: ON

</details>

---

## ⚠️ Common Issues

<details>
<summary><b>Bot keeps running away from monsters</b></summary>

**Cause:** Pull System or Dynamic Lure is triggering

**Solution:** 
1. Increase `Pull Min` value
2. Or disable Pull System for this hunt
3. Check `killUnder` threshold in Extras

</details>

<details>
<summary><b>Not attacking the right monster</b></summary>

**Cause:** Priority settings

**Solution:**
1. Increase priority for desired creatures
2. Use creature name instead of `*`
3. Check exclusion patterns

</details>

<details>
<summary><b>Keeps switching targets</b></summary>

**Cause:** Multiple creatures with same priority

**Solution:**
1. Give different priorities to different creatures
2. Enable "Don't Loot" for low-priority creatures

</details>
