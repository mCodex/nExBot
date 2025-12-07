# 🗺️ nExBot Development Roadmap

> Future improvements for autonomy, resource optimization, smart algorithms, and efficiency

---

## 🧠 **AUTONOMY & SMART DECISION MAKING**

### 1. Smart Supply Prediction System ⭐⭐⭐ ✅ IMPLEMENTED
- [x] Analyze historical consumption rates per spawn
- [x] Predict exact supplies needed based on:
  - Average hunt duration
  - Potions/runes per kill
  - XP/hour to time remaining
- [x] Auto-adjust supply amounts
- **Files**: `core/smart_hunt.lua`, `cavebot/supply_check.lua`

### 2. Adaptive Hunting Route Optimizer ⭐⭐⭐ ✅ IMPLEMENTED
- [x] Track kill count + XP per waypoint segment
- [x] Identify "cold spots" (low monster spawn)
- [x] Auto-skip or fast-walk through low-yield areas
- [x] Learn optimal route timing based on spawn rates
- **Files**: `core/smart_hunt.lua`, `cavebot/actions.lua`

### 3. Dynamic Lure Threshold ⭐⭐⭐ ✅ IMPLEMENTED
- [x] Monitor player HP loss rate during lures
- [x] Auto-adjust max creatures to lure based on:
  - Current healing efficiency
  - Remaining supplies
  - Death risk calculation
- **Files**: `core/smart_hunt.lua`

### 4. Smart Refill Decision Engine ⭐⭐ ✅ IMPLEMENTED
- [x] Calculate: "Can I finish one more round?"
- [x] Based on: current supplies, avg consumption, round time
- [x] Avoid over-refilling or under-refilling
- **Files**: `core/smart_hunt.lua`, `cavebot/supply_check.lua`

### 5. Auto-Learning Monster Database ⭐⭐ ✅ IMPLEMENTED
- [x] Track damage taken/dealt per monster type
- [x] Auto-classify monster danger levels
- [x] Suggest TargetBot priority based on data
- **Files**: `core/smart_hunt.lua`

---

## 💰 **RESOURCE MANAGEMENT & WASTE OPTIMIZATION**

### 6. Mana Efficiency Optimizer ⭐⭐⭐
- [ ] Track mana waste (healing when not needed)
- [ ] Calculate optimal mana threshold per spawn
- [ ] Suggest better healing spell combinations
- **Files**: `core/HealBot.lua`

### 7. Potion Usage Analytics ⭐⭐⭐
- [ ] Log all potion uses with context (HP%, combat state)
- [ ] Identify panic healing (could have used spell instead)
- [ ] Calculate waste per hour
- [ ] Show: "You wasted X potions, Y gold this session"
- **Files**: `core/HealBot.lua`, `core/analyzer.lua`

### 8. Rune Conservation Mode ⭐⭐
- [ ] For low-value monsters, reduce rune usage
- [ ] Auto-switch to cheaper attacks when:
  - Monster HP < threshold
  - Cap is getting low
  - Supplies running out
- **Files**: `core/AttackBot.lua`, `targetbot/creature_attack.lua`

### 9. Gold/Hour Optimizer ⭐⭐
- [ ] Real-time profit calculator
- [ ] Factor in: loot value, supply cost, time
- [ ] Alert when profit drops below threshold
- [ ] Suggest spawn changes based on data
- **Files**: `core/analyzer.lua`

### 10. Capacity Manager ⭐⭐
- [ ] Predict when cap will run out
- [ ] Priority drop system (drop lowest value first)
- [ ] Smart dropper that considers loot value
- **Files**: `core/Dropper.lua`

---

## ⚔️ **COMBAT INTELLIGENCE**

### 11. Multi-Target Wave Optimizer ⭐⭐⭐ ✅ IMPLEMENTED
- [x] For area spells (GFB, Avalanche, etc.)
- [x] Calculate optimal cast position for max hits
- [x] Consider: monster positions, cooldowns, mana
- [x] Reposition suggestions for better coverage
- **Files**: `core/combat_intelligence.lua`

