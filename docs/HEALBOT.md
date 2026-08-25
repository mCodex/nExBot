# HealBot

Automated healing — spells, potions, support buffs, condition curing.

## Quick Start

1. Open **Heal** in the cockpit
2. Add spell: `exura vita` at 50% HP
3. Add potion: `Great Health Potion` at 40% HP
4. Toggle HealBot **ON**

## How Healing Works

```
Health changed →
  ├── Spell threshold met? → Off cooldown? → Enough mana? → Cast
  ├── Potion threshold met? → Have potion? → Use potion
  └── No action
```

Spells checked first by priority (0 = highest). Potions as fallback.

## Configuring Spells

| Field | Description |
|-------|-------------|
| **Formula** | Spell words (e.g. `exura vita`) |
| **Threshold** | HP% at or below which spell fires |
| **Priority** | Evaluation order — 0 is highest |

Example:

| Priority | Spell | Threshold | Purpose |
|----------|-------|-----------|---------|
| 0 | `exura gran` | 20% | Emergency |
| 1 | `exura vita` | 50% | Main heal |
| 2 | `exura` | 70% | Light heal |

## Configuring Potions

| Field | Description |
|-------|-------------|
| **Item** | Potion name or ID |
| **Threshold** | HP% at or below which potion is used |

Multiple potions: priority by availability, threshold match, cost efficiency.

Potions found anywhere — backpacks, equipped containers, ground.

## Support Spells

| Type | Example | Trigger |
|------|---------|---------|
| Mana Shield | `utamo vita` | Below HP% |
| Haste | `utani hur` | When moving |
| Buff | `utito tempo` | Before combat |
| Protection | `utamo tempo` | Below HP% |

Same threshold/priority system as healing spells.

## Food Management

Auto-eat every 3 minutes. Scans all open containers for food items.

## Condition Handling

Works with the **Conditions** module:

| Condition | Cure |
|-----------|------|
| Poison | Antidote potion or `exana pox` |
| Burn | Move away, heal through it |
| Paralyze | `utani hur` or wait for decay |
| Bleed | Heal through damage |

## Vocation Examples

**Knight:**
```
Spells:  exura vita @ 50% | exura @ 30%
Potions: Great Health Potion @ 40%
Support: utito tempo (always)
```

**Paladin:**
```
Spells:  exura vita @ 55% | exura @ 35%
Potions: Great Health Potion @ 45% | Great Spirit Potion @ 60% mana
Support: utani hur (when moving)
```

**Sorcerer/Druid:**
```
Spells:  exura @ 60% | exura vita @ 40% | exura gran @ 20%
Potions: Health Potion @ 30% | Great Mana Potion @ 50% mana
Support: utamo vita @ 80% HP | utani hur (always)
```

## Troubleshooting

**HealBot not healing:**
1. Toggle enabled?
2. Spell names correct? (`exura vita`, not `exuravita`)
3. HP below threshold?
4. Enough mana?
5. On cooldown? (1–2s cooldowns normal)

**Dying too fast:** Lower thresholds (60% instead of 50%), add potion fallbacks, add `utamo vita`.

**Potions not used:** Spells take priority at same threshold — set potion threshold lower.

## Technical Details

Spell/potion conversion logic is in `core/heal/spell_resolver.lua` — pure functions, testable independently.
Profile defaults and validation are in `core/heal/heal_config.lua` — pure functions.

## Integration

- **CaveBot:** Keeps you alive during walks. Critical HP pauses navigation.
- **TargetBot:** Responds to combat damage. Support spells enhance survivability.
- **Tactical Intelligence:** Every cast/use reported for analytics.
