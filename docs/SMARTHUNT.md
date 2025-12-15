# 📊 Hunt Analyzer - Complete Session Analytics

![Version](https://img.shields.io/badge/version-2.0-blue.svg)
![Status](https://img.shields.io/badge/status-Released-green.svg)

**Real-time hunting analytics with intelligent insights, resource tracking, and trend analysis**

---

## Table of Contents

- [Overview](#-overview)
- [Core Metrics](#-core-metrics)
- [Hunt Scoring](#-hunt-score-0-100)
- [Resource Tracking](#-resource-tracking)
- [Insights Engine](#-insights-engine)
- [Data Visualization](#-data-visualization)
- [Configuration](#-configuration)
- [Examples](#-examples)

---

## 🎯 Overview

Hunt Analyzer provides **real-time session tracking** with automatic insights. It monitors:

- 📈 **Efficiency Metrics** - XP/hour, kills/hour, profit/hour
- 💰 **Economic Data** - Loot value, top drops, net profit
- 💊 **Resource Usage** - Spells, potions, runes consumed
- 📊 **Trends** - Direction indicators, consistency analysis
- 🧠 **Insights** - Recommendations, warnings, survival tips

> [!NOTE]
> Hunt Analyzer starts automatically when CaveBot or TargetBot is enabled. All data persists across game sessions.

### Quick Facts

- **Response Time**: ~20ms per metric calculation
- **Memory Usage**: ~5-10MB for full session data
- **Storage**: Persists to disk automatically every 5 minutes
- **Session Duration**: Unlimited (tracked to the minute)
- **Data Retention**: 30 sessions cached in memory

---

## 📈 Core Metrics

### Real-Time Calculations

Hunt Analyzer continuously tracks and updates these metrics:

#### Experience (XP)
```
Current Rate: [XP earned in last minute] × 60 = XP/hour
Peak Rate:    Maximum hourly rate observed
Total:        All XP earned this session
Formula:      Based on actual game XP gain events
```

**Example**: If you earned 5000 XP in the last 60 seconds:
- Current Rate = 300,000 XP/hour
- Shown as: "300k XP/h ↑" (↑ if improving)

#### Monster Kills
```
Kill Rate:    [Kills in last minute] × 60 = kills/hour
Consistency:  Standard deviation (lower = more consistent)
Total:        All monsters killed
Formula:      Counted when creature dies or disappears
```

**Consistency Scoring**:
```
Deviation   Rating           Color
< 10%       🟢 Excellent     Very consistent hunting
10-20%      🟡 Good          Normal variation
20-40%      🟠 Fair          Some fluctuation
> 40%       🔴 Poor          Highly variable
```

#### Damage Output
```
Damage/Hour:  Total damage dealt ÷ elapsed time
Damage/Spell: Total damage ÷ spells cast
Efficiency:   Damage per resource used (damage/potion)
```

**Calculation**:
- Attack spells: Estimated based on spell level
- Runes: Based on rune type damage scaling
- Potions: Healing is tracked separately

#### Profit Analysis
```
Session Profit = Loot Value - Supplies Used - Deaths
Loot Value:     Sum of all items dropped
Supplies Cost:  Potions, spells, runes consumed
Death Cost:     10k gold penalty per death
```

**Example**:
```
Items Dropped:      150,000 gold
Potions Used:       -30,000 gold
Runes Used:         -5,000 gold
Deaths Penalty:     -10,000 gold
─────────────────────────────────
Net Profit:         105,000 gold
Profit/Hour:        17,500 gold/hour
```

#### Time Tracking
```
Session Duration:  Elapsed time since session start
Active Time:       Time actually hunting (excludes pauses)
AFK Time:          Time when bot is paused
Stamina Cost:      Estimated based on playtime
```

---

## 🏆 Hunt Score (0-100)

The **Hunt Score** is a comprehensive measure of hunt quality across 5 dimensions:

```
┌─────────────────────────────────────────────────────────┐
│           HUNT SCORE BREAKDOWN                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1️⃣  XP Efficiency (25 points)                          │
│     └─ Based on XP gained per spawn tick                │
│     └─ Compares to expected XP for level/area           │
│                                                         │
│  2️⃣  Kill Efficiency (20 points)                        │
│     └─ Based on kills per minute                        │
│     └─ Adjusted for monster difficulty                  │
│                                                         │
│  3️⃣  Survivability (25 points)                          │
│     └─ Deaths/near-deaths per session                   │
│     └─ Healing effectiveness ratio                      │
│     └─ Health restoration speed                         │
│                                                         │
│  4️⃣  Resource Efficiency (15 points)                    │
│     └─ Mana waste prevention                            │
│     └─ Potion consumption ratio                         │
│     └─ Rune efficiency (damage per rune)                │
│                                                         │
│  5️⃣  Combat Uptime (10 points)                          │
│     └─ Percentage of time in combat                     │
│     └─ Movement inefficiency detection                  │
│                                                         │
│  🎁 Bonus: Profit +5 bonus pts (if > 100k/hour)        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Score Interpretation

| Score | Rating | Status |
|-------|--------|--------|
| 90-100 | 🟢 **Excellent** | Optimal hunting - excellent profit |
| 75-89 | 🟢 **Very Good** | Efficient hunt - good profit |
| 60-74 | 🟡 **Good** | Normal hunting - decent profit |
| 40-59 | 🟠 **Fair** | Room for improvement |
| 20-39 | 🔴 **Poor** | Major issues detected |
| < 20 | 🔴 **Critical** | Immediate action needed |

### Example Score Calculation

```
Hunt Stats:
- XP Rate: 300k/h (20/25 pts) ← Excellent
- Kills: 60/h with 12% consistency (18/20 pts) ← Good
- Deaths: 0 deaths, 50% healing efficiency (20/25 pts) ← Good
- Mana waste: 15% (12/15 pts) ← Acceptable
- Combat uptime: 85% (8/10 pts) ← Good
- Profit: 250k/hour (+5 bonus)

TOTAL SCORE: 20+18+20+12+8 = 78 + 5 = 83 🟢 VERY GOOD
```

---

## 💊 Resource Tracking

### New in v2.0: Detailed Consumption Analytics

Hunt Analyzer now tracks **exactly which spells, potions, and runes** you use:

#### Spells Used
```
Healing Spells:
├─ exura vita       5 casts (estimated 600 heal/cast)
├─ exura          12 casts (estimated 200 heal/cast)
└─ heal friend     2 casts (group healing)

Attack Spells:
├─ exori            125 casts (main attack)
├─ exori con       45 casts (crowd control)
└─ spell MASACRE    12 casts (high damage)

Support Spells:
├─ utani hur        8 casts (haste)
├─ protection       4 casts (damage reduction)
└─ mana shield      15 casts (mana-based shield)
```

#### Potions Used
```
Health Potions:
├─ Ultimate Health Potion    20 used @ 200 gold = 4,000 gold
├─ Great Health Potion       45 used @ 100 gold = 4,500 gold
└─ Health Potion             12 used @  50 gold =   600 gold

Mana Potions:
├─ Ultimate Mana Potion      15 used @ 200 gold = 3,000 gold
├─ Great Mana Potion         30 used @ 100 gold = 3,000 gold
└─ Mana Potion               8 used @  50 gold =   400 gold
```

#### Runes Used
```
Attack Runes:
├─ Sudden Death             12 used @ 500 gold = 6,000 gold
├─ Fireball Rune            5 used @ 150 gold =   750 gold
└─ Explosion Rune           3 used @ 100 gold =   300 gold

Support Runes:
├─ Heal Friend Rune         2 used @ 200 gold =   400 gold
└─ Paralyze Rune            1 used @ 300 gold =   300 gold
```

### Resource Insights

Hunt Analyzer provides **automated analysis** of your consumption:

```
⚠️  WARNING: High potion usage
    → Using 45 potions/hour (expected 20)
    → Suggestion: Adjust healing spells to reduce potion dependency
    → Cost: 12,000 gold/hour → 8,000 gold/hour with better healing

✅ GOOD: Efficient mana usage
    → 85% of mana spells hit (vs 70% average)
    → Mana waste: 5% (excellent!)

📊 ANALYSIS: Spell selection
    → Your top 3 spells account for 65% of all attacks
    → Consider: Adding more variety for adaptability
```

---

## 🧠 Insights Engine

Hunt Analyzer generates **intelligent, context-aware insights** based on your hunt data.

### Insight Categories

#### 1. Efficiency Recommendations
```
"Your XP rate dropped 15% in the last 10 minutes"
├─ Severity: YELLOW (warning)
├─ Cause: Kill rate decreased
└─ Action: Check if monsters respawning normally
```

#### 2. Resource Analysis
```
"You used 50 greater mana potions - unusually high"
├─ Severity: YELLOW (warning)
├─ Cause: Likely spell spamming or low mana management
└─ Suggestions:
    ├─ Reduce area spells frequency
    ├─ Add mana shield for protection
    └─ Use runes instead for burst damage
```

#### 3. Survivability Warnings
```
"0 deaths this session - excellent survival!"
├─ Severity: GREEN (good)
├─ Metrics: Perfect health management
└─ Action: Keep current healing setup
```

#### 4. Monster Analysis
```
"Dragons deal 40% more damage than Demon Lords"
├─ Severity: BLUE (info)
├─ Recommendation: Use protection spell against Dragons
└─ Comparison: Your damage output is 25% higher
```

#### 5. Equipment Suggestions
```
"Using heavy armor with mage setup detected"
├─ Severity: YELLOW (warning)
├─ Impact: 10% slower movement speed
└─ Suggestion: Switch to light armor for better positioning
```

### Confidence Scoring

Each insight includes a **confidence score** (0-1):

```
Confidence 0.95 = Very reliable (many data points)
           0.75 = Reliable (enough data)
           0.50 = Moderate (uncertain)
           < 0.50 = Low reliability (need more data)

Example:
"Kill rate is decreasing" (0.87 confidence)
└─ Based on 5 minutes of consistent decline
```

---

## 📊 Data Visualization

### Summary Display

```
╔════════════════════════════════════════════════════════╗
║          HUNT ANALYZER - SESSION SUMMARY                ║
╠════════════════════════════════════════════════════════╣
║                                                        ║
║  ⏱️  SESSION TIME: 1 hour 23 minutes                   ║
║                                                        ║
║  📈 EXPERIENCE:       415,000 XP                       ║
║     Rate:            300,000 XP/hour ↑ (improving)    ║
║     Peak:            340,000 XP/hour (best achieved)  ║
║                                                        ║
║  🎯 KILLS:            52 monsters                      ║
║     Rate:            38 kills/hour ✓ (consistent)     ║
║     Consistency:     12% deviation (excellent)        ║
║                                                        ║
║  💰 PROFIT:           156,000 gold                     ║
║     Supplies Cost:   -18,000 gold                      ║
║     Death Penalty:    -0 gold (no deaths!)             ║
║     Net Profit/h:    112,500 gold/hour                ║
║                                                        ║
║  🎓 HUNT SCORE:       85/100 🟢 VERY GOOD              ║
║     XP Efficiency:    22/25 ⭐                         ║
║     Kill Efficiency:  19/20 ⭐                         ║
║     Survivability:    23/25 ⭐                         ║
║     Resource Eff:     14/15 ⭐                         ║
║     Combat Uptime:    7/10                            ║
║                                                        ║
║  💊 RESOURCES USED:                                    ║
║     Spells:          125 casts (70% attack)            ║
║     Potions:         77 used (4,000 gold)              ║
║     Runes:           18 used (7,050 gold)              ║
║                                                        ║
║  🔝 TOP 5 DROPS:                                       ║
║     1. Dragon's Eye (12x) - 6,000 gold                 ║
║     2. Platinum Coin (450x) - 45,000 gold              ║
║     3. Demonic Essence (8x) - 24,000 gold              ║
║     4. Ancient Coin (15x) - 15,000 gold                ║
║     5. Gold Nugget (6x) - 18,000 gold                  ║
║                                                        ║
╠════════════════════════════════════════════════════════╣
║  💡 INSIGHTS:                                          ║
║                                                        ║
║  ✅ Excellent session! Continue current hunting route  ║
║  ⚠️  Potion usage slightly high (try haste spell)      ║
║  ✅ Zero deaths - excellent survival skills!           ║
║  📊 Kill rate stable - consistent hunt quality        ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
```

### Detailed Analytics Tabs

**SPELLS USED** Tab:
```
Spell Name              Casts    Damage/Spell    Total Damage
────────────────────────────────────────────────────────────
exori (single)           125        240          30,000
exori con (crowd)         45        320          14,400
exori gran (strong)       12        680           8,160
┌─────────────────────────────────────────────────────────┐
│ TOTAL ATTACK: 182 spells cast, 52,560 damage total   │
└─────────────────────────────────────────────────────────┘

Healing Spell           Casts    Heal/Spell      Total Heal
────────────────────────────────────────────────────────────
exura vita              5          600            3,000
exura                  12          200            2,400
exura gran              1          900              900
┌─────────────────────────────────────────────────────────┐
│ TOTAL HEALING: 18 spells cast, 6,300 heal total      │
└─────────────────────────────────────────────────────────┘
```

**POTIONS USED** Tab:
```
Potion Type                    Quantity    Cost Each    Total Cost
───────────────────────────────────────────────────────────────────
Ultimate Health Potion            20         200         4,000
Great Health Potion               45         100         4,500
Health Potion                      12         50           600
Ultimate Mana Potion              15         200         3,000
Great Mana Potion                 30         100         3,000
Mana Potion                         8          50           400
───────────────────────────────────────────────────────────────────
TOTAL POTIONS: 130 used          TOTAL COST: 15,500 gold
```

**RUNES USED** Tab:
```
Rune Type                       Quantity    Cost Each    Total Cost
──────────────────────────────────────────────────────────────────
Sudden Death                        12         500         6,000
Fireball Rune                        5         150           750
Explosion Rune                       3         100           300
Heal Friend Rune                     2         200           400
──────────────────────────────────────────────────────────────────
TOTAL RUNES: 22 used            TOTAL COST: 7,450 gold
```

---

## ⚙️ Configuration

### Session Management

```lua
-- Auto-start options (in bot config):
AutoStartHuntAnalyzer = true   -- Starts when bot loads

-- Data retention:
MaxSessions = 30               -- Keep last 30 sessions
AutoSaveInterval = 5 * 60      -- Save to disk every 5 min

-- Metrics to track:
TrackXPMetrics = true
TrackKillMetrics = true
TrackProfitMetrics = true
TrackResourceUsage = true      -- NEW in v2.0
TrackMonsterBreakdown = true
```

### Consumption Tracking

Hunt Analyzer automatically tracks when HealBot and TargetBot report usage:

```lua
-- From HealBot (automatic):
HuntAnalytics.trackHealSpell(spellName, manaUsed, estimatedHeal)
HuntAnalytics.trackPotion(potionName, healthRestored)

-- From TargetBot (automatic):
HuntAnalytics.trackAttackSpell(spellName, damageEstimate)
HuntAnalytics.trackRune(runeName, damageEstimate)
HuntAnalytics.trackSupportSpell(spellName, effect)
```

> [!NOTE]
> No configuration needed! Tracking is 100% automatic when the bots use resources.

---

## 📚 Examples

### Example 1: Good Hunt Session

```
Hunt Statistics:
├─ Duration: 2 hours
├─ Level: 150 (Knight, 2-handed sword)
├─ Area: Oramond Minotaurs
├─ XP Rate: 420k/hour (peak 480k)
├─ Kill Rate: 42 kills/hour
├─ Profit: 250k/hour
└─ Deaths: 0

Hunt Score: 92/100 🟢 EXCELLENT

Breakdown:
├─ XP Efficiency: 24/25 (excellent experience)
├─ Kill Efficiency: 20/20 (perfect kills)
├─ Survivability: 25/25 (zero deaths!)
├─ Resource Eff: 14/15 (great mana management)
├─ Combat Uptime: 9/10 (very active)
└─ Profit Bonus: +5 (high gold/hour)

Resources Used:
├─ Spells: 280 casts (avg 3 per minute)
├─ Potions: 45 (great health potion)
├─ Runes: 8 (sudden death)
└─ Mana Efficiency: 92% (minimal waste)

Key Insights:
✅ Optimal hunting - continue this setup
✅ Combat skills excellent
✅ Equipment well-matched to area
💡 Slight potion usage - consider using more haste
```

### Example 2: Problem Hunt Session

```
Hunt Statistics:
├─ Duration: 1 hour 30 minutes
├─ Level: 120 (Sorcerer, low setup)
├─ Area: Dark Cathedral Demons
├─ XP Rate: 140k/hour (declining)
├─ Kill Rate: 12 kills/hour
├─ Profit: -50k/hour (losing money!)
└─ Deaths: 3 (18,000 gold penalty)

Hunt Score: 35/100 🔴 POOR

Breakdown:
├─ XP Efficiency: 8/25 (very low for area)
├─ Kill Efficiency: 5/20 (struggling to kill)
├─ Survivability: 5/25 (frequent deaths)
├─ Resource Eff: 6/15 (major waste)
├─ Combat Uptime: 4/10 (lots of downtime)
└─ Profit Bonus: 0 (negative profit)

Resources Used:
├─ Spells: 80 casts (many wasted)
├─ Potions: 150 (extremely high!)
├─ Runes: 0 (none used)
└─ Mana Efficiency: 45% (lots of waste!)

Red Flags:
🔴 Extreme potion usage - healing failing
🔴 Frequent deaths - underprepared for area
🔴 Low damage output - weak gear
🔴 Losing money - cost > loot value

Recommendations:
1. ⛔ Leave this area (too difficult for setup)
2. 🔄 Lower level monsters (check level-appropriate areas)
3. 💪 Get better equipment (shield, magic level rings)
4. 📚 Learn monster patterns (Demons are aggressive)
5. 🛡️ Use better healing (acquire better spells)
```

### Example 3: Analyzing Consumption

```
Resource Usage Report:

SPELL EFFICIENCY:
├─ exori cast: 125 times
│  └─ Damage total: 30,000
│  └─ Damage per cast: 240
│  └─ Mana cost: 25 each
│  └─ Mana efficiency: 9.6 damage/mana ⭐
│
└─ exori con cast: 45 times
   └─ Damage total: 14,400
   └─ Damage per cast: 320
   └─ Mana cost: 45 each
   └─ Mana efficiency: 7.1 damage/mana ⭐ (use less?)

POTION ANALYSIS:
├─ Ultimate Health: 20 used
│  └─ Cost: 4,000 gold
│  └─ Rate: 15/hour
│  └─ Efficiency: 200 HP each
│
└─ Great Health: 45 used
   └─ Cost: 4,500 gold
   └─ Rate: 33/hour ⚠️ (high!)
   └─ Efficiency: 100 HP each

INSIGHT:
"You're using 33 Great Health potions per hour"
├─ Compared to baseline: Normal is 15-20/hour
├─ Cost impact: 1,500 extra gold/hour
└─ Suggestion: Your healing spells aren't efficient enough
   → Try adding "exura" at 40% HP
   → This should reduce potion dependency by 30%
```

---

## 🎨 Advanced Usage

### Session Comparison

```
Last 5 Sessions Summary:
┌─────────────────────────────────────────────────────┐
│ Session  Location          Score   Rate     Profit  │
├─────────────────────────────────────────────────────┤
│ Today    Oramond Minos      92/100  420k/h  +250k/h │
│ Monday   Dark Cathedral     35/100  140k/h  -50k/h  │
│ Sunday   Oramond Hydras     78/100  280k/h  +120k/h │
│ Saturday Demon Helm         88/100  380k/h  +200k/h │
│ Friday   Krailos Skeletons  72/100  240k/h  +80k/h  │
└─────────────────────────────────────────────────────┘

TREND ANALYSIS:
📈 Today's hunt is best (92/100) - Oramond Minos optimal
⬇️  Dark Cathedral too difficult (35/100) - AVOID
⬆️  Weekend hunts better than Friday
💡 Best route: Oramond Minos (consistent 90+ scores)
```

### Create Hunt Notes

```lua
-- Add custom notes to sessions:
HuntAnalyzer.addNote("Great hunt - used new AoE spell rotation")
HuntAnalyzer.addNote("Server lag today - affects kill rate")
HuntAnalyzer.addNote("Tested lower level area - too easy")

-- Notes appear in session history:
Session: Oramond Minos (Today 2:15pm)
Score: 92/100
Note: "Great hunt - used new AoE spell rotation"
```

---

## 📞 Support

For more information:
- 📖 [Main README](README.md)
- 🤖 [CaveBot Guide](CAVEBOT.md)
- 🎯 [TargetBot Guide](TARGETBOT.md)
- 💊 [HealBot Guide](HEALBOT.md)

---

<div align="center">

**Hunt Analyzer v2.0** - Advanced Session Analytics Engine 📊

*Powered by nExBot - Real-Time Intelligent Insights*

</div>
