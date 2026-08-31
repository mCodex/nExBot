# nExBot Reliability Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a responsive nExBot cockpit/workspace, reliable transition-aware CaveBot movement, and authoritative combat gating without duplicate workflows or unbounded client/network work.

**Architecture:** Preserve the existing OTClient adapters and introduce only two deep seams: a pure waypoint movement policy and a single combat ownership query. The UI keeps `ModuleRegistry` as the sole route source and uses shared components for all controls and data views. Independent agents may implement non-overlapping tasks in isolated worktrees; integration changes are reviewed and tested centrally.

**Tech Stack:** Lua 5.1/LuaJIT, OTClient OTUI, Busted, Luacheck, existing `PathStrategy`, `AttackFSM`, `ModuleRegistry`, and `WidgetHarness`.

## Global Constraints

- nExBot owns `modules.game_bot.contentsPanel.botPanel` after attachment.
- Profile selection remains available through the dedicated nExBot workspace, backed by the existing profile/storage contracts.
- `ModuleRegistry` is the single source of navigation truth.
- Normal routes continue using the existing pathfinder and efficient auto-walk dispatch.
- `AttackFSM` is the authoritative owner of target acquisition, attack state, target release, and route blocking.
- Every collection, history, cache, timer retry, event batch, and rendered table has an explicit upper bound; overflow follows a documented drop, trim, or stop policy.
- Every behavior change begins with a failing focused test.
- Never add retries that can produce unbounded OTClient calls.
- Preserve unrelated user worktree changes.

---

## File Map

- `ui/init.lua`: bounded, retry-safe shell attachment.
- `ui/shell/shell.lua`: host ownership, cockpit shortcuts, workspace lifecycle, unique routing.
- `ui/shell/styles.otui`: shared control states, responsive host/workspace geometry.
- `ui/components/components.lua`: shared control factories and visual state patterns.
- `ui/components/table_model.lua`: bounded filtering/fingerprints.
- `ui/components/data_table.lua`: stable-key incremental row updates.
- `ui/modules/workflows/shared.lua`: shared rerender behavior.
- `ui/modules/page.lua`: generic page cleanup.
- `cavebot/waypoint_policy.lua`: pure waypoint classification and movement policy.
- `cavebot/walking.lua`: policy-aware dispatch using existing path strategy.
- `cavebot/actions.lua`: policy-aware arrival and advancement.
- `cavebot/cavebot.lua`: single combat gate before route progress.
- `targetbot/target_coordinator.lua`: authoritative combat facade and bounded live-target scan.
- `targetbot/target_events.lua`: authoritative deferred combat-end validation.
- `targetbot/attack_fsm.lua`: target ownership/release contract if required by tests.
- `tests/helpers/widget_harness.lua`: minimal geometry and ownership assertions.
- `tests/unit/ui/*.lua`: UI regressions.
- `tests/unit/cavebot/*.lua`: pure waypoint regressions.
- `tests/integration/*.lua`: combat/route integration regressions.

## Task 1: Authoritative Combat Ownership

**Files:**
- Modify: `targetbot/target_coordinator.lua`
- Modify: `targetbot/target_events.lua`
- Modify: `cavebot/cavebot.lua`
- Modify: `targetbot/attack_fsm.lua` only if the public query is missing
- Test: `tests/integration/target_abandonment_spec.lua`
- Test: `tests/unit/targetbot/combat_ownership_spec.lua`

**Interfaces:**
- Produce one `TargetBot.CombatOwnership` interface with `isBlockingRoute()`, `getTarget()`, `hasLiveConfiguredTarget()`, and `canReleaseTarget()`.
- Consume the existing `AttackFSM` target/state methods and `TargetBot.Creature.getConfigs()`.
- CaveBot must call only `TargetBot.CombatOwnership.isBlockingRoute()` for combat gating.

- [ ] **Step 1: Write the failing split-brain test.**

Add a test where `AttackFSM` owns a live configured creature while `AttackStateMachine` is idle. Assert `TargetBot.CombatOwnership.isBlockingRoute()` is true and CaveBot does not dispatch the next action.

- [ ] **Step 2: Run the focused test and verify it fails for the split-brain reason.**

Run: `busted tests/unit/targetbot/combat_ownership_spec.lua tests/integration/target_abandonment_spec.lua`

Expected: FAIL because the ownership facade does not exist or CaveBot consults the wrong state machine.

- [ ] **Step 3: Implement the smallest authoritative facade.**

Resolve the current `AttackFSM` target and state once per bounded tick. Return true when the target is live and configured, or when a fresh shared-range scan finds a live configured monster awaiting evaluation. Treat explicit all-blocked evidence as the only bypass. Keep detection range in one constant consumed by both detection and targeting.

- [ ] **Step 4: Make deferred combat end consult the facade.**

