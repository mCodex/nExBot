# 📊 Hunt Analyzer

Hunt Analyzer is an advanced hunting analytics system that provides real-time insights, detailed tracking, and data-driven recommendations to optimize your hunting sessions.

## Features

### Real-Time Tracking
- **XP Tracking** - Experience gained and XP/hour rate
- **Kill Tracking** - Total kills and kills/hour rate
- **Skill Gains** - All skill level increases during session
- **Movement** - Tiles walked and tiles/minute rate
- **Damage Output** - Total damage dealt, damage/hour, damage per kill/attack

### Bot Integration

Hunt Analyzer integrates directly with HealBot and AttackBot to collect accurate usage data:

#### HealBot Data
- Individual healing spell counts (e.g., "1543x exura gran")
- Individual potion usage with item names (e.g., "500x Ultimate Health Potion")
- Total spell casts and potion uses
- Mana waste detection (spells cast when already healthy)
- Potion waste detection (potions used when above HP threshold)

#### AttackBot Data
- Individual attack spell counts (e.g., "2000x exori gran ico")
- Individual rune usage with item names (e.g., "150x Sudden Death Rune")
- Empowerment buff casts (utito tempo, etc.)
- Total attacks executed

#### Damage Output (from Analyzer)
- **Total Damage Dealt** - Cumulative damage during session
- **Damage/Hour** - Damage output rate
- **Avg Damage/Kill** - How much damage to kill a monster on average
- **Avg Damage/Attack** - Damage efficiency per AttackBot action

### Survivability Metrics
- **Death Count** - Number of deaths during session
- **Near-Death Events** - Times HP dropped below 20%
- **Lowest HP Percent** - Lowest HP% reached during session
- **Highest Damage Hit** - Largest single hit taken
- **Damage Ratio** - Damage taken vs healing done (Safe/Risky/Dangerous)

### Economic Analysis
Integrates with the existing Analyzer module to provide:
- **Loot Value** - Total value of looted items
- **Waste Value** - Total value of used supplies
- **Balance** - Profit or loss (loot - waste)
- **Profit/Hour** - Economic efficiency rate

### Peak Performance
Tracks your best rates achieved during the session:
- **Best XP/Hour** - Maximum XP rate achieved
- **Best Kills/Hour** - Maximum kill rate achieved
- **Current vs Peak** - Shows how current rates compare to your best

### Resource Tracking
- **Capacity Used** - How much cap you've used (loot collected)
- **Current Cap** - Remaining free capacity
- **Stamina Used** - Minutes of stamina consumed
- **Current Stamina** - Remaining stamina

---

## Hunt Efficiency Score

Hunt Analyzer calculates a 0-100 efficiency score based on four weighted categories:

### Efficiency Factors (40 points max)
| Metric | Points |
|--------|--------|
| XP/Hour > 1M | 20 |
| XP/Hour > 500k | 17 |
| XP/Hour > 200k | 14 |
| XP/Hour > 100k | 10 |
| Kills/Hour > 300 | 15 |
| Kills/Hour > 200 | 12 |
| Tiles/Kill < 10 | 5 |

### Survivability Factors (30 points max)
| Metric | Points |
|--------|--------|
| No deaths | +10 |
| Each death | -10 |
| Damage ratio < 0.4 | +15 |
| Damage ratio > 1.2 | -5 |
| No near-death events | +5 |
| Near-death rate > 5/hr | -5 |

### Resource Factors (20 points max)
| Metric | Points |
|--------|--------|
| Potions/kill < 0.3 | +10 |
| Potions/kill < 0.7 | +7 |
| Mana waste < 5% | +5 |
| Potion waste < 5% | +5 |

### Economic Factors (10 points max)
| Metric | Points |
|--------|--------|
| Profit/Hour > 100k | +10 |
| Profit/Hour > 50k | +7 |
| Profit/Hour < -20k | -3 |

### Score Ratings
| Score | Rating |
|-------|--------|
| 80-100 | Excellent |
| 60-79 | Good |
| 40-59 | Average |
| 20-39 | Below Average |
| 0-19 | Poor |

---

## Insights Engine

The Insights Engine analyzes your hunting data and provides actionable recommendations:

### Severity Levels
- `[!]` **Critical** - Immediate attention required (death risk)
- `[*]` **Warning** - Significant issues to address
- `[>]` **Tip** - Optimization suggestions
- `[i]` **Info** - Informational observations

### Analysis Categories

#### Efficiency Analysis
- XP per kill evaluation
- Kill rate optimization
- Movement efficiency (tiles per kill)

#### Survivability Analysis
- Damage vs healing balance
- Death risk warnings
- HealBot threshold recommendations

