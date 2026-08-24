# nExBot v5 UI — Dead-Code Removal Report

Every removal lists: item, reason, replacement, and the tests proving safety.
Compatibility code was only removed where usage is proven absent and the
replacement is covered by tests.

## Removed

| Removed item | Reason | Replacement | Tests proving safety |
|---|---|---|---|
| `core/smart_hunt.otui` (`HuntAnalyzerWindow`) | Style-imported by `_Loader.lua` sweep but never instantiated; `core/smart_hunt.lua` is analytics-only and contains no window creation. Orphaned UI. | `ui/modules/intelligence.lua` Hunt Performance page + dashboard aggregates | `tests/unit/ui/modules_spec.lua`, `tests/unit/ui/registry_integration_spec.lua` |
| `targetbot/opentibiabr_targeting.lua` (352 lines) | Zero production references; only a stale comment in `creature_priority.lua` mentioned it. Not in any `_Loader` phase list. | AoE helpers live in `PriorityEngine` | Full suite still green; `tests/unit/domain/priorityEngine_spec.lua` covers scoring |
| `core/antiRs.lua` duplicate macro branch | `if UnifiedTick then macro(...) else macro(...) end` — both branches identical; one macro registered. | Single `macro(50, "AntiRS & Msg", function() end)` | Full suite green; `core/bot_database.lua` macro registry unaffected |
| `core/bot_core/init.lua` empty `onSpellCooldown(function() end)` hook | Dead callback with empty body; hooks nothing. | Removed | Full suite green; cooldown handled by `bot_core/cooldown.lua` |
| `creature_priority.lua` stale comment referencing deleted module | Comment referenced removed file. | Updated doc comment | n/a (comment) |

## Kept (deliberately, with rationale)

| Item | Why kept |
|---|---|
| `navigation/legacy_bridge.lua` | Active production wiring via `_Loader.lua:461-468`; replaces `WaypointNavigator`. Tested by `tests/unit/navigation/legacy_bridge_spec.lua`. |
| Legacy tab-fill UI (`setDefaultTab` + `UI.*` across ~30 modules) | Feature parity requirement: host client tabs remain the fallback entry points while the new shell routes modules progressively. The shell is now the primary surface; legacy surfaces are redirect targets, not duplicated navigation within the shell. |
| `core/cavebot_control_panel.lua` | Active; sets `storage.caveBot.*` flags consumed by `supply_check.lua`. |
| Old intelligence window (`IntelligenceDashboardWindow`) | Reused state binding; the new Intelligence page reads the same `TacticalIntelligence:view()` projection. Removed in a follow-up once the shell page fully supersedes it in-client. |

## Process

- Candidates identified in Phase 1 audit (`docs/ui/feature-map.md`).
- Each candidate verified for zero references before removal.
- Dead code removed only after `make check` (busted) stayed green with the
  replacement in place.
- User configs (`*configs`, `storage/`, `private/`) untouched.
