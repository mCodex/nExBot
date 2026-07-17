# Containers

Automated container management with event-driven BFS, O(1) operations, generation-based cancellation, and reconnect recovery coordination.

## Quick Start

1. Open **Inventory & Containers** panel
2. Go to **Roles** subtab — assign Main BP, Loot, Supplies, Runes
3. Enable **Auto Open on Login**
4. (Paladin) Enable Quiver in **Quiver & Ammo** subtab

## Container Roles

Assign roles in the **Roles** subtab. Each role maps to a specific physical backpack identified by root, path, and configured slot — not by item ID alone. Two brown backpacks remain distinct physical containers.

| Role | Purpose | Required for |
|------|---------|-------------|
| `MAIN` | Primary container; root of the graph | All inventory ops |
| `HEALING_SUPPLIES` | Health/mana potions | HealBot potion fallback |
| `MANA_SUPPLIES` | Mana potions (separate from health) | HealBot mana restore |
| `RUNES` | Attack/utility runes | AttackBot rune rotation |
| `AMMO_RESERVE` | Arrows/bolts reserve (paladin) | Quiver refill |
| `LOOT` | Monster drop destination | Looting |
| `FOOD` | Food items | Auto-eat |
| `STACKING` | Item stacking / sorting destination | Container management |
| `QUIVER` | Equipped quiver slot (auto-detected) | Ammo tracking |
| `CUSTOM` | User-defined purpose | Scripting |

When two containers share the same item type, the bot shows an **ambiguity warning** in the Roles subtab and asks you to identify the intended container. The selector persists a path-based identity that survives reconnect.

## Container Graph

The inventory is modeled as a directed graph rooted at equipped containers:

```
Main Backpack  (root: MAIN_BACKPACK)
├── Healing Supplies  [HEALING_SUPPLIES]
│   ├── Health Potions
│   └── Mana Potions
├── Loot  [LOOT]
├── Ammo Reserve A  [AMMO_RESERVE]
│   └── Ammo Reserve B  [AMMO_RESERVE]
│       └── Ammo Reserve C  [AMMO_RESERVE]
└── Runes  [RUNES]

Quiver  (root: QUIVER, paladin only)
```

Each node has a physical identity that includes generation, root kind, parent identity, parent slot, item type, and path signature. Physical identity survives reconnect and distinguishes duplicate item types.

## Open-Window Modes

Configure in **Reconnect Recovery** subtab → **Window Mode**:

### KEEP_ALL_OPEN (default)
Every discovered backpack stays open in its own window when capacity permits. If the client limit (≈19 windows) is reached, the bot shows a warning and switches to PIN_CRITICAL_AND_TRAVERSE for the remaining nodes.

### PIN_CRITICAL_AND_TRAVERSE
Critical containers stay open permanently:
- Main Backpack
- Quiver
- Ammo reserves
- Healing supplies
- Configured rune container
- Loot destination

Non-critical containers are temporarily opened to scan children, then closed once all children are discovered. Reduces window pressure for large inventories.

### ROLE_CONTAINERS_ONLY
Opens only root and explicitly assigned role containers. Minimum windows, minimum actions. Suitable for large inventories or when the server has aggressive open limits.

## Readiness Model

The container system publishes **derived readiness** — not a single boolean. Each dependent module declares what it needs.

| Level | Meaning |
|-------|---------|
| `SESSION_READY` | Game session detected, generation assigned |
| `ROOTS_READY` | Main backpack and quiver (if paladin) open |
| `SURVIVAL_READY` | Healing supplies indexed |
| `QUIVER_READY` | Quiver open and contents known |
| `AMMO_READY` | Compatible ammo source discovered |
| `COMBAT_READY` | All required combat containers available |
| `LOOT_READY` | Loot destination available |
| `FULLY_DISCOVERED` | All configured containers traversed |
| `DEGRADED` | Some non-critical containers unavailable |
| `FAILED` | Critical container could not be recovered |

### What requires what