#### Resource Efficiency
- Potion usage per kill
- Mana waste detection
- Rune efficiency analysis

#### HealBot Analysis
- Mana waste percentage
- Potion waste detection
- Healing spell diversity suggestions

#### AttackBot Analysis
- Attacks per kill efficiency
- Rune vs spell balance
- Empowerment usage recommendations
- **Damage Efficiency** - Avg damage per attack analysis
- **One-Shot Detection** - Identifies efficient damage setups
- **Attack Diversity** - Recommends using multiple attack types
- **Rune Cost Analysis** - Warns about expensive rune usage (e.g., SD spam)
- **Missing Buffs** - Suggests adding empowerment spells

---

## Usage

### Opening Analytics Window
Click the **"Hunt Analyzer"** button on the Main tab to open the analytics window.

### Session Management
- **Start Session** - Click "Start" to begin tracking
- **Reset Session** - Click "Reset" to clear all data and start fresh
- **Refresh** - Updates the display with current data

### Best Practices
1. Start a session before entering your hunting spawn
2. Let the session run for at least 5 minutes for accurate insights
3. Check insights periodically to optimize your setup
4. Use the efficiency score to compare different hunting spots
5. Reset session when changing spawns for accurate per-spawn data

---

## Technical Details

### Event-Driven Architecture
Hunt Analyzer uses the EventBus pattern for efficient data collection:
- `onWalk` - Tracks player movement
- `onCreatureHealthPercentChange` - Tracks monster kills
- `onPlayerHealthChange` - Tracks damage/healing and near-death events
- `onDeath` - Tracks player deaths

### Bot API Integration
Hunt Analyzer accesses bot analytics through public APIs:
```lua
-- HealBot
HealBot.getAnalytics() -- Returns spell/potion usage data
HealBot.resetAnalytics() -- Clears tracking data

-- AttackBot  
AttackBot.getAnalytics() -- Returns spell/rune usage data
AttackBot.resetAnalytics() -- Clears tracking data
```

### Analyzer Integration
Economic data is pulled from the existing Analyzer module:
```lua
bottingStats() -- Returns loot, waste, balance
```

---

## Example Output

```
============================================
        HUNT ANALYZER
============================================

[SESSION]
--------------------------------------------
  Duration: 1h 23m
  Status: ACTIVE

[EXPERIENCE]
--------------------------------------------
  XP Gained: 2,456,789
  XP/Hour: 1,892,345

[HEALBOT - HEALING SPELLS]
--------------------------------------------
  1543x exura gran
  234x exura vita
  Total: 1,777 casts
  Mana Wasted: 12,500

[HEALBOT - POTIONS]
--------------------------------------------
  500x Ultimate Health Potion
  120x Great Spirit Potion
  Total: 620 used
  Wasted (used when already healthy): 15

[ATTACKBOT - ATTACK SPELLS]
--------------------------------------------
  2000x exori gran ico
  500x exori hur
  Empowerment Buffs: 45

[ATTACKBOT - RUNES]
--------------------------------------------
  150x Sudden Death Rune
  Total Attacks: 2,650

[DAMAGE OUTPUT]
--------------------------------------------
  Total Damage Dealt: 4,567,890
  Damage/Hour: 3,520,000
  Avg Damage/Kill: 1,234
  Avg Damage/Attack: 1,723

[ECONOMY]
--------------------------------------------
  Loot Value: 1,234,567 gp
  Waste Value: 456,789 gp
  Balance: +777,778 gp
  Profit/Hour: 599,000 gp/h

[SURVIVABILITY]
--------------------------------------------
  Deaths: 0
  Near-Death Events: 2
  Lowest HP: 15%
  Highest Hit Taken: 1,234
  Damage Ratio: 0.65 (Safe)

[PEAK PERFORMANCE]
--------------------------------------------
  Best XP/Hour: 2,100,000
  Best Kills/Hour: 312
  Current vs Peak XP: 90%

[HUNT EFFICIENCY SCORE]
--------------------------------------------
  [########--] 78/100 (Good)

  Score Factors:
    Efficiency (XP+Kills+Movement): 40 pts max
    Survivability (Deaths+Damage): 30 pts max
    Resources (Potions+Mana): 20 pts max
    Economy (Profit): 10 pts max

[INSIGHTS & RECOMMENDATIONS]
--------------------------------------------
  [>] 15% of potions wasted. Lower HP trigger threshold.
  [>] Using 0.8 runes per kill. Consider AOE for multi-target.
  [i] Excellent spawn density! Minimal walking between kills.
  [i] Good spell-based attack rotation. Mana efficient!

  Legend: [!]=Critical [*]=Warning [>]=Tip [i]=Info

============================================
```
