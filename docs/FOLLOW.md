# Follow Player

Party hunt companion — keeps your bot near the party leader while attacking monsters.

---

## Overview

Follow Player is a single-purpose module: stay close to your party leader. When monsters appear, the bot attacks them but never walks past the leader to chase. If the leader moves beyond max distance, the bot catches up immediately.

Key behaviors:

- Attacks monsters on screen but stays within max distance of leader
- Follows while attacking (parallel mode) — attack persists via ASM, movement uses forceWalk
- When leader moves beyond threshold, cancels attack and catches up
- Recovers to last known position if leader goes off-screen (10s window)
- MovementCoordinator integration — FOLLOW intent (priority 95) beats CHASE (priority 35)

---

## Quick Start

1. Open the **Tools** tab.
2. Enter the party leader's **name** in the Target field.
3. Toggle **Follow** ON.
4. Toggle **Follow While Attacking** ON (recommended).

---

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| **Target** | "" | Player name to follow |
| **Follow While Attacking** | ON | Walk toward leader while fighting monsters |
| **Max Distance** | 3 | Tiles before bot catches up to leader |

---

## How It Works

### Priority System

The bot uses MovementCoordinator's FOLLOW intent (priority 95) which beats:

| Intent | Priority | Result |
|--------|----------|--------|
| FOLLOW | 95 | Bot catches up to leader |
| WAVE_AVOIDANCE | 90 | Dodge wave attacks |
| FINISH_KILL | 80 | Chase wounded target |
| CHASE | 35 | Close gap to monster |

If the leader is beyond max distance, the bot stops chasing monsters and catches up. Monsters within max distance are attacked normally.

### Parallel Mode

When `followWhileAttacking` is ON and the bot is attacking:

1. Attack continues via AttackStateMachine (server-maintained)
2. MovementCoordinator registers FOLLOW intent
3. Bot walks toward leader using `forceWalk()` (does not cancel attack)
4. Attack re-sends automatically if dropped

### Lost Leader Recovery

If the leader goes off-screen:

1. Bot walks to last known position for up to 10 seconds
2. If leader reappears, resumes following immediately
3. If 10s passes, stops and waits

---

## Troubleshooting

### Bot walks away from leader to chase monsters

- Max distance is too high — lower it to 2-3
- `followWhileAttacking` is OFF — enable it so bot walks while fighting
- Check ASM state — attack must be active for parallel mode

### Bot stutters (follow, stop, follow)

- Leader distance fluctuates around maxDistance — lower maxDistance by 1
- Native follow is conflicting with forceWalk — check `isFollowing()` state

### Bot doesn't follow after login

- Re-enter the leader name in the Target field
- Toggle Follow OFF then ON

---

## Technical Details

- Module: `core/follow.lua`
- Macro interval: 75ms
- Pathfinding: `g_map.findPath` with fallback to `findPath`
- EventBus listeners: `creature:move`, `combat:end`
- MovementCoordinator intent: `FOLLOW` (priority 95)
