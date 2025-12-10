# 🤖 nExBot - Next Generation Tibia Bot

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![OTClientV8](https://img.shields.io/badge/OTClientV8-compatible-orange.svg)
![Lua](https://img.shields.io/badge/Lua-5.1+-purple.svg)

**A high-performance automation bot for OTClientV8**

[Features](#-features) • [Architecture](#-architecture) • [Installation](#-installation) • [Performance](#-performance)

</div>

---

## ✨ Features

### 🎯 TargetBot
- **Weighted Target Priority** - Scoring with health, distance, and danger factors
- **Wave Attack Avoidance** - Front-arc detection with dynamic scaling based on monster count
- **Movement Coordinator** - Unified movement with dynamic confidence thresholds
- **Dynamic Reactivity** - More reactive when surrounded (7+ monsters), conservative when few
- **Monster Behavior Analysis** - Pattern recognition and attack prediction
- **Spell Position Optimizer** - Calculates optimal position for AoE spell damage
- **Pull with Pause** - Pauses waypoint walking to maximize exp/hour
- **Tactical Reposition** - Multi-factor tile scoring (escape routes, danger zones, target distance)
- **Dynamic Lure** - Pull more monsters when pack is below threshold
- **Priority Movement System** - Emergency → Safety → Kill → Spell → Distance → Chase
- **Exclusion Patterns** - Use `!` prefix to exclude monsters (e.g., `*, !Dragon`)

### 🧠 Monster Behavior System
- **Behavior Tracking** - Real-time tracking of monster movement patterns
- **Attack Prediction** - Predicts wave attacks based on monster facing and timing
- **Pattern Learning** - Learns monster behavior (static, chase, kite, erratic)
- **Confidence Scoring** - Each prediction includes confidence score (0-1)
- **Extensible Database** - Register known monster patterns for better accuracy

### ⚡ Movement Coordinator
- **Intent-Based Architecture** - Each system registers movement "intents"
- **Dynamic Threshold Scaling** - Thresholds adjust based on monster count
- **Voting System** - Similar intents aggregate, conflicting intents cancel
- **Adaptive Reactivity** - Low thresholds when surrounded, high when safe
- **Strong Anti-Oscillation** - Tracks recent moves, blocks erratic behavior
- **Dynamic Hysteresis** - Less sticky to positions when many monsters nearby
- **Unified Decision Point** - Single coordinated movement execution

### 🗺️ CaveBot  
- **Efficient Execution** - Skips macro ticks when walking (reduces CPU by 60%)
- **Walk State Tracking** - Knows when walking is in progress, prevents redundant pathfinding
- **Waypoint Guard** - Checks CURRENT waypoint (not first), skips unreachable after 3 failures
- **Stuck Detection** - Auto-recovers after 3 seconds of no movement
- **Path Caching** - LRU cache with 2-second TTL and invalidation
- **Pull Integration** - Automatically pauses when TargetBot is pulling
- **Floor Change Prevention** - Detects stairs/ladders to prevent accidental floor changes
- **Native autoWalk** - Uses reliable OTClient pathfinding

### 💊 HealBot
- **75ms Spell Response** - Ultra-fast healing for critical situations
- **Cached LocalPlayer** - 1-second revalidation interval reduces API calls
- **Conditional Stat Updates** - Only writes when values actually change
- **O(1) Condition Checking** - Pre-built lookup tables for instant evaluation
- **Hotkey-Style Potions** - Works without open backpack
- **Auto Eat Food** - Simple 3-minute timer, searches all open containers

### ⚔️ AttackBot
- **Monster Count Caching** - 100ms TTL reduces redundant calculations
- **Attack Entry Caching** - 500ms cache for UI children list
- **Lazy Safety Evaluation** - Only checks PvP/blacklist when needed
- **Hotkey-Style Runes** - All rune types work without open backpack

### 📊 Hunt Analyzer
- **Real-Time Tracking** - XP/hour, kills/hour, profit/hour with peak metrics
- **Trend Analysis** - Rolling window with direction indicators (↑↓→)
- **Confidence Scores** - Statistical confidence for all insights
- **Stamina Tracking** - Session start stamina and time spent
- **Bot Integration** - Pulls data from HealBot and AttackBot
- **Insights Engine** - Recommendations with confidence levels
- **Efficiency Score** - 0-100 weighted score based on multiple factors

### 🛠️ Core Utilities
- **BotCore Module** - Unified statistics, cooldowns, and analytics
- **EventBus** - Centralized event system for decoupled modules
- **Object Pool** - Reusable tables to reduce GC pressure
- **Memoization** - Cache pure function results with optional TTL
- **Multi-Client Support** - Per-character profile persistence

---

## 🏗️ Architecture

### Module Structure

```
nExBot/
├── _Loader.lua              # Main entry point
├── core/                    # Core libraries
│   ├── lib.lua              # Utilities + Object Pool + Memoization + Shapes
│   ├── event_bus.lua        # Centralized event system
│   ├── Containers.lua       # Container panel with slot-based tracking
│   ├── HealBot.lua          # Healing automation
│   ├── AttackBot.lua        # Attack automation
│   └── ...
├── cavebot/                 # CaveBot system
│   ├── cavebot.lua          # Main loop (250ms interval)
│   ├── walking.lua          # Path caching + floor prevention
│   ├── actions.lua          # Waypoint actions
│   └── ...
├── targetbot/               # TargetBot system
│   ├── target.lua           # Creature cache + EventBus + LRU eviction
│   ├── creature_attack.lua  # Movement priority + MovementCoordinator
│   ├── creature_priority.lua # Weighted scoring
│   ├── creature.lua         # Config lookup with LRU cache
│   ├── core.lua             # Pure utility functions (geometry, combat)
│   ├── monster_behavior.lua # Behavior pattern recognition + prediction
│   ├── spell_optimizer.lua  # AoE position optimization
│   ├── movement_coordinator.lua # Intent voting + anti-oscillation
│   └── ...
└── storage/                 # User settings
```

### TargetBot Movement Priority

```
╔═══════════════════════════════════════════════════════════════════════════╗
║      UNIFIED MOVEMENT SYSTEM - Coordinated Movement                       ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  PHASE 1: CONTEXT GATHERING                                               ║
║  ├─ Health status (targetIsLowHealth = health < killUnder)               ║
║  ├─ Trapped detection (no walkable adjacent tiles)                       ║
║  ├─ Anchor position management                                           ║
║  ├─ Path distance calculation                                            ║
║  └─ Monster behavior analysis (patterns, confidence)                     ║
║                                                                           ║
║  PHASE 2: LURE DECISIONS (CaveBot delegation)                            ║
║  ├─ SKIP if target has low health! (prevents abandoning kills)           ║
║  ├─ SKIP if player is trapped                                            ║
║  ├─ pull → shape-based monster counting                                  ║
║  ├─ dynamicLure → target count threshold                                 ║
║  └─ closeLure → legacy support                                           ║
║                                                                           ║
║  PHASE 3: MOVEMENT COORDINATOR (Intent-Based Voting)                      ║
║  ├─ Dynamic scaling based on monster count                               ║
║  ├─ 1. EMERGENCY (0.45→0.23): Critical danger evasion                    ║
║  ├─ 2. WAVE_AVOID (0.70→0.35): Monster attack prediction                 ║
║  ├─ 3. FINISH_KILL (0.65→0.33): Low-health target priority               ║
║  ├─ 4. SPELL_POSITION (0.80→0.56): AoE optimization                      ║
║  ├─ 5. CHASE (0.60→0.51): Close distance to target                       ║
║  └─ 6. KEEP_DISTANCE (0.65→0.46): Ranged positioning                     ║
║       (Thresholds show: base → with 7+ monsters)                         ║
║                                                                           ║
║  FEATURES:                                                                ║
║  • Dynamic reactivity: reactive when surrounded, conservative when safe  ║
║  • Behavior tracking, attack prediction, wave cooldowns                  ║
║  • Position scoring for AoE spells/runes                                 ║
║  • Confidence voting with dynamic hysteresis                             ║
║  • Strong anti-oscillation (3 moves in 2.5s = blocked)                   ║
║                                                                           ║
║  INTEGRATIONS:                                                            ║
║  • anchor respected by: keepDistance, rePosition, chase, faceMonster     ║
║  • targetIsLowHealth checked by: pull, dynamicLure, closeLure            ║
║  • isTrapped checked by: dynamicLure, rePosition                         ║
║  • danger zones considered by: rePosition scoring                        ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### Key Design Patterns

| Pattern | Usage |
|---------|-------|
| **Object Pool** | Path cache entries, position tables |
| **LRU Cache** | Creature configs, path calculations |
| **Event-Driven** | Health/mana changes, creature updates, container opens |
| **Slot Tracking** | Container opening without duplicates |
| **Multi-Factor Scoring** | Tile evaluation for repositioning |
| **Intent Voting** | MovementCoordinator confidence-based decisions |
| **Behavior Analysis** | Monster pattern recognition |
| **Pure Functions** | TargetBotCore geometry/combat utilities |

---

## 📊 Performance

### Optimization Summary

| Component | Technique | Benefit |
|-----------|-----------|---------|
| **CaveBot** | Cached TargetBot refs | Avoid repeated table lookups |
| **CaveBot** | 250ms interval | Responsive yet efficient |
| **HealBot** | Cached LocalPlayer | 1s revalidation vs every tick |
| **HealBot** | Conditional updates | Only write when values change |
| **AttackBot** | Pre-allocated arrays | Zero per-tick allocations |
| **AttackBot** | Unrolled loops | Direct comparisons |
| **TargetBot** | Object pooling | Reuse cache entries |
| **TargetBot** | Multi-factor scoring | Optimal tile selection |
| **TargetBot** | LRU cache eviction | Bounded memory (50 entries) |
| **MonsterAI** | Behavior caching | Pattern reuse per monster type |
| **MovementCoordinator** | Intent deduplication | Reduced decision overhead |
| **Containers** | Slot-based tracking | No infinite loops |
| **Containers** | Event-driven opens | Responsive feedback |

### Memory Management

```lua
-- Object Pool usage
local pos = nExBot.acquireTable("position")
pos.x, pos.y, pos.z = 100, 200, 7
-- ... use pos ...
nExBot.releaseTable("position", pos)

-- Memoization
local cachedFn = nExBot.memoize(expensiveFunction, 5000) -- 5s TTL

-- Shape-based monster counting
local count = getMonstersAdvanced(range, nExBot.SHAPE.CIRCLE)
```

---

## 🚀 Installation

1. **Copy** nExBot folder to:
   ```
   %APPDATA%/OTClientV8/<your-config>/bot/
   ```
2. **Load** in OTClientV8 Bot settings
3. **Configure** via in-game panels

---

## 📝 Recent Changes (v1.0.0)

### Multi-Client Profile Persistence
- **Character-Based Storage** - Each character remembers their own active profiles
- **Supported Bots**: HealBot, AttackBot, CaveBot, TargetBot profiles
- **Auto-Restore** - Profiles automatically load when switching characters

### Hunt Analyzer
- **Complete Rewrite** - Event-driven architecture using EventBus pattern
- **Bot Integration** - Pulls real data from HealBot and AttackBot analytics APIs
- **Damage Output Section** - Tracks damage dealt, damage/hour, damage per kill/attack
- **Detailed Tracking**: Individual spell counts, potion/rune usage, waste detection
- **Survivability Metrics**: Death count, near-death events, lowest HP, damage ratio
- **Insights Engine**: Damage efficiency, attack diversity, resource optimization
- **Efficiency Score** (0-100) with multi-factor scoring

### TargetBot Unified Movement System
- **Complete feature integration**: All features work together seamlessly
- **Three-phase execution**: Context → Lure → Movement
- **Priority-based movement**: Safety → Survival → Distance → Tactical → Melee → Facing
- **Anchor integration**: All movement features respect anchor constraint
- **Low-health protection**: Lure features won't trigger when target is almost dead
- **Trapped detection**: Prevents lure when stuck
- **Higher confidence thresholds**: Conservative movement to reduce oscillation

### Tactical Reposition
- **2-tile search radius** with multi-factor scoring
- **Escape routes** (+15 per walkable tile)
- **Danger zones** (-22 per monster front arc)
- **Target distance** (stay in attack range)
- **Movement cost** (prefer closer tiles)
- **Anchor constraint** (skip tiles outside anchor range)
- **Stay bonus** (+15 for current position)

### Pull Improvements
- **Shape-based counting**: Circle, Square, Diamond, Cross
- **Health check first**: Never abandon low-health targets
- **Visual shape labels**: Slider shows shape name instead of number

### Container Panel
- **Slot-based tracking**: Prevents infinite open/close loops
- **Auto-open on login**: Toggle switch with `onPlayerHealthChange` detection
- **Quiver support**: Opens equipped quiver from right hand slot
- **Improved timing**: 250ms open delay, 400ms verification

### Performance
- CaveBot macro: 1000ms → 250ms with cached function refs
- HealBot: Cached LocalPlayer with conditional stat updates
- AttackBot: Pre-allocated direction arrays, unrolled loops
- TargetBot: Object pooling for path cache entries

### Memory Management
- Added `nExBot.acquireTable/releaseTable` object pool
- Added `nExBot.memoize` for pure function caching
- LRU eviction in creature config cache

---

## 🤝 Contributing

### Guidelines
- **DRY** - Don't Repeat Yourself
- **KISS** - Keep It Simple
- **SRP** - Single Responsibility
- **Cache** - Use TTL-based caching for expensive operations
- **Pool** - Reuse tables instead of creating new ones

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

---

<div align="center">

**Made with ❤️ for the Tibia community**

</div>
