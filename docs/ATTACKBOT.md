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
- Per-profile configurations (5 profiles)
- Priority-ordered attack rules (first-match-wins per 100ms tick)
- Direct execution: no event system, no middleware, no analytics overhead

---

## Quick Start

1. Open the **Main** tab and click **AttackBot**.
2. Click **Add Rule** to create an attack entry.
3. Select a category (Targeted Spell, Area Rune, etc.), set conditions (monster count, HP range, mana%), and type the spell or drag a rune.
4. Toggle AttackBot **ON**.

---

## Attack Types

### Targeted Spell

Direct damage spells that hit a single creature. Evaluated against the current target with configurable range (1–10 sqm).

| Vocation | Spell | Words |
|----------|-------|-------|
| Knight | Fierce Berserk | `exori gran` |
| Knight | Berserk | `exori` |
| Knight | Front Sweep | `exori min` |
| Paladin | Ethereal Spear | `exori con` |
| Paladin | Divine Missile | `exori san` |
| Sorcerer | Energy Strike | `exori vis` |
| Druid | Terra Strike | `exori tera` |

### Area Rune

Runes that affect an area. Uses pattern-based tile search to find the best position maximizing monster hits. Patterns: Cross (explosion), Bomb (fire bomb), Ball (GFB, avalanche). PvP-safe variants use larger patterns to avoid hitting nearby players.

### Targeted Rune

Single-target runes like Sudden Death or Heavy Magic Missile. Uses hotkey-style `useWith()` for closed-backpack compatibility.

### Empowerment

Buff spells like `utito tempo` or `utamo vita`. Triggered like any other attack rule.

### Absolute Spell

Area spells centered on the player or a directional beam/wave. Pattern shapes define the area: adjacent, wave (3 sizes), beam (2 sizes), small/medium/large area. Monster count is counted within the pattern shape.

---

## Attack Rules

Each attack rule consists of:

| Field | Description |
|-------|-------------|
| **Spell/Rune** | Which spell or rune to use |
| **Monster Count** | Minimum creatures in the area to trigger |
| **Or More** | "≥ N" vs "== N" mode |
| **Mana%** | Minimum mana required (0 = always) |
| **HP Range** | Valid target HP% (0-100) |
| **Cooldown** | Seconds between uses |
| **Monster Names** | Comma-separated, or `*` for any |

### Evaluation Order (per 100ms tick)

```text
For each rule (by priority):
  1. Is the rule enabled?
  2. Do I have enough mana?
  3. Is it off cooldown?
  4. Does the target exist?
  5. Is the target in valid HP range?
  6. [Area runes] Find best tile, check monster count
  7. [Absolute] Count monsters in pattern shape
  8. → Execute attack (spell: cast(), rune: useWith())
```

First matching rule executes — one action per tick.

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

---

## Safety Features

| Feature | Description |
|---------|-------------|
| **PvP Mode** | Disables area runes when players are nearby |
| **PvP Safe Patterns** | Uses expanded area shapes to avoid hitting players |
| **Blacklist** | Stops all attacks if a blacklisted player is in range |
| **Kills Counter** | Stops after N kills (for PvP risk management) |

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

### Rune not used

- AttackBot uses `useWith(runeId, target)` — no open backpack required
- If that fails, falls back to `g_game.useInventoryItemWith()`
- Ensure the rune is in your main backpack, not a sub-container

### Spell priority conflicts

- Order rules so that expensive/powerful spells are at the top
- Put filler attacks at the bottom
- One action per tick ensures no double-casting
