# nExBot UI — Verified Audit & Feature Map (v5)

This map records each feature's destination in the shell after the headless UI
cutover.

## Runtime model (host constraints)

- nExBot runs inside OTClient's `game_bot` bot module. The host provides:
  `UI.*` (createWindow/createWidget/Button/Label/Separator/TextEdit/DualLabel/
  Config/createMiniWindow), `g_ui.*`, `setDefaultTab`, `modules.game_bot`,
  `modules.game_buttons`, `modules.client_topmenu`, `storage`, `schedule`,
  `macro`.
- nExBot owns one shell mounted in the host bot panel. The old
  `Main/Cave/Target/HP/Tools` content is not created; detailed configuration
  remains in native `MainWindow` dialogs.
- Widget classes (`MainWindow`, `BotSwitch`, `BotButton`, `ComboBox`, ...) come
  from the client stylesheet.
- Workflow landmarks use native Tibia `UIItem` sprites; no icon asset pipeline
  is required.
- Font pipeline is client-owned (`.otfont` + `.png` bitmap atlases). The v5 UI
  uses only approved client font names; the font-rendering workstream is
  **explicitly out of scope** for this iteration.

## Old → new feature map

### CaveBot — `cavebot/`
| Feature | Source | New destination |
|---|---|---|
| Waypoint list + engine | `cavebot/cavebot.lua`, `cavebot/cavebot.otui` | Shell > CaveBot > Routes |
| Waypoint editor (move/edit/remove, action buttons) | `cavebot/editor.lua`, `cavebot/editor.otui` | CaveBot > Routes > Waypoints (editor panel) |
| Auto recorder | `cavebot/recorder.lua` | CaveBot > Auto Recorder |
| Config (ping, walkDelay, tools, doors) | `cavebot/config.lua`, `cavebot/config.otui` | CaveBot > Advanced |
| Extensions: Travel/Doors/BuySupplies/SupplyCheck/SellAll/Depositor/Withdraw/Bank/Lure/StandLure/ClearTile/Tasker/Imbuing/PosCheck | `cavebot/travel.lua` … `cavebot/pos_check.lua` | CaveBot > Advanced (registered actions preserved) |
| Navigation/recovery/obstacles/retry | `navigation/` context + `cavebot/cavebot.lua` WaypointEngine | CaveBot > Navigation + Recovery + Obstacles |
| Control panel (Force Refill / Back&Stop / Trainers / Offline) | `core/cavebot_control_panel.lua` + `.otui` | CaveBot > Supplies integration (rebuilt as actions) |
| Minimap GoTo marks | `cavebot/minimap.lua` | preserved (client integration) |
| Diagnostics (stuck waypoints, recovery state) | `cavebot/cavebot.lua` WaypointEngine | CaveBot > Diagnostics |

### TargetBot — `targetbot/`
| Feature | Source | New destination |
|---|---|---|
| Status/target/danger labels, creature list | `targetbot/target.otui`, `target_coordinator.lua` | Shell > TargetBot > Creatures |
| Creature editor (priority, ranges, toggles) | `targetbot/creature_editor.lua` + `.otui` | TargetBot > Creatures (shared rows) |
| Lure / Dynamic Lure / Pull / Reposition | `targetbot/tactical/*`, `cavebot/lure.lua` | TargetBot > Tactics |
| Wave avoidance, keep distance, chase | `targetbot/attack_waves.lua`, `chase_controller.lua` | TargetBot > Strategy |
| Priority engine | `targetbot/priority_engine.lua`, `creature_priority.lua` | TargetBot > Priorities |
| ML models (shadow) | `targetbot/ml/*` | TargetBot > ML (read-only) |
| Diagnostics | `targetbot/target_coordinator.lua` | TargetBot > Diagnostics |

### Healing — `core/`
| Feature | Source | New destination |
|---|---|---|
| Spell list + item list, profiles 1-5 | `core/HealBot.lua`, `core/HealBot.otui` | Shell > Healing > Health / Mana |
| Emergency thresholds | `core/heal_context.lua` | Healing > Emergency |
| Party/friend healer | `core/HealBot.lua` (FriendHealer), `core/new_healer.otui`, `core/bot_core/friend_healer.lua` | Healing > Party |
| Conditions cure/hold | `core/Conditions.lua` + `.otui` | Healing > Conditions |
| HealEngine | `core/heal_engine.lua` | preserved (domain) |