Before clearing combat after the grace interval, re-read `CombatOwnership.getTarget()` and `isBlockingRoute()`. A transient client `target=nil` event must not end combat while a live target remains owned. Do not count disappearance as a kill without confirmed death or invalidation.

- [ ] **Step 5: Route CaveBot through the facade.**

Replace direct `AttackStateMachine`/allowance checks in the route gate with the single ownership query. Keep non-combat pull and force-follow behavior explicit and bounded.

- [ ] **Step 6: Add the target-loss, range, and disappearance regressions.**

Cover a live monster at the shared detection edge, transient target loss, confirmed death, disappearance without death, and fresh all-blocked bypass. Assert no attack/path command is issued during blocked states.

- [ ] **Step 7: Run focused tests and commit.**

Run: `busted tests/unit/targetbot/combat_ownership_spec.lua tests/integration/target_abandonment_spec.lua`

Expected: all focused tests pass. Commit only the combat files and tests with message `fix: unify combat ownership for cavebot`.

## Task 2: Transition-Aware Waypoint Policy

**Files:**
- Create: `cavebot/waypoint_policy.lua`
- Modify: `cavebot/walking.lua`
- Modify: `cavebot/actions.lua`
- Modify: `cavebot/cavebot.lua` only for policy state reset if required
- Test: `tests/unit/cavebot/waypoint_policy_spec.lua`
- Test: `tests/unit/cavebot/waypoint_search_spec.lua` if selection behavior changes

**Interfaces:**
- Produce pure `WaypointPolicy.classify(waypoint, topology)` and `WaypointPolicy.forApproach(context)` functions.
- `classify` returns one of `normal`, `corridor`, `transition`, or `recovery`.
- `forApproach` returns bounded values `{ arrivalPrecision, dispatch, maxSteps, allowAdvance }`.
- Consume waypoint metadata, player position, destination position, floor-change detection, and local walkability callbacks. Do not access OTClient globals in the new module.

- [ ] **Step 1: Write failing table-driven policy tests.**

Cover a normal waypoint, a corner in a one-tile corridor, an adjacent stair/ladder/hole, a cross-floor transition, and a post-floor-change recovery. Assert transition policies require exact precision, keyboard dispatch near the tile, and `allowAdvance = false` until the floor result is observed.

- [ ] **Step 2: Run the focused policy test and verify it fails because the module is absent.**

Run: `busted tests/unit/cavebot/waypoint_policy_spec.lua`

Expected: FAIL with the missing module/function error.

- [ ] **Step 3: Implement the pure policy with fixed bounds.**

Use direct conditionals and small lookup tables. Do not use recursion or currying. Classify transitions before normal-distance rules; cap local topology inspection to adjacent tiles and cap approach steps to the existing path limit.

- [ ] **Step 4: Integrate policy into walking dispatch.**

Use existing `PathStrategy` for path search. Disable smoothing and auto-walk crossing for transition approaches. Use keyboard stepping within the close-transition threshold. Preserve existing failure cooldowns and reset policy state on floor changes.

- [ ] **Step 5: Integrate policy into arrival/advance decisions.**

Separate “near destination” from “safe to advance.” Require exact transition tile and expected floor for stairs/ladders/holes. Keep normal waypoint precision behavior unchanged unless the policy identifies a corridor or transition.

- [ ] **Step 6: Add integration regressions for narrow corridors and transitions.**

Use the fake path strategy to assert no smoothing crosses a transition, no broad precision skips an adjacent transition tile, and recovery refocuses after a floor change.

- [ ] **Step 7: Run focused tests and commit.**

Run: `busted tests/unit/cavebot/waypoint_policy_spec.lua tests/unit/cavebot/waypoint_search_spec.lua tests/integration/property_invariants_spec.lua`

Expected: all focused tests pass. Commit with message `fix: make cavebot waypoint approaches transition-aware`.

## Task 3: Host-Owned Cockpit and Workspace UX

**Files:**
- Modify: `ui/init.lua`
- Modify: `ui/shell/shell.lua`
- Modify: `ui/shell/styles.otui`
- Modify: `tests/helpers/widget_harness.lua` only for host geometry/ownership support
- Test: `tests/unit/ui/host_integration_spec.lua`
- Test: `tests/unit/ui/shell_spec.lua`
- Test: `tests/unit/ui/bootstrap_spec.lua`

**Interfaces:**
- Preserve `Shell.show()`, `Shell.select(id)`, `shell:setupHostHooks()`, `shell:isPanelMode()`, and singleton behavior.
- Add only the smallest internal host attachment retry and cockpit shortcut rendering functions.
- Cockpit shortcuts resolve through existing module IDs and `ModuleRegistry`; no second route table.

- [ ] **Step 1: Write failing ownership and routing tests.**

Assert startup attachment retries until `contentsPanel.botPanel` exists, the legacy toolbar/tab navigation is hidden and disabled, exactly one controller remains, all shortcut IDs resolve to registered modules, and configuration opens only in the workspace.

