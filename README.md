# nExBot

![Version](https://img.shields.io/badge/version-4.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Lua](https://img.shields.io/badge/Lua-5.1-purple)

**A high-performance automation bot for OTClientV8 (vBot) and OpenTibiaBR (OTCR) with AI-powered combat, real-time analytics, and intelligent navigation.**

> nExBot runs on both **vBot (OTClientV8)** and **OTCR (OpenTibiaBR)** — the client is auto-detected at startup, no manual configuration needed.

---

## Table of Contents

- [What is nExBot?](#what-is-nexbot)
- [Quick Start](#quick-start)
- [Features](#features)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## What is nExBot?

nExBot is a modular Tibia bot that automates hunting, healing, navigation, and analytics.

### Core Modules

| Module | What it does |
|--------|-------------|
| **HealBot** | Ultra-fast healing (75 ms response) with spells, potions, support buffs, and condition curing |
| **AttackBot** | Automated attack spells and runes with AoE optimization and cooldown management |
| **CaveBot** | Linear waypoint navigation with floor-change safety, field handling, supply refills, and 50+ pre-built routes |
| **TargetBot** | Intelligent targeting with direct spectator scans, priority scoring, AttackStateMachine, and movement |
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

> Load a pre-built config from `cavebot_configs/` for the fastest setup — **50+ routes** are included for popular hunting spots.

### 4. Hunt

Enable CaveBot and TargetBot, press **Start** (`Ctrl+Z`), and monitor progress in **Hunt Analyzer**.

### Note for OT Developers

> **Do NOT place nExBot inside a `mods/` folder or custom mod directory.** The auto-updater requires write access to the user-data `bot/` path — mod folders are read-only at runtime, so updates will fail silently.

See the [Installing guide — Auto-Updater section](docs/INSTALLING.md#%EF%B8%8F-auto-updater--custom-mod-folders-ot-developers) for the full explanation and correct folder setup.

---

## Features

### TargetBot — Intelligent Targeting
- **AttackStateMachine** — sole attack issuer, eliminates attack-once-then-stop bugs
- **Direct spectator scans** — every 100ms, no event cache or monitoring layer (vBot 4.8 hybrid)
- **Priority scoring** — config priority, distance bonus, HP-based finish-kill bonus
- **Movement system** — chase, keep-distance, avoid-attacks, reposition

### CaveBot — Navigation
- **Linear waypoint execution** — strictly follows user-defined waypoints 1→2→3→...→N, no Pure Pursuit lookahead, no blacklist state machine
- **Waypoint recovery** — pathfinding-based stuck detection and recovery; finds the nearest reachable waypoint when pushed off-path or started mid-cave
- **15+ waypoint types** — goto, label, action, buy, sell, lure, standLure, depositor, travel, imbuing, tasker, withdraw
- **50+ pre-built configs** — Asura, Banuta, Demons, Dragons, Hydras, Nagas, and more

### HealBot — Survival
- **75 ms response** — event-driven, cached health data, zero-allocation casting
- **Cascading priority** — multiple spells and potions at different HP/MP thresholds
- **Condition handling** — auto-cure poison, paralyze, burn

### Client Abstraction (ACL)

> The ACL auto-detects vBot vs. OTCR at startup — all game operations use a unified `ClientService` API. OTCR-exclusive features (imbuing, stash, forge, prey, market) are enabled automatically.

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
├── AttackBot ←── TargetBot current target (direct read)
├── CaveBot ←──── 100ms linear waypoint macro
├── TargetBot ←── creature events + Monster AI
│   ├── AttackStateMachine (sole attack issuer)
│   └── creature_attack.lua (movement + spells)
│
└── Hunt Analyzer ←── passive analytics
```

| Pattern | Where |
|---------|-------|
| Event-Driven | EventBus, HealBot |
| State Machine | AttackStateMachine |
| Direct Scan | TargetBot (vBot 4.8 style, every 100ms) |
| BFS Traversal | ContainerOpener, Looting |

---

## Documentation

| Guide | Description |
|-------|-------------|
| Installing | Installation for vBot and OTCR |
| HealBot | Healing spells, potions, conditions |
| AttackBot | Attack spells, runes, AoE optimization |
| CaveBot | Navigation, waypoints, supply management |
| TargetBot | Targeting, combat movement, looting |
| Containers | Container management, quiver system |
| Hunt Analyzer | Session analytics and insights (SmartHunt) |
| Extras & Tools | Safety, equipment, utilities |
| Architecture | Technical design and internals |
| Performance | Optimization and tuning |
| FAQ | Troubleshooting and common questions |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

> Always test your changes on multiple servers before submitting a PR. Follow existing Lua style (2-space indentation) and update docs for notable changes.

---

## License

[MIT License](LICENSE) — see LICENSE file for details.
