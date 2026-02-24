# HealBot

The survival engine that keeps your character alive with ultra-fast spell and potion healing.

---

## 📖 Overview

HealBot is nExBot's automated healing system. It monitors your health and mana in real time and casts healing spells or uses potions the moment you need them — with a response time of around **75 ms**, far faster than any human can react.

Key capabilities:

- Cast healing spells at configurable HP thresholds
- Use healing potions as primary or fallback healing
- Handle mana potions and mana regeneration
- Cast support spells (haste, mana shield, buffs)
- Cure conditions (poison, paralyze, burn)
- Auto-eat food on a timer
- Track all consumption for the Hunt Analyzer

---

## 🚀 Quick Start

1. Open the **Main** tab and click the **Healing** button.
2. Add a healing spell — for example, `exura vita` at **50%** HP.
3. Add a potion — for example, `Great Health Potion` at **40%** HP.
4. Toggle HealBot **ON**.

That's it. HealBot will keep you alive while you hunt.

---

## ⚙️ How Healing Works

When your health changes, HealBot runs this evaluation:

```text
Health Changed →
  ├── Is HP ≤ threshold of any spell? →
  │     Yes → Is spell off cooldown? → Do I have enough mana? → Cast spell
  │     No  ↓
  ├── Is HP ≤ threshold of any potion? →
  │     Yes → Do I have the potion? → Use potion
  │     No  ↓
  └── No action needed
```

Spells are checked first in **priority order** (lower number = higher priority). If no spell can fire (cooldown, insufficient mana), potions are used as fallback.

---

## 🪄 Configuring Healing Spells

### Adding a Spell

In the Healing panel, click **+** in the Spells section:

| Field | Description |
|-------|-------------|
| **Formula** | The spell words (e.g. `exura vita`) |
| **Threshold** | HP percentage at or below which the spell fires |
| **Priority** | Order of evaluation — 0 is highest |

### Threshold Logic

A spell set to **50%** HP will cast whenever your current HP is at or below 50% of your max HP. Multiple spells can be active simultaneously — HealBot evaluates them in priority order and casts the first one that matches.

### Example Setup

| Priority | Spell | Threshold | Purpose |
|----------|-------|-----------|---------|
| 0 | `exura gran` | 20% HP | Emergency heal |
| 1 | `exura vita` | 50% HP | Main heal |
| 2 | `exura` | 70% HP | Light heal |

---

## 🧪 Configuring Healing Potions

### Adding a Potion

In the Healing panel, click **+** in the Potions section:

| Field | Description |
|-------|-------------|
| **Item** | The potion name or ID (e.g. `Great Health Potion`) |
| **Threshold** | HP percentage at or below which the potion is used |

### Potion Priority

When multiple potions are configured, HealBot picks the best option based on:

1. **Availability** — do you actually have it?
2. **Threshold match** — is your HP low enough?
3. **Efficiency** — prefer cheaper potions when sufficient

### Potions Don't Require a Specific Position

HealBot finds potions anywhere — in backpacks, equipped containers, or on the ground. You don't need to place them in a specific slot.

---

## 🛡️ Support Spells

You can add non-healing spells to HealBot's rotation:

| Spell Type | Example | Trigger |
|------------|---------|---------|
| Mana Shield | `utamo vita` | When under attack or below HP% |
| Haste | `utani hur` | When moving or always |
| Buff | `utito tempo` | Before combat |
| Protection | `utamo tempo` | When below HP% |

Support spells use the same threshold/priority system as healing spells.

---

## 🍗 Food Management

HealBot includes an auto-eat feature:

- Scans all open containers for food items
- Eats every **3 minutes** (configurable) to maintain regeneration
- Recognizes all standard Tibia food items
- Simple timer-based — no complex regeneration tracking

---

## 🩹 Condition Handling

HealBot works alongside the **Conditions** module to detect and cure harmful conditions:

| Condition | Detection | Auto-Cure |
|-----------|-----------|-----------|
| Poison | Green effect, status icon | Antidote potion or `exana pox` |
| Burn | Fire effect, periodic damage | Move away, heal through it |
| Paralyze | Purple aura, movement blocked | `utani hur` or wait for decay |
| Bleed | Periodic damage | Heal through damage |
| Curse | Reduced output | Cure spell or wait |

The Conditions panel (separate from HealBot) lets you configure automatic cures for each condition type.

---

## 🔗 Integration with Other Modules

### CaveBot

- HealBot keeps you alive during waypoint walks
- If HP drops critically low, CaveBot pauses navigation
- Condition cures unblock movement (e.g. paralyze)

### TargetBot

- HealBot responds to incoming damage during combat
- Support spells (haste, mana shield) enhance combat survivability

### Hunt Analyzer

- Every spell cast and potion used is reported to Hunt Analyzer
- The analytics panel shows detailed consumption data per session

---

## 🧙 Vocation Examples

### Knight

```text
Spells:   exura vita @ 50% HP  |  exura @ 30% HP
Potions:  Great Health Potion @ 40% HP
Support:  utito tempo (always)
Food:     Every 3 minutes
```

### Paladin

```text
Spells:   exura vita @ 55% HP  |  exura @ 35% HP
Potions:  Great Health Potion @ 45% HP  |  Great Spirit Potion @ 60% mana
Support:  utani hur (when moving)
Food:     Every 3 minutes
```

### Sorcerer / Druid

```text
Spells:   exura @ 60% HP  |  exura vita @ 40% HP  |  exura gran @ 20% HP
Potions:  Health Potion @ 30% HP  |  Great Mana Potion @ 50% mana
Support:  utamo vita (at 80% HP)  |  utani hur (always)
Food:     Every 3 minutes
```

---

## ❓ Troubleshooting

### HealBot not healing

1. Is the toggle **enabled** (green)?
2. Are spells configured with correct names? (`exura vita`, not `exuravita`)
3. Is your HP actually below the configured threshold?
4. Do you have enough mana for the spell?
5. Is the spell on cooldown? (1–2 second cooldowns are normal)

### Dying too fast

- Lower your thresholds (heal earlier — e.g. 60% instead of 50%)
- Add more healing tiers at different HP percentages
- Add potion fallbacks for when mana runs out
- Consider using `utamo vita` (mana shield) for dangerous areas
- You may be in an area too difficult for your level

### Potions not being used

- Verify you have potions in your inventory
- Check that the potion is configured in the Healing panel
- Spells take priority over potions at the same threshold — set potion threshold slightly lower

### "Not enough mana" constantly

- Add a mana potion to your supply rotation
- Use lower-cost healing spells
- Consider a mana ring for sustained healing
