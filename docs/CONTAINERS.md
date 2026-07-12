# Containers

Automated container management with event-driven BFS, O(1) operations, and generation-based cancellation.

## Quick Start

1. Open **Containers** panel (Main tab)
2. Assign roles: Slot 0 = Main BP, Slot 1 = Loot, Slot 2 = Supplies, Slot 3 = Runes
3. Enable **Auto Open on Login**

## Container Roles

| Role | Purpose |
|------|---------|
| Main Backpack | Primary container holding others |
| Loot Container | Monster drops during hunting |
| Supplies Container | Potions, food, consumables |
| Runes Container | Attack/utility runes |

## Architecture

The container system runs as 10 focused modules under `core/containers/`:

| Module | Responsibility | Complexity |
|--------|---------------|------------|
| `identity.lua` | Physical container identity, generation tagging | O(1) |
| `queue.lua` | Head/tail FIFO queue | O(1) enqueue/dequeue |
| `state_machine.lua` | 13 explicit states, generation tracking | O(1) |
| `registry.lua` | Container registry, incremental item index | O(1) lookup |
| `bfs.lua` | Event-driven BFS traversal | O(C + I + P) |
| `scheduler.lua` | UnifiedTick integration, priority scheduling | O(1) |
| `readiness.lua` | Derived readiness snapshots | O(1) |
| `client_adapter.lua` | OTClient API wrapper | O(1) |
| `quiver.lua` | Quiver ownership, vocation detection | O(1) |
| `discovery.lua` | Orchestrator | O(1) |

### State Machine

The discovery process follows 13 explicit states:

```
idle → waitingForSession → discoveringRoots → reconciling → traversing
                                                        ↓
                                              waitingForAcknowledgement
                                                        ↓
                                                 waitingForPage
                                                        ↓
                                                  completed
```

Any state can transition to `cancelled` (relog) or `failed` (unrecoverable error).

### Generation Tracking

Every login/reconnect increments a generation counter. All candidates, timers, and callbacks carry this generation. Old callbacks from generation N cannot mutate generation N+1.

### Event-Driven BFS

1. Discover roots (main backpack, quiver for paladins)
2. Reconcile containers already open
3. Process queue one container at a time
4. On container opened: inspect contents, discover children
5. Handle pages sequentially (not pre-scheduled)
6. Complete when queue empty and no in-flight requests

### Identity

Physical containers identified by:
```
generation:rootKind:parentIdentity:slotIndex:itemType:version
```

Three brown backpacks with the same item ID remain distinct physical instances.

## Quiver Management

For Paladins — the quiver is an independent BFS root. One service owns opening and lifecycle. The quiver manager consumes readiness and indexed contents.

Non-Paladins: no quiver open attempts. Stale quiver state cleared on relog.

## Configuration

| Setting | Default |
|---------|---------|
| Auto Open | OFF |
| Auto Stack | ON |
| Sort Containers | OFF |
| Close Empty | OFF |

## Setup Examples

**Knight:**
```
Main BP: Golden Backpack
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
└── Runes: Blue Backpack (SD / Magic Wall)
```

**Paladin:**
```
Main BP: Adventurer's Bag
├── Supplies: Beach Bag (potions)
├── Loot: Beach Bag (drops)
├── Ammo: Grey Backpack (arrow reserve)
└── Quiver: Auto-managed
```

## EventBus

```lua
-- All containers opened
EventBus.on("containers:open_all_complete", function(readiness)
  print("Discovery complete:", readiness.status)
end)

-- Readiness changes
EventBus.on("containers:readiness", function(readiness)
  if readiness.status == "ready" then
    -- containers available
  end
end)

-- Container opened
EventBus.on("container:open", function(container)
  -- handle open
end)
```

## Performance

| Operation | Complexity |
|-----------|------------|
| Queue enqueue/dequeue | O(1) amortized |
| Candidate lookup | O(1) |
| Deduplication | O(1) |
| Item lookup by type | O(1) |
| Full discovery | O(C + I + P) |
| Page traversal | Sequential, ack-driven |

Benchmarks (10k operations): Queue <1ms, Registry <2ms.

## Troubleshooting

**Not opening:** Auto Open enabled? Containers assigned? Wait a few seconds. Check console.

**Quiver not refilling:** Arrows/bolts in supply container? Quiver equipped? Correct type?

**Items going wrong:** Verify slot order matches in-game layout.

**Closing immediately:** Server limit ~20. Bot enforces 19. Keep assigned under 15-18.

**Discovery too slow:** Container discovery runs at LOW priority. Critical actions (healing, survival) always take precedence.
