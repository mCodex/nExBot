# nExBot v5 UI — Final Report

## 1. Current UI audit

The v5 branch had no bot-owned shell. UI was tab-fill content (`Main/Cave/
Target/HP/Tools`) via `setDefaultTab` + `UI.*` helpers plus ~15 floating
`MainWindow`/`MiniWindow` dialogs, wired by `_Loader.lua` phase lists.
No module registry, sidebar, or navigation model existed. Verified inventory:
22 `.otui` files, 403 `.lua` files, 5 host tabs, 1 client top-button (analyzer),
1 context-menu hook (`xeno_menu.lua`).

## 2. Font rendering audit

Both clients (OTBR, OTCv8) render text from pre-rendered bitmap glyph atlases
(`.otfont` descriptor + `.png`). Font assets are NOT bundled in this repo; the
client owns `fonts.xml`/`g_fonts`. The repo references 4 approved font names.
**The font-rendering workstream was explicitly skipped per product decision.**
Typography is centralized as a named-style registry over the approved client
fonts; no global filtering change, no sprite impact.

## 3. Verified bottlenecks / code smells

- No module registry; navigation scattered across `_Loader.lua` phase lists.
- Duplicate tab-fill calls in ~30 modules.
- `core/analyzer.lua` updated ~30 labels unconditionally every 500ms.
- `UnifiedTick.register` has no unregister (only `setEnabled`).
- Orphaned UI: `smart_hunt.otui`, `opentibiabr_targeting.lua` (removed).
- Empty `onSpellCooldown` hook (removed); duplicate antiRs macro branch (removed).

## 4. Old → new feature map

See `docs/ui/feature-map.md` (full table; every feature mapped to its source
and shell destination; none removed).

## 5. Final information architecture

Dashboard · CaveBot · TargetBot · Healing · Looting · Supplies · Scripts ·
Intelligence · Profiles · Settings · Diagnostics — one sidebar, one header,
one content/footer model, driven by `ModuleRegistry`.

## 6. Clean Architecture / DDD diagram

See `docs/ui/architecture.md` (presentation/domain boundary; data flow;
view-model contract; command/typed results; lifecycle ownership).

## 7. Design token catalog

`ui/design_system/tokens.lua` (frozen): semantic colors (canvas/base/elevated/
interactive/selected; border subtle/default/strong; text primary/secondary/
muted; accent; success/warning/danger/info/active/paused/disabled/degraded),
spacing `2,4,6,8,12,16,20,24`, radii sm/md/lg, borders subtle/default/strong,
dimensions, density presets, status→color map, typography registry.

## 8. Typography / font strategy

`ui/design_system/typography.lua`: 10 named styles mapped to approved client
font names (`verdana-11px-rounded`, `verdana-11px-monochrome`, `terminus-10px`).
DPI buckets, glyph atlases, and FreeType work are out of scope (skipped).

## 9. Icon inventory & generated assets

56 original SVG icons (24×24, stroke, currentColor): 15 module, 20 action,
15 navigation, 6 status glyphs. Build: `tools/icons/build.mjs` (+`catalog.mjs`)
via `@resvg/resvg-js` → 224 committed PNGs (16/20/24/32px) under
`ui/assets/icons/generated/`. Runtime never converts SVG.

## 10. Shared component inventory

`ui/components/components.lua`: 21 factories (label, button+variants,
iconButton, card, sectionHeader, statusBadge, metricCard, keyValueRow,
toggleRow, checkboxRow, selectRow, inputRow, sliderRow, searchToolbar,
listRow, emptyState, loadingState, errorState, inlineWarning, footerActions,
diagnosticBlock, helpTooltip). All resolve tokens/icons; none read globals.

## 11. Before/after source architecture

- **Before:** no shell; navigation in loader lists; ~15 standalone dialogs;
  per-screen hard-coded colors/fonts.
- **After:** one shell (`ui/shell/`), one registry, one design system, one
  icon registry, one shared component library, 11 module pages with pure
  view models + nil-safe status providers, generation-guarded lifecycle.

## 12. Dead-code removal report

See `docs/ui/removal-report.md` (5 removals with reasons, replacements, and
proving tests).

## 13. Algorithmic complexity review

- Module lookup `Registry.get`: O(1) (keyed map).
- Icon lookup `IconRegistry.resolve`: O(1).
- Status tick: only updates header badge when module revision changes
  (dirty rendering); content rebuilds only on module select.
- Lists: `BoundedList` top-K bounded rendering.
- Timings: `Perf` bounded 256-sample buckets, p95/p99.
- No per-frame UI rebuild; hidden modules do no rendering.

## 14. Performance measurements

Per-module widget creation (measured, 0 domain state):

| Module | widgets | setText |
|---|---|---|
| dashboard | 71 | 45 |
| targetbot | 56 | 34 |
| intelligence | 60 | 36 |
| cavebot | 51 | 30 |
| healing | 54 | 32 |
| looting | 44 | 26 |
| profiles | 40 | 24 |
| supplies | 32 | 18 |
| settings | 30 | 18 |
| scripts | 19 | 11 |
| diagnostics | 44 | 26 |

Bounds: 19–71 widgets / 11–45 text writes per module render; unchanged
revision → zero widget creation on tick.

## 15. Tests added

- `tests/unit/ui/`: module_registry (9), view_model (7), command (8),
  lifecycle (7), tokens (7), design_system (9), icon_registry (7),
  icon_assets (3), components (17), shell (8), dirty_rendering (1),
  bounded_list (4), perf (5), dashboard (6), modules (50),
  registry_integration (7), performance (4).
- New harness: `tests/helpers/widget_harness.lua`.
- **1247 total tests green** (was 1092 before this work).

## 16. Before/after screenshots

Not captured: no runnable client in this environment. Visual fixtures are
provided as deterministic widget-tree assertions (`tests/unit/ui/*`); a
cross-client validation pass must run on real OTBR/OTCv8 builds.

## 17. Cross-client validation

Architecture verified against OTBR + OTCv8 API surface (widget classes, PNG
image loading, `.otui` style import, `loadfile`-based module loading). Live
launch validation on both clients is the required follow-up.

## 18. Migration notes

- Configs untouched; module enable/disable preserved via existing domain
  globals + UnifiedStorage; host tabs remain legacy redirect targets.
- UI scale bucket, density, theme persisted under existing `storage` keys;
  unknown values clamp to defaults.
- Backward compatible: shell opens over existing windows; no global behavior
  change for combat/navigation.

## 19. Remaining risks

1. **In-client validation pending** — OTUI layout/anchor correctness can only
   be confirmed on a real client build; harness covers structure, not layout.
2. `UnifiedTick` lacks `unregister`; lifecycle uses `setEnabled` + generation
   guards as the safe pattern.
3. Legacy tab-fill content still present as redirects (per "shell-first,
   migrate module-by-module"); full removal is a follow-up per module once
   parity is confirmed in-client.
4. `make lint` (luacheck) is broken in this environment (Lua 5.5 vs
   luacheck 1.2 incompatibility) — pre-existing, unrelated to these changes.

## 20. Recommendations

- Run a live validation pass on OTBR + OTCv8 and capture before/after shots.
- Add `UnifiedTick.unregister` for true handler removal.
- Migrate remaining deep config dialogs (HealWindow, Equipper, etc.) into
  shell pages using the shared component library.
- Consider SDF font path only if/when a rendering workstream is approved.
