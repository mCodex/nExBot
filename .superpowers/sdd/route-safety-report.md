# Route Safety Report

## Scope

Implemented the wall-traversal route-safety slice only. Unrelated UI, combat,
and existing user worktree changes were not modified.

## Findings Fixed

- `StepValidator.canMergeDiagonal` checked only the traversed cardinal tile and
  diagonal destination. It now checks both orthogonal corner tiles.
- `PathStrategy.findPath` accepted malformed or wall-crossing native direction
  arrays. Every returned direction is now structurally and geometrically
  validated, including diagonal corners and destination walkability.
- `PathStrategy.nativePathIsSafe` stopped checking after an invalid direction
  and could dereference missing tile helpers. It now fails closed.
- CaveBot's field loop called raw `walk(d)`. It now validates each exact step
  and dispatches through `PathStrategy.walkStep`.
- CaveBot used keyboard nudge and relaxed searches after strict path failure.
  Those unsafe fallback paths were removed; strict failure returns `false`.
- The OTBR adapter dropped `maxSteps` and shifted the options argument. Its
  `autoWalk(destination, maxSteps, options)` forwarding now matches callers.

## TDD Evidence

Failing focused run before implementation:

```text
15 successes / 5 failures / 0 errors / 0 pending
```

Failures covered diagonal corner rejection, native path validation, raw field
walking, and OTBR argument forwarding.

Passing focused run after implementation:

```text
38 successes / 0 failures / 0 errors / 0 pending
```

Command:

```text
busted tests/unit/navigation/step_validator_spec.lua \
  tests/unit/navigation/route_safety_spec.lua \
  tests/unit/navigation/path_planner_spec.lua \
  tests/unit/navigation/obstacles_spec.lua
```

`git diff --check` passed.

## Verification Limitation

The focused `luacheck` command could not start because the installed Luacheck
1.2.0 loader is incompatible with the installed Lua 5.5 runtime:

```text
luacheck/standards.lua:134: attempt to assign to const variable 'field_name'
```

No code lint result is claimed from that command.

## Changed Files

- `cavebot/walking.lua`
- `utils/path_strategy.lua`
- `core/acl/adapters/opentibiabr.lua`
- `navigation/step_validator.lua`
- `tests/unit/navigation/step_validator_spec.lua`
- `tests/unit/navigation/route_safety_spec.lua`