| Module | Minimum readiness required |
|--------|--------------------------|
| Emergency spell healing | None (no containers needed) |
| Potion healing | `SURVIVAL_READY` |
| Ammo refill | `QUIVER_READY` and `AMMO_READY` |
| Looting | `LOOT_READY` |
| CaveBot supply refill waypoints | `COMBAT_READY` |
| TargetBot aggressive modes | `COMBAT_READY` |
| Full sorting / stacking | `FULLY_DISCOVERED` |

## Reconnect Recovery Workflow

When the game session starts or reconnects, the **ContainerRecoveryCoordinator** runs this sequence:

```
1. Game session detected
   → Debounce duplicate start signals (500ms window)
   → Increment session generation
   → Enter SURVIVAL_ONLY policy

2. Wait for local player and inventory stability (1–2s)
   → Emergency healing and escape remain active

3. Reconcile already-open client windows
   → Bind live windows to known physical identities

4. Discover equipped roots (Main BP, Quiver)
   → Enter CONTAINER_CRITICAL_RECOVERY policy

5. Open critical containers (healing supplies, runes)
   → Verify quiver and ammo for paladins
   → Publish SURVIVAL_READY

6. Publish QUIVER_READY and AMMO_READY when applicable
   → Publish COMBAT_READY

7. Resume TargetBot (from fresh, valid state — no stale targets)
   → Resume CaveBot (recalculated from current position)
   → Enter COMBAT_READY policy

8. Continue full graph traversal at low priority
   → Publish FULLY_DISCOVERED or DEGRADED
   → Enter FULLY_READY policy
```

### Recovery Policy States

The coordinator enforces one policy state at a time:

| State | TargetBot | CaveBot | Looting | Healing |
|-------|-----------|---------|---------|---------|
| `SURVIVAL_ONLY` | Paused (no new pulls) | Paused | Paused | **Always active** |
| `CONTAINER_CRITICAL_RECOVERY` | Hold (no aggressive) | Hold | Paused | **Always active** |
| `COMBAT_DEGRADED` | Limited (defensive only) | Cautious | Limited | **Always active** |
| `COMBAT_READY` | **Active** | **Active** | Active | **Always active** |
| `FULLY_READY` | **Active** | **Active** | **Active** | **Always active** |

Emergency healing, escape spells, and defensive movement are **never paused** regardless of policy state.

### TargetBot Resume Rules

Before resuming, TargetBot:
1. Invalidates all stale targets from the previous session
2. Rescans visible candidates from current game state
3. Verifies the game client is in a valid, stable state
4. Starts from an explicit idle state — no old lure state
5. Checks that required container readiness is met for the selected strategy

### CaveBot Resume Rules

Before resuming, CaveBot:
1. Invalidates the stale path from the previous session
2. Preserves the logical route and waypoint index
3. Recalculates the actual path from current position
4. Avoids replaying old waypoint side effects
5. Waits for `COMBAT_READY` or `SURVIVAL_READY` depending on configuration
6. Resumes through MovementCoordinator only

## Paladin Quiver & Ammo

Quiver recovery is treated as a **critical first-class workflow**:

```
1. Detect paladin vocation from client API
2. Detect equipped quiver slot
3. Establish quiver physical identity
4. Open or reconcile quiver window
5. Scan contents and capacity
6. Discover configured ammo reserve containers
7. Verify compatible ammo types
8. Publish QUIVER_READY
9. Publish AMMO_READY when a valid source is confirmed
10. Enable refill policy
```

### Multiple Ammo Reserve Backpacks

The bot supports deeply nested ammo reserves:

```
Main Backpack
├── Ammo Reserve A  [AMMO_RESERVE]
│   └── Ammo Reserve B  [AMMO_RESERVE]
│       └── Ammo Reserve C  [AMMO_RESERVE]
```

All three are discovered and indexed. The refill service picks the shallowest available source deterministically. Each ammo move is:
- Serialized through the action scheduler (no concurrent moves)
- Acknowledged before the next move starts
- Generation-tagged to reject stale callbacks
- Stopped when the quiver is full or no compatible ammo remains

### Ammo Refill Policies

