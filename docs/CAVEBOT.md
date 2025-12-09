# 🗺️ CaveBot Documentation

**Automated waypoint navigation and hunting**

---

## 📖 Overview

CaveBot automates your hunting route by following waypoints. It handles:
- Walking between locations
- Opening doors
- Using tools (rope, shovel, machete)
- Refilling supplies
- Depositing loot

---

## 🚀 Quick Start

### Creating a Simple Route

1. **Open the Editor**
   - Click `Show Editor` in CaveBot panel

2. **Add Waypoints**
   - Stand at desired location
   - Click `Add Goto` to add walk waypoint
   - Repeat for your entire route

3. **Add Labels**
   - Use `label` action to mark important spots
   - Example: `label:hunt`, `label:depot`

4. **Save Configuration**
   - Enter a name in the config dropdown
   - Click save icon

---

## 📍 Waypoint Types

### Movement Actions

<details>
<summary><b>🚶 goto</b></summary>

Walk to a specific coordinate.

**Format:** `x,y,z` or `x,y,z,precision`

**Examples:**
```
32000,32000,7      → Walk to exact position
32000,32000,7,3    → Walk within 3 tiles of position
```

> [!TIP]
> Use precision for areas where exact positioning isn't needed.

</details>

<details>
<summary><b>🏷️ label</b></summary>

Mark a location with a name for jumping.

**Format:** `labelName`

**Examples:**
```
label:hunt
label:refill
label:depot
```

> [!IMPORTANT]
> Labels are case-sensitive! `Hunt` ≠ `hunt`

</details>

<details>
<summary><b>↪️ gotolabel</b></summary>

Jump to a labeled waypoint.

**Format:** `labelName`

**Examples:**
```
gotolabel:hunt     → Jump to "hunt" label
gotolabel:depot    → Jump to "depot" label
```

</details>

---

### Conditional Actions

<details>
<summary><b>🎒 checkSupplies</b></summary>

Check if supplies are low and go to refill.

**Format:** `itemId,minAmount,gotoLabel`

**Examples:**
```
3160,50,refill     → If mana potions < 50, goto refill
3155,20,depot      → If health potions < 20, goto depot
```

</details>

<details>
<summary><b>⚖️ checkCapacity</b></summary>

Check if capacity is low.

**Format:** `minCap,gotoLabel`

**Examples:**
```
200,depot          → If cap < 200, goto depot
```

</details>

<details>
<summary><b>🧪 checkMana</b></summary>

Check mana percentage.

**Format:** `minPercent,gotoLabel`

**Examples:**
```
30,refill          → If mana% < 30, goto refill
```

</details>

---

### Town Actions

<details>
<summary><b>🏦 depositor</b></summary>

Deposit items in depot.

**Format:** `depositAll` or item-specific

> [!TIP]
> Configure deposit settings in the Depositor panel for full control.

</details>

<details>
<summary><b>🛒 buy</b></summary>

Buy items from NPC.

**Format:** `itemId,amount,npcName`

**Examples:**
```
3160,200,Eremo     → Buy 200 mana potions from Eremo
```

</details>

<details>
<summary><b>💰 sell</b></summary>

Sell items to NPC.

**Format:** `itemId,npcName`

</details>

---

## 🛡️ Safety Features

### Smart Execution System

> [!NOTE]
> CaveBot now intelligently skips macro execution when not needed!

**How it works:**
- Tracks walk state (isWalkingToWaypoint, targetPos)
- Skips execution while player is actively walking
- Detects arrival at waypoint automatically
- Auto-recovers from stuck state after 3 seconds

```lua
-- The bot only executes when there's work to do
if shouldSkipExecution() then return end  -- Walking? Skip!
```

---

### Smart Waypoint Guard

> [!IMPORTANT]
> Checks distance from CURRENT waypoint, not first waypoint!

**Key improvements over old guard:**

| Old Guard | New Smart Guard |
|-----------|----------------|
| Checked first waypoint | Checks **current focused waypoint** |
| Ran every 250ms | **Rate-limited to every 5 seconds** |
| Blocked execution | **Skips unreachable waypoint** |
| Caused infinite loops | **3-failure auto-skip** |

**Configuration:**
```lua
WaypointGuard = {
  CHECK_INTERVAL = 5000,     -- Check every 5 seconds
  EXTREME_DISTANCE = 100,    -- Only trigger if >100 tiles
  MAX_FAILURES = 3           -- Skip waypoint after 3 failures
}
```

**Triggers when:**
- Player is on different floor than current waypoint
- Player is >100 tiles from current waypoint
- After 3 consecutive failures → **skips to next waypoint**

### Smart Pull Integration

When TargetBot's Smart Pull is active:
- CaveBot **pauses** waypoint execution
- Player stays and fights current monsters
- Prevents running away from respawns

---

## ⚙️ Configuration

### Settings Panel

| Setting | Description | Default |
|---------|-------------|---------|
| **Use Delay** | Delay after using items | 400ms |
| **Walk Delay** | Delay between steps | 100ms |
| **Ping Compensation** | Add to delays | 0ms |
| **Auto Use Tools** | Use rope/shovel automatically | ON |

### Tool Configuration

| Tool | Item ID | Target Tiles |
|------|---------|--------------|
| Rope | Set in config | Rope holes |
| Shovel | Set in config | Stone piles |
| Machete | Set in config | Jungle grass |
| Scythe | Set in config | Wheat |

---

## 📝 Script Examples

<details>
<summary><b>Basic Hunting Loop</b></summary>

```
label:hunt
goto:32000,32000,7
goto:32010,32000,7
goto:32010,32010,7
goto:32000,32010,7
checkCapacity:200,depot
gotolabel:hunt

label:depot
goto:32100,32100,7
depositor
gotolabel:hunt
```

</details>

<details>
<summary><b>Full Refill Script</b></summary>

```
label:hunt
-- hunting waypoints here --
checkSupplies:3160,50,refill
checkCapacity:300,depot
gotolabel:hunt

label:refill
goto:32500,32500,7  -- NPC location
buy:3160,200,Eremo
gotolabel:hunt

label:depot
goto:32600,32600,7  -- Depot location
depositor
gotolabel:refill
```

</details>

---

## ⚠️ Common Issues

<details>
<summary><b>Client freezes when far from waypoint</b></summary>

**Cause:** Expensive pathfinding calculation

**Solution:** Already fixed! WaypointGuard now:
1. Detects when player > 100 tiles away
2. Uses autoWalk instead of findPath
3. Prevents the freeze automatically

</details>

<details>
<summary><b>Bot not walking</b></summary>

**Check:**
1. Is CaveBot enabled? (green light)
2. Is TargetBot blocking it? (check smartPull)
3. Are there waypoints in the list?
4. Is there a path to the waypoint?

</details>

<details>
<summary><b>Stuck at door</b></summary>

**Solution:**
1. Enable `Auto Open Doors` in config
2. Make sure door item IDs are correct
3. Add a manual `use` waypoint if needed

</details>

<details>
<summary><b>Wrong floor after teleport</b></summary>

**Cause:** Unexpected floor change

**Solution:**
1. The bot auto-detects floor changes
2. Add a waypoint on each floor
3. Use `stairs` action for known level changes

</details>

---

## 💡 Pro Tips

> [!TIP]
> **Efficiency Tip:** Use precision in waypoints to reduce exact positioning time.
> `32000,32000,7,2` is faster than `32000,32000,7`

> [!TIP]
> **Memory Tip:** Keep scripts under 200 waypoints for best performance.

> [!TIP]
> **Safety Tip:** Always add a `label:depot` and escape route for emergencies.
