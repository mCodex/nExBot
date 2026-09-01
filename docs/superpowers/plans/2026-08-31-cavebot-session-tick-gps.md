# CaveBot Session-Tick GPS Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execution note for this repo:** subagent dispatch (`task`) fails with a billing error. Execute INLINE in this session using `superpowers:executing-plans`, one phase (task) at a time, with a test run + `luac -p` + `git diff` between phases, committing per phase.

**Goal:** Make the CaveBot's primary goto movement run through the strict S9 `NavigationSession` (`bridge.tick`) instead of the legacy `goto`→`walkTo` flow, so the player follows the precomputed route graph (the "GPS guide") node-by-node with ack-driven, wall-safer movement — behind a config kill-switch until proven.

**Architecture:** The S9 engine already exists and is well-tested (`navigation/` + `tests/unit/navigation/`, 14 specs, Fake harness). The rewrite is a *wiring* change: the `goto` action callback (`cavebot/actions.lua:444`) currently calls legacy `CaveBot.walkTo`. We make it, when enabled, call `nExBot.Navigation.tick` (via `Session:tick`) and map the `NavigationResult` back onto the same return contract the outer WaypointEngine loop already consumes (`"walking"`/`"retry"`/`true`/`false`). The outer WaypointEngine state machine, combat preemption, and floor-change arrival logic are left intact. A config flag (default OFF) is the kill-switch.

**Tech Stack:** Lua 5.1/LuaJIT, OTClient sandbox (no `require`/`package` at runtime; `legacy_bridge` uses `require` only inside test/fake context), Busted, `luac -p`. `nExBot.Navigation` is the singleton `legacy_bridge` wired in `_Loader.lua`.

## Global Constraints

- **Bounded everything:** no unbounded tables/loops. All caches bounded; all route/waypoint scans bounded by `#route.nodes`.
- **Default profile toolbar must remain authoritative** — do not touch UI/profile logic in this plan.
- **Combat preemption must work:** when the bot is attacking, movement must PAUSE (the session must return `WAITING_BLOCKER` via `ctx.preempted` / `ctx.combatActive`), and resume/re-pause correctly with the chain-kill behavior (from `event_targeting.lua`).
- **Never dispatch toward walls:** strict flags only — no `ignoreNonPathable`/`ignoreNonWalkable` (already enforced in `adapter_otclient` / `path_planner`).
- **Movement smoothness preserved** (no lag/diagonal rubber-banding — the fixes we did prior). The session dispatches keyboard steps near corners/transitions and bounded auto-walk chunks in open areas; do not re-add dampening.
- **Config flag is the kill-switch:** default `OFF`. Flipping it ON must not be able to corrupt the legacy path when OFF.
- **Quality gates:** `luac -p <file>` on every changed Lua file; `busted tests/` runs the full suite (currently 1394 green); `git diff --check`.
- OTClient sandbox: no `require`/`package`/`_G` at runtime in `cavebot/*.lua`; communicate via globals (`nExBot.Navigation`, `CaveBot.Config`). The `navigation/*.lua` modules use `require` and are loaded by `_Loader.lua` via a preload — do NOT add `require` to `cavebot/actions.lua`.

---

### Phase 1 — Config flag + session-tick driver inside the goto callback

**Files:**
- Modify: `cavebot/cavebot.lua` — define the config flag default and accessor.
- Create: `cavebot/session_driver.lua` — a thin, pure-ish driver that turns a `NavigationResult` into the goto callback's return contract. (Placed here so `actions.lua` stays a callback dispatcher.)
- Modify: `cavebot/actions.lua:444` (`goto` callback) — when enabled and route built, use the session driver.
- Test: `tests/unit/navigation/session_driver_spec.lua` (uses existing Fake harness).