| Policy | Behavior |
|--------|---------|
| `maintain_minimum` | Refill only when below configured minimum |
| `fill_to_target` | Refill until target count is reached |
| `fill_to_capacity` | Fill quiver completely |
| `disabled` | No automatic refill |

### Non-Paladin Behavior

Non-paladins: no quiver open attempts. Stale quiver bindings are cleared on every new generation. Quiver UI is hidden or disabled.

## Discovery State Machine

The bot uses 13 explicit states instead of loosely related booleans:

```
DISABLED
IDLE
WAITING_FOR_SESSION
WAITING_FOR_INVENTORY
DISCOVERING_ROOTS
RECONCILING_OPEN_WINDOWS
PLANNING
TRAVERSING
WAITING_FOR_ACTION_BUDGET
OPENING_CONTAINER
WAITING_FOR_ACKNOWLEDGEMENT
SCANNING_PAGE
WAITING_FOR_PAGE
INDEXING_ITEMS
DISCOVERING_CHILDREN
VERIFYING_CRITICAL_READINESS
VERIFYING_FULL_READINESS
COMPLETED
COMPLETED_DEGRADED
RETRY_BACKOFF
PAUSED_FOR_CRITICAL_ACTION
CANCELLED
FAILED
```

Every state transition records: allowed source states, reason code, generation, timestamp, timeout, retry count, and diagnostic payload.

## Session Generation

Every game session, reconnect, and bot reload gets a monotonically increasing generation number. All queue entries, open requests, acknowledgements, and callbacks carry their generation. Callbacks from generation N are automatically rejected when generation N+1 is active.

Repeated `onGameStart` events are idempotent — only one discovery run starts per stable session.

## Exhaustion & Backoff

The action scheduler detects server exhaustion through multiple signals (status messages, action rejection, missing acknowledgement within timeout) rather than one hardcoded string.

Reason codes:

```
SERVER_EXHAUSTED     → exponential backoff + jitter
ACTION_COOLDOWN      → wait for cooldown
ACK_TIMEOUT          → retry with longer delay
CONTAINER_NOT_FOUND  → skip node, continue
CONTAINER_LIMIT      → switch to PIN_CRITICAL mode
INVALID_ITEM         → skip, report
INVALID_PARENT       → reconcile parent, retry
STALE_GENERATION     → reject, do not retry
UNKNOWN              → bounded retry, then degrade
```

Default retry policy:
- Attempt 1: normal adaptive delay
- Attempt 2: 2× delay
- Attempt 3: 4× delay + jitter
- Then: mark node as temporarily failed, continue with other nodes
- After queue completes: one bounded reconciliation pass for retryable failures

One failed node does not block the rest of the graph.

## Diagnostics

The **Diagnostics** subtab shows actionable status:

| Metric | Description |
|--------|-------------|
| Discovery duration | Time from session start to FULLY_DISCOVERED |
| Roots discovered | Count of authoritative roots found |
| Nodes opened | Physical containers successfully opened |
| Failed opens | Containers that could not be opened |
| Retries | Retry attempts made |
| Ack latency | Observed acknowledgement latency (EWMA) |
| Exhaustion events | Server exhaustion detections |
| Stale callbacks | Generation-mismatched callbacks rejected |
| Refill moves | Ammo moves completed this session |
| Queue depth | Current BFS queue depth |

Export diagnostics with **Export** button in Diagnostics subtab. The export contains state transitions, queue events, action submissions, acknowledgements, and readiness transitions.

## Architecture

The container system runs as focused modules under `containers/`:

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
| `discovery.lua` | Discovery orchestrator | O(1) |
| `recovery_coordinator.lua` | Reconnect recovery policy | O(1) |

### Physical Identity

Containers identified by:
```
generation : rootKind : parentIdentity : slotIndex : itemType : pathVersion
```

Three brown backpacks with the same item ID remain distinct physical instances. Moved backpacks can be reconciled. Identity collisions are detected and reported.

### Event-Driven BFS Algorithm

```
1. Enqueue authoritative roots
2. Dequeue one candidate
3. Validate generation and physical identity
4. Reconcile whether it is already open
5. Request one open action through the scheduler
6. Wait for real client acknowledgement
7. Bind the live client container
8. Scan current page
9. Index items incrementally
10. Discover child containers
11. Enqueue unseen physical children
12. Process additional pages sequentially
13. Mark node complete
14. Continue to next candidate
```

