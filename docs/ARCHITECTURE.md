# Architecture

Technical overview of nExBot's internal architecture and design patterns.

---

## Overview

nExBot is a modular, event-driven bot built in Lua for OTClient. It uses a layered architecture with clear separation between client abstraction, core systems, and feature modules.

---

## System Architecture

```
┌──────────────────────────────────────────────────────┐
│                    _Loader.lua                        │
│              (Entry point, load phases)               │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │              Anti-Corruption Layer (ACL)        │  │
│  │  Auto-detects client: vBot or OTCR             │  │
│  │  Loads appropriate adapter                     │  │
│  │  Exposes unified ClientService API             │  │
│  └────────────────────────────────────────────────┘  │
│                         │                            │
│  ┌──────────┬───────────┼───────────┬─────────────┐  │
│  │ EventBus │ UnifiedTick│UnifiedStorage│CreatureCache│ │
│  └──────────┴───────────┴───────────┴─────────────┘  │
│                         │                            │
│  ┌──────────────────────┼──────────────────────────┐ │
│  │       Feature Modules (independent)             │ │
│  │  HealBot  AttackBot  CaveBot  TargetBot  Extras │ │
│  └─────────────────────────────────────────────────┘ │
│                         │                            │
│  ┌──────────────────────┼──────────────────────────┐ │
│  │              Analytics Layer                     │ │
│  │  Hunt Analyzer   Spy Level   Supplies Monitor   │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## Anti-Corruption Layer (ACL)

The ACL provides a unified API regardless of whether nExBot is running on vBot (OTClientV8) or OTCR (OpenTibiaBR).

### Client Detection

At startup, the ACL detects the client by:

1. Checking for OTCR-exclusive module files (`game_cyclopedia`, `game_forge`)
2. Probing for OTCR-exclusive APIs (`g_game.forceWalk()`)
3. Checking for vBot-exclusive APIs (`g_game.moveRaw()`)
4. A deferred re-detection runs 1.5 seconds later to catch late-loading APIs

### Adapters

| Adapter | Client | Extra APIs |
|---------|--------|-----------|
| **Base** | OTClientV8 (vBot) | Standard game operations |
| **OpenTibiaBR** | OTCR | forceWalk, stash, imbuements, prey, forge, market |

### ClientService API

The global `getClient()` function returns a unified interface:

```lua
local Client = getClient()
Client.getLocalPlayer()
Client.attack(creature)
Client.walk(direction)

-- OTCR-specific (gracefully degrade on vBot)
Client.stashWithdraw(itemId, count)
Client.applyImbuement(slotId, imbuementId, useProtection)
```

---

## EventBus

The centralized event dispatcher connects game callbacks to module handlers. All native OTClient callbacks are routed through EventBus so modules can subscribe without interfering with each other.

### Key Events

| Event | Source | Consumers |
|-------|--------|-----------|
| `creature:appear` | Native callback | TargetBot, Monster AI |
| `creature:disappear` | Native callback | TargetBot, Looting |
| `creature:health` | Native callback | TargetBot, Hunt Analyzer |
| `player:health` | Native callback | HealBot |
| `player:position` | Native callback | CaveBot, Spy Level |
| `effect:missile` | Native callback | Monster AI Spell Tracker |
| `containers:open_all_complete` | Container Opener | Other modules |

### Z-Change Burst Detection

During floor transitions, hundreds of creature events fire in a single frame. EventBus detects this burst (threshold: 5 events per frame) and sets `_zBlocked = true`, suppressing expensive callbacks for 150 ms.

---

## Unified Tick System

Instead of each module running its own `macro()` timer, `UnifiedTick` provides a single **50 ms master tick**. Modules register callbacks at their desired intervals:

```lua
UnifiedTick.register("myModule", 250, function()
  -- runs every 250ms
end)
```

This reduces timer overhead from 30+ separate timers to one.

---

## Unified Storage

Per-character persistent storage using JSON serialization:

- Namespace-based access: `UnifiedStorage.get("healing.enabled")`
- Batch updates for atomicity
- Migration helpers from legacy storage patterns
- Handles sparse array sanitization on startup

---

## Loading Order

The `_Loader.lua` organizes initialization into phases:

| Phase | Modules |
|-------|---------|
| 1 | ACL + Client abstraction |
| 2 | Constants (floor items, food, directions) |
| 3 | Utils (shared, ring buffer, path utils) |
| 4 | Core libraries (lib, items, configs, database) |
| 5 | Architecture (EventBus, UnifiedStorage, UnifiedTick) |
| 6 | Feature modules (HealBot, AttackBot, CaveBot, TargetBot, etc.) |
| 7 | Tools (Containers, Dropper, antiRs, etc.) |
| 8 | Analytics (Analyzer, Hunt Analyzer, Spy Level) |
| 9 | Private scripts (user custom scripts) |
| 10 | Activate UnifiedTick |

Each module is error-isolated — a failure in one module doesn't prevent others from loading.

---

## Design Patterns

| Pattern | Purpose | Where Used |
|---------|---------|------------|
| **Event-Driven** | Efficient reactivity | EventBus, HealBot, TargetBot |
| **State Machine** | Deterministic attacks | AttackStateMachine |
| **Intent Voting** | Conflict-free movement | MovementCoordinator |
| **LRU Cache** | Bounded memory | Creature configs, pathfinding |
| **Object Pool** | Reduce GC pressure | Path entries, position tables |
| **EWMA** | Smooth statistics | Monster tracking, cooldowns |
| **BFS Traversal** | Container opening/looting | ContainerOpener, Looting |
| **Engagement Lock** | Anti-zigzag targeting | ScenarioManager |
| **Lazy Evaluation** | Skip unnecessary work | Safety checks, pathfinding |
| **Burst Detection** | Z-change protection | EventBus |

---

## Module Communication

Modules communicate through three mechanisms:

1. **EventBus** — loose coupling via named events
2. **Direct API** — modules expose public functions (e.g. `CaveBot.isOn()`)
3. **Shared state** — `nExBot` global namespace for cross-module data

Circular dependencies are avoided by loading modules in a strict phase order and using deferred event subscriptions.

---

## Error Handling

- Each module loads inside `pcall()` — failures are logged but don't crash the bot
- Optional modules (marked in `OPTIONAL_MODULES`) fail silently if missing
- Load times are tracked per module for profiling
- Errors are collected in `nExBot.loadErrors` for debugging

---

## Private Scripts

Users can place custom `.lua` files in a `private/` folder. These are auto-loaded after all core modules, giving them access to the full nExBot API. Private scripts are recursively discovered and sorted alphabetically.
