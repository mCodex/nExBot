# 🎯 TargetBot Documentation

**Smart creature targeting and combat automation**

---

## 📖 Overview

TargetBot is the combat brain of nExBot. It automatically:
- Selects the best target based on priority
- Manages positioning during combat
- Coordinates with CaveBot for luring
- Avoids wave attacks from monsters

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

## 🔄 Smart Features

### 🧲 Smart Pull

Pauses waypoint walking when you have fewer monsters than desired.

**Settings:**
- `Smart Pull Range`: Detection radius (1-10 tiles)
- `Smart Pull Min`: Minimum monsters needed
- `Smart Pull Shape`: Detection shape

**Shapes:**
| Shape | Description | Best For |
|-------|-------------|----------|
| ⬛ Square | Box pattern | General use |
| 🔵 Circle | Round pattern | AoE spells |
| 💎 Diamond | Diagonal pattern | Melee combat |
| ✚ Cross | Cardinal only | Beam spells |

> [!IMPORTANT]
> Smart Pull **pauses** CaveBot walking - it won't run to the next waypoint and lose your respawn!

**Safeguard:** Smart Pull only activates when there are monsters on screen!
```lua
-- First checks if ANY monsters are visible (range 7)
local screenMonsters = getMonsters(7)
if screenMonsters == 0 then
  -- No monsters? Don't pause, let CaveBot walk!
  TargetBot.smartPullActive = false
else
  -- Monsters exist - check pull range and minimum
  if nearbyMonsters < pullMin then
    TargetBot.smartPullActive = true  -- Pause waypoints
  end
end
```

```
When smartPullMin = 3 and you have 2 monsters:
1. CaveBot PAUSES waypoint walking
2. You stay and fight current monsters
3. Only continues when monsters >= 3 OR all dead
```

### 🌊 Wave Attack Avoidance

Automatically dodges monster wave attacks.

> [!TIP]
> Works best against monsters with directional attacks like:
> - Dragons (fire wave)
> - Demons (energy wave)
> - Hydras (wave attack)

**How it works:**
1. Detects monster facing direction
2. Calculates "danger zones" in front of monsters
3. Moves to safe tile when in danger zone
4. Uses 300ms cooldown to prevent jittering

### 🔄 Reposition

Moves to tiles with better tactical advantage.

**Scoring factors:**
| Factor | Points | Description |
|--------|--------|-------------|
| Escape routes | +10 each | Walkable adjacent tiles |
| Danger zones | -15 each | In front of monster |
| Target distance | +20/+10 | Adjacent/Close range |
| Movement cost | -3 each | Tiles to move |
| Cardinal direction | +5 | Easier pathing |

---

## 🎮 Priority System

TargetBot uses a priority-based movement system:

```
┌─────────────────────────────────────────┐
│  1. SAFETY     - Wave attack avoidance  │
│  2. SURVIVAL   - Kill low-health targets│
│  3. DISTANCE   - Keep distance mode     │
│  4. TACTICAL   - Reposition for safety  │
│  5. MELEE      - Chase mode             │
│  6. FACING     - Face monster           │
└─────────────────────────────────────────┘
```

> [!NOTE]
> Higher priority actions always take precedence. If you're in a wave attack zone, you'll dodge even if "chase" is enabled.

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
- ✅ Smart Pull: ON
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

**Cause:** Smart Pull or Dynamic Lure is triggering

**Solution:** 
1. Increase `Smart Pull Min` value
2. Or disable Smart Pull for this hunt
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