Maximum one open request in flight at default settings. No fixed-delay cascades. No pre-scheduled flood of open calls.

Complexity:
```
C = discovered physical containers
I = inspected items
P = inspected pages

Traversal:           O(C + I + P)
Queue operations:    O(1) amortized
Registry lookup:     O(1) average
Item-type lookup:    O(1) after indexing
```

## EventBus

```lua
-- Readiness changed
EventBus.on("containers:readiness", function(snapshot)
  -- snapshot.status: "COMBAT_READY", "FULLY_DISCOVERED", "DEGRADED", ...
  -- snapshot.generation, snapshot.mainBackpackReady, snapshot.quiverReady, ...
end)

-- Full discovery complete (or degraded)
EventBus.on("containers:open_all_complete", function(snapshot)
  print("Discovery:", snapshot.status, "failed:", snapshot.failedNodes)
end)

-- Individual container opened
EventBus.on("container:open", function(container)
  -- container.id, container.role, container.identity
end)

-- Recovery policy changed
EventBus.on("containers:recovery_policy", function(policy)
  -- policy.state: "SURVIVAL_ONLY", "COMBAT_READY", "FULLY_READY", ...
end)
```

## Configuration Reference

| Setting | Default | Purpose | Safety note |
|---------|---------|---------|-------------|
| `autoOpen` | `false` | Open containers on login | — |
| `windowMode` | `"KEEP_ALL_OPEN"` | Window management policy | Change with caution in large inventories |
| `maxOpenWindows` | `19` | Hard cap on open windows | Never set above server limit |
| `recoveryPolicy` | `"balanced"` | Reconnect behavior preset | — |
| `pauseCaveBotOnRecovery` | `true` | Pause CaveBot during recovery | Disable only if route is safe |
| `pauseTargetBotOnRecovery` | `true` | Pause TargetBot during recovery | Disable only if no combat expected |
| `maxRetries` | `3` | Max retries per failed node | — |
| `ackTimeoutMs` | `5000` | Ack timeout before retry | Increase on high-latency servers |
| `exhaustionBackoffMs` | `1000` | Base backoff on exhaustion | — |
| `quiverMinAmmo` | `50` | Minimum ammo before refill | — |
| `quiverTargetAmmo` | `200` | Target ammo after refill | — |
| `quiverRefillPolicy` | `"fill_to_target"` | Refill policy | — |

## Setup Examples

**Knight:**
```
Main BP: Golden Backpack  [MAIN]
├── Supplies: Beach Bag   [HEALING_SUPPLIES]
│   ├── Great Health Potions
│   └── Great Mana Potions
├── Loot: Beach Bag       [LOOT]
└── Runes: Blue Backpack  [RUNES]
```

**Paladin (deeply nested ammo):**
```
Main BP: Adventurer's Bag    [MAIN]
├── Supplies: Beach Bag      [HEALING_SUPPLIES]
├── Loot: Beach Bag          [LOOT]
├── Ammo Reserve A: Grey BP  [AMMO_RESERVE]
│   └── Ammo Reserve B       [AMMO_RESERVE]
│       └── Ammo Reserve C   [AMMO_RESERVE]
└── Runes: Blue Backpack     [RUNES]

Equipped Quiver              [QUIVER] (auto-detected)
```

After reconnect with TargetBot and CaveBot active:
1. `SURVIVAL_ONLY`: emergency healing and escape active, all combat paused
2. Main BP opens → `ROOTS_READY`
3. Healing supplies indexed → `SURVIVAL_READY`
4. Quiver opens → `QUIVER_READY`
5. Ammo Reserve A opened → traversal continues to B and C → `AMMO_READY`
6. `COMBAT_READY` published → TargetBot resumes with fresh state
7. CaveBot recalculates path from current tile → resumes
8. Remaining traversal (Loot, Runes) continues at low priority → `FULLY_DISCOVERED`

