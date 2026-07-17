# Performance

Optimization reference for nExBot.

## Architecture

**Event-Driven:** Most modules trigger on game events, not polling:

| Module | Trigger |
|--------|---------|
| HealBot | `onHealthChange` |
| TargetBot | `creature:appear/disappear` |
| AttackBot | TargetBot tick |
| Hunt Analyzer | Kill/spell/potion events |

**UnifiedTick:** Single 50ms master tick replaces 30+ timers.

**Z-Change Burst Detection:** Blocks expensive callbacks during floor transitions (≥5 events/frame → 150ms suppress).

## Caching

| Cache | TTL | Purpose |
|-------|-----|---------|
| AttackBot entries | Infinite (config change) | Compiled attack rules |
| Monster count | 100ms | Shared across AttackBot + MovementCoordinator |
| Creature configs | LRU (50 entries) | TargetBot creature lookups |
| Pathfinding | LRU (8 entries), 200ms | Repeated A* queries |
| Negative pathfinding | 500ms (32 entries) | Proven-unreachable destinations |

**Pathfinding early exit:** For distances >30 tiles, runs 3 attempts instead of 5 (skips unseen tiles + field ignore). 40% fewer A* calls.

## Walking

**Pathfinding strategy:**
1. Strict (respects PZ, walls)
2. Allow non-pathable
3. Ignore creatures
4. Allow unseen (distance ≤30)
5. Ignore fields (distance ≤30)

**autoWalk:** Activates for paths ≥5 tiles with ≤55% direction changes. Chunked at 25 tiles max.

**Keyboard stepping:** Paths ≤2 tiles. 2-step pipelining for smooth animation.

**PathCursor preservation:** Cursor survives across ticks for same destination. Eliminates redundant A*.

**Pathfinding cap:** 50 tiles max. Beyond that, autoWalk only.

## CaveBot Skipping

Skips macro iterations when:
- Player actively walking (150ms verification)
- After item use delays
- TargetBot Pull System active
- Floor-change recovery

~60% fewer executions during walks.

## Memory

- Object pooling for positions/paths (acquire/release)
- Sparse array sanitization on startup
- Bounded caches with LRU eviction

## Dynamic Scaling

Movement thresholds scale with monster count:

| Monsters | Scale |
|----------|-------|
| 1–2 | 1.0x |
| 3–4 | 0.85x |
| 5–6 | 0.70x |
| 7+ | 0.50x |

## Tuning Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MAX_PATHFIND_DIST` | 50 | Max pathfinding range |
| `MONSTER_CACHE_TTL` | 100ms | Monster count cache |
| `CREATURE_CACHE_SIZE` | 50 | LRU creature entries |
| `NEG_CACHE_TTL` | 500ms | Negative pathfinding cache |
| `NEG_CACHE_MAX` | 32 | Max negative cache entries |
| `MAX_WALK_CHUNK` | 25 | Max tiles per autoWalk |
| `KEYBOARD_THRESHOLD` | 2 | Max tiles for keyboard stepping |
| `DIR_CHANGE_TOLERANCE` | 55% | Max direction changes for autoWalk |
| `BLACKLIST_BASE_TTL` | 15s | Base waypoint blacklist |
| `BLACKLIST_MAX_TTL` | 120s | Max waypoint blacklist |

## Startup

| Phase | Time |
|-------|------|
| Storage sanitization | 15–50ms |
| Style loading | 10–30ms |
| Core modules | 100–200ms |
| TargetBot + CaveBot | 100–200ms |
| **Total** | **< 1s** |

View: `nExBot.printStartupProfile()`

## Benchmarks

Run the intelligence pipeline benchmark with `lua tests/performance/intelligence_pipeline_benchmark.lua`. On the recorded arm64 Lua 5.5 baseline, mean snapshot, features, and arbitration time measured 0.006521 ms for one creature and 0.435285 ms for 100 creatures over 1,000 iterations. Tactical memory and metric samples retained their configured 100-entry bound after 1,000 writes.

The Adaptive Intelligence runtime selects idle, route, combat, and emergency snapshot rates. A 5 ms measured budget degrades optional work in a fixed order; hard safety and execution stay enabled.

| Component | Operation | Speed |
|-----------|-----------|-------|
| HealBot | Health check → cast | ~75ms |
| CaveBot | Pathfinding + walk | ~100ms |
| TargetBot | Target evaluation | ~50ms |
| Hunt Analyzer | Metric calculation | ~20ms |
| Monster AI | Behavior prediction | ~10ms |
| **Container Queue** | 10k enqueue/dequeue | <1ms |
| **Container Registry** | 1k add + lookup | <2ms |
| **Container State** | 1k transitions | <1ms |

## Container System

Event-driven BFS with O(1) operations:

| Operation | Before | After |
|-----------|--------|-------|
| Dequeue | O(n) | O(1) |
| Candidate lookup | O(n) scan | O(1) |
| Deduplication | O(n) scan | O(1) |
| Item lookup | O(C*I) full scan | O(1) |
| Full discovery | O(C*I) | O(C+I+P) |

Container discovery runs at LOW priority (25) on UnifiedTick. Critical actions always take precedence.

## Troubleshooting

FPS drops: reduce TargetBot creatures, increase CaveBot interval, disable unused modules, check for infinite loops in custom actions.
