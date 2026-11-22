# nExBot

![Version](https://img.shields.io/badge/version-4.0.0-blue)
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

### Start the Rust engine automatically

Install the per-user startup service once for the bot profile, using a verified engine build that supports `serve`. The installer starts the engine immediately and registers it for OS sign-in. The default Lua profile connects over loopback and authenticates again after a game relog. The Rust bridge currently runs in diagnostic mode.

- [macOS LaunchAgent](tools/macos/README.md)
- [Linux systemd user service](tools/linux/README.md)
- [Windows Task Scheduler](tools/windows/README.md)

### Inspect profiles with the Rust binary

Run these commands against saved profiles while the client is open or closed.

```sh
nexbot-engine inspect-route cavebot_configs/Demon_Alburn.cfg
nexbot-engine inspect-target targetbot_configs/Chicken.json
```

`inspect-route` reports valid waypoints, floor changes and malformed rows with line numbers. Custom actions are counted as data. `inspect-target` reports target priority, matching patterns, chase and distance rules, plus loot items and destination containers. Both commands write JSON to stdout and leave the profiles untouched.

Set `storage.rustTargetRanking = true` in the bot profile to use the Rust ranking for combat targets. The client requires a reply from the last 200 ms and checks that the same reachable creatures, positions, health, scores, path costs and line of sight still apply. The client checks target switches against the profile and uses its Lua ranking when a reply is missing or the snapshot changed.

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

## Architecture

```
 Loader.lua (entry)
├── ACL (vBot/OTCR detection + adapter)
├── EventBus (event-driven communication)
├── UnifiedTick (single 50ms master timer)
├── UnifiedStorage (per-character JSON persistence)
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
| [FAQ](docs/FAQ.md) | Troubleshooting |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `make check` before submitting. Follow existing Lua style (2-space indentation).

## License

[MIT License](LICENSE)
