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
│  BotShell (sidebar/header/content/footer)                  │
│  ModuleRegistry · IconRegistry · DesignSystem (tokens)     │
│  Presenter/view-model projection · Commands · Lifecycle    │
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
| `ui/core/` | ModuleRegistry, IconRegistry, ViewModel, CommandDispatcher, Lifecycle, BoundedList, Perf, resolve |
| `ui/design_system/` | tokens (colors/spacing/radii/borders/dimensions), typography, density, status |
| `ui/components/` | shared widget library (buttons, cards, rows, badges, states, lists) |
| `ui/shell/` | BotShell + styles.otui |
| `ui/modules/` | 11 module pages + shared page renderer |
| `ui/assets/icons/` | SVG sources (source of truth) + `generated/*.png` runtime assets |
| `tools/icons/` | Node build pipeline (catalog + build.mjs) |

## View model contract

Every module exposes a versioned snapshot:

```
{ schemaVersion=1, revision, moduleId, generatedAt, state, header, sections, actions, errors }
```

States: `LOADING EMPTY READY DEGRADED ERROR`. Revisions advance only via
`commit()`. Snapshots are frozen copies.

## Registry

`ModuleRegistry` is the single source of truth for navigation. It drives the
sidebar, ordering, icons, availability, status badges, and tests. No hard-coded
navigation lists exist elsewhere.

## Commands

`CommandDispatcher` gives typed results: `{ ok=true, data=... }` or
`{ ok=false, error="CODE" }`. Prerequisites are validated; destructive
commands require explicit confirmation; exceptions are contained.

## Lifecycle

`UiLifecycle` generation tokens guard every delayed callback. Destroying the
shell advances the generation, so stale callbacks no-op. Opening twice returns
the same shell instance.

## Loading

`_Loader.lua` Phase 12 loads `ui/init.lua`, which:
1. creates `nExBot.UI` up front (the namespace must exist before any module
   self-registration runs);
2. loads core/design-system/components/shell modules via `loadfile+call`;
3. registers all 11 modules into ModuleRegistry;
4. registers the icon catalog into IconRegistry;
5. imports `ui/shell/styles.otui`.

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
the sole visible navigation surface: a module sidebar (driven by
ModuleRegistry) on the left, and header/content/footer on the right.

**Legacy tab UI is hidden, not destroyed.** The module engines (CaveBot,
TargetBot, ...) hold direct widget references into their tab panels (e.g.
`CaveBot.actionList = ui.list`) and write to them every tick. Destroying the
tabs would dangle those references and break the engines. Hiding keeps them
running while the shell is the visible surface — the correct shell-first
migration posture.

It auto-attaches shortly after startup (`ui/init.lua`) and re-attaches via
`setupHostHooks()` if the framework rebuilds the panel on reload. The legacy
floating-window path is retained only as a fallback when the host panel is
unavailable (tests). Module page actions dispatch through `ui/core/actions.lua`
to real domain functions; legacy deep config dialogs (HealWindow, creature
editor, etc.) are reachable from the shell's module pages.

## Adding a module

1. `ui/modules/<name>.lua`: implement `viewModel(state)` (pure, testable),
   `statusProvider()` (nil-safe projection), `render(shell, content, lifecycle)`,
   and `register()`.
2. Register in `ui/init.lua` module list + icon catalog list.
3. Add `tests/unit/ui/<name>_spec.lua` (view-model contract) and a case in
   `tests/unit/ui/modules_spec.lua` + `registry_integration_spec.lua`.
4. `make check`.

## Performance

- Registry/icon lookup: O(1) keyed maps.
- Dirty rendering: tick updates only the header badge when revision changes;
  content rebuilds only on module select.
- `BoundedList`: top-K bounded rendering.
- `Perf`: bounded (256-sample) p95/p99 timings for render/tick.
