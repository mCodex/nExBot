# nExBot

![Version](https://img.shields.io/badge/version-5.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Lua](https://img.shields.io/badge/Lua-5.1-purple)

Modular Tibia bot for OTClientV8 and OTCR. Auto-detects client at startup.

## Quick Start

1. Copy `nExBot/` into your client's `bot/` directory
2. Open client, press **Ctrl+B**, select nExBot, click **Enable**
3. Configure HealBot (healing), TargetBot (creatures), CaveBot (route)

Install paths:
- **vBot:** `%APPDATA%/OTClientV8/<ServerName>/bot/nExBot`
- **OTCR:** `~/.local/share/<otcr-data>/<ServerName>/bot/nExBot`

## Modules

| Module | Function |
|--------|----------|
| **HealBot** | Spell/potion healing at configurable HP thresholds. 75ms response. |
| **AttackBot** | Attack spell/rune rotation with AoE optimization |
| **CaveBot** | Waypoint navigation, floor-change safety, supply refills, 50+ pre-built routes |
| **TargetBot** | 9-stage priority targeting, Monster Insights AI, movement coordination |
| **Hunt Analyzer** | Session analytics — kills/hr, XP/hr, profit, Hunt Score |
| **Containers** | Event-driven BFS, O(1) operations, generation tracking, quiver management 🎒 |
| **Follow Player** | Party hunt — stays near leader while attacking |
| **Extras** | Anti-RS, alarms, equipment swap, combo system, push max |

## Adaptive Intelligence

nExBot shares combat and navigation context through one bounded intelligence runtime:

- TargetBot evaluates candidates through deterministic proposal arbitration and a hard safety envelope.
- Dynamic Lure, Pull, and wave avoidance use explicit state machines.
- CaveBot preserves route intent across combat pauses, path failures, and recovery.
- Twelve local models learn in `SHADOW` mode without changing actions.
- Replay, calibration, resource tracking, learned navigation costs, and Bot Doctor diagnostics use bounded storage.
- Adaptive tick rates reduce background work while combat and safety paths keep their priority.

Open **nExBot Tactical Intelligence** from the Main tab to inspect lifecycle, targeting, routes, models, replay, resources, and diagnostics.

## Architecture

```
 Loader.lua (entry)
├── ACL (vBot/OTCR detection + adapter)
├── EventBus (event-driven communication)
├── UnifiedTick (single 50ms master timer)
├── UnifiedStorage (per-character JSON persistence)
├── Adaptive Intelligence
│   ├── immutable world snapshot + feature pipeline
│   ├── proposal arbitration + hard safety envelope
│   ├── bounded SHADOW models, replay, calibration, and diagnostics
│   └── adaptive tick and optional-work budgets
│
├── Containers 🎒
│   ├── identity (physical container identity)
│   ├── queue (head/tail FIFO, O(1) dequeue)
│   ├── state_machine (13 states, generation tracking)
│   ├── registry (O(1) lookups, incremental item index)
│   ├── bfs (event-driven traversal)
│   ├── scheduler (UnifiedTick integration)
│   ├── readiness (derived snapshots)
│   ├── quiver (paladin ownership)
│   └── discovery (orchestrator)
│
├── HealBot ←── player:health events
│   └── spell_resolver (conversion functions)
├── AttackBot ←─ TargetBot decisions
│   ├── attack_data (pure data tables)
│   └── attack_analytics (recording functions)
├── CaveBot ←─── 250ms waypoint engine
├── TargetBot ←─ creature events + Monster AI
│   ├── AttackStateMachine (sole attack issuer)
│   ├── Monster Insights (12 AI modules)
│   └── MovementCoordinator (intent voting)
│
└── Hunt Analyzer ←─ passive analytics
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Installing](docs/INSTALLING.md) | Installation for vBot and OTCR |
| [HealBot](docs/HEALBOT.md) | Healing spells, potions, conditions |
| [AttackBot](docs/ATTACKBOT.md) | Attack spells, runes, AoE optimization |
| [CaveBot](docs/CAVEBOT.md) | Navigation, waypoints, supply management |
| [TargetBot](docs/TARGETBOT.md) | Combat AI, Monster Insights, movement |
| [Follow Player](docs/FOLLOW.md) | Party hunt companion |
| [Containers](docs/CONTAINERS.md) | Container management, quiver system |
| [Hunt Analyzer](docs/SMARTHUNT.md) | Session analytics |
| [Extras](docs/EXTRAS.md) | Safety, equipment, utilities |
| [Architecture](docs/ARCHITECTURE.md) | Technical design |
| [Performance](docs/PERFORMANCE.md) | Optimization and tuning |
| [Adaptive Intelligence](docs/INTELLIGENCE.md) | Arbitration, learning, replay, diagnostics, and UI |
| [FAQ](docs/FAQ.md) | Troubleshooting |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `make check` before submitting. Follow existing Lua style (2-space indentation).

## License

[MIT License](LICENSE)