**Sorcerer:**
```
Main BP: Adventurer's Bag   [MAIN]
├── Supplies: Beach Bag     [HEALING_SUPPLIES]
├── Loot: Beach Bag         [LOOT]
└── Runes: Blue Backpack    [RUNES]
    ├── Sudden Death Runes
    └── Magic Wall Runes
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

Benchmarks (10k operations): Queue <1ms, Registry <2ms, State transitions <1ms.

Container discovery runs at LOW priority (25) on UnifiedTick. Critical actions (healing, survival) always take precedence.

## Migration Notes

When upgrading from a version that used slot-number-only role assignment:
1. The bot automatically maps old slot assignments to the new role system
2. If the mapping is ambiguous (two containers with same item type), a warning appears in the Roles subtab
3. The old configuration is backed up before migration
4. Migration is idempotent — safe to run multiple times
5. No user configuration is silently overwritten

Changed defaults:
- `autoOpen` is now `false` by default (was `true` in some previous versions)
- `windowMode` replaces the old `keepOpen` boolean
- Per-role configuration replaces indexed slot numbers

## Troubleshooting

**Not opening all backpacks**
- Verify Auto Open is enabled
- Check assigned roles in Roles subtab
- Wait 3–5 seconds after login (discovery runs at low priority)
- Open Diagnostics subtab and check for failed nodes
- Look for exhaustion events — server may be rate-limiting

**Repeated backpack types cause confusion**
- Two backpacks with the same item ID are intentionally tracked as distinct physical containers
- If role assignment is ambiguous, the bot shows a warning and asks you to identify each
- Use the Container Graph subtab to see how each backpack is classified

**Server exhausted / bot slows down**
- Normal — the bot uses adaptive backoff automatically
- Check Diagnostics → exhaustion event count
- If persistent, increase `ackTimeoutMs` and `exhaustionBackoffMs` in Advanced settings

**Reconnect during hunt: not all containers reopen**
- Check Recovery Policy setting — `Balanced` should recover critical containers within 5–10s
- If TargetBot or CaveBot resume too fast, check `pauseTargetBotOnRecovery` setting
- Check Diagnostics for failed opens — the failed node reason explains what happened

**Quiver not detected**
- Verify character is a Paladin
- Verify quiver is actually equipped (not just in a backpack)
- Check Quiver & Ammo subtab for detection status
- Check Diagnostics for `QUIVER_NOT_FOUND` reason

**Ammo not being moved to quiver**
- Verify compatible ammo type is configured in Quiver & Ammo subtab
- Verify ammo reserve container has the correct role assigned
- Check for `INCOMPATIBLE_AMMO` reason in Diagnostics
- Verify quiver is not full (Quiver & Ammo subtab shows current count)

**Open window limit reached**
- Server supports approximately 19 simultaneous open containers
- Switch to `PIN_CRITICAL_AND_TRAVERSE` window mode
- Or reduce the number of role assignments
- Diagnostics will show a `CONTAINER_LIMIT` warning

**Recovery stuck / spinning**
- Open Diagnostics subtab → check current state machine state
- Look for repeated `RETRY_BACKOFF` or `WAITING_FOR_ACKNOWLEDGEMENT` states
- Use **Retry Failed** button in Overview subtab
- If completely stuck, use **Safely Reset Runtime State** button
- Export diagnostics and check for the root cause

**Degraded readiness**
- Some containers failed but others are available — this is by design
- Check Diagnostics for which nodes failed and their reason codes
- Non-critical failures produce `DEGRADED` readiness; combat can still proceed
- Critical failures (main BP, quiver) produce `FAILED` readiness

## Known Limitations

- Physical container identity relies on generation + path + item type. If the server does not expose unique item IDs, two freshly swapped identical backpacks in the same slot may require one full traversal before being correctly re-identified.
- The maximum open window count depends on the server. The bot defaults to 19. Servers with lower limits need manual configuration.
- Ammo compatibility is determined by configured item type — the bot does not auto-detect compatible ammo types from server data.
- On servers with extreme action rate limiting, discovery may complete in `DEGRADED` mode due to exhaustion timeouts on deeply nested containers.


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
