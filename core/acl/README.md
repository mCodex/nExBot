# nExBot ACL - Anti-Corruption Layer

The ACL (Anti-Corruption Layer) provides a unified interface for nExBot to work with multiple OTClient implementations:
- **OTCv8** - Original target client
- **OpenTibiaBR/OTClient Redemption** - Modern Tibia client

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     nExBot Modules                       │
│  (HealBot, CaveBot, AttackBot, Equipper, etc.)          │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   ClientService                          │
│            (Unified API for all modules)                 │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                      ACL Layer                           │
│         (Anti-Corruption Layer / Abstraction)            │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────┐         ┌─────────────────┐        │
│  │  OTCv8 Adapter  │         │ OpenTibiaBR     │        │
│  │                 │         │ Adapter         │        │
│  └────────┬────────┘         └────────┬────────┘        │
└───────────┼────────────────────────────┼────────────────┘
            │                            │
            ▼                            ▼
┌─────────────────────┐      ┌─────────────────────┐
│      OTCv8          │      │    OpenTibiaBR      │
│   (g_game, g_map)   │      │   (g_game, g_map)   │
└─────────────────────┘      └─────────────────────┘
```

## Design Principles Applied

### SOLID Principles

1. **Single Responsibility (SRP)**
   - Each adapter handles only its specific client
   - ClientService only handles API delegation
   - ACL init only handles detection and loading

2. **Open/Closed (OCP)**
   - New client adapters can be added without modifying existing code
   - Just create a new adapter in `acl/adapters/`

3. **Liskov Substitution (LSP)**
   - All adapters implement the same interface
   - Any adapter can be swapped without breaking functionality

4. **Interface Segregation (ISP)**
   - Interfaces are split by domain: game, map, callbacks, etc.
   - Clients only implement what they support

5. **Dependency Inversion (DIP)**
   - Modules depend on ClientService abstraction
   - Not on concrete client implementations

### Other Principles

- **DRY (Don't Repeat Yourself)**: Common logic in BaseAdapter
- **KISS (Keep It Simple, Stupid)**: Simple detection and delegation
- **ACL Pattern**: Isolates external dependencies from core logic

## File Structure

```
core/
├── acl/
│   ├── init.lua           # ACL initialization and client detection
│   ├── interfaces.lua     # Interface definitions
│   └── adapters/
│       ├── base.lua       # Base adapter with shared logic
│       ├── otcv8.lua      # OTCv8 specific implementation
│       └── opentibiabr.lua# OpenTibiaBR specific implementation
├── client_service.lua     # Unified client service API
└── ...
```

## Usage

### In Bot Modules

Instead of directly using `g_game`, `g_map`, etc., use `ClientService`:

```lua
-- Old way (client-specific)
local player = g_game.getLocalPlayer()
g_game.attack(creature)

-- New way (client-agnostic via ACL)
local player = ClientService.getLocalPlayer()
ClientService.attack(creature)
```

### Client Detection

```lua
-- Check which client is running
if ClientService.isOTCv8() then
    print("Running on OTCv8")
elseif ClientService.isOpenTibiaBR() then
    print("Running on OpenTibiaBR")
end

-- Get client name
local clientName = ClientService.getClientName() -- "OTCv8" or "OpenTibiaBR"
```

### Accessing Client-Specific Features

```lua
-- Access ACL directly for advanced features
local ACL = dofile("/core/acl/init.lua")

-- OTCv8 specific
if ACL.isOTCv8() then
    ACL.game.moveRaw(item, pos, count)
end

-- OpenTibiaBR specific
if ACL.isOpenTibiaBR() then
    ACL.game.sendQuickLoot(pos)
    ACL.bestiary.request()
end
```

## Adding Support for New Clients

1. Create a new adapter file: `core/acl/adapters/newclient.lua`
2. Extend the base adapter
3. Implement client-specific methods
4. Update `core/acl/init.lua` detection logic

### Adapter Template

```lua
-- Load base adapter
local BaseAdapter = dofile("/core/acl/adapters/base.lua")

-- Create new adapter
local NewClientAdapter = {}

-- Copy base adapter
for k, v in pairs(BaseAdapter) do
    if type(v) == "table" then
        NewClientAdapter[k] = {}
        for k2, v2 in pairs(v) do
            NewClientAdapter[k][k2] = v2
        end
    else
        NewClientAdapter[k] = v
    end
end

-- Adapter metadata
NewClientAdapter.NAME = "NewClient"
NewClientAdapter.VERSION = "1.0.0"

-- Override or add methods as needed
function NewClientAdapter.game.specificFeature()
    -- Implementation
end

return NewClientAdapter
```

## API Reference

### ClientService

#### Game Operations
- `isOnline()` - Check if connected to game
- `isDead()` - Check if player is dead
- `attack(creature)` - Attack a creature
- `cancelAttack()` - Cancel current attack
- `follow(creature)` - Follow a creature
- `walk(direction)` - Walk in direction
- `autoWalk(dest, steps, options)` - Auto-walk to destination
- `move(thing, toPos, count)` - Move item
- `use(thing)` - Use item
- `useWith(item, target)` - Use item on target
- `talk(message)` - Say message
- `getLocalPlayer()` - Get local player
- `getContainers()` - Get open containers

#### Map Operations
- `getTile(pos)` - Get tile at position
- `getSpectators(pos, multifloor)` - Get creatures around position
- `isSightClear(from, to, floorCheck)` - Check line of sight
- `findPath(start, goal, options)` - Find path between positions

#### Utilities
- `getPos(x, y, z)` - Create position
- `getDistanceBetween(pos1, pos2)` - Get distance
- `findItem(itemId, subType)` - Find item
- `itemAmount(itemId, subType)` - Count items
- `getCreatureByName(name, caseSensitive)` - Find creature

#### Callbacks
- `onCreatureAppear(callback)`
- `onCreatureDisappear(callback)`
- `onPlayerPositionChange(callback)`
- `onTalk(callback)`
- `onTextMessage(callback)`
- `onContainerOpen(callback)`
- `onSpellCooldown(callback)`

## Client-Specific Features

### OTCv8 Only
- `game.moveRaw()` - Raw movement with more control
- `map.getSpectatorsByPattern()` - Pattern-based spectators

### OpenTibiaBR Only
- `game.forceWalk()` - Force walk without prewalk
- `game.sendQuickLoot()` - Quick loot integration
- `game.stashWithdraw()` - Stash operations
- `game.stashStowItem()` - Stash operations
- `game.isUsingProtobuf()` - Protobuf support check
- `bestiary.*` - Bestiary system
- `bosstiary.*` - Bosstiary system
- `paperdolls.*` - Paperdoll system
- `gameConfig.*` - Game configuration

## Backward Compatibility

The ACL is designed to be fully backward compatible. Existing scripts that use global functions like `g_game.attack()` will continue to work. The ACL only adds new abstraction layers on top.

For gradual migration:
1. New modules should use `ClientService`
2. Existing modules can be updated over time
3. Both approaches work simultaneously