**Interfaces:**
- Consumes: `CaveBot.Config.get(name)`; `nExBot.Navigation` (bridge) with `isRouteBuilt()`, `tick(ctx)`; `player` global; `CaveBot.clearWalkingState()`; `CaveBot.delay(ms)`.
- Produces: `SessionDriver.shouldUse(nExBotNav)` → bool; `SessionDriver.tickAndMap(bridge, playerPos, opts)` → `walkResult, blockClass` where `walkResult` ∈ { `"walking"`, `"retry"`, `"nudge"`, `true`, `false` }.

**Step 1 — Add the config flag (default OFF).** In `cavebot/cavebot.lua`, near where other `Config` defaults are registered, add:

```lua
-- ponytail: sessions as primary mover is behind a kill-switch; legacy goto
-- stays the default until the session path is proven in-game.
CaveBot.Config.defaults = CaveBot.Config.defaults or {}
CaveBot.Config.defaults.sessionNav = false
```

Verify there is a `CaveBot.Config.defaults` table or the equivalent existing registration mechanism — read `cavebot/cavebot.lua` Config section first and add the flag using the SAME mechanism (do not invent a second config system). If the config system uses `Config.new("name", default)`, use that instead.

**Step 2 — Write the failing spec.** Create `tests/unit/navigation/session_driver_spec.lua`:

```lua
-- tests/unit/navigation/session_driver_spec.lua
-- SessionDriver: maps a NavigationResult onto the goto callback contract.
local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Bridge = require("navigation.legacy_bridge")
local SD = require("cavebot.session_driver")

describe("SessionDriver", function()
  local world, player, port, bridge
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 13, y = 10, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 20, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player, { onEvent = function() end })
    bridge = Bridge.new({ port = port, owner = "CAVEBOT" })
  end)

  it("maps a dispatched step to 'walking'", function()
    bridge:goTo(B, { playerPos = A })
    local res = bridge:tick(A)
    assert.equals("STEP_DISPATCHED", res.reason)
    local walk, _ = SD.tickAndMap(bridge, A, { preempted = false, combatActive = false })
    assert.equals("walking", walk)
  end)

  it("returns 'retry' when the engine is waiting on a temporary blocker", function()
    -- A creature on B makes the goal temporarily unreachable for a strict path.
    world:spawnCreature(B)
    bridge:goTo(B, { playerPos = A })
    -- Simulate a few ticks; the strict planner refuses the creature tile.
    local walk = SD.tickAndMap(bridge, A, { preempted = false, combatActive = false })
    assert.is_truthy((walk == "retry") or (walk == false))
  end)

  it("reports preemption as 'retry' (never walks during combat)", function()
    bridge:goTo(B, { playerPos = A })
    local walk = SD.tickAndMap(bridge, A, { preempted = true, combatActive = true })
    assert.equals("retry", walk)
  end)
end)
```

**Step 3 — Run the spec, verify it fails** with "module 'cavebot.session_driver' not found":

```bash
busted tests/unit/navigation/session_driver_spec.lua
```

**Step 4 — Write minimal implementation.** Create `cavebot/session_driver.lua`:

```lua
-- cavebot/session_driver.lua
-- Bridges the strict S9 NavigationSession result contract back onto the
-- CaveBot goto callback contract, so the outer WaypointEngine loop can drive
-- the session without knowing anything about it. Pure function of inputs;
-- no OTClient globals (player/game go through the args).
--
-- Result -> callback mapping:
--   STEP_DISPATCHED / EDGE_COMPLETED / TRANSITION_BEGIN -> "walking" (wait ack)
--   WAITING_ACK                                      -> "walking" (still in-flight)
--   WAITING_BLOCKER / FAILED_RETRYABLE / REPLAN      -> "retry"
--   COMPLETED                                        -> true
--   FAILED_TERMINAL                                  -> false
local SessionDriver = {}

local NavStatus = (require and require("navigation.domain").NavStatus) or nil

function SessionDriver.shouldUse(nav)
  if not nav then return false end
  if not nav.isRouteBuilt then return false end
  local ok, built = pcall(nav.isRouteBuilt, nav)
  return ok and built == true
end

function SessionDriver.tickAndMap(bridge, playerPos, opts)
  opts = opts or {}
  local res = bridge:tick({
    playerPos = playerPos,
    combatActive = opts.combatActive or false,
    preempted = opts.preempted or false,
    mapGeneration = opts.mapGeneration,
  })
  if not res then return "retry", "none" end
  local st = res.status
  if st == "COMPLETED" then return true, "none" end
  if st == "FAILED_TERMINAL" then return false, "static" end
  if st == "WAITING_BLOCKER" or st == "FAILED_RETRYABLE" or st == "REPLAN" then
    return "retry", "none"
  end
  -- PROGRESS / WAITING_ACK / ACTION_REQUIRED / TRANSITION_PENDING
  return "walking", "none"
end

return SessionDriver
```

