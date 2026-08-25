# CaveBot

Waypoint navigation, supply management, hunting route automation.

## Quick Start

1. Open **Cave** in the cockpit → **Edit route**
2. Stand at start → **Add Goto**
3. Walk to next → **Add Goto** again
4. Save as `Dragon_Darashia`
5. Toggle CaveBot **ON** → press **Start** (`Ctrl+Z`)

## Waypoint Types

### Movement

| Type | Syntax | Description |
|------|--------|-------------|
| `goto` | `32000,32000,7` or `32000,32000,7,3` | Walk to position (optional precision) |
| `label` | `label:hunt` | Named position marker |
| `gotolabel` | `gotolabel:hunt` | Jump to label |

### Conditional

| Type | Syntax | Description |
|------|--------|-------------|
| `checkSupplies` | `3160,50,refill` | If item < 50, goto label |
| `checkCapacity` | `200,depot` | If cap < 200oz, goto label |
| `posCheck` | — | Check floor/position, branch |

### Town

| Type | Syntax | Description |
|------|--------|-------------|
| `depositor` | — | Deposit all loot |
| `buy` | `3160,200,Eremo` | Buy from NPC |
| `sell` | — | Sell to NPC |
| `bank` | — | Bank operations |

### Tools

| Type | Description |
|------|-------------|
| `rope` | Use rope at position |
| `shovel` | Use shovel at position |
| `machete` | Use machete at position |
| `door` | Open door at position |

### Special

| Type | Syntax | Description |
|------|--------|-------------|
| `lure` | `lure Dragon 1` | Pull creatures before moving |
| `standLure` | — | Wait for creatures to come |
| `action` | `action() function() ... end` | Custom Lua code |
| `travel` | — | Boats, carpets, teleports |
| `imbuing` | — | Apply imbuements (OTCR only) |
| `tasker` | — | Task NPC interaction |
| `withdraw` | — | Withdraw from depot/inbox |

## Walking Engine

### Floor-Change Prevention

Validates every tile. Stops before stairs/ladders/ramps.

### Field Handling

1. Try pathfinding without `ignoreFields`
2. If fails, retry with `ignoreFields = true`
3. Use keyboard stepping to cross field tiles

Enable **"Ignore fields"** in config.

### Chunked Walking

- Paths split into 25-tile max chunks
- autoWalk for paths ≥3 tiles with ≤55% direction changes
- Keyboard stepping for ≤2 tiles

### Step Pipelining

2-step lookahead for smooth animation. Disabled when:
- Direction change >90°
- Floor-change tile within 2 steps
- `canWalkDirection` fails for lookahead

### PathCursor Preservation

Cursor preserved across ticks for same waypoint. Only resets when destination changes.

### Stuck Detection

3 consecutive goto failures → RECOVERING state. Progressive escalation: ignoreCreatures → ignoreFields → blocker attack.

The intelligence route state records route generation, current waypoint, pause reason, path failure, recovery success, and recovery failure. CaveBot still executes its validated waypoint path directly. Combat interruptions pause route dispatch without discarding the destination.

### Pathfinding Strategy

1. Strict (respects PZ, walls)
2. Allow non-pathable
3. Ignore creatures
4. Allow unseen (distance ≤30)
5. Ignore fields (distance ≤30)

Attempts 4–5 skipped for distances >30 tiles.

## Waypoint Advancement

| Result | Meaning | Behavior |
|--------|---------|----------|
| `true` | Success | Advance to next |
| `false` | Failure | Stay, trigger stuck detection (goto) |
| `"retry"` | In progress | Stay, increment retry counter |

## Recovery

```
NORMAL → RECOVERING → (found reachable WP) → NORMAL
                   → (no candidates) → idle, retry every 1s
                   → (5min timeout) → clear blacklists
```

### Path-Validated Scan

1. Collect all WPs within 1.5x `gotoMaxDistance`
2. Validate top 5 with `PathStrategy.findPath()`
3. Always validate 3 closest by distance

### Adaptive Blacklists

```
TTL = 15s * 2^(fail_count - 1), capped at 120s
```

`recordSuccess()` clears all blacklists. 5-minute safety valve clears everything.

### Learned Navigation Costs

Movement outcomes add bounded, decaying penalties to recovery candidates. Models in `SHADOW` record these costs but do not change waypoint ranking. An `ACTIVE` NavigationCostModel can add at most 10 percent of the deterministic distance score. Native path validation still decides whether a tile or waypoint is reachable, and learning cannot replace the configured waypoint order.

### Combat Pause and Resume

Dynamic Lure, Pull, and active combat can pause CaveBot through the shared route state. Each pause carries a reason and generation. Completion resumes the same route when the generation still matches; stale callbacks cannot resume a replaced route.

## Supply Management

```text
label:hunt
  ... hunting ...
  checkSupplies:3160,50,refill
  checkCapacity:200,depot
  gotolabel:hunt

label:refill
  goto NPC
  buy:3160,200,NPC_Name
  gotolabel:hunt

label:depot
  goto depot
  depositor
  bank
  gotolabel:refill
```

## Configuration

| Setting | Default |
|---------|---------|
| Use Delay | 400ms |
| Walk Delay | 100ms |
| Ping Compensation | 0ms |
| Auto Use Tools | ON |
| Ignore Fields | ON |

50+ pre-built configs in `cavebot_configs/`.

## Troubleshooting

**Stops moving:** Enabled? Started (`Ctrl+Z`)? Pull System pausing? ASM active? Coordinates reachable? Door blocking? Fields?

**Stuck at door:** Enable Auto Open Doors, add `door` waypoint, verify door item IDs.

**Wrong floor after teleport:** Add waypoint on each floor.

**Route stays paused:** Open **nExBot Tactical Intelligence**, select **CaveBot Intelligence**, and check the route state and pause reason. Bot Doctor reports disconnected lifecycle or ownership state under **Diagnostics**.

## Profile Switching

CaveBot profile selection is **atomic** and **preserves desired enabled state**:

- Selecting a new profile while **ON** → new profile + ON after successful apply
- Selecting a new profile while **OFF** → new profile + OFF
- Failed validation → previous profile + previous desired state unchanged
- Internal suspension uses inhibitor, not `setOff()` / `setOn()` (does not touch user preference)

### Algorithm

```
1. Validate & canonicalize requested profile name
2. Reject traversal, separators, invalid extension, unsupported chars
3. Resolve exact config file under active root profile
4. Read & parse into temporary model
5. Validate schema & required fields BEFORE touching runtime
6. Capture current selected, desired, effective state
7. Add PROFILE_APPLY inhibitor (no desired-state mutation)
8. Apply config data silently to module + UI
9. Update selected profile in ONE state transaction
10. Flush committed selection
11. Remove PROFILE_APPLY inhibitor
12. Reconcile effective state from desired state
13. Emit ONE consolidated profile-changed event
14. On ANY failure: restore previous validated profile + state
```

The selected profile and desired state are stored in UnifiedStorage per-character:
- `cavebot.selectedConfig` — profile name
- `cavebot.desiredEnabled` — boolean
- `cavebot.revision` — incremented per change
