# Performance

Optimization guide for understanding and tuning nExBot's performance.

---

## Overview

nExBot is engineered for minimal CPU and memory impact. Every module uses caching, event-driven execution, and lazy evaluation to avoid unnecessary work. This page documents the optimizations in place and the tuning parameters available.

---

## Architecture Optimizations

### Event-Driven Design

Rather than polling every tick, most nExBot modules are triggered by game events:

| Module | Trigger | Benefit |
|--------|---------|---------|
| HealBot | `onHealthChange` | Only runs when health changes |
| TargetBot | `onCreatureAppear/Disappear` | Reacts to world changes |
| AttackBot | TargetBot tick | Only evaluates when attacking |
| Hunt Analyzer | Kill/spell/potion events | Passive recording |
| Eat Food | Timer (3 min) | No constant polling |

### Unified Tick System

Instead of 30+ separate macro timers, nExBot consolidates into a single **50 ms master tick** via `UnifiedTick`. Modules register callbacks at different intervals, and the master tick dispatches them efficiently.

### Z-Change Burst Detection

Floor transitions fire hundreds of creature appear/disappear events in a single frame. nExBot's `EventBus` detects this burst pattern and blocks expensive callbacks (targeting, looting, Monster AI) during the transition, preventing freezes.

---

## Caching Systems

### AttackBot Entry Cache

Attack rules are compiled once and cached. The cache invalidates only when the configuration changes — not every tick.

- **Before:** 20 ms per rebuild, every tick
- **After:** Build once, reuse indefinitely
- **Impact:** ~50% CPU reduction in AttackBot

### Monster Count Cache

The count of nearby monsters is cached with a **100 ms TTL**:

- Avoids recounting creatures on every evaluation
- Shared across AttackBot and MovementCoordinator
- **Impact:** ~30% CPU reduction in combat

### LRU Creature Cache

TargetBot caches creature configurations with Least Recently Used eviction:

- Max 50 entries
- O(1) lookup after first access
- Bounded memory, no unbounded growth

### Pathfinding Cache

The reachability system caches pathfinding results per creature ID with TTL expiration:

- Avoids repeated expensive pathfinding to the same creature
- Cache invalidates when the creature moves significantly
- **Impact:** Major reduction in pathfinding CPU during combat

---

## Walking Optimizations

### autoWalk-First Strategy

CaveBot tries the client's built-in `autoWalk` first, which uses the game engine's fast pathfinding. Only when autoWalk fails does it fall back to manual `findPath` calls.

```text
1. autoWalk (fast, client-native)
2. findPath simple (local pathfinding)
3. findPath ignore creatures (if distance ≤ 30)
4. findPath allow unseen (if distance ≤ 15)
```

Most walks complete with a single autoWalk call.

### Pathfinding Distance Limit

Pathfinding is capped at **50 tiles** maximum. Beyond that, autoWalk is used exclusively. This prevents O(n²) pathfinding explosions that would freeze the client.

```text
50 tiles:  ~2,500 nodes → fast
100 tiles: ~10,000 nodes → slow
200 tiles: ~40,000 nodes → client freeze
```

### CaveBot Execution Skipping

CaveBot's macro runs every 250 ms, but the Optimized Execution System skips iterations when unnecessary:

- Skip while player is actively walking
- Skip during delays (after using items)
- Skip when TargetBot's Pull System is active
- **Impact:** ~60% fewer macro executions during walks

---

## Memory Management

### Object Pooling

Frequently created tables (positions, paths) are pooled and reused instead of being allocated and garbage-collected:

```lua
local pos = nExBot.acquireTable("position")
pos.x, pos.y, pos.z = 100, 200, 7
-- ... use position ...
nExBot.releaseTable("position", pos)
```

### Storage Sanitization

On startup, nExBot scans all stored data for sparse arrays (which prevent JSON serialization) and fixes them automatically. This runs in chunks to avoid blocking the main thread.

### Cache Lifecycle

```text
Module loaded → Cache is nil
First access  → Build and cache
Config change → Invalidate cache
Next access   → Rebuild cache
```

---

## Dynamic Scaling

TargetBot movement thresholds automatically scale based on monster count:

| Monsters | Scale | Effect |
|----------|-------|--------|
| 1–2 | 1.0x | Full cooldowns, conservative movement |
| 3–4 | 0.85x | Slightly faster reactions |
| 5–6 | 0.70x | Faster reactions, lower stickiness |
| 7+ | 0.50x | Maximum reactivity |

Affected parameters:
- Movement cooldowns
- Target stickiness
- Confidence thresholds
- Hysteresis values

---

## Tuning Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MAX_PATHFIND_DIST` | 50 | Max pathfinding range (tiles) |
| `FAR_WAYPOINT_DIST` | 100 | Distance threshold for autoWalk |
| `MONSTER_CACHE_TTL` | 100 ms | Monster count cache lifetime |
| `CHECK_INTERVAL` | 2000 ms | Waypoint Guard check interval |
| `EAT_COOLDOWN` | 1000 ms | Min time between eating |
| `CREATURE_CACHE_SIZE` | 50 | LRU creature cache max entries |

> Only adjust these if you understand the performance trade-offs. Lower values = faster response but more CPU. Higher values = less CPU but slower response.

---

## Startup Performance

nExBot tracks load times for every module. Total startup is typically under 1 second:

| Phase | Typical Time |
|-------|-------------|
| Storage sanitization | 15–50 ms |
| Style loading | 10–30 ms |
| Core modules | 100–200 ms |
| TargetBot + CaveBot | 100–200 ms |
| **Total** | **< 1 second** |

If startup exceeds 1 second, a warning is logged with the slowest modules listed:

```lua
-- View startup profile
nExBot.printStartupProfile()
```

---

## Benchmarks

| Component | Operation | Typical Speed |
|-----------|-----------|---------------|
| HealBot | Health check → spell cast | ~75 ms |
| CaveBot | Pathfinding + walking | ~150 ms |
| TargetBot | Target evaluation | ~50 ms |
| Hunt Analyzer | Metric calculation | ~20 ms |
| Monster AI | Behavior prediction | ~10 ms |

---

## Signs of Good Performance

- Client runs at 60 FPS during hunting
- No freezing or stuttering during floor changes
- Quick response to incoming damage
- Smooth walking along waypoints

## Signs of Problems

- FPS drops during combat
- Client freezes while walking (pathfinding too large)
- Delayed healing or spell casting
- Walking stutters or stops

### If You Have Performance Issues

1. Reduce the number of creatures in TargetBot
2. Increase CaveBot walk interval (500 ms is fine)
3. Disable unused modules (Hunt Analyzer, Monster Inspector)
4. Check for infinite loops in custom CaveBot actions
5. Close other heavy applications (browser, Discord)
