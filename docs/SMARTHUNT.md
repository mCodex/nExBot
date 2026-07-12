# Hunt Analyzer

Session analytics — kills, damage, loot, supplies, XP, efficiency.

## Auto-Start

Starts automatically when **CaveBot** or **TargetBot** is turned on. Background macro checks every 5s.

## Tracked Metrics

| Metric | Source |
|--------|--------|
| Kills | `onCreatureHealthPercentChange` (health → 0) |
| Monster breakdown | Per-type counting |
| Spells cast | `onSpellCooldown` (cooldown > 0) |
| Runes used | AttackBot reporting |
| Potions used | HealBot reporting |
| Damage dealt | Mana proxy from AttackBot |
| Tiles walked | `onWalk` callback |
| XP gained | Experience tracking |
| Loot value | Analyzer integration |

## Insights

**Rates:** kills/hr, XP/hr (with peak), profit/hr, damage/hr

**Efficiency:** potions/kill, damage/spell, attacks/kill, combat uptime

**Trends:** ↑ improving, ↓ declining, → stable (vs session average)

## Hunt Score

Composite 0–100 rating:

| Factor | Weight |
|--------|--------|
| XP Efficiency | 25 pts |
| Survivability | 25 pts |
| Kill Efficiency | 20 pts |
| Resource Efficiency | 15 pts |
| Combat Uptime | 10 pts |
| Profit Bonus | 5 pts |

80+ = well-optimized hunt.

## API

```lua
Analytics.isSessionActive()     -- boolean
Analytics.getMetrics()          -- table
Analytics.buildSummary()        -- multi-line text
Analytics.showAnalytics()       -- show UI
```

Other modules report via `HuntAnalytics`:
```lua
HuntAnalytics.trackRuneUse("sudden death rune")
HuntAnalytics.trackPotionUse("great health potion")
HuntAnalytics.trackAttackSpell("exori vis", manaCost)
```

## Troubleshooting

**No data:** Turn on CaveBot or TargetBot. Manual-only hunting won't trigger tracking.

**Kill count at 0:** `onCreatureHealthPercentChange` may not fire on your server.

**Analytics button missing:** Module load error. Check console.
