# ❤️ HealBot Documentation

**Smart healing automation for survival**

---

## 📖 Overview

HealBot automatically heals your character using spells and potions based on your health and mana levels. It supports:
- Health and mana threshold healing
- Party healing
- Emergency healing triggers
- Conditional spell casting

---

## 🚀 Quick Start

### Basic Setup

1. **Open HealBot Panel**
   - Click HealBot tab in main window

2. **Add Healing Rules**
   - Click `Add` button
   - Set health threshold (e.g., 70%)
   - Select spell or potion
   - Save rule

3. **Enable HealBot**
   - Toggle the ON/OFF switch

---

## 💊 Healing Types

### Instant Healing

<details>
<summary><b>🔴 Health Potions</b></summary>

**Best For:** Emergency healing, high damage situations

| Potion | Item ID | Heal Amount |
|--------|---------|-------------|
| Health Potion | 7618 | ~100-150 |
| Strong Health | 7588 | ~200-300 |
| Great Health | 7591 | ~400-600 |
| Ultimate Health | 8473 | ~600-900 |
| Supreme Health | 23375 | ~800-1200 |

> [!TIP]
> Potions have no cooldown - use for burst healing!

</details>

<details>
<summary><b>🔵 Mana Potions</b></summary>

**Best For:** Sustaining mana for spells

| Potion | Item ID | Mana Amount |
|--------|---------|-------------|
| Mana Potion | 268 | ~75-125 |
| Strong Mana | 237 | ~100-200 |
| Great Mana | 238 | ~150-300 |
| Ultimate Mana | 23374 | ~400-700 |

</details>

---

### Spell Healing

<details>
<summary><b>✨ Single Target Spells</b></summary>

| Spell | Words | Mana | Cooldown |
|-------|-------|------|----------|
| Light Healing | exura | 25 | 1s |
| Intense Healing | exura gran | 70 | 1s |
| Ultimate Healing | exura vita | 160 | 1s |
| Divine Healing | exura san | 160 | 1s |

</details>

<details>
<summary><b>👥 Party Healing</b></summary>

| Spell | Words | Area |
|-------|-------|------|
| Mass Healing | exura gran mas res | 3x3 |
| Heal Friend | exura sio "NAME" | Single target |

> [!IMPORTANT]
> Party healing only works with shared experience enabled.

</details>

---

## ⚙️ Rule Configuration

### Priority System

Rules are executed **top to bottom**. Higher rules have priority.

```
Priority 1: HP < 30% → Ultimate Health Potion (emergency)
Priority 2: HP < 50% → exura vita (spell heal)
Priority 3: HP < 80% → exura gran (maintenance)
Priority 4: MP < 50% → Great Mana Potion
```

### Condition Options

| Condition | Description | Example |
|-----------|-------------|---------|
| **HP%** | Health percentage | `< 70` |
| **MP%** | Mana percentage | `< 50` |
| **HP Amount** | Absolute health | `< 500` |
| **MP Amount** | Absolute mana | `< 200` |
| **Monsters** | Monster count nearby | `>= 2` |
| **Status** | Has condition | `poisoned`, `burning` |

---

## 🛡️ Safety Features

### Emergency Healing

> [!WARNING]
> Always set up an emergency heal at very low HP!

**Recommended Setup:**
```
HP < 25%: Supreme Health Potion (no cooldown)
HP < 25%: Exura Vita (if potion on CD)
```

### Cooldown Management

The system tracks:
- Potion exhaustion (1 second)
- Spell cooldowns (varies by spell)
- Group cooldowns (healing, attack, support)

> [!NOTE]
> HealBot won't try to cast if a spell is on cooldown.

---

## 📝 Rule Examples

<details>
<summary><b>Knight Build (High HP, Low Mana)</b></summary>

```
1. HP < 20% → Supreme Health Potion
2. HP < 40% → Great Health Potion
3. HP < 70% → Strong Health Potion
4. HP < 90% → Exura Ico
5. MP < 30% → Mana Potion
```

</details>

<details>
<summary><b>Mage Build (Balanced)</b></summary>

```
1. HP < 25% → Ultimate Health Potion
2. HP < 50% → Exura Vita
3. HP < 80% → Exura Gran
4. MP < 40% → Great Mana Potion
5. MP < 80% → Strong Mana Potion
```

</details>

<details>
<summary><b>Paladin Build (Hybrid)</b></summary>

```
1. HP < 30% → Supreme Health Potion
2. HP < 50% → Exura Gran San
3. HP < 80% → Exura San
4. MP < 30% → Great Spirit Potion
5. MP < 60% → Strong Mana Potion
```

</details>

---

## ⚠️ Common Issues

<details>
<summary><b>Healing not working</b></summary>

**Check:**
1. Is HealBot enabled?
2. Do you have supplies in containers?
3. Is the spell on cooldown?
4. Is mana sufficient for spell?

</details>

<details>
<summary><b>Healing too slow</b></summary>

**Solution:**
1. Reduce delay between heals
2. Add backup healing rules
3. Use potions for emergencies (no CD)

</details>

<details>
<summary><b>Wasting potions</b></summary>

**Cause:** Threshold too high

**Solution:**
1. Lower HP% trigger
2. Use spells for high HP maintenance
3. Add mana condition to potion rules

</details>

---

## 💡 Pro Tips

> [!TIP]
> **Efficiency:** Combine spell and potion heals for continuous healing.

> [!TIP]
> **Safety:** Set emergency heal at HP < 25% with Supreme Health Potion.

> [!TIP]
> **Mana Management:** Keep one rule for low mana emergencies (< 20%).

> [!TIP]
> **Party Hunting:** Use Mass Healing when 3+ party members are nearby and damaged.

---

## 📊 Analytics Integration

HealBot tracks detailed usage statistics that are displayed in SmartHunt Analytics:

### Tracked Metrics
- **Individual spell counts** - Each healing spell with exact usage count
- **Individual potion counts** - Each potion type with usage count
- **Mana waste** - Mana spent on spells when HP was already high
- **Potion waste** - Potions used when HP was above trigger threshold

### API Access
```lua
-- Get HealBot analytics
local data = HealBot.getAnalytics()
-- data.spells = { ["exura gran"] = 1543, ["exura vita"] = 234 }
-- data.potions = { [23375] = 500, [7642] = 120 }
-- data.spellCasts = 1777
-- data.potionUses = 620
-- data.manaWaste = 12500
-- data.potionWaste = 15

-- Reset analytics (usually done by SmartHunt on session start)
HealBot.resetAnalytics()
```

---

## 🍄 Auto Eat Food

The bot includes automatic food eating to maintain regeneration.

### How It Works

- **Trigger on Enable:** Immediately eats food when macro is enabled
- **Eat Until Full:** Continues eating with 200ms delays until "You are full"
- **Container search:** Searches all open containers for food
- **Multiple food types:** Supports mushrooms, ham, meat, bread, fruits

### Supported Foods

| Food | Item ID |
|------|---------|
| Brown Mushroom | 3725 |
| Fire Mushroom | 3731 |
| White Mushroom | 3723 |
| Ham | 3582 |
| Meat | 3577 |
| Cheese | 3585 |
| Bread | 3600 |
| Fish | 3578 |

> [!IMPORTANT]
> Make sure your food container is **open** for the bot to find food!