- [ ] **Step 2: Run focused UI tests and verify the new ownership expectations fail.**

Run: `busted tests/unit/ui/host_integration_spec.lua tests/unit/ui/shell_spec.lua tests/unit/ui/bootstrap_spec.lua`

Expected: FAIL for the current one-shot fallback or visible legacy toolbar behavior.

- [ ] **Step 3: Implement bounded host attachment.**

Retry attachment with a fixed attempt count and delay, stop after success or the cap, and keep generation guards. Cleanup must remove only legacy content owned by the host panel while preserving profile state through the profile/storage contract.

- [ ] **Step 4: Render the compact cockpit.**

Use `UIItem` Tibia sprites, shared button/toggle/status styles, explicit text/tooltip labels, and one workspace action. Keep the cockpit content bounded and avoid full forms.

- [ ] **Step 5: Normalize styles and responsive geometry.**

Make cockpit/workspace buttons, state buttons, focus, hover, disabled, spacing, and typography use the same style pattern. Keep existing minimum/maximum window bounds and compact navigation behavior. Ensure anchored children have a single owner and cannot overlap the host panel.

- [ ] **Step 6: Run focused UI tests and commit.**

Run: `busted tests/unit/ui/host_integration_spec.lua tests/unit/ui/shell_spec.lua tests/unit/ui/bootstrap_spec.lua`

Expected: all focused tests pass. Commit with message `feat: make nexbot own the bot cockpit panel`.

## Task 4: Shared Components and Bounded Data Views

**Files:**
- Modify: `ui/components/components.lua`
- Modify: `ui/components/table_model.lua`
- Modify: `ui/components/data_table.lua`
- Modify: `ui/modules/workflows/shared.lua`
- Modify: `ui/modules/page.lua`
- Modify: workflow modules with duplicated rerender helpers
- Test: `tests/unit/ui/components_spec.lua`
- Test: `tests/unit/ui/data_table_spec.lua`

**Interfaces:**
- Preserve existing component factory call shapes.
- `Shared.rerender(parent, renderFn)` remains the common workflow refresh path.
- Table rows use stable keys and bounded revisions/fingerprints.

- [ ] **Step 1: Write failing tests for stable table updates and shared rerender behavior.**

Assert unchanged revisions cause zero widget writes, changed row data updates the existing row, missing revisions produce a bounded deterministic fingerprint, and shared rerender is used by representative workflow modules.

- [ ] **Step 2: Run the focused component tests and verify the failures.**

Run: `busted tests/unit/ui/components_spec.lua tests/unit/ui/data_table_spec.lua`

Expected: FAIL for stale rows, full rebuilds, or duplicated refresh behavior.

- [ ] **Step 3: Consolidate duplicated helpers and control styles.**

Move only identical rerender logic to `workflows/shared.lua`. Keep module-specific rendering in the module. Use one shared visual pattern for buttons and state controls; do not add a generalized component framework.

- [ ] **Step 4: Make table updates stable and bounded.**

Update by stable key, cap visible rows using existing table limits, and fingerprint only the displayed fields when a producer lacks a revision. Avoid sorting/filtering more than once per update.

- [ ] **Step 5: Remove confirmed dead code.**

Delete unused imports and metadata only after repository-wide search confirms no consumers. Keep APIs covered by tests or external compatibility paths.

- [ ] **Step 6: Run focused component tests and commit.**

Run: `busted tests/unit/ui/components_spec.lua tests/unit/ui/data_table_spec.lua`

Expected: all focused tests pass. Commit with message `refactor: share bounded nexbot UI components`.

## Task 5: Integration, Cleanup, and Quality Gate

**Files:**
- Modify only files required by failing integration tests.
- Test: all existing `tests/` suites.
- Check: `Makefile`, `.luacheckrc`, final diff.

- [ ] **Step 1: Run the full quality gate before integration changes.**

Run: `make check`

Record every failure without changing unrelated code.

- [ ] **Step 2: Add only missing cross-track regressions.**

Cover the combined case where a live target is present near a transition waypoint. Assert combat ownership blocks route advance, and after confirmed kill the transition policy still requires exact approach.

- [ ] **Step 3: Run the full quality gate after fixes.**

Run: `make check`

Expected: Luacheck exits 0 and Busted reports 0 failures.

- [ ] **Step 4: Review complexity and network bounds.**

Verify each new loop has a fixed bound, each cache has invalidation, each retry has a cap, and unchanged UI state produces no writes. Search for direct CaveBot checks of `AttackStateMachine` and duplicate route tables.

- [ ] **Step 5: Review the final diff and commit only intended changes.**

Run: `git status --short`, `git diff --check`, `git diff --stat`, and `git diff`.

Preserve the user’s pre-existing modifications and commit the integrated implementation with message `feat: improve nexbot ui navigation and combat reliability`.
