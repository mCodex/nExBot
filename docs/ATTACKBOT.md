# ⚔️ AttackBot Documentation

**Automated attack spell and rune casting**

---

## 📖 Overview

AttackBot automates your offensive abilities:
- Cast attack spells and runes
- Optimized AoE decisions based on monster count
- Combo rotations for maximum DPS
- Safety checks to prevent waste

---

## 🚀 Quick Start

### Basic Setup

1. **Open AttackBot Panel**
   - Click AttackBot tab in main window

2. **Add Attack Rules**
   - Click `Add` button
   - Select spell or rune
   - Set monster count condition
   - Configure priority

3. **Enable AttackBot**
   - Toggle the ON/OFF switch

---

## 🔥 Attack Types

### Single Target

<details>
<summary><b>⚡ Attack Spells</b></summary>

| Class | Spell | Words | CD |
|-------|-------|-------|-----|
| Knight | Fierce Berserk | exori gran | 6s |
| Knight | Berserk | exori | 4s |
| Paladin | Divine Caldera | exevo mas san | 4s |
| Mage | Wand/Rod Attack | - | 2s |

</details>

<details>
<summary><b>🎯 Runes</b></summary>

| Rune | Item ID | Damage Type |
|------|---------|-------------|
| Sudden Death | 3155 | Death |
| Heavy Magic Missile | 3198 | Physical |
| Fireball | 3189 | Fire |
| Icicle | 3158 | Ice |

</details>

---

### Area of Effect (AoE)

<details>
<summary><b>💥 Area Spells</b></summary>

| Class | Spell | Words | Area |
|-------|-------|-------|------|
| Knight | Groundshaker | exori mas | 5x5 |
| Knight | Annihilation | exori gran ico | 3x3 |
| Paladin | Mas San | exori san | 3x3 |
| Mage | Hell's Core | exevo gran mas flam | 5x5 |
| Mage | Rage of the Skies | exevo gran mas vis | 5x5 |

</details>

<details>
<summary><b>🎯 Area Runes</b></summary>

| Rune | Item ID | Area |
|------|---------|------|
| Great Fireball | 3191 | 3x3 |
| Avalanche | 3161 | 3x3 |
| Thunderstorm | 3202 | 3x3 |
| Stone Shower | 3175 | 3x3 |

</details>

---

## ⚙️ Optimized Algorithm

### Entry Caching System

> [!NOTE]
> AttackBot now caches attack entries for better performance!

**How it works:**
```lua
-- Entries are cached and only rebuilt when config changes
cachedAttackEntries = nil  -- Reset on config change

local function getAttackEntries()
  if cachedAttackEntries then
    return cachedAttackEntries
  end
  -- Build entries only once
  cachedAttackEntries = buildEntries()
  return cachedAttackEntries
end
```

### Monster Count Caching

```lua
-- Monster counts cached with 100ms TTL
monsterCountCache = {
  count = 0,
  timestamp = 0,
  TTL = 100  -- milliseconds
}
```

> [!TIP]
> Caching reduces CPU usage by ~70% in intense combat!

---

### Priority Evaluation

<details>
<summary><b>📊 Attack Priority Flow</b></summary>

```
1. Check if attack entry is enabled
2. Check monster count (from cache)
3. Check spell/rune cooldown
4. Check mana requirement
5. Check safety conditions (lazy eval)
6. Execute attack!
```

> [!IMPORTANT]
> Safety checks are evaluated LAST (lazy evaluation) for efficiency.

</details>

---

## 🛡️ Safety Features

### Lazy Safety Evaluation

> [!NOTE]
> Safety is only checked when an attack would actually fire!

**Old method (slow):**
```lua
for each entry do
  checkSafety()     -- Always runs (expensive)
  checkConditions()
  attack()
end
```

**New method (fast):**
```lua
for each entry do
  checkConditions()  -- Fast checks first
  if shouldAttack then
    checkSafety()    -- Only if needed
    attack()
  end
end
```

### Monster Filters

| Filter | Description | Use Case |
|--------|-------------|----------|
| **Min Count** | Minimum monsters for AoE | Don't waste on 1 monster |
| **Max Count** | Maximum monsters | Don't spam in crowds |
| **Distance** | Target within range | Ranged attacks |
| **Health%** | Target health | Finish low HP first |

---

## 📝 Attack Entry Examples

<details>
<summary><b>Knight AoE Build</b></summary>

```
1. Monsters >= 4: Groundshaker (exori mas)
2. Monsters >= 2: Fierce Berserk (exori gran)
3. Monsters >= 1: Berserk (exori)
4. Always: Front Kick (exori ico)
```

</details>

<details>
<summary><b>Mage Hunt Build</b></summary>

```
1. Monsters >= 5: Hell's Core (mas flam)
2. Monsters >= 3: Great Fireball rune
3. Monsters >= 1: Wand attack
4. Target HP < 20%: Sudden Death (finish)
```

</details>

<details>
<summary><b>Paladin Team Hunt</b></summary>

```
1. Monsters >= 3: Divine Caldera
2. Monsters >= 1: Ethereal Spear
3. Target HP < 30%: Sudden Death
```

</details>

---

## ⚠️ Common Issues

<details>
<summary><b>Attack not firing</b></summary>

**Check:**
1. Is AttackBot enabled?
2. Is there a valid target?
3. Is the spell on cooldown?
4. Is mana sufficient?
5. Are conditions met (monster count)?

</details>

<details>
<summary><b>AoE not triggering</b></summary>

**Cause:** Monster count not reached

**Solution:**
1. Lower the minimum monster count
2. Check monster detection range
3. Verify monsters are attackable

</details>

<details>
<summary><b>Wasting runes on single target</b></summary>

**Solution:**
1. Add monster count condition `>= 2`
2. Use single target for low counts
3. Separate AoE rules from single target

</details>

---

## 💡 Pro Tips

> [!TIP]
> **Priority:** Put emergency spells at top, fillers at bottom.

> [!TIP]
> **Efficiency:** Set AoE spells to trigger at 3+ monsters for better value.

> [!TIP]
> **Mana:** Add mana checks to prevent going OOM during fights.

> [!TIP]
> **Combo:** Stagger cooldowns - use fast spells between slow ones!

---

## 📊 Analytics Integration

AttackBot tracks detailed usage statistics that are displayed in Hunt Analyzer:

### Tracked Metrics
- **Individual spell counts** - Each attack spell with exact usage count
- **Individual rune counts** - Each rune type with usage count
- **Empowerment buffs** - Times utito tempo/utamo vita were cast
- **Total attacks** - Combined count of all attack actions

### API Access
```lua
-- Get AttackBot analytics
local data = AttackBot.getAnalytics()
-- data.spells = { ["exori gran ico"] = 2000, ["exori hur"] = 500 }
-- data.runes = { [3155] = 150 }  -- Sudden Death Rune
-- data.empowerments = 45
-- data.totalAttacks = 2650

-- Reset analytics (usually done by Hunt Analyzer on session start)
AttackBot.resetAnalytics()
```

### Hunt Analyzer Integration
AttackBot analytics are automatically pulled by Hunt Analyzer to provide:
- Attacks per kill efficiency analysis
- Spell vs rune usage balance recommendations
- Empowerment uptime suggestions
