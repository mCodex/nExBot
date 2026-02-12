# 🤖 nExBot - Next Generation Tibia Bot

<div align="center">

![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![OTClientV8](https://img.shields.io/badge/OTClientV8-compatible-orange.svg)
![OpenTibiaBR](https://img.shields.io/badge/OpenTibiaBR-compatible-brightgreen.svg)
![Lua](https://img.shields.io/badge/Lua-5.1+-purple.svg)
![Performance](https://img.shields.io/badge/Performance-Optimized-brightgreen.svg)

**A high-performance, intelligent automation bot for OTClientV8 and OpenTibiaBR with advanced AI, real-time analytics, and battle-tested reliability**

[🚀 Quick Start](#-quick-start) • [✨ Features](#-features) • [🏗️ How It Works](#-how-it-works) • [📚 Documentation](#-documentation) • [⚙️ Configuration](#-configuration)

</div>

---

## 📋 Table of Contents

- [What is nExBot?](#what-is-nexbot)
- [Quick Start](#-quick-start)
- [Core Features](#-features)
- [How It Works](#-how-it-works)
- [Architecture](#-architecture)
- [Configuration](#-configuration)
- [Performance](#-performance)
- [Advanced Topics](#-advanced-topics)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

## 🎯 What is nExBot?

**nExBot** is a sophisticated, multi-system automation bot for Tibia that combines:

- 🗺️ **CaveBot** - Automated waypoint navigation with intelligent floor detection
- 🎯 **TargetBot** - AI-powered creature targeting with behavior prediction
- 💊 **HealBot** - Ultra-fast healing with spell and potion management
- ⚔️ **AttackBot** - Automated spell and rune attack system
- 📊 **Hunt Analyzer** - Real-time session analytics with insights engine
- 🛡️ **Defense Systems** - Anti-RS protection, condition handling, equipment management

All systems work together seamlessly with a unified event bus, shared analytics, and intelligent decision-making.

> [!NOTE]
> nExBot is designed for **reliability** and **performance**. Every feature is battle-tested with real game scenarios, optimized for minimal CPU impact, and carefully validated for edge cases.

---

## 🚀 Quick Start

### Step 1: Installation

1. **Copy** nExBot folder to:
   ```
   %APPDATA%/OTClientV8/<your-config>/bot/
   ```
   Example: `C:\Users\YourName\AppData\Roaming\OTClientV8\Tibia Realms RPG\bot\nExBot`

2. **Load** in OTClientV8:
   - Open OTClientV8
   - Press `Ctrl+B` to open Bot Settings
   - Select **nExBot** from the bot dropdown
   - Click **Enable**

3. **Verify** it loaded:
   - Check that the bot panels appear in your tabs
   - You should see: Main, Cave, Target tabs

### Step 2: Basic Setup

#### HealBot (Most Important! ⚡)

> [!WARNING]
> Set up HealBot FIRST. Your survival depends on it!

1. Open the **Main** tab
2. Click **Healing** button
3. Add your healing spells:
   - Formula: `exura vita` at 50% HP
   - Formula: `exura` at 30% HP
4. Add healing potions:
   - Item: Great Health Potion at 40% HP
5. Enable **HealBot** switch
6. Test by taking damage

#### CaveBot (Automation)

1. Open **Cave** tab
2. Click **Show waypoints editor**
3. Stand at your starting location
4. Click **Add Goto** to add waypoints
5. Repeat for your hunting route
6. Click Save and name your config
7. Enable **CaveBot** switch

#### TargetBot (Combat)

1. Open **Target** tab
2. Click the **+** button to add monsters
3. Set spell and rune attacks
4. Enable **TargetBot** switch

### Step 3: Start Hunting!

1. Load your CaveBot config
2. Enable CaveBot and TargetBot
3. Click **Start** (Ctrl+Z)
4. Watch your hunting data in **Hunt Analyzer** (Main tab)

---

## ✨ Features

### 🎯 TargetBot - Intelligent Combat System

```
┌─────────────────────────────────────────────────────────────┐
│  INTELLIGENT TARGETING & COMBAT COORDINATION  (v3.0)        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ⚡ AttackStateMachine (SOLE attack issuer)                 │
│  ├─ IDLE → ACQUIRING → CONFIRMING → ATTACKING → RECOVERING │
│  ├─ Only ONE module can issue attacks (no competing issuers)│
│  ├─ Engagement lock prevents target-switching mid-fight     │
│  └─ Configurable reissue interval (1200ms default)         │
│                                                             │
│  📊 9-Stage Priority Scoring (TBI)                         │
│  ├─ Distance, health, tracker data, wave prediction        │
│  ├─ Classification, movement/trajectory, adaptive weights  │
│  ├─ Telemetry correlation, final clamp                     │
│  └─ Scenario-aware stickiness bonuses                      │
│                                                             │
│  🧠 Monster Insights v3.0 (12 SRP modules)                │
│  ├─ Pattern Recognition (static/chase/kite/erratic)        │
│  ├─ Attack Prediction (EWMA cooldown + wave anticipation)  │
│  ├─ Confidence Scoring (0-1 reliability metric)            │
│  ├─ Spell Tracker (missile/cast frequency analysis)        │
│  ├─ Combat Feedback (adaptive accuracy learning)           │
│  └─ Reachability (pathfinding + cache + blocked list)      │
│                                                             │
│  ⚡ Advanced Movement                                       │
│  ├─ Wave Attack Avoidance (front-arc detection)            │
│  ├─ Dynamic Reactivity (volume adaptation)                 │
│  ├─ Tactical Reposition (multi-factor tile scoring)        │
│  ├─ AoE Spell Optimization (calculates best position)      │
│  ├─ Keep Distance (ranged positioning)                     │
│  └─ Anchor System (prevent wandering too far)              │
│                                                             │
│  🛑 Safety Features                                        │
│  ├─ Auto-stop on death                                     │
│  ├─ Low HP warnings                                        │
│  ├─ Trapped detection (no escape routes)                   │
│  └─ Anti-zigzag (engagement lock + scenario awareness)     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Key Abilities:**

- ✅ **Pattern Matching** - Use `*` for any monster, `!` to exclude (e.g., `*, !Dragon`)
- ✅ **Weighted Scoring** - Combines health, distance, and danger into smart priority
- ✅ **Wave Detection** - Predicts group attacks before they happen
- ✅ **Movement Coordination** - Intent-based voting system prevents erratic movement
- ✅ **Spell Optimization** - Finds best position for AoE spells automatically
- ✅ **Behavior Learning** - Recognizes monster patterns (roaming, chasing, luring)

### 🗺️ CaveBot - Intelligent Navigation

```
┌──────────────────────────────────────────────────────────────┐
│  AUTOMATED WAYPOINT NAVIGATION                               │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  🚶 Walking v3.2.0 (Complete Rewrite)                       │
│  ├─ Floor-Change Prevention (never steps on stairs)         │
│  ├─ Field Handling (fire/poison/energy fields)              │
│  ├─ Chunked Walking (15 tiles max per call)                 │
│  ├─ Keyboard Fallback (when autoWalk fails)                 │
│  └─ Stuck Detection (auto-recovery in 3 sec)                │
│                                                              │
│  🛠️ Intelligent Actions                                     │
│  ├─ Auto Door Opening                                       │
│  ├─ Tool Usage (rope, shovel, machete, scythe)             │
│  ├─ Supply Refilling (HP/MP potions)                        │
│  ├─ Loot Depositing (automatic bank routing)                │
│  ├─ Waypoint Jumping (teleporter support)                   │
│  └─ Action Scripting (custom Lua in waypoints)              │
│                                                              │
│  📍 Waypoint Types                                           │
│  ├─ goto (walk to coordinates)                              │
│  ├─ label (mark locations)                                  │
│  ├─ action (custom scripts)                                 │
│  ├─ buy (NPC trading)                                       │
│  ├─ lure (creature pulling)                                 │
│  └─ 15+ more specialized actions                            │
│                                                              │
│  💾 Config Persistence                                       │
│  ├─ Save/Load complete routes                               │
│  ├─ Per-character profiles                                  │
│  ├─ Auto-restore on relog                                   │
│  └─ Multi-floor support                                     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Smart Features:**

- ✅ **Floor-Change Detection** - Validates entire path before walking
- ✅ **Field Navigation** - Automatically walks through damaging fields with keyboard
- ✅ **Waypoint Recovery** - Finds nearest waypoint if stuck
- ✅ **Waypoint Guard** - Skips unreachable waypoints with throttled checks
- ✅ **Pull Integration** - Pauses navigation during TargetBot pulls
- ✅ **Tool Management** - Auto-equips and uses tools
- ✅ **Supply Refilling** - Automatically replenishes potions at depots

### 💊 HealBot - Ultra-Fast Healing

```
┌───────────────────────────────────────────────────────────┐
│  RESPONSIVE HEALING SYSTEM (75ms response time!)           │
├───────────────────────────────────────────────────────────┤
│                                                           │
│  ⚡ Performance                                            │
│  ├─ 75ms spell response (faster than manual!)             │
│  ├─ Cached health data (1 second revalidation)            │
│  ├─ O(1) condition checking (instant lookups)             │
│  └─ Zero-allocation spell casting                         │
│                                                           │
│  📋 Flexibility                                            │
│  ├─ Multiple healing spells (cascading priority)          │
│  ├─ HP/MP triggered spells                                │
│  ├─ Potion support (no backpack needed)                   │
│  ├─ Support spells (mana shield, haste)                   │
│  └─ Condition handlers (poison, paralyze, burn)           │
│                                                           │
│  🛡️ Safeguards                                            │
│  ├─ Won't heal when already full                          │
│  ├─ Respects PvP protection (check PvP flag)              │
│  ├─ Group healing support (friend healer)                 │
│  └─ Mana waste detection (only casts when needed)         │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

**Advanced Options:**

- ✅ **Conditional Spells** - Different spells at different HP thresholds
- ✅ **Potion Priority** - Mix spells and potions optimally
- ✅ **Food Management** - Auto-eat food on timer
- ✅ **Mana Shield** - Automatic protection spell casting
- ✅ **Low Mana Handling** - Fallback to potions when out of mana

### ⚔️ AttackBot - Automated Combat

```
┌────────────────────────────────────────────────────────┐
│  ATTACK AUTOMATION                                     │
├────────────────────────────────────────────────────────┤
│                                                        │
│  🎯 Attack Types                                       │
│  ├─ Single-target spells (targeted attacks)            │
│  ├─ Area spells (group damage)                         │
│  ├─ Runes (no backpack needed!)                        │
│  ├─ Hotkey items (scroll wheels, wands)                │
│  └─ Custom sequences (combo support)                   │
│                                                        │
│  ⚙️ Configuration                                      │
│  ├─ Per-monster spell selection                        │
│  ├─ Mana requirements (won't cast if low)              │
│  ├─ Cooldown management                                │
│  ├─ Danger level thresholds                            │
│  └─ Attack pattern chains                              │
│                                                        │
│  📊 Tracking                                            │
│  ├─ Spell cast counts                                  │
│  ├─ Rune usage tracking                                │
│  ├─ Attack frequency analysis                          │
│  └─ Damage output estimation                           │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### 📊 Hunt Analyzer - Real-Time Analytics

```
┌──────────────────────────────────────────────────────────────┐
│  COMPREHENSIVE SESSION ANALYTICS                             │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  📈 Real-Time Metrics                                        │
│  ├─ XP Rate (XP/hour with peak tracking)                    │
│  ├─ Kill Rate (kills/hour with consistency analysis)        │
│  ├─ Profit Rate (loot value/hour)                           │
│  ├─ Damage Output (damage/hour, efficiency metrics)         │
│  ├─ Stamina Usage (session duration tracking)               │
│  └─ All peaks (best rates achieved)                         │
│                                                              │
│  🎯 Detailed Tracking                                        │
│  ├─ Spell usage counts (individual spells)                  │
│  ├─ Potion usage (ultimate health potion vs regular)        │
│  ├─ Rune usage (sudden death, etc.)                         │
│  ├─ Monster kills (breakdown by type)                       │
│  ├─ Loot items (top 5 drops)                                │
│  └─ Deaths/near-deaths (survivability)                      │
│                                                              │
│  🧠 Intelligent Insights                                     │
│  ├─ Efficiency recommendations                              │
│  ├─ Resource usage analysis                                 │
│  ├─ Survivability warnings                                  │
│  ├─ Equipment suggestions                                   │
│  ├─ Spell selection advice                                  │
│  └─ Confidence scoring (reliability metrics)                │
│                                                              │
│  🏆 Hunt Score (0-100)                                       │
│  ├─ XP Efficiency (25 pts)                                  │
│  ├─ Kill Efficiency (20 pts)                                │
│  ├─ Survivability (25 pts)                                  │
│  ├─ Resource Efficiency (15 pts)                            │
│  ├─ Combat Uptime (10 pts)                                  │
│  └─ Profit Bonus (5 pts)                                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Analytics Features:**

- ✅ **Trend Analysis** - Shows direction indicators (↑ improving, ↓ declining)
- ✅ **Consistency Scoring** - Standard deviation of kill rates
- ✅ **Damage Efficiency** - Damage per spell/rune cast
- ✅ **Time Tracking** - Session duration with stamina breakdown
- ✅ **Economic Analysis** - Profit calculation with loot breakdown
- ✅ **Confidence Metrics** - Reliability score for each insight

### 🛡️ Integrated Safety Systems

```
┌─────────────────────────────────────────────────────────┐
│  PROTECTION & EMERGENCY SYSTEMS                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  🚨 Anti-RS (Rapid Skulling)                            │
│  ├─ Detects PvP flag changes                            │
│  ├─ Auto-unequips weapons                               │
│  ├─ Stops all combat                                    │
│  ├─ Exits game safely                                   │
│  └─ Configurable delays                                 │
│                                                         │
│  ⚠️ Condition Handlers                                  │
│  ├─ Poison detection & cure                             │
│  ├─ Burn effect handling                                │
│  ├─ Paralysis recovery                                  │
│  ├─ Silence/mute prevention                             │
│  └─ Automatic antidote usage                            │
│                                                         │
│  🎽 Equipment Management                                │
│  ├─ Auto-equip spell rings                              │
│  ├─ Weapon switching                                    │
│  ├─ Armour optimization                                 │
│  └─ Belt/amulet swapping                                │
│                                                         │
│  🔌 System Health                                        │
│  ├─ Connection monitoring                               │
│  ├─ Logout on disconnect                                │
│  ├─ Crash recovery                                      │
│  └─ Error logging                                       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🏗️ How It Works

### System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     nExBot Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UNIFIED EVENT BUS                                              │
│  ├─ onWalk (waypoint progress)                                 │
│  ├─ onCreatureHealthChange (damage tracking)                   │
│  ├─ onPlayerHealthChange (healing tracking)                    │
│  └─ onContainerOpen (supply management)                        │
│                                                                 │
│           │                                                     │
│           ├──────────────────┬──────────────────┐              │
│           ▼                  ▼                  ▼               │
│      CaveBot            TargetBot            HealBot            │
│  (Navigation)      (Intelligence)        (Protection)           │
│           │                  │                  │               │
│           └──────────────────┴──────────────────┘              │
│                           │                                     │
│                           ▼                                     │
│                    Hunt Analyzer                                │
│              (Session Analytics)                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Execution Flow

```
GAME TICK (250ms for CaveBot, event-driven for others)
    │
    ├─→ Event Check (health change, creature update)
    │   └─→ HealBot: Evaluate healing need
    │   └─→ TargetBot: Update creature priority
    │   └─→ Hunt Analyzer: Track metrics
    │
    ├─→ CaveBot Tick
    │   ├─ Get next waypoint
    │   ├─ Check walking status
    │   ├─ Validate path (floor-change check)
    │   └─ Execute movement/action
    │
    ├─→ TargetBot Combat (v3.0 attack flow)
    │   ├─ MonsterAI subsystems collect data (EWMA, spells, patterns)
    │   ├─ TBI calculates 9-stage priority for each creature
    │   ├─ Scenario manager enforces engagement lock (anti-zigzag)
    │   ├─ AttackStateMachine (SOLE issuer) manages attack lifecycle
    │   │   ├─ IDLE → ACQUIRING: requestSwitch(creature, priority)
    │   │   ├─ ACQUIRING → CONFIRMING: g_game.attack() sent
    │   │   ├─ CONFIRMING → ATTACKING: server confirmed (getAttackingCreature)
    │   │   └─ ATTACKING → RECOVERING: target dead/gone/unreachable
    │   └─ creature_attack.lua handles chase/positioning/spells
    │
    └─→ HealBot Response
        ├─ Check health thresholds
        ├─ Evaluate mana available
        └─ Execute spell or potion
```

### Data Flow & Integration

```
HealBot Reports Usage        AttackBot Reports Usage
       │                             │
       └─────────────┬───────────────┘
                     │
                     ▼
            Hunt Analyzer Aggregates
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    Session     Metrics      Insights
    Duration    (kills,      (trends,
    (elapsed)   damage,      recommendations)
               loot)
```

---

## ⚙️ Architecture

### Multi-Client Support via ACL (Anti-Corruption Layer)

```
┌────────────────────────────────────────────────────────────────┐
│                  CLIENT ABSTRACTION LAYER                      │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                   ClientService API                      │  │
│  │  Unified interface for ALL client operations             │  │
│  │  - getClient() returns ClientService globally            │  │
│  │  - 100+ abstracted functions                             │  │
│  └─────────────────────────────────────────────────────────┘  │
│                            │                                   │
│                            ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                     ACL Layer                            │  │
│  │  Anti-Corruption Layer for client abstraction            │  │
│  │  - Auto-detects client type at startup                   │  │
│  │  - Loads appropriate adapter                             │  │
│  └─────────────────────────────────────────────────────────┘  │
│                            │                                   │
│           ┌────────────────┴────────────────┐                 │
│           ▼                                 ▼                  │
│  ┌─────────────────┐              ┌─────────────────────────┐ │
│  │   OTCv8 Adapter │              │  OpenTibiaBR Adapter    │ │
│  │                 │              │  - forceWalk            │ │
│  │  Base client    │              │  - stash operations     │ │
│  │  operations     │              │  - imbuement system     │ │
│  │                 │              │  - prey system          │ │
│  │                 │              │  - forge operations     │ │
│  │                 │              │  - market APIs          │ │
│  └─────────────────┘              └─────────────────────────┘ │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### ClientService API Examples

```lua
-- The global getClient() function returns ClientService
local Client = getClient()

-- Basic operations work on both OTCv8 and OpenTibiaBR
local player = Client.getLocalPlayer()
Client.attack(creature)
Client.walk(direction)

-- OpenTibiaBR-specific operations (gracefully degrade on OTCv8)
Client.stashWithdraw(itemId, count)
Client.applyImbuement(slotId, imbuementId, useProtection)
Client.preyAction(slotId, actionType)
Client.forgeFuse(item1, item2, useCore)

-- Event callbacks work uniformly
Client.onCreatureAppear(function(creature) ... end)
Client.onImbuementWindow(function(data) ... end)
Client.onForgeResult(function(result) ... end)
```

### Module Organization

```
nExBot/
├── 📄 _Loader.lua                    # Main entry point - loads everything
│
├── 📁 core/                          # Core libraries & systems
│   ├── 📁 acl/                       # Anti-Corruption Layer
│   │   ├── init.lua                  # Client detection & adapter loading
│   │   ├── compat.lua                # Backward compatibility shim
│   │   └── 📁 adapters/              # Client-specific implementations
│   │       ├── base.lua              # Base adapter (OTCv8)
│   │       └── opentibiabr.lua       # OpenTibiaBR adapter (50+ extra APIs)
│   │
│   ├── client_service.lua            # Unified ClientService API
│   ├── event_bus.lua                 # Centralized event dispatcher
│   ├── lib.lua                       # Utils: Object Pool, Memoization, Shapes
│   ├── bot_database.lua              # Unified item/config database
│   ├── HealBot.lua                   # Healing automation
│   ├── AttackBot.lua                 # Attack automation
│   ├── heal_engine.lua               # Healing algorithm
│   ├── Containers.lua                # Backpack/depot management
│   ├── analyzer.lua                  # Loot tracking
│   ├── smart_hunt.lua                # Hunt Analyzer v3.0 (auto-start CaveBot+TargetBot)
│   └── 20+ other modules
│
├── 📁 cavebot/                       # Navigation system
│   ├── cavebot.lua                   # Main loop (250ms interval)
│   ├── walking.lua                   # v3.2.0 walking engine
│   ├── actions.lua                   # Waypoint action handlers
│   ├── editor.lua                    # Waypoint editor UI
│   ├── doors.lua                     # Door handling
│   ├── tools.lua                     # Tool management (rope, shovel, etc)
│   └── 10+ extension modules
│
├── 📁 targetbot/                     # Combat system
│   ├── target.lua                    # Main targeting loop & UI
│   ├── core.lua                      # Pure utility functions
│   ├── creature_attack.lua           # Movement & combat logic
│   ├── creature_priority.lua         # Target scoring algorithm
│   ├── attack_state_machine.lua      # SOLE attack issuer (state machine)
│   ├── event_targeting.lua           # Event-driven target acquisition
│   ├── movement_coordinator.lua      # Intent-based movement voting
│   │
│   │  ── Monster Insights v3.0 (SRP modules) ──────────────
│   ├── monster_ai_core.lua           # Namespace, helpers, constants
│   ├── monster_patterns.lua          # Pattern persistence & lookup
│   ├── monster_tracking.lua          # Per-creature EWMA learning
│   ├── monster_prediction.lua        # Wave/beam prediction & confidence
│   ├── monster_combat_feedback.lua   # Adaptive targeting weights
│   ├── monster_spell_tracker.lua     # Spell/missile cooldown analysis
│   ├── auto_tuner.lua                # Behaviour classification & tuning
│   ├── monster_scenario.lua          # Scenario detection & engagement locks
│   ├── monster_reachability.lua      # Smart unreachable detection
│   ├── monster_tbi.lua               # 9-stage priority scoring (TBI)
│   ├── monster_ai.lua                # Orchestrator / glue (v3.0 slim)
│   ├── monster_inspector.lua         # Pattern visualization UI
│   └── 5+ other modules
│
├── 📁 cavebot_configs/               # User waypoint scripts (.cfg)
├── 📁 targetbot_configs/             # User creature configs (.json)
├── 📁 nExBot_configs/                # User bot profiles
│
├── 📁 docs/                          # Complete documentation
│   ├── README.md                     # Main reference
│   ├── CAVEBOT.md                    # CaveBot guide
│   ├── TARGETBOT.md                  # TargetBot guide
│   ├── HEALBOT.md                    # HealBot guide
│   ├── SMARTHUNT.md                  # Analytics guide
│   ├── PERFORMANCE.md                # Optimization guide
│   └── FAQ.md                        # Troubleshooting
│
└── 📄 README.md                      # This file
```

### Design Patterns

| Pattern | Purpose | Example |
|---------|---------|---------|
| **Object Pool** | Reuse tables, reduce GC pressure | Path cache entries |
| **LRU Cache** | Bounded memory caches | Creature configs (50 max) |
| **Event-Driven** | Efficient updates | Health changes trigger HealBot |
| **Pure Functions** | Testability & reliability | TargetCore geometry functions |
| **Intent Voting** | Coordinated movement | MovementCoordinator resolves conflicts |
| **Behavior Database** | Pattern learning | MonsterAI tracks creature types |
| **State Machine** | Deterministic attacks | AttackStateMachine (sole issuer) |
| **Engagement Lock** | Anti-zigzag | Scenario.startEngagement prevents target flicker |
| **Multi-Factor Scoring** | Smart decisions | Tile evaluation uses 5+ factors |

---

## ⚡ Performance

nExBot is **heavily optimized** for:

### CPU Efficiency
- 🚀 **250ms CaveBot interval** (vs 500ms for other bots)
- 🚀 **Event-driven HealBot** (only runs on health change)
- 🚀 **Cached player data** (updates once per second)
- 🚀 **LRU cache eviction** (prevents memory bloat)

### Memory Management
```lua
-- Object pooling reduces garbage collection
local pos = nExBot.acquireTable("position")
pos.x, pos.y, pos.z = 100, 200, 7
-- ... use position ...
nExBot.releaseTable("position", pos)  -- Returns to pool

-- Memoization caches expensive function results
local cachedFn = nExBot.memoize(expensiveFunction, 5000)  -- 5s TTL
```

### Startup Time
- **Sanitization**: 15-50ms (fixes sparse arrays)
- **Style Loading**: 10-30ms (batched imports)
- **Core Modules**: 100-200ms (event system, database)
- **Total**: **< 1 second** for full startup

### Benchmarks

| Component | Operation | Speed |
|-----------|-----------|-------|
| HealBot | Health check → spell cast | ~75ms |
| CaveBot | Pathfinding + walking | ~150ms |
| TargetBot | Target evaluation | ~50ms |
| Hunt Analyzer | Metric calculation | ~20ms |
| Monster AI | Behavior prediction | ~10ms |

> [!TIP]
> All metrics are on a mid-range PC. Modern systems will be 2-3x faster!

---

## 📚 Documentation

Complete guides for each system:

| Module | Guide | Topics |
|--------|-------|--------|
| **CaveBot** | [CAVEBOT.md](docs/CAVEBOT.md) | Navigation, walking, waypoints, actions |
| **TargetBot** | [TARGETBOT.md](docs/TARGETBOT.md) | Targeting, combat, behavior AI, optimization |
| **HealBot** | [HEALBOT.md](docs/HEALBOT.md) | Healing spells, potions, conditions |
| **AttackBot** | [ATTACKBOT.md](docs/ATTACKBOT.md) | Spells, runes, attack patterns |
| **Hunt Analyzer** | [SMARTHUNT.md](docs/SMARTHUNT.md) | Analytics, scoring, insights |
| **Performance** | [PERFORMANCE.md](docs/PERFORMANCE.md) | Optimization, profiling, best practices |
| **FAQ** | [FAQ.md](docs/FAQ.md) | Common questions, troubleshooting |

---

## 🔧 Configuration

### HealBot Configuration

```lua
-- Format: formula/item, threshold, priority
HealBot Configuration Example:
├─ Healing Spells:
│  ├─ exura vita at 50% HP (Priority 1)
│  ├─ exura at 30% HP (Priority 2)
│  └─ exura gran at 80% HP (Priority 0 - highest)
│
└─ Healing Potions:
   ├─ Great Health Potion at 40% HP
   └─ Health Potion at 20% HP
```

### TargetBot Configuration

```lua
Creature Format: MONSTER_NAME or ALL or MONSTER_#ID-#ID
Patterns:       *, !exclusion, #100-#150, Dragon King
Priority:       Health, Distance, Danger
```

### CaveBot Waypoints

```
Action Types:
├─ goto X,Y,Z           (walk to position)
├─ label LABEL          (mark location)
├─ action SCRIPT        (execute custom code)
├─ buy ITEM,COUNT,NPC   (trade with NPC)
├─ lure MONSTER,COUNT   (pull creatures)
├─ rope/shovel          (use tool)
├─ travel WAYPOINT      (teleport)
└─ 15+ more actions
```

---

## 🎓 Advanced Topics

### Custom Scripts in CaveBot

```lua
-- Example: Hunt only during green stamina
action() function()
  if Player.staminaInfo().greenRemaining > 0 then
    CaveBot.setOn()
  else
    CaveBot.setOff()
  end
end
```

### Monster Behavior Profiles

```lua
-- MonsterAI learns and remembers patterns:
Monster Type    Behavior        Confidence
Dragon          Chase           0.95
Vampire         Static          0.87
Demon           Kite            0.76
```

### Spell Optimizer Usage

```lua
-- Finds best position for AoE spells:
local recommendation = SpellOptimizer.recommend(
  configuredSpells,
  nearbyMonsters
)

if recommendation.needsMovement then
  Walk(recommendation.optimalTile)
end
```

---

## 🆘 Troubleshooting

> [!WARNING]
> **Bot not loading?**
> 1. Check file path: `%APPDATA%/OTClientV8/<config>/bot/nExBot`
> 2. Verify `_Loader.lua` exists
> 3. Check OTClientV8 version (must be v8+)
> 4. Enable bot debugging: Press `Ctrl+Shift+D`

> [!TIP]
> **Healing not working?**
> 1. HealBot shows red when disabled
> 2. Check formulas are spelled correctly (`exura` not `exra`)
> 3. Add potions as fallback
> 4. Test manually first

> [!TIP]
> **CaveBot stops moving?**
> 1. Check if floor-change detection triggered
> 2. Verify waypoint coordinates are reachable
> 3. Use precision parameter for area waypoints: `1000,1000,7,3`
> 4. Check fields config: `ignoreFields` toggle

> [!NOTE]
> **Performance issues?**
> 1. Reduce TargetBot creature count
> 2. Lower CaveBot interval (not below 100ms)
> 3. Disable Hunt Analyzer if not needed
> 4. Clear old configs (takes memory)
>
> [!TIP]
> **Container/Panel errors** (e.g. `attempt to call global 'isExcludedContainer' (a nil value)` or `minimizeContainer` nil errors):
> - Ensure you have the updated `core/Containers.lua` (v6). Partial or out-of-order edits may cause missing helpers. Replace and restart the client to load the full module.
> - Check logs for `containers:open_all_complete` or missing `container:open` events.

See [FAQ.md](docs/FAQ.md) for more solutions.

---

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Code Standards
- **DRY** - Don't Repeat Yourself
- **KISS** - Keep It Simple & Stupid
- **SRP** - Single Responsibility Principle
- **SOLID** - Object-oriented design principles

### Testing
- Test on multiple servers/servers
- Check edge cases (low mana, trapped, etc)
- Profile performance (use `nExBot.loadTimes`)
- Document changes clearly

### Pull Requests
1. Fork and create feature branch
2. Write clear commit messages
3. Test thoroughly
4. Update relevant docs
5. Submit PR with description

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file

Copyright © 2025 nExBot Contributors

---

## 🎉 Credits

- **Architecture**: Advanced event-driven design with unified decision systems
- **Performance**: Optimized for minimal CPU/memory impact
- **Reliability**: Battle-tested across multiple servers with edge-case handling
- **Community**: Built with feedback from thousands of botters

---

## 📞 Support

- 📖 **Documentation**: Read [docs/](docs/) folder
- ❓ **FAQ**: Check [docs/FAQ.md](docs/FAQ.md)
- 🐛 **Bug Report**: Document the issue clearly and include logs (`client logs`, `lua stack`) and steps to reproduce; attach your `core/Containers.lua` version if reporting container-related issues
- 💡 **Feature Request**: Describe use case and implementation ideas

> [!TIP]
> For OSS contributions: open a small, focused PR and include tests or manual QA steps where possible.

---

<div align="center">

**Made with ❤️ for the Tibia Community**

*nExBot - High-Performance, Intelligent, Reliable* ⚡🤖

</div>