### 12. Combo Sequencer ⭐⭐⭐ ✅ IMPLEMENTED
- [x] Define spell/rune combos per target count
- [x] Auto-execute optimal combo based on:
  - Number of monsters
  - Monster types
  - Cooldown states
- [x] Vocation-specific combo sequences
- **Files**: `core/combat_intelligence.lua`

### 13. Threat Prediction System ⭐⭐ ✅ IMPLEMENTED
- [x] Predict monster spawn patterns
- [x] Pre-position for incoming waves
- [x] Avoid walking into spawn points
- [x] Flank detection (monsters behind player)
- [x] Threat level classification (safe/moderate/high/critical)
- **Files**: `core/combat_intelligence.lua`

### 14. Kill Priority Optimizer ⭐⭐ ✅ IMPLEMENTED
- [x] Factor in: HP remaining, danger level, loot value
- [x] Kill high-value low-HP targets first
- [x] Optimize for both XP and profit
- [x] Escape prevention for low HP monsters
- **Files**: `core/combat_intelligence.lua`, `targetbot/creature_priority.lua`

### 15. Exori/Area Spell Timing ⭐ ✅ IMPLEMENTED
- [x] Track when monsters are stacked
- [x] Wait for optimal grouping before casting
- [x] Balance speed vs efficiency
- [x] Stack ratio analysis
- **Files**: `core/combat_intelligence.lua`

---

## 🛡️ **SAFETY & ANTI-DETECTION**

### 16. Humanized Action Delays ⭐⭐⭐
- [ ] Add slight randomization to all actions
- [ ] Variable delays based on action type
- [ ] Simulate human reaction times
- **Files**: All macro files

### 17. Behavior Pattern Randomizer ⭐⭐
- [ ] Occasionally walk "wrong" path briefly
- [ ] Random pauses during hunting
- [ ] Vary attack patterns slightly
- **Files**: `cavebot/walking.lua`, `targetbot/target.lua`

### 18. Smart Anti-Kick ⭐⭐
- [ ] Current: Turn every 10 min
- [ ] Improved: Random actions (look, small walk, use item)
- [ ] Simulate natural AFK behavior
- **Files**: `core/extras.lua`

### 19. Player Detection Response ⭐⭐⭐
- [ ] When player detected:
  - Option to pause hunting
  - Walk to safe spot
  - Switch to "casual" behavior
  - Log player name/time
- **Files**: `core/alarms.lua`, `cavebot/cavebot.lua`

### 20. Death Prevention System ⭐⭐⭐
- [ ] Monitor HP trend (falling fast?)
- [ ] Emergency protocol:
  - Use emergency ring/amulet
  - Cast best heal regardless of mana
  - Escape to safe tile
- **Files**: `core/HealBot.lua`, `core/Equipper.lua`

---

## 📊 **ANALYTICS & INSIGHTS**

### 21. Session Statistics Dashboard ⭐⭐
- [ ] XP/hour trend graph
- [ ] Loot value over time
- [ ] Supply consumption rates
- [ ] Profit margin calculations
- **Files**: `core/analyzer.lua`

### 22. Hunt Comparison Tool ⭐
- [ ] Compare current session to previous
- [ ] Track improvement over time
- [ ] Identify best hunting times
- **Files**: `core/analyzer.lua`

### 23. Efficiency Scoring ⭐⭐
- [ ] Rate hunting efficiency: A-F grade
- [ ] Based on: XP/waste ratio, deaths, route efficiency
- [ ] Suggest improvements
- **Files**: `core/analyzer.lua`

---

## ⚡ **PERFORMANCE & EFFICIENCY**

### 24. Predictive Pathfinding ⭐⭐ ✅ IMPLEMENTED
- [x] Pre-calculate next 2-3 waypoints
- [x] Cache paths that don't change
- [x] Reduce pathfinding calls by 50%+
- [x] LRU cache with TTL for path storage
- **Files**: `core/performance_optimizer.lua`

