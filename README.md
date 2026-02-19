# nExBot

**A high-performance automation bot for OTClientV8 (vBot) and OpenTibiaBR (OTCR) with AI-powered combat, real-time analytics, and intelligent navigation.**

---

## What is nExBot?

nExBot is a modular Tibia bot that automates hunting, healing, navigation, and analytics. It runs on both vBot (OTClientV8) and OTCR (OpenTibiaBR) — the client is auto-detected at startup, no configuration needed.

### Core Modules

| Module | What it does |
|--------|-------------|
| **HealBot** | Ultra-fast healing (75 ms response) with spells, potions, support buffs, and condition curing |
| **AttackBot** | Automated attack spells and runes with AoE optimization and cooldown management |
| **CaveBot** | Waypoint navigation with floor-change safety, field handling, supply refills, and 50+ pre-built routes |
| **TargetBot** | AI combat with 9-stage priority scoring, behavior learning, wave prediction, and movement coordination |
| **Hunt Analyzer** | Real-time session analytics — kills/hour, XP/hour, profit, Hunt Score, efficiency insights |
| **Containers** | Auto-open, quiver management, and container role assignments |
| **Extras** | Anti-RS, alarms, equipment swapping, conditions, combo system, push max |

---

## Quick Start

### 1. Install

Copy the `nExBot` folder into your client's bot directory:

**vBot (OTClientV8 — Windows):**
```
%APPDATA%/OTClientV8/<ServerName>/bot/nExBot
```

**OTCR (OpenTibiaBR — Linux):**
```
~/.local/share/<otcr-data>/<ServerName>/bot/nExBot
```

See the full [Installing guide](docs/INSTALLING.md) for step-by-step instructions.

### 2. Enable

1. Open the client, log in, press **Ctrl+B**.
2. Select **nExBot** from the bot dropdown and click **Enable**.
3. You should see Main, Cave, and Target tabs.

### 3. Configure

1. **HealBot** — Set healing spells and potions (Main tab → Healing).
2. **TargetBot** — Add monsters to fight (Target tab → +).
3. **CaveBot** — Load a pre-built config or record waypoints (Cave tab → Show Editor).
4. **AttackBot** — Set attack spell rotation (Main tab → AttackBot).

### 4. Hunt

Enable CaveBot and TargetBot, press **Start** (`Ctrl+Z`), and monitor progress in **Hunt Analyzer**.

---

## Highlights

### TargetBot — AI Combat
- **AttackStateMachine** — sole attack issuer, eliminates attack-once-then-stop bugs
- **9-stage TBI priority** — distance, health, danger, wave prediction, adaptive weights
- **Monster Insights** — 12 SRP modules that learn monster behavior in real-time
- **Movement coordination** — intent-based voting resolves wave avoidance, keep-distance, AoE positioning, and chase

### CaveBot — Navigation
- **Walking engine v3.2** — floor-change prevention, chunked walks, field handling, keyboard fallback
- **15+ waypoint types** — goto, label, action, buy, sell, lure, standLure, depositor, travel, imbuing, tasker, withdraw
- **50+ pre-built configs** — Asura, Banuta, Demons, Dragons, Hydras, Nagas, and more

### HealBot — Survival
- **75 ms response** — event-driven, cached health data, zero-allocation casting
- **Cascading priority** — multiple spells and potions at different HP/MP thresholds
- **Condition handling** — auto-cure poison, paralyze, burn

### Client Abstraction (ACL)
- Auto-detects vBot vs. OTCR at startup
- Unified `ClientService` API for all game operations
- OTCR-exclusive features (imbuing, stash, forge, prey, market) enabled automatically

---

## Architecture

```text
_Loader.lua (entry point)
├── ACL (client detection + adapter)
├── EventBus (event-driven communication)
├── UnifiedTick (single 50ms master timer)
├── UnifiedStorage (per-character JSON persistence)
│
├── HealBot ←──── player:health events
├── AttackBot ←── TargetBot decisions
├── CaveBot ←──── 250ms waypoint engine
├── TargetBot ←── creature events + Monster AI
│   ├── AttackStateMachine (sole attack issuer)
│   ├── Monster Insights (12 AI modules)
│   └── MovementCoordinator (intent voting)
│
└── Hunt Analyzer ←── passive analytics
```

| Pattern | Where |
|---------|-------|
| Event-Driven | EventBus, HealBot, TargetBot |
| State Machine | AttackStateMachine |
| Intent Voting | MovementCoordinator |
| LRU Cache | Creature configs, pathfinding |
| Object Pool | Position tables, path entries |
| EWMA | Monster tracking, cooldowns |
| BFS Traversal | ContainerOpener, Looting |
| Burst Detection | Z-change protection |

---

## Documentation

| Guide | Description |
|-------|-------------|
| [Installing](docs/INSTALLING.md) | Installation for vBot and OTCR |
| [HealBot](docs/HEALBOT.md) | Healing spells, potions, conditions |
| [AttackBot](docs/ATTACKBOT.md) | Attack spells, runes, AoE optimization |
| [CaveBot](docs/CAVEBOT.md) | Navigation, waypoints, supply management |
| [TargetBot](docs/TARGETBOT.md) | Combat AI, Monster Insights, movement |
| [Containers](docs/CONTAINERS.md) | Container management, quiver system |
| [Hunt Analyzer](docs/SMARTHUNT.md) | Session analytics and insights |
| [Extras & Tools](docs/EXTRAS.md) | Safety, equipment, utilities |
| [Architecture](docs/ARCHITECTURE.md) | Technical design and internals |
| [Performance](docs/PERFORMANCE.md) | Optimization and tuning |
| [FAQ](docs/FAQ.md) | Troubleshooting and common questions |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Small, focused PRs preferred. Follow existing Lua style (2-space indentation). Test on multiple servers. Update docs for notable changes.

---

## License

MIT License
