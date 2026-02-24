# 📊 Hunt Analyzer

Real-time session analytics that track kills, damage, loot, supply usage, experience, and efficiency metrics.

---

## 📖 Overview

The Hunt Analyzer (`smart_hunt.lua`) is a passive analytics engine that records data from every hunt session. It collects kills, spell casts, potion usage, loot, and experience — then computes efficiency metrics, trends, and actionable insights.

Key capabilities:

- Zero-config — starts automatically when CaveBot or TargetBot is enabled
- Passive observation — never issues game actions
- Real-time metrics (kills/hour, XP/hour, profit/hour)
- Per-monster kill breakdown
- Supply efficiency analysis
- Hunt Score (0–100) composite rating
- Trend indicators (improving/declining)
- Session history

---

## 🚀 Auto-Start

The Hunt Analyzer automatically starts a new session when **either**:

- **CaveBot** is turned on
- **TargetBot** is turned on

This means TargetBot-only players (without CaveBot) also get full session tracking. A background macro checks every 5 seconds and starts a session if one isn't already active.

---

## 📊 Tracked Metrics

| Metric | Source | Description |
|--------|--------|-------------|
| Kills | `onCreatureHealthPercentChange` | Monster health reaching 0 |
| Monster breakdown | Per-creature-type counting | How many of each monster killed |
| Spells cast | `onSpellCooldown` | Any spell with cooldown > 0 |
| Runes used | AttackBot reporting | Each rune with usage count |
| Potions used | HealBot reporting | Each potion with usage count |
| Damage dealt | Mana proxy from AttackBot | Estimated from spell costs |
| Tiles walked | `onWalk` callback | Player movement distance |
| Session duration | `os.time()` delta | Wall-clock elapsed time |
| XP gained | Experience tracking | Total and per-hour |
| Loot value | Analyzer integration | Total and per-hour |

---

## 🧠 Insights Engine

The `buildInsights()` function computes derived analytics:

### Rate Metrics

- **Kills/hour** — total kills divided by session hours
- **XP/hour** — experience gained per hour, with peak tracking
- **Profit/hour** — loot value minus supply cost per hour
- **Damage/hour** — estimated damage output per hour

### Efficiency Metrics

- **Supply efficiency** — potions used per kill
- **Damage per spell** — average damage per cast
- **Attacks per kill** — how many attacks to kill each creature
- **Combat uptime** — percentage of session spent in combat

### Trend Analysis

Each metric includes a trend indicator:

- **↑** Improving compared to session average
- **↓** Declining compared to session average
- **→** Stable

---

## 🏆 Hunt Score

The Hunt Score is a composite 0–100 rating based on five weighted factors:

| Factor | Weight | What it measures |
|--------|--------|-----------------|
| XP Efficiency | 25 pts | XP/hour relative to expected rate |
| Kill Efficiency | 20 pts | Consistent kill rate |
| Survivability | 25 pts | Deaths and near-deaths |
| Resource Efficiency | 15 pts | Supply usage per kill |
| Combat Uptime | 10 pts | Time actively fighting |
| Profit Bonus | 5 pts | Net gold earned |

A score of 80+ indicates a well-optimized hunt.

---

## 💰 Loot Tracking

Integrated with `core/analyzer.lua`, the loot tracker records:

- Every item picked up during the session
- Estimated value per item
- Top 5 most valuable drops
- Total loot value for profit calculation

---

## 🖥️ UI

Click **Hunt Analyzer** on the Main tab. The window displays:

- Session duration
- Total kills (with per-monster breakdown)
- Tiles walked
- Spells cast / Runes used / Potions used
- Rate metrics (XP/hour, kills/hour, profit/hour)
- Insights section with recommendations
- Hunt Score

If the UI fails to open (rare edge case), the summary is printed to the console as a fallback.

---

## 🔧 API for Custom Scripts

```lua
-- Check if session is running
Analytics.isSessionActive()        -- boolean

-- Get current metrics snapshot
Analytics.getMetrics()             -- table with all metrics

-- Build human-readable summary string
Analytics.buildSummary()           -- multi-line text

-- Show the analytics UI window
Analytics.showAnalytics()
```

### Reporting from Other Modules

Other modules report usage through the global `HuntAnalytics` alias:

```lua
HuntAnalytics.trackRuneUse("sudden death rune")
HuntAnalytics.trackPotionUse("great health potion")
HuntAnalytics.trackAttackSpell("exori vis", manaCost)
```

---

## ❓ Troubleshooting

### No data shown

Turn on **CaveBot** or **TargetBot** to auto-start a session. Manual-only hunting without either module enabled won't trigger session tracking.

### Kill count stays at 0

The kill counter relies on `onCreatureHealthPercentChange`. If this callback doesn't fire on your server, kills won't be counted. Check the server's OTClient compatibility.

### Analytics button missing

A module load error prevented the Hunt Analyzer from initializing. Check the console (`Ctrl+Shift+D`) for Lua errors during startup.

### Duplicate kill counts

The native callback is the single source of truth. EventBus `creature:death` events do not double-count — they are used for different subsystems.