**Step 5 — Run the spec, verify it passes:**

```bash
busted tests/unit/navigation/session_driver_spec.lua
```

Note: adapt assertions if `AdapterFake` names differ (e.g., `freespaceRect`, `spawnCreature`). Read `tests/helpers/fake_otclient.lua` + `navigation/adapter_fake.lua` first and use their real APIs.

**Step 6 — Wire into the goto callback.** In `cavebot/actions.lua` `goto` (line 444), BEFORE the legacy `CaveBot.walkTo(...)` call and AFTER the existing arrival check, insert the session path:

```lua
  -- ========== SESSION-TICK GPS PATH (kill-switch: sessionNav) ==========
  if CaveBot.Config and CaveBot.Config.get and CaveBot.Config.get("sessionNav") then
    local SD = SessionDriver  -- dofile'd once at top of actions.lua
    if SD.shouldUse(nExBot.Navigation) then
      local walk, blockClass = SD.tickAndMap(nExBot.Navigation, playerPos, {
        preempted = (not targetBotAvailable),  -- true when the bot is attacking / manual
        combatActive = (not targetBotAvailable),
      })
      if walk == "walking" or walk == "nudge" then
        if CaveBot.setCurrentWaypointTarget then
          CaveBot.setCurrentWaypointTarget(destPos, precision)
        end
        return "walking"
      elseif walk == "retry" then
        CaveBot.delay(50)
        return "retry"
      elseif walk == true then
        CaveBot.clearWaypointTarget()
        return true
      else
        return false, true
      end
    end
    -- fall through to legacy when no route built
  end
```

Where `SessionDriver` is made available. Because `cavebot/actions.lua` runs in the OTClient sandbox (no `require`), load the driver once near the top of `actions.lua` using the pattern already used for other modules in this repo. Check how `actions.lua` currently references sibling modules (e.g., `TargetBot`, `MovementCoordinator`) — mirror that loading mechanism. If the repo preloads modules onto a global namespace via `_Loader`, add `session_driver` to that preload list in `_Loader.lua` (match how `navigation.legacy_bridge` is preloaded at `_Loader.lua:490`) and reference `nExBot.SessionDriver`.

Determine the correct worker for "is the bot currently attacking / is movement preempted." Grep for the existing combat/pause variable (`targetState.combatActive`, `MovementCoordinator` owner, or `TargetBot` state). Use that source of truth and thread it as `preempted`.

**Step 7 — Quality gates:**

```bash
luac -p cavebot/actions.lua cavebot/session_driver.lua cavebot/cavebot.lua
busted tests/ 2>&1 | grep -E "successes|failures|errors"
git diff --check
```

- [ ] **Commit** (only after all gates pass):
```bash
git add cavebot/session_driver.lua cavebot/actions.lua cavebot/cavebot.lua _Loader.lua tests/unit/navigation/session_driver_spec.lua
git commit -m "feat(cavebot): session-tick GPS driver behind sessionNav kill-switch"
```

---

### Phase 2 — Route lifecycle from the cavebot (build route + edge targeting)

