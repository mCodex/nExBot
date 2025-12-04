# NexBot - Advanced Tibia Bot Framework

A modern, modular bot framework implementing SOLID principles, DRY patterns, and advanced optimization techniques.

## Version 1.0.0

## Overview

NexBot is a comprehensive bot framework for OTClient (OTCv8) designed for Tibia automation. Built from the ground up with:

- **Modular Architecture**: Clean separation of concerns with dedicated modules
- **Event-Driven Design**: Decoupled communication via EventBus pattern
- **Performance Optimizations**: Object pooling, path caching, and weak references
- **Enhanced Features**: Smart luring, priority targeting, dynamic spell selection

## Project Structure

```
NexBot/
├── core/                       # Core infrastructure modules
│   ├── init.lua                # Core loader
│   ├── event_bus.lua           # Event-driven communication
│   ├── bot_state.lua           # Centralized state management
│   ├── distance_calculator.lua # DRY distance calculations
│   ├── performance_monitor.lua # Profiling and GC management
│   ├── config_manager.lua      # Configuration with profiles
│   └── nlib.lua                # Core utilities
│
├── modules/                    # Feature modules
│   ├── combat/
│   │   ├── auto_haste.lua      # Vocation-based haste system
│   │   └── spell_registry.lua  # OCP spell management
│   │
│   ├── pathfinding/
│   │   ├── path_cache.lua      # TTL-based path caching
│   │   └── optimized_astar.lua # A* with node limits
│   │
│   ├── luring/
│   │   ├── luring_patterns.lua # Circle/spiral/zigzag patterns
│   │   ├── creature_tracker.lua# Spawn tracking system
│   │   └── luring_manager.lua  # Luring orchestration
│   │
│   ├── targeting/
│   │   ├── priority_target_manager.lua  # Score-based targeting
│   │   └── dynamic_spell_selector.lua   # AOE optimization
│   │
│   └── memory/
│       ├── object_pool.lua     # Object reuse for GC reduction
│       └── weak_reference_tracker.lua   # Auto-cleanup
│
├── tests/                      # Unit testing framework
│   ├── test_framework.lua      # Testing infrastructure
│   └── core_tests.lua          # Core module tests
│
├── main.lua                    # Main entry point
└── version.txt                 # Version file
```

## Key Features

### 1. Event-Driven Architecture
```lua
-- Subscribe to events
NexBot.EventBus:on("CREATURE_SPOTTED", function(creature)
    -- Handle creature appearance
end)

-- Emit events
NexBot.EventBus:emit("CREATURE_SPOTTED", creature)
```

### 2. Centralized State Management
```lua
-- Access shared state
local state = NexBot.BotState
state:set("combat.target", creature)
local target = state:get("combat.target")
```

### 3. Smart Auto-Haste
- Automatic vocation detection (Knight, Paladin, Mage)
- Correct haste spell selection (utani hur, utani gran hur, utani tempo hur)
- Mana management and safe casting

### 4. Optimized Pathfinding
- A* algorithm with node limits (prevents freezing)
- TTL-based path caching (reuses recent paths)
- Directional walking optimization

### 5. Smart Luring System
- Multiple patterns: Circle, Spiral, Zigzag
- Creature spawn tracking
- Safety checks (HP, players, blocked paths)

### 6. Priority Targeting
- Score-based target selection
- Configurable weights (threat, health, distance)
- Dynamic spell selection based on creature count

### 7. Memory Optimization
- Object pooling for frequently allocated objects
- Weak reference tracking for auto-cleanup
- Scheduled garbage collection

## Configuration

NexBot uses a centralized configuration system:

```lua
local config = NexBot.modules.ConfigManager

-- Get values
local enabled = config:get("combat.enabled", true)

-- Set values
config:set("combat.autoHaste", true)

-- Profile management
config:createProfile("hunting")
config:switchProfile("hunting")
```

## Installation

1. Copy the `NexBot` folder to your OTClient bot config directory
2. Use `_NexBotLoader.lua` to load the system

## Testing

Run the test suite:
```lua
local runTests = dofile("/NexBot/tests/core_tests.lua")
local success = runTests()
```

## Contributing

When adding new features:
1. Follow SOLID principles
2. Use the EventBus for communication between modules
3. Add unit tests for new functionality
4. Use the ObjectPool for frequently allocated objects

## License

MIT License - See LICENSE file for details

## Credits

- NexBot Team
- Community contributors

## Changelog

### Version 1.0.0
- Initial release
- Modular architecture with core and feature modules
- Event-driven communication system
- Auto haste with vocation detection
- Optimized A* pathfinding with caching
- Smart luring system with patterns
- Priority-based targeting
- Memory optimization with object pooling
- Unit testing framework
- Centralized configuration management
