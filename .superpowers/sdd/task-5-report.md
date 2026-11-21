# Task 5 Report

## Result

Implemented attack synchronization and lifecycle recovery without changing UI,
navigation, CaveBot, or the legacy `AttackStateMachine`.

## Root cause

`AttackFSM` treated `pcall` success as a successful native attack, so a native
`attack()` returning `false` was accepted. Same-target requests also returned
success without dispatch, and `LOCKED` refreshed confirmation from the stale
red-square selection on every tick. Disappearance had no authoritative FSM
path and could be counted as a kill by the active attack flow.

## Changes

- `targetbot/application/attack_fsm.lua`
  - Separates selected target, command dispatch, client confirmation, and health progress evidence.
  - Rejects explicit false native attack returns.
  - Re-dispatches same targets after connection-generation invalidation.
  - Adds `isProgressing()` and `onConnectionGeneration()`.
  - Adds bounded `STALLED` recovery at 200 ms, 1 s, and 3 s, then releases.
  - Adds disappearance and health-progress event entry points.
  - Keeps disappearance from incrementing kill statistics.
- `targetbot/target_events.lua`
  - Routes target disappearance and health progress to the authoritative FSM.
- `targetbot/target_coordinator.lua`
  - Wires game/login/logout and recovery-pause generations to FSM invalidation.
- `tests/unit/domain/attack_fsm_spec.lua`
  - Adds regression coverage for false returns, reconnect recovery, stale selection, progress evidence, bounded retries, and disappearance.

## TDD evidence

Initial focused run before implementation:

```text
23 successes / 2 failures / 2 errors
```

The failures were the expected missing behaviors: false attack accepted,
missing `onConnectionGeneration`, missing `isProgressing`, and stale state
transitions.

Final focused run:

```text
busted tests/unit/domain/attack_fsm_spec.lua tests/integration/combat_pipeline_spec.lua tests/integration/target_abandonment_spec.lua
29 successes / 0 failures / 0 errors / 0 pending
```

## Self-review

- No files outside the requested target files, listed tests, and report were staged.
- `core/client_lifecycle.lua` was unchanged because its existing generation callback contract was sufficient.
- Native confirmation is no longer refreshed merely because the red square remains selected.
- Recovery is timer-bounded and does not retry on every tick.
- Unrelated pre-existing UI, navigation, and CaveBot changes remain untouched.