**Files:**
- Modify: `cavebot/cavebot.lua` — ensure `bridge.buildRoute` is called with the full `waypointPositionCache` whenever the focused goto waypoint changes, and that `getNextWaypoint`-driven edge selection targets the correct node.
- Test: extend `tests/unit/navigation/session_driver_spec.lua` or add `tests/unit/navigation/route_lifecycle_spec.lua`.

**Goal:** When `sessionNav` is ON, the bridge holds a route that matches the current cavebot waypoint list and the active edge points toward the currently-focused goto waypoint. This makes movement follow the waypoint corridor (GPS guide).

**Step 1 — Write the failing spec.** Add to `session_driver_spec.lua` (or new spec):

```lua
  it("builds a route from waypoints and targets the focused node", function()
    local wps = {
      { x = 10, y = 10, z = 7 }, { x = 12, y = 10, z = 7 }, { x = 14, y = 10, z = 7 },
    }
    assert.is_true(bridge:buildRoute(wps, 7))
    assert.is_true(SD.shouldUse(bridge))
    -- Player near node 1: getNextWaypoint returns node 1's cacheIndex (1).
    local idx, pos = bridge:getNextWaypoint(A)
    assert.equals(1, idx)
    assert.equals(10, pos.x)
  end)
```

**Step 2 — Run, verify fail** (or pass if already green — in that case the wiring task is trivial and this phase confirms it).

**Step 3 — Wire routing in the cavebot.** In `cavebot/cavebot.lua`, wherever `waypointPositionCache` is built and the focused goto child changes (find the existing `buildWaypointCache` call sites, ~1302 and ~1382), when `sessionNav` is enabled call:

```lua
if CaveBot.Config.get("sessionNav") and nExBot.Navigation
   and type(nExBot.Navigation.buildRoute) == 'function' and playerFloor then
  nExBot.Navigation.buildRoute(waypointPositionCache, playerFloor)
end
```

Wire demand-routing so the route is (re)built only when the focused goto waypoint or the waypoint list changes (bounded: no rebuild every tick). Look for an existing "lastDispatchedChild" or waypoint-cache-invalidation signal (`invalidateWaypointCache`) and rebuild on that signal, with a throttle (e.g., at most once per 500ms) to keep it bounded.

**Step 4 — Verify node targeting in `actions.lua`:** the `goto` callback should drive the session such that the active edge leads to the focused goto node. Confirm `bridge.tick` advances edges via `_selectSuccessor`, so a linear route self-advances. No extra change needed if `getNextWaypoint` + `tick` already handle it (they do — `_selectSuccessor` selects edge+1 on completion). Add a spec asserting the session completes edge 1 then moves to edge 2 after movement.

**Step 5 — Gates + commit** (same commands as Phase 1 Step 7).

---

### Phase 3 — Combat preemption correctness (chain-kill interplay)

**Files:**
- Modify: `cavebot/actions.lua` — feed the correct `preempted`/`combatActive` so the session WAITS (never walks) while attacking, and resumes after combat/chain-kill.
- Test: `tests/unit/navigation/session_driver_spec.lua` — asserts the session returns WAITING_BLOCKER/retry while combatActive, and PROGRESS once combat clears.

**Goal:** When the bot is attacking (or manually moving), the session must not issue movement; when combat ends (including the chain-kill re-acquire where a new target is picked in `checkCombatStatus`), movement must correctly resume only when no reachable monster remains.

**Step 1 — Write failing spec:** In the Fake harness, set `ctx.preempted=true, ctx.combatActive=true` → `tickAndMap` returns `"retry"` (already covered in Phase 1 test). The NEW assertion: after clearing combat (`combatActive=false, preempted=false`) on the same edge, the next `tickAndMap` returns `"walking"` (movement resumes). Write this; it should pass already if the driver is correct — if so, the coding task is wiring the *source* of preempted correctly in `actions.lua` (ties to the real `targetState.combatActive`), which is not unit-testable in isolation; document it as a manual/integration check.

