# 🤖 nExBot - Next Generation Tibia Bot

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![OTClientV8](https://img.shields.io/badge/OTClientV8-compatible-orange.svg)
![Lua](https://img.shields.io/badge/Lua-5.1+-purple.svg)

**A high-performance, event-driven automation bot for OTClientV8**

[Features](#-features) • [Architecture](#-architecture) • [Installation](#-installation) • [Performance](#-performance)

</div>

---

## ✨ Features

### 🎯 TargetBot
- **Smart Target Priority** - Weighted scoring with health, distance, and danger factors
- **Wave Attack Avoidance** - Front-arc detection with anti-oscillation (300ms cooldown)
- **Smart Pull with Pause** - Pauses waypoint walking to maximize exp/hour (prevents respawn loss)
- **Tactical Reposition** - Multi-factor tile scoring (escape routes, danger zones, target distance)
- **Dynamic Lure** - Pull more monsters when pack is below threshold
- **Priority Movement System** - Safety → Survival → Positioning → Combat
- **Exclusion Patterns** - Use `!` prefix to exclude monsters (e.g., `*, !Dragon`)

### 🗺️ CaveBot  
- **Smart Execution System** - Skips macro ticks when walking (reduces CPU by 60%)
- **Walk State Tracking** - Knows when walking is in progress, prevents redundant pathfinding
- **Smart Waypoint Guard** - Checks CURRENT waypoint (not first), skips unreachable after 3 failures
- **Stuck Detection** - Auto-recovers after 3 seconds of no movement
- **Path Caching** - LRU cache with 2-second TTL and smart invalidation
- **Smart Pull Integration** - Automatically pauses when TargetBot is pulling
- **Floor Change Prevention** - Detects stairs/ladders to prevent accidental floor changes
- **Optimized Pathfinding** - autoWalk first, manual findPath only if needed
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
- **Pre-cached Target Data** - Single target info fetch per tick
- **Conditional Direction Calc** - Only calculates when Rotate is enabled
- **Hotkey-Style Runes** - All rune types work without open backpack
- **Non-Blocking Cooldowns** - No UI freezing

### 📦 Container Panel
- **Auto Open on Login** - Toggle to automatically open all containers when logging in
- **Slot-Based Tracking** - Accurate nested container detection (no infinite loops)
- **Quiver Support** - Opens equipped quiver from right hand slot
- **Purse Support** - Opens purse alongside backpacks
- **Auto Minimize** - Keeps UI clean by minimizing opened containers

### 📊 SmartHunt Analytics v3.0
- **Real-Time Tracking** - XP/hour, kills/hour, profit/hour with peak performance metrics
- **Bot Integration** - Pulls detailed data from HealBot and AttackBot
- **Spell Breakdown** - Shows exact count of each healing and attack spell used
- **Potion/Rune Tracking** - Individual item usage with waste detection
- **Damage Output** - Total damage dealt, damage/hour, avg damage per kill/attack
- **Skill Gains** - Tracks all skill level increases during session
- **Survivability Metrics** - Death count, near-death events, lowest HP, highest damage taken
- **Economic Analysis** - Loot value, waste value, profit balance from Analyzer integration
- **AI Insights Engine** - Intelligent recommendations including damage efficiency analysis
- **Efficiency Score** - 0-100 weighted score based on 4 factor categories
- **Peak Performance** - Tracks best XP/hour and kills/hour achieved

### 🛠️ Core Utilities
- **Object Pool** (`nExBot.acquireTable/releaseTable`) - Reusable tables to reduce GC
- **Memoization** (`nExBot.memoize`) - Cache pure function results with optional TTL
- **EventBus** - Centralized event system for decoupled modules
- **Shape Distance** - Circle/Square/Diamond/Cross distance calculations
- **Multi-Client Support** - Per-character profile persistence (HealBot, AttackBot, CaveBot, TargetBot)

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
│   ├── target.lua           # Creature cache + EventBus
│   ├── creature_attack.lua  # Movement priority system + reposition
│   ├── creature.lua         # Config lookup with LRU cache
│   └── ...
└── storage/                 # User settings
```

### TargetBot Movement Priority

```
╔═══════════════════════════════════════════════════════════════════════════╗
║           UNIFIED MOVEMENT SYSTEM v3 - Feature Integration                ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  PHASE 1: CONTEXT GATHERING                                               ║
║  ├─ Health status (targetIsLowHealth = health < killUnder)               ║
║  ├─ Trapped detection (no walkable adjacent tiles)                       ║
║  ├─ Anchor position management                                           ║
║  └─ Path distance calculation                                            ║
║                                                                           ║
║  PHASE 2: LURE DECISIONS (CaveBot delegation)                            ║
║  ├─ SKIP if target has low health! (prevents abandoning kills)           ║
║  ├─ SKIP if player is trapped                                            ║
║  ├─ smartPull → shape-based monster counting                             ║
║  ├─ dynamicLure → target count threshold                                 ║
║  └─ closeLure → legacy support                                           ║
║                                                                           ║
║  PHASE 3: MOVEMENT PRIORITY                                               ║
║  ├─ 1. SAFETY: avoidAttacks (wave avoidance)                             ║
║  ├─ 2. SURVIVAL: Chase low-health targets (override all)                 ║
║  ├─ 3. DISTANCE: keepDistance (ranged positioning + anchor)              ║
║  ├─ 4. TACTICAL: rePosition (better tile + anchor)                       ║
║  ├─ 5. MELEE: chase (close gap + anchor)                                 ║
║  └─ 6. FACING: faceMonster (diagonal correction + anchor)                ║
║                                                                           ║
║  INTEGRATIONS:                                                            ║
║  • anchor respected by: keepDistance, rePosition, chase, faceMonster     ║
║  • targetIsLowHealth checked by: smartPull, dynamicLure, closeLure       ║
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

### SmartHunt Analytics v3.0
- **Complete Rewrite** - Event-driven architecture using EventBus pattern
- **Bot Integration** - Pulls real data from HealBot and AttackBot analytics APIs
- **Damage Output Section** - Tracks damage dealt, damage/hour, damage per kill/attack
- **Detailed Tracking**: Individual spell counts, potion/rune usage, waste detection
- **Survivability Metrics**: Death count, near-death events, lowest HP, damage ratio
- **AI Insights Engine**: Damage efficiency, attack diversity, resource optimization
- **Efficiency Score** (0-100) with multi-factor scoring

### TargetBot Unified Movement System v3
- **Complete feature integration**: All features work together seamlessly
- **Three-phase execution**: Context → Lure → Movement
- **Priority-based movement**: Safety → Survival → Distance → Tactical → Melee → Facing
- **Anchor integration**: All movement features respect anchor constraint
- **Low-health protection**: Lure features won't trigger when target is almost dead
- **Trapped detection**: Prevents lure when stuck

### Tactical Reposition
- **2-tile search radius** with multi-factor scoring
- **Escape routes** (+10 per walkable tile)
- **Danger zones** (-15 per monster front arc)
- **Target distance** (stay in attack range)
- **Movement cost** (prefer closer tiles)
- **Anchor constraint** (skip tiles outside anchor range)

### Smart Pull Improvements
- **Shape-based counting**: Circle, Square, Diamond, Cross
- **Health check first**: Never abandon low-health targets
- **Visual shape labels**: Slider shows shape name instead of number

### Container Panel v4
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
