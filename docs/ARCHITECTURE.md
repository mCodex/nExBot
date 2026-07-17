# Architecture

Technical reference for nExBot internals.

## Loading Order

`_Loader.lua` initializes in phases:

| Phase | Modules |
|-------|---------|
| 1 | ACL + Client abstraction |
| 2 | Constants (floor items, food, directions) |
| 3 | Utils (shared, shared_helpers, storage_engine, safe_creature, path_utils, path_strategy) |
| 4 | Core libraries (lib, items, configs, database, updater) |
| 5 | UnifiedTick, EventBus, UnifiedStorage, Adaptive Intelligence, CreatureCache, ZChangeGuard, KillTracker |
| 6 | Feature modules (CaveBot, TargetBot, HealBot, AttackBot, Combo, Extras) |
| 7 | **Container modules** (queue, identity, state_machine, registry, client_adapter, readiness, bfs, scheduler, quiver, discovery) |
| 8 | Legacy tools (Containers, Dropper, antiRs, Tools, Equip, EatFood) |
| 9 | Analytics (Analyzer, HuntAnalyzer, SpyLevel, Supplies, NPC Talk, HoldTarget) |

Each module loads inside `pcall()`. Failures are logged but don't crash other modules.

## Anti-Corruption Layer (ACL)

Auto-detects vBot vs OTCR at startup:

1. Check for OTCR-exclusive modules (`game_cyclopedia`, `game_forge`)
2. Probe OTCR APIs (`g_game.forceWalk()`)
3. Fallback to vBot detection (`g_game.moveRaw()`)
4. Deferred re-detection at 1.5s for late-loading APIs

Returns a unified `ClientService` via `getClient()`. OTCR-specific methods (stash, imbuing, forge, prey) degrade gracefully on vBot.

## EventBus

Central event dispatcher. Modules subscribe without interfering with each other.

| Event | Source | Consumers |
|-------|--------|-----------|
| `creature:appear` | Native callback | TargetBot, Monster AI |
| `creature:disappear` | Native callback | TargetBot, Looting |
| `creature:health` | Native callback | TargetBot, Hunt Analyzer |
| `player:health` | Native callback | HealBot |
| `player:position` | Native callback | CaveBot, Spy Level |
| `effect:missile` | Native callback | Monster AI Spell Tracker |

### Z-Change Burst Detection

Floor transitions fire hundreds of creature events per frame. EventBus detects bursts (≥5 events/frame), sets `_zBlocked = true`, suppresses expensive callbacks for 150ms.

## UnifiedTick

Single 50ms master tick replaces 30+ individual timers:

```lua
UnifiedTick.register("myModule", {
  interval = 250,
  priority = UnifiedTick.Priority.NORMAL,
  handler = function()
    -- runs every 250ms
  end,
})
```

## UnifiedStorage

Per-character JSON persistence:

- Namespace access: `UnifiedStorage.get("healing.enabled")`
- Batch updates for atomicity
- Sparse array sanitization on startup
- Migration helpers from legacy storage

## Module Communication

Three mechanisms:

1. **EventBus** — loose coupling via named events
2. **Direct API** — modules expose public functions (e.g. `CaveBot.isOn()`)
3. **Shared state** — `nExBot` global namespace

Circular dependencies avoided by strict phase loading and deferred event subscriptions.

## Adaptive Intelligence

The code follows feature-based boundaries under `core/intelligence/`:

| Folder | Responsibility |
|--------|----------------|
| `foundation/` | Lifecycle, snapshots, events, blackboard, features, scheduling, configuration |
| `decisions/` | Arbitration, hard safety, CaveBot route state, lure, pull, wave/beam states |
| `learning/` | Model registry, calibration, memory, latency, navigation costs, reward calculation |
| `observability/` | Replay, metrics inputs, resource/loot observation, Bot Doctor |
| `ui/` | Shared presenter and OTClient Tactical Intelligence window |
| `runtime.lua` | Wires the feature folders to EventBus, UnifiedTick, UnifiedStorage, TargetBot, and CaveBot |

