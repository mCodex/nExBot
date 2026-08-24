# nExBot UI — Design System, Components, Icons, Migration

## Design system

Single source: `ui/design_system/tokens.lua` (frozen, proxy-protected).

- **Colors** — semantic: background (canvas/base/elevated/interactive/selected),
  border (subtle/default/strong), text (primary/secondary/muted),
  accent (primary/hover), success, warning, danger, info, active, paused,
  disabled, degraded.
- **Spacing** — `2, 4, 6, 8, 12, 16, 20, 24`; accessor `sp(step)`.
- **Radii** — sm 2 / md 4 / lg 6. **Borders** — subtle 1 / default 1 / strong 2.
- **Dimensions** — compact footer 32 and min/max viewport bounds.
- **Typography** — `ui/design_system/typography.lua` maps named styles to
  approved client font names. Styles: displayMetric, windowTitle, moduleTitle,
  sectionTitle, body, rowTitle, helper, metadata, badge, mono.
- **Density** — `ui/design_system/density.lua`: default / compact / comfortable;
  row and control sizes resolve through the preset.
- **Status** — `ui/design_system/status.lua`: one canonical color per status
  (OK/ACTIVE/RUNNING=success; PAUSED; WARNING; DEGRADED; ERROR/DANGER; DISABLED).

## Shared components (`ui/components/components.lua`)

`label`, `button` (variants: primary/secondary/ghost/danger; disabled),
`iconButton`, `card`, `sectionHeader`, `statusBadge`, `metricCard`,
`keyValueRow`, `toggleRow`, `checkboxRow`, `selectRow`, `inputRow`,
`sliderRow`, `searchToolbar`, `listRow`, `emptyState`, `loadingState`,
`errorState`, `inlineWarning`, `footerActions`, `diagnosticBlock`,
`helpTooltip`.

Each component: `factory(parent, options)` -> widget (or row handle with
`getSwitch/getInput/getCombo/setValue`). Components resolve colors/fonts/icons
through the design system; they never read domain globals.

## Icon system

- SVG sources: `ui/assets/icons/*.svg` (24×24 viewBox, stroke-based,
  currentColor). Canonical catalog: `tools/icons/catalog.mjs`.
- Build: `node tools/icons/build.mjs` -> `ui/assets/icons/generated/<name>_<size>.png`
  at 16/20/24/32px via `@resvg/resvg-js`. PNGs are committed; runtime never
  converts SVG.
- Registry: `ui/core/icon_registry.lua` — O(1) lookup, safe fallback
  (warning icon), `resolve(id, size)`.
- Adding an icon: add to `catalog.mjs`, run the build script, add to the
  IconRegistry registration list in `ui/init.lua`, add to
  `tests/unit/ui/icon_assets_spec.lua` + `icon_registry_spec.lua`.

## Shell

`ui/shell/shell.lua` replaces the host client's left bot bar with one narrow
hunt cockpit: four engine controls, truthful live telemetry, attention state,
and a compact footer. Advanced pages live behind More; rich configuration and
AI views open in dedicated client windows. One generation-guarded instance
auto-attaches and re-attaches on reload. Legacy tab panels are detached, not
destroyed, so domain engines keep valid widget references. The 250 ms UI tick
re-renders only when the cockpit fingerprint changes.

## Module pages

`ui/modules/cockpit.lua` owns the primary state projection. Compatibility and
advanced modules (dashboard, cavebot, targetbot, healing, looting, supplies,
scripts, intelligence, profiles, settings, diagnostics) provide
`viewModel/statusProvider/render/register` and render through
`ui/modules/page.lua` (shared shape: title + badge + section cards + actions).

## Migration notes

- Configs are untouched: `nExBot_configs/`, `cavebot_configs/`,
  `targetbot_configs/`, `storage/` are never written by the shell.
- Module enable/disable state stays in the existing domain globals and
  `UnifiedStorage` keys; the shell only reads projections.
- Host tab widgets remain alive but detached. Existing editors are the focused
  configuration surfaces; the cockpit does not duplicate their controls.
- Hotkeys, macros, and client-topmenu integration are preserved.
- No global texture filtering changes: the icon/font system only selects asset
  paths and approved font names; game sprite rendering is untouched.

## Supported client matrix

| Client | Widget system | Icons | Fonts |
|---|---|---|---|
| OpenTibiaBR OTClient | OTUI (`UI.*`, `g_ui.*`) | PNG (committed) | client `verdana-11px-rounded` etc. |
| OTCv8 | OTUI (same) | PNG (committed) | client fonts |

## Sandbox note (important for contributors)

OTClient's bot sandbox has **no `_G`**. All `ui/` modules must reference
globals directly (`nExBot`, `g_ui`, `UI`, `player`, `CaveBot`, ...) and
self-register via `if nExBot then nExBot.UI = nExBot.UI or {}; ... end`.
Cross-module deps resolve as `(nExBot and nExBot.UI and nExBot.UI["ui.<name>"])
or (require and require("ui.<name>"))`. See `docs/ui/architecture.md`
("Sandbox constraints").

## Running the quality gate

```
make test      # busted tests/ (all units + integration + performance)
make lint      # luacheck (note: Lua 5.5 + luacheck 1.2 incompatibility in this env)
node tools/icons/build.mjs   # regenerate icons after catalog changes
```