### 25. Lazy Evaluation System ⭐⭐ ✅ IMPLEMENTED
- [x] Only recalculate when state changes
- [x] Cache creature danger scores
- [x] Event-driven updates for everything
- [x] Configurable cache TTLs per data type
- **Files**: `core/performance_optimizer.lua`

### 26. Batch Item Operations ⭐⭐ ✅ IMPLEMENTED
- [x] Move/use multiple items in one operation
- [x] Reduce server requests
- [x] Faster looting and depositing
- [x] Priority queue for operations
- **Files**: `core/performance_optimizer.lua`

### 27. Smart Container Caching ⭐ ✅ IMPLEMENTED
- [x] Track container contents changes
- [x] Only scan when container updates
- [x] Reduce O(n) scans
- [x] Item index for fast lookups
- **Files**: `core/performance_optimizer.lua`

---

## 🎮 **QUALITY OF LIFE**

### 28. Quick Config Switcher ⭐⭐
- [ ] Hotkey to switch TargetBot configs
- [ ] Auto-switch based on spawn detection
- [ ] Profile per hunting area
- **Files**: `targetbot/target.lua`

### 29. Voice Alert System ⭐
- [ ] Text-to-speech for critical events
- [ ] "Low health", "Player nearby", "Supplies low"
- **Files**: `core/alarms.lua`

### 30. Remote Monitoring ⭐⭐
- [ ] WebSocket server for status updates
- [ ] Mobile app integration
- [ ] Discord webhook alerts
- **Files**: New module `core/remote.lua`

### 31. Auto-Backup System ⭐
- [ ] Backup configs before changes
- [ ] Version history for profiles
- [ ] One-click restore
- **Files**: `core/configs.lua`

---

## 🔧 **TECHNICAL IMPROVEMENTS**

### 32. State Machine Architecture ⭐⭐⭐ ✅ IMPLEMENTED
- [x] Replace boolean flags with proper states
- [x] Clear state transitions
- [x] Better debugging and logging
- [x] CaveBot FSM: idle, walking, hunting, looting, refilling, banking, etc.
- [x] TargetBot FSM: idle, scanning, targeting, attacking, chasing, looting
- [x] Global state coordinator
- **Files**: `core/state_machine.lua`

### 33. Module Hot-Reload ⭐
- [ ] Reload individual modules without restart
- [ ] Faster development/testing
- **Files**: `_Loader.lua`

### 34. Error Recovery System ⭐⭐
- [ ] Graceful handling of edge cases
- [ ] Auto-recovery from stuck states
- [ ] Detailed error logging
- **Files**: All modules

### 35. Config Validation ⭐
- [ ] Validate configs on load
- [ ] Warn about invalid settings
- [ ] Suggest fixes
- **Files**: `core/configs.lua`

### 36. Floor-Change Prevention ⭐⭐⭐ ✅ IMPLEMENTED
- [x] Detect stairs, ladders, holes, teleports
- [x] Prevent accidental floor changes during walking
- [x] Track expected floor and warn on unexpected changes
- [x] Find safe alternative tiles around floor-change points
- [x] Path safety checking
- **Files**: `cavebot/walking.lua`

---

## 📅 **IMPLEMENTATION PHASES**

| Phase | Features | Impact | Status |
|-------|----------|--------|--------|
| **Phase 0** | #1, #2, #3, #4, #5, #11-15, #24-27, #32, #36 | Smart Autonomy + Combat + Performance | ✅ Complete |
| **Phase 1** | #6, #7, #16, #19, #20 | Safety + Waste reduction | 🔲 Pending |
| **Phase 2** | #8, #14 | Smart decision making | 🔲 Pending |
| **Phase 3** | #21, #23, #30 | Analytics + Monitoring | 🔲 Pending |
| **Phase 4** | #33, #34, #35 | Technical Improvements | 🔲 Pending |

---

## 🏆 **Priority Legend**

- ⭐⭐⭐ = High priority (game-changing impact)
- ⭐⭐ = Medium priority (significant improvement)
- ⭐ = Low priority (nice to have)

---

*Last updated: December 2025*
