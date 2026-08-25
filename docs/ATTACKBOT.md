# AttackBot

Automated attack spells and runes with AoE optimization.

## Quick Start

1. Open **More → Equipment** and open the Attack configuration window.
2. Click **Add** — select spell/rune, set monster count, configure priority
3. Toggle **ON**

## Attack Types

### Single-Target Spells

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

| Vocation | Spell | Words | Area |
|----------|-------|-------|------|
| Knight | Groundshaker | `exori mas` | 5x5 |
| Knight | Annihilation | `exori gran ico` | 3x3 |
| Paladin | Divine Caldera | `exevo mas san` | 5x5 |
| Sorcerer | Hell's Core | `exevo gran mas flam` | 5x5 |
| Sorcerer | Rage of the Skies | `exevo gran mas vis` | 5x5 |
| Druid | Eternal Winter | `exevo gran mas frigo` | 5x5 |

### Runes

| Rune | Area |
|------|------|
| Sudden Death | Single target |
| Great Fireball | 3x3 |
| Avalanche | 3x3 |
| Thunderstorm | 3x3 |
| Stone Shower | 3x3 |

## Attack Rules

| Field | Description |
|-------|-------------|
| **Spell/Rune** | What to use |
| **Monster Count** | Minimum nearby monsters to trigger |
| **Mana** | Minimum mana required |
| **Cooldown** | Respected automatically |
| **Priority** | Higher = evaluated first |

Evaluation order:
1. Rule enabled?
2. Enough monsters in range?
3. Off cooldown?
4. Enough mana?
5. Safety checks pass?
6. → Execute

## Configurations

**Knight AoE:**

| Priority | Rule | Condition |
|----------|------|-----------|
| 1 | Groundshaker (`exori mas`) | Monsters ≥ 4 |
| 2 | Fierce Berserk (`exori gran`) | Monsters ≥ 2 |
| 3 | Berserk (`exori`) | Monsters ≥ 1 |
| 4 | Front Kick (`exori ico`) | Always |

**Mage Hunting:**

| Priority | Rule | Condition |
|----------|------|-----------|
| 1 | Hell's Core (`exevo gran mas flam`) | Monsters ≥ 5 |
| 2 | Great Fireball rune | Monsters ≥ 3 |
| 3 | Wand attack | Monsters ≥ 1 |
| 4 | Sudden Death rune | Target HP < 20% |

## Technical Details

Attack categories, patterns, and spell shapes are in `core/attack/attack_data.lua` — pure data, testable independently.
Analytics recording is in `core/attack/attack_analytics.lua` — pure functions.
Profile management is in `core/attack/attack_config.lua` — pure functions.
Combat execution is in `core/attack/combat_executor.lua` — uses dependency injection.

## Performance

- **Entry cache:** Rules compiled once, rebuilt only on config change (~50% CPU reduction)
- **Monster count cache:** 100ms TTL, shared across AttackBot and MovementCoordinator
- **Lazy safety:** PvP/player checks only run when attack would fire

## Safety

| Feature | Behavior |
|---------|----------|
| PvP Protection | Won't AoE if friendly players in range |
| Blacklist | Players that should never be hit |
| Anti-RS | Stops all attacks if PK skull would result |
| Mana Guard | Won't cast if mana below floor |

## Analytics

Reports to Tactical Intelligence: spell counts, rune counts, empowerment buffs, total attacks.

## Troubleshooting

**Attack not firing:** Enabled? Target exists? Off cooldown? Enough mana? Monster count met?

**AoE not triggering:** Threshold too high? Monsters in range? Creatures attackable?

**Wasting runes on single targets:** Add `Monsters ≥ 2` condition. Separate AoE from single-target rules.

**Priority conflicts:** Expensive spells at top, filler at bottom. Stagger cooldowns.