### Looting & Containers
| Feature | Source | New destination |
|---|---|---|
| Loot list, corpse behavior, max danger/capacity | `targetbot/looting.lua` + `.otui` | Shell > Looting |
| Container manager (auto-open, sort, rename, loot bag, nested BFS) | `core/Containers.lua` + `.otui` | Looting > Containers |
| Depositor stash config | `core/depositer_config.lua` + `.otui` | Looting > Depositor |
| Quiver manager | `core/quiver_manager.lua`, `quiver_label.lua` | Looting > Ammo |

### Supplies
| Feature | Source | New destination |
|---|---|---|
| Item thresholds (min/max/avg), profiles | `core/supplies.lua` + `.otui` | Shell > Supplies |
| Soft boots / stamina / cap / imbue | `core/supplies.lua` | Supplies > Additional |
| BuySupplies / SupplyCheck route actions | `cavebot/buy_supplies.lua`, `supply_check.lua` | Supplies > Route integration (documented) |

### Scripts / Macros / Hotkeys / Tools
| Feature | Source | New destination |
|---|---|---|
| Ingame editor + saved scripts | `core/ingame_editor.lua` | Shell > Scripts |
| Macro registry (on/off persisted) | `core/bot_database.lua` | Scripts > Macros |
| Tools (exchange, levitate, haste, mount, fishing, follow, mana train) | `core/tools.lua` | More > Tools |
| Hotkeys (pushmax, useAll, MW/WG, spy level) | `core/pushmax.lua`, `extras.lua`, `spy_level.lua` | Scripts > Hotkeys |

### Intelligence (Tactical Intelligence)
| Feature | Source | New destination |
|---|---|---|
| Overview / Live Decisions / Monsters / Hunt Performance / Learning / Diagnostics | `core/intelligence/ui/ui_bridge.lua` + `.otui`, `ui_presenter.lua` | Shell > Intelligence (rebuild on shared cards + presenter) |
| Replay export/import | `core/intelligence/observability/replay.lua` | Intelligence > Replay |
| Bot Doctor | `core/intelligence/observability/bot_doctor.lua` | Diagnostics > Bot Doctor |

### Profiles
| Feature | Source | New destination |
|---|---|---|
| Profile dirs 1-10, JSON per module | `core/configs.lua` | Shell > Profiles |
| Character binding / profile switching | `core/configs.lua`, `character_profile_coordinator.lua` | Profiles > Ownership |
| CaveBot/TargetBot configs | `Config.setup` | Profiles (bound config lists) |

### Settings
| Feature | Source | New destination |
|---|---|---|
| Extras panel (all `storage.extras.*` toggles) | `core/extras.lua` + `.otui` | Shell > Settings |
| Theme/density/typography (new) | — | Settings > UI |
| GlobalConfig (tools) | `core/global_config.lua` | Settings > Compatibility |

### Diagnostics
| Feature | Source | New destination |
|---|---|---|
| UnifiedTick diagnostics | `core/unified_tick.lua:getDiagnostics` | Shell > Diagnostics |
| EventBus stats | `core/event_bus.lua` | Diagnostics > Subscriptions |
| Bot Doctor issues | `core/intelligence/observability/bot_doctor.lua` | Diagnostics > Bot Doctor |
| Replay export | `core/intelligence/observability/replay.lua` | Diagnostics > Export |

### Analyzer / SmartHunt / Analytics
| Feature | Source | New destination |
|---|---|---|
| Analyzer mini-windows (hunt/loot/supply/impact/xp/party/drop/cavebot/boss) | `core/analyzer.lua` + `.otui` | Dashboard > Performance + Intelligence > Hunt |
| SmartHunt insights | `core/smart_hunt.lua` | Intelligence > Hunt Performance |
| Bot analytics | `core/bot_core/analytics.lua` | Dashboard aggregates |

## Known dead / orphaned paths
- `core/smart_hunt.otui` — imported but never instantiated (analytics-only module).
- `targetbot/opentibiabr_targeting.lua` — no production references.
- `core/bot_core/init.lua:122-125` — empty `onSpellCooldown` hook.
- `core/antiRs.lua:119-121` — duplicate 50ms macro registration.
- Tab-fill duplication: ~30 modules call `setDefaultTab` + `UI.*`; consolidated by the shell.