`UnifiedTick` invokes the intelligence runtime. It creates one generation-tagged immutable snapshot and one indexed feature source. Tactical modules submit proposals. The Decision Engine rejects stale or invalid proposals, runs the hard safety envelope, resolves conflicts, and forwards the selected intent to its application service.

```text
native callbacks -> EventBus -> Intelligence Event Aggregator
                              -> immutable snapshot -> feature pipeline
feature modules -> proposals -> Decision Engine -> Safety Envelope
                                           |-> MovementCoordinator -> walk/chase executors
                                           `-> AttackStateMachine -> native attack API
outcomes -> bounded replay, metrics, calibration, and SHADOW learning
```

`MovementCoordinator` arbitrates TargetBot tactical movement. CaveBot owns deterministic waypoint execution and pauses its route while combat owns movement. `ChaseController` is the sole native chase-mode writer. `AttackStateMachine` is the sole autonomous native attack issuer. User clicks and explicitly user-authored example scripts are outside tactical arbitration.

TargetBot loads `ChaseController` before `MovementCoordinator`, AttackStateMachine, and EventTargeting. This order guarantees that a chase-enabled monster profile can apply native chase mode before the attack request reaches the client.

Models start in `SHADOW`: they observe, predict, and record evidence but cannot change actions. `ACTIVE` requires the registry promotion gates. Budget overruns disable optional diagnostics, replay, learning, neural inference, and route alternatives in that order; safety and execution are never disabled.

User configuration is the primary decision tier. The Decision Engine compares configured target priority before computed priority, confidence, utility, or learned context adjustment. Route and monster context needs 30 observations and 0.7 confidence before it can contribute, and the contribution stays within 10 percent. Native reachability and hard safety still accept or reject the final candidate.

See [Adaptive Intelligence](INTELLIGENCE.md) for operating modes, model behavior, replay, diagnostics, and configuration migration.

## Design Patterns

| Pattern | Purpose | Where |
|---------|---------|-------|
| Event-Driven | Efficient reactivity | EventBus, HealBot, TargetBot |
| State Machine | Deterministic attacks | AttackStateMachine |
| State Machine | Container discovery (13 states) | Containers state_machine |
| State Machine | Stuck detection | CaveBot WaypointEngine |
| Intent Voting | Conflict-free movement | MovementCoordinator |
| LRU Cache | Bounded memory | Creature configs, pathfinding |
| Negative Cache | Skip unreachable paths | PathUtils (500ms TTL) |
| PathCursor Preservation | Avoid redundant A* | Walking engine |
| Step Pipelining | Smooth keyboard walking | Walking engine |
| Adaptive Blacklist Decay | Prevent cascading exclusion | CaveBot recovery |
| EWMA | Smooth statistics | Monster tracking, cooldowns |
| BFS Traversal | Container opening | Container discovery |
| Head/Tail Queue | O(1) FIFO operations | Container queue |
| Generation Tracking | Cancel stale work on relog | Container state machine |
| Engagement Lock | Anti-zigzag targeting | ScenarioManager |
| Burst Detection | Z-change protection | EventBus + ZChangeGuard |
| Extract Pure Functions | Testable domain logic | attack_data, spell_resolver, containers |
| Table-Driven Delegation | 209 ACL methods | ClientService |
| Unified Storage Engine | Single JSON backend | utils/storage_engine |

## Error Handling

- Each module loads inside `pcall()` — failures logged, don't crash bot
- Optional modules (`OPTIONAL_MODULES`) fail silently
- Load times tracked per module
- Errors collected in `nExBot.loadErrors`

## Private Scripts

Place `.lua` files in `private/` folder. Auto-loaded after all core modules, full API access. Discovered recursively, sorted alphabetically.
