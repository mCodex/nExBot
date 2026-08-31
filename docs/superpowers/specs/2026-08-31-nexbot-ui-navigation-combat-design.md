# nExBot UI, Navigation, and Combat Reliability Design

**Status:** Approved design

## Goal

Make nExBot a responsive, beginner-friendly Tibia bot UI with one clear route to each feature, reliable CaveBot movement around transitions and narrow corridors, and authoritative combat ownership so live configured monsters are not abandoned.

## Scope

This is an incremental refactor with three coordinated tracks:

1. Left-panel cockpit and dedicated nExBot workspace.
2. Waypoint approach and floor-transition reliability.
3. Combat ownership and CaveBot progression gating.

The existing `PathStrategy`, `ModuleRegistry`, `WaypointSearch`, design tokens, and test harness remain the foundation. This is not a full rewrite and does not add a second pathfinder or parallel navigation registry.

## UI Design

### Host ownership

- nExBot owns `modules.game_bot.contentsPanel.botPanel` after attachment.
- Host legacy tab navigation and visible profile/config toolbar controls are disabled and hidden.
- Profile selection remains available through the dedicated nExBot workspace, backed by the existing profile/storage contracts.
- Attachment must be retry-safe and must not permanently fall back to a floating controller because of startup ordering.
- Reattachment after host panel rebuild is idempotent and leaves exactly one nExBot controller in the host panel.

### Cockpit

The left panel contains only high-frequency actions:

- Tibia item-sprite shortcuts for CaveBot, TargetBot, Healing, Looting, and Attack.
- Current character/profile summary.
- Truthful engine states with accessible text, not color alone.
- One action to open the dedicated workspace.

The cockpit never renders full configuration forms. It is a shallow shortcut surface with no duplicate feature workflows.

### Workspace

- One dedicated window is the only place for profiles, route editing, targeting rules, advanced healing, loot, settings, diagnostics, and analytics.
- `ModuleRegistry` is the single source of navigation truth.
- Category navigation and contextual page navigation must resolve to one registered module ID.
- Responsive layout uses the existing width/height constraints and switches to compact navigation at narrow widths.
- Data-heavy views use shared table components with stable columns, graceful empty/loading/error states, and incremental row updates where possible.
- Shared component factories own labels, buttons, toggles, status badges, headers, rows, tables, and feedback states.
- Buttons, state buttons, toggles, configure actions, focus states, spacing, and disabled states use the same shared visual and interaction pattern across the cockpit and workspace.
- Basic controls are visible by default; advanced options use progressive disclosure.

## Waypoint Design

Add a small pure policy module at the existing CaveBot seam. It receives waypoint metadata and a lightweight local topology snapshot, then returns a movement policy. The policy distinguishes:

- normal waypoint;
- narrow-corridor or corner approach;
- stair, ladder, hole, rope, and other floor-transition waypoint;
- post-transition recovery.

Normal routes continue using the existing pathfinder and efficient auto-walk dispatch. Transition approaches require exact tile arrival, avoid smoothing across the transition, and use bounded keyboard steps when close. Corridor approaches preserve enough path context to avoid stopping on the wrong side of a turn or transition.

Arrival and advancement are separate decisions. A waypoint may be visually close but must not advance until its policy confirms the required tile, floor, or transition result.

## Combat Ownership

`AttackFSM` is the authoritative owner of target acquisition, attack state, target release, and route blocking because the active attack path already uses it. Existing `AttackStateMachine` consumers must either query a single compatibility facade during migration or be removed only after call-site and test verification.

Required invariants:

- CaveBot consults one combat interface before dispatching or advancing.
- A live configured target owned by combat blocks route progression.
- A live configured monster in the shared detection range blocks route progression while it is actionable or awaiting evaluation.
- The explicit all-blocked/unreachable bypass requires fresh reachability evidence and never relies only on a stale allowance timer.
- A transient `target=nil` event cannot end combat while the authoritative FSM still owns a live target.
- A disappearance event is not counted as a kill without confirmed death or invalidation.
- Detection and targeting ranges come from one source of truth.
- Engagement timestamps are updated at real engagement boundaries or the dependent cache is removed.

## Performance and Network Discipline

- Do not rebuild the whole workspace when only a status fingerprint is unchanged.
- Update table rows by stable key and revision; derive a bounded fingerprint when a producer does not provide one.
- Keep nearby-creature scans single-pass and bounded by the configured detection radius.
- Rate-limit repeated pathfinding, attack commands, and recovery attempts; reuse existing cooldowns and invalidate caches on world/route changes.
- Never add retries that can produce unbounded OTClient calls.
- Every collection, history, cache, timer retry, event batch, and rendered table has an explicit upper bound; overflow follows a documented drop, trim, or stop policy.
- Prefer closures and forward declarations where they make ownership explicit. Do not use recursion, currying, or metaprogramming unless a bounded, tested case is clearer and measurably better.

## Cleanup Rules

- Consolidate duplicated workflow rerender helpers through `ui/modules/workflows/shared.lua`.
- Remove confirmed unused imports and metadata only after repository-wide reference checks.
- Remove dead compatibility paths only after tests prove no supported client depends on them.
- Avoid broad formatting churn and preserve unrelated user worktree changes.

## Testing

Every behavior change begins with a failing focused test. The suite must cover:

- host takeover, startup retry, legacy cleanup, reattachment, and exactly-one-controller ownership;
- narrow workspace layout, compact navigation, Tibia item shortcut rendering, and unique route resolution;
- incremental tables and stable row updates;
- waypoint classification, exact transition arrival, corridor turns, blocked paths, and post-floor recovery;
- authoritative combat blocking, FSM split-brain regression, transient target loss, detection-range consistency, and no false kill on disappearance;
- bounded pathfinding/attack retry behavior and unchanged-state zero-write behavior.

The final quality gate is `make check`, plus focused regression tests for each reported defect and a final diff review.

## Non-goals

- Reimplementing OTClient pathfinding.
- Adding a new UI framework or asset pipeline.
- Rewriting all bot intelligence modules.
- Adding speculative abstractions or unmeasured caches.
- Making the UI web-based; "web-like tables" means responsive, readable data presentation inside the OTClient UI.