**Step 2 — Wire `preempted` source.** In `actions.lua` goto, replace the placeholder `(not targetBotAvailable)` with the real combat signal. Grep for the authoritative flag (e.g., `EventTargeting`'s `targetState.combatActive`, `TargetBot`'s current state, or `MovementCoordinator.getOwner() ~= "CAVEBOT"`). Set `preempted = movementOwnedByCombat` and `combatActive = same`. Add a `ponytail:` comment naming the source.

**Step 3 — Verify chain-kill interplay:** the chain-kill re-acquire (`event_targeting.lua:reacquireBestRemaining`) calls `acquireTarget` which sets `combatActive=true` and pauses CaveBot. With the session path, when a new target is acquired the next `goto` tick must see `preempted=true` and return `"retry"` (no movement). This is preserved because the outer loop still consults `TargetBot`/combat state. Add a note in code; manual in-game verification.

**Step 4 — Gates + commit.**

---

### Phase 4 — Default-ON cutover (optional hardening, separate decision)

**Files:**
- Modify: `cavebot/cavebot.lua` — flip `sessionNav` default to `true` ONLY after in-game verification.

**Goal:** Make the session the default mover. This is a separate, later decision made after the user tests Phases 1–3 in a real game (stair/ladder/hole/wall scenarios, chain-kill timing). Do NOT flip the default in Phases 1–3. When flipped, keep the legacy path reachable via the same config flag set to false (kill-switch stays available).

**Step 1:** After user confirmation, set `CaveBot.Config.defaults.sessionNav = true`.
**Step 2:** Full suite + gates.
**Step 3:** Commit.

---

## Self-Review

**Spec coverage (user's requirements):**
- "Route-graph as primary path (GPS)" → Phase 1 + 2 drive movement through the route graph via `bridge.tick`.
- "Stair/ladder/hole/wall stuck" and "too inaccurate after last fixes" → the session engine enforces strict step validation, floor-transition edges via coordinator, and exact arrival (no adaptive precision widening). These are the engine's invariants, now applied as the primary mover.
- "More linear and smoother, no lagging/diagonal" → session dispatches keyboard steps at corners/transitions and bounded auto-walk chunks; no dampening re-added.
- "Not all monsters attacked" → already fixed and committed (chain-kill); Phase 3 ensures combat preemption keeps movement silent during attack and resumes correctly.
- Config kill-switch + toolbar authority → default OFF; UI/profile untouched.

**Correctness of the mapping:** The `NavigationResult` statuses map to `"walking"`/`"retry"`/`true`/`false` which the WaypointEngine loop (cavebot.lua:986-1027) already handles. `"retry"` increments `actionRetries` → triggers recovery on persistent failure, matching legacy behavior. `"walking"` doesn't count as a retry, so ack-wait ticks don't spuriously blacklist (matches legacy `"walking"`).

**Test harness dependency:** The spec relies on `tests/helpers/fake_otclient.lua` and `navigation/adapter_fake.lua`. Phase 1 Step 5 explicitly says to read those files and use their real API names — no hardcoded assumptions.

**Type/interface consistency:** `SD.tickAndMap(bridge, playerPos, opts)` → `walkResult, blockClass`. `walkResult` values match the loop's expectations exactly. `bridge:tick(ctx)` accepts `{playerPos, combatActive, preempted, mapGeneration}` per `Session:tick` (session.lua:288). Consistent throughout.

**Realistic risk note:** Phases 1–3 keep the legacy path as the default (kill-switch OFF), so the rewrite never degrades the current behavior until the user flips it and validates in-game. Phase 4 (default-ON) is gated on explicit user confirmation — it is deliberately NOT auto-executed.

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-08-31-cavebot-session-tick-gps.md`.

**Execution:** inline, this session (subagent dispatch is blocked by billing). Execute Phase 1 first, run the full suite + `luac -p` + `git diff --check`, then report and get the go-ahead before Phase 2.
