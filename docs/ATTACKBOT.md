# AttackBot

Automated offensive spell and rune casting with intelligent AoE optimization.

---

## Overview

AttackBot handles all your offensive abilities automatically. It casts attack spells, uses runes, optimizes AoE positioning, and manages cooldowns — so you can focus on navigation and survival.

Key capabilities:

- Single-target spell casting
- Area-of-effect (AoE) spell optimization
- Rune usage (Sudden Death, Avalanche, Great Fireball, etc.)
- Monster count conditions for intelligent AoE decisions
- Cooldown management and mana checks
- Combo rotations with staggered cooldowns
- Per-profile configurations (5 profiles)

---

## Quick Start

1. Open the **Main** tab and click **AttackBot**.
2. Click **Add** to create an attack rule.
3. Select a spell or rune, set a monster count condition, and configure priority.
4. Toggle AttackBot **ON**.

---

## Attack Types

### Single-Target Spells

Direct damage spells that hit a single creature:

| Vocation | Spell | Words | Cooldown |
|----------|-------|-------|----------|
| Knight | Fierce Berserk | `exori gran` | 6s |
| Knight | Berserk | `exori` | 4s |
| Knight | Front Sweep | `exori min` | 2s |
| Paladin | Ethereal Spear | `exori con` | 2s |
| Paladin | Divine Missile | `exori san` | 2s |
| Sorcerer | Energy Strike | `exori vis` | 2s |
| Druid | Terra Strike | `exori tera` | 2s |

### AoE Spells

Area spells that damage multiple creatures at once:

| Vocation | Spell | Words | Area |
|----------|-------|-------|------|
| Knight | Groundshaker | `exori mas` | 5x5 |
| Knight | Annihilation | `exori gran ico` | 3x3 |
| Paladin | Divine Caldera | `exevo mas san` | 5x5 |
| Sorcerer | Hell's Core | `exevo gran mas flam` | 5x5 |
| Sorcerer | Rage of the Skies | `exevo gran mas vis` | 5x5 |
| Druid | Eternal Winter | `exevo gran mas frigo` | 5x5 |

### Runes

Attack runes that don't require mana to use:

| Rune | Damage Type | Area |
|------|-------------|------|
| Sudden Death | Death | Single target |
| Heavy Magic Missile | Physical | Single target |
| Great Fireball | Fire | 3x3 |
| Avalanche | Ice | 3x3 |
| Thunderstorm | Energy | 3x3 |
| Stone Shower | Earth | 3x3 |

---

## Attack Rules

Each attack rule consists of:

| Field | Description |
|-------|-------------|
| **Spell/Rune** | Which spell or rune to use |
| **Monster Count** | Minimum monsters nearby to trigger this rule |
| **Mana** | Minimum mana required |
| **Cooldown** | Respected automatically |
| **Priority** | Higher-priority rules are evaluated first |

### Evaluation Order

```text
For each rule (by priority):
  1. Is the rule enabled?
  2. Are there enough monsters in range?
  3. Is the spell/rune off cooldown?
  4. Do I have enough mana?
  5. [Lazy] Do safety checks pass?
  6. → Execute attack
```

> Safety checks (PvP protection, blacklisted players) are evaluated **last** for performance. Fast checks are done first to skip unnecessary work.

---

## Example Configurations

### Knight AoE Build

| Priority | Rule | Condition |
|----------|------|-----------|
| 1 | Groundshaker (`exori mas`) | Monsters ≥ 4 |
| 2 | Fierce Berserk (`exori gran`) | Monsters ≥ 2 |
| 3 | Berserk (`exori`) | Monsters ≥ 1 |
| 4 | Front Kick (`exori ico`) | Always |

### Mage Hunting Build

| Priority | Rule | Condition |
|----------|------|-----------|
| 1 | Hell's Core (`exevo gran mas flam`) | Monsters ≥ 5 |
| 2 | Great Fireball rune | Monsters ≥ 3 |
| 3 | Wand attack | Monsters ≥ 1 |
| 4 | Sudden Death rune | Target HP < 20% |

### Paladin Team Hunt

| Priority | Rule | Condition |
|----------|------|-----------|
| 1 | Divine Caldera (`exevo mas san`) | Monsters ≥ 3 |
| 2 | Ethereal Spear (`exori con`) | Monsters ≥ 1 |
| 3 | Sudden Death rune | Target HP < 30% |

---

## Performance Optimizations

### Entry Caching

Attack rules are compiled and cached. The cache is only rebuilt when the configuration changes — not every tick. This reduces CPU usage by around 50% compared to rebuilding every evaluation.

### Monster Count Caching

The count of nearby monsters is cached with a 100 ms TTL. During intense combat, this avoids recounting creatures on every single iteration.

### Lazy Safety Evaluation

Safety checks (PvP flags, player blacklists) are the most expensive part of the evaluation. They are only run when an attack would actually fire — never speculatively.

---

## Safety Features

| Feature | Description |
|---------|-------------|
| **PvP Protection** | Won't cast AoE if friendly players are in range |
| **Blacklist** | Players that should never be hit |
| **Anti-RS** | Stops all attacks if PK skull would result |
| **Mana Guard** | Won't cast if mana is below a configured floor |

---

## Analytics Integration

AttackBot reports detailed usage statistics to the Hunt Analyzer:

- **Spell counts** — each attack spell with exact cast count
- **Rune counts** — each rune type with usage count
- **Empowerment buffs** — times `utito tempo` or `utamo vita` were cast
- **Total attacks** — combined count of all attack actions

These metrics feed into the Hunt Analyzer's efficiency calculations (attacks per kill, spell vs. rune balance, empowerment uptime).

---

## Troubleshooting

### Attack not firing

1. Confirm AttackBot is **enabled**
2. Verify a valid target exists — TargetBot must be attacking something
3. Is the spell off cooldown?
4. Ensure sufficient mana for the spell
5. Check that monster count conditions are met

### AoE not triggering

- Your monster count threshold may be too high — try lowering it
- Check that monsters are within the spell's detection range
- Verify that creatures are attackable (not NPCs or summons)

### Wasting runes on single targets

- Add a `Monsters ≥ 2` condition to area runes
- Separate your AoE rules from single-target rules
- Put single-target attacks at lower priority

### Spell priority conflicts

- Order rules so that expensive/powerful spells are at the top (highest priority)
- Put filler attacks at the bottom
- Stagger cooldowns: use fast spells between slow ones for maximum DPS
