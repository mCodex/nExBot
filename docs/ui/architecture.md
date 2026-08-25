# nExBot v5 UI Architecture

## Overview

The nExBot UI is a presentation layer (`ui/`) built on the host OTClient
widget system. It follows Clean Architecture within the constraints of the
OTClient sandbox: no `_G`, no `require` (patched loader), `dofile` discards
returns — modules load via `loadfile+call` and self-register into `nExBot.UI`.

```
┌─────────────────────────────────────────────────────────────┐
│  INFRASTRUCTURE (host)                                      │
│  g_ui / UI.* / setDefaultTab / modules.game_bot            │
│  EventBus · UnifiedTick · UnifiedStorage · core/acl        │
├─────────────────────────────────────────────────────────────┤
│  PRESENTATION (ui/)                                        │
│  BotShell (cockpit/content/footer)                         │
│  ModuleRegistry · DesignSystem (tokens)                    │
│  Presenter/view-model projection · Actions · Lifecycle     │
│  Components (shared widget library) · Module pages         │
├─────────────────────────────────────────────────────────────┤
│  DOMAIN (existing bot contexts — untouched)                │
│  Navigation · Combat · Healing · Looting · Supplies        │
│  Profiles · Intelligence · Diagnostics                     │
└─────────────────────────────────────────────────────────────┘
```

## Data flow

```
domain state/events
  -> module statusProvider (bounded projection, nil-safe)
  -> view model (schemaVersion, revision, state, header, sections, actions)
  -> presenter/renderer
  -> shared components -> OTUI widgets

user action:
  widget action -> command -> domain use case -> event/state update -> new revision
```

Widgets never mutate domain globals directly. Modules read domain state only
through `statusProvider()` projections; commands are the only write path.

## Directory layout

| Path | Purpose |
|---|---|
| `ui/core/` | ModuleRegistry, ViewModel, actions, Lifecycle, Perf |
| `ui/design_system/` | tokens (colors/spacing/radii/borders/dimensions), typography, density, status |
| `ui/components/` | shared widget library (buttons, cards, rows, badges, states, lists) |
| `ui/shell/` | BotShell + styles.otui |
| `ui/modules/` | cockpit, embedded workflow pages, and shared page renderer |

## View model contract

Every module exposes a versioned snapshot:

```
{ schemaVersion=1, revision, moduleId, generatedAt, state, header, sections, actions, errors }
```

States: `LOADING EMPTY READY DEGRADED ERROR`. Revisions advance only via
`commit()`. Snapshots are frozen copies.

## Registry

`ModuleRegistry` stores the secondary pages available through More in
deterministic order.

## Lifecycle

`UiLifecycle` generation tokens guard every delayed callback. Destroying the
shell advances the generation, so stale callbacks no-op. Opening twice returns
the same shell instance.

## Loading

`_Loader.lua` Phase 12 loads `ui/init.lua`, which:
1. creates `nExBot.UI` up front (the namespace must exist before any module
   self-registration runs);
2. loads core/design-system/components/shell modules via `dofile`;
3. registers the embedded workflow pages into ModuleRegistry;
4. imports `ui/shell/styles.otui`.

## Sandbox constraints (critical)

OTClient's bot sandbox has **no `_G`** (see `utils/client_helper.lua` — "no _G in
OTClient sandbox") and may not resolve `require("ui.*")` natively. Rules:

- **Never use `_G`** — reference globals directly (`nExBot`, `g_ui`, `UI`,
  `player`, `CaveBot`, ...). This matches the navigation modules
  (`if nExBot and nExBot.Nav then ...`), which provably work in production.
- **Self-register via the plain global**: `if nExBot then
  nExBot.UI = nExBot.UI or {}; nExBot.UI.X = X end`.
- **Resolve cross-module deps** via `(nExBot and nExBot.UI and
  nExBot.UI["ui.<name>"]) or (require and require("ui.<name>"))` — namespace
  first (populated in load order by `ui/init.lua`), `require` as fallback for
  busted. Never call `require("ui.*")` unconditionally.

## Shell

`BotShell` **replaces the host client's left bot bar** (`modules.game_bot.
contentsPanel.botPanel`). It attaches directly into the left panel and becomes
the sole visible navigation surface: a compact hunt cockpit with secondary
pages behind More.

Engine state is headless. Routes, creature rules, profiles, and feature
toggles no longer depend on tab widgets. During attachment the shell destroys
the replaced host content and disables the host tab bar, leaving one nExBot
surface.

It auto-attaches shortly after startup (`ui/init.lua`) and re-attaches via
`setupHostHooks()` if the framework rebuilds the panel on reload. The floating
window path is retained only as a fallback when the host panel is unavailable.
Browser-style history connects workflows and grouped Tools, Safety, Equipment,
Analytics, and Utilities pages. Primary profile, navigation, and supply controls
render inside the scrollable shell; dense auxiliary editors keep their existing
native windows until they expose domain-level editing APIs.

## Adding a module

1. `ui/modules/<name>.lua`: implement `viewModel(state)` (pure, testable),
   `statusProvider()` (nil-safe projection), `render(shell, content, lifecycle)`,
   and `register()`.
2. Register it in the `ui/init.lua` module list.
3. Add its view-model and registry integration tests.
4. `make check`.

## Performance

- Registry lookup: O(1) keyed map.
- Dirty rendering: tick updates only the header badge when revision changes;
  content rebuilds only on module select.
- `Perf`: bounded (256-sample) p95/p99 timings for render/tick.
