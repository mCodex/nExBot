# TargetBot

Combat targeting and positioning system.

## Overview

TargetBot controls creature targeting, combat movement, and looting. It uses a vBot 4.8 hybrid approach: direct spectator scans every 100ms with simple priority-based target selection.

Key capabilities:
- Direct `g_map.getSpectatorsInRange` creature detection — no event caches, no monitoring layer
- Simple priority scoring (config priority + distance + HP)
- AttackStateMachine — sole attack issuer, eliminates attack conflicts
- Chase, keep-distance, avoid-attacks movement
- Per-creature configurations with pattern matching
- Integrated looting

## Quick Start

1. Open the **Target** tab.
2. Click **+** to add a creature.
3. Enter monster name (e.g. `Dragon`), configure spells and behavior.
4. Toggle TargetBot ON.
5. TargetBot automatically targets and fights creatures.

## Architecture

The targeting system is intentionally simple, modeled after vBot 4.8's proven approach:

```text
Macro (100ms):
  ├── g_map.getSpectatorsInRange → creatures on screen
  ├── For each creature:
  │     ├── Validate (monster, alive, same floor)
  │     ├── findPath(7 steps)
  │     ├── calculateParams → priority + danger
  │     └── Track highest priority
  ├── AttackStateMachine.requestAttack(best)
  ├── TargetBot.Creature.attack (spells + movement)
  └── TargetBot.walk()
```

No event cache, no debounce, no monitoring layer. Every tick is a fresh scan.

## Target Selection

### Pattern Matching

| Pattern | Matches |
|---------|---------|
| `Dragon` | Exact name |
| `Dragon*` | Dragon, Dragon Lord, Dragon Knight |
| `*Demon` | Demon, Grand Demon, Evil Demon |
| `*, !Dragon` | Everything except Dragons |

### Priority Scoring

Each creature receives a priority score based on:
- **Config priority** — base weight from creature editor
- **Distance** — closer creatures get a bonus (up to +16 for adjacent)
- **Health** — low-HP creatures get a finish-kill bonus

The creature with the highest score becomes the active target.

## Attack State Machine

All attacks go through AttackStateMachine (ASM). No other module calls `g_game.attack()` directly — this eliminates attack conflicts.

### States

| State | Description |
|-------|-------------|
| IDLE | Waiting for target |
| ACQUIRING | Target selected, attack command sent |
| CONFIRMING | Waiting for server confirmation |
| ATTACKING | Server confirmed, actively fighting |
| RECOVERING | Target died, grace period before IDLE |

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Reissue Interval | 1400 ms | Re-send attack if unconfirmed |
| Confirm Timeout | 1000 ms | Wait for server confirmation |
| Attack Cooldown | 300 ms | Minimum between attack commands |
| Switch Cooldown | 5000 ms | Minimum between target switches |

## Creature Editor

| Setting | Description |
|---------|-------------|
| **Name** | Monster name or pattern |
| **Priority** | Base weight for targeting |
| **Danger** | Danger rating for loot/walk decisions |
| **Keep Distance** | Ranged positioning |
| **Distance Range** | How far to stay |
| **Lure Count** | Pull this many before fighting |
| **Attack Spells** | Spells to use |
| **Attack Runes** | Runes to use |

## Looting

- Automatic item pickup from dead creatures
- BFS container traversal for nested loot
- Configurable loot filters
- Loot-to-container assignment
- Eat Food from Corpses (optional)

## Debugging

```lua
-- Check ASM state
print(AttackStateMachine.getState(), AttackStateMachine.getTargetId())
```
