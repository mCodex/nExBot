# Follow Player

Party hunt companion — stays near leader while attacking monsters.

## Quick Start

1. Open **Tools** tab → **Auto Follow**
2. Enter leader's **name**
3. Toggle **Follow Player** ON
4. Toggle **Follow While Attacking** ON (recommended)

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| Target | "" | Player name to follow |
| Follow Player | OFF | Macro toggle |
| Follow While Attacking | ON | Walk toward leader while fighting |
| Max Distance | 3 | Tiles before catching up |

## How It Works

FOLLOW intent (priority 95) beats wave avoidance (90), finish kill (80), chase (35).

**Parallel Mode:** Attack continues via ASM, bot walks toward leader using `forceWalk()`. Attack re-sends if dropped.

**Lost Leader Recovery:** Walks to last known position for 10s. If leader reappears, resumes. Otherwise stops.

## Troubleshooting

**Walks away from leader:** Max distance too high? `followWhileAttacking` OFF?

**Stutters:** Distance fluctuates around maxDistance. Lower by 1.

**Doesn't follow after login:** Re-enter name, toggle OFF then ON.

## Technical

- Module: `core/follow.lua`
- Interval: 75ms
- Pathfinding: `g_map.findPath` with fallback
- EventBus: `creature:move`, `combat:end`
