# CaveBot

Automated waypoint navigation, supply management, and hunting route automation.

---

## Overview

CaveBot is nExBot's navigation engine. It follows a list of waypoints to walk your character through hunting routes, open doors, use tools, refill supplies, deposit loot, and interact with NPCs — all automatically.

Key capabilities:

- Waypoint-based route navigation
- Floor-change prevention (never accidentally walks on stairs)
- Intelligent field handling (fire, poison, energy)
- Door opening and tool usage (rope, shovel, machete)
- Supply refilling and loot depositing
- NPC trading (buy/sell)
- Lure and stand-lure systems
- Bank operations (deposit gold, withdraw)
- Imbuing automation (OTCR only)
- Travel system (boats, carpets, teleports)
- Task/quest management
- Save/load complete routes as config files

---

## Quick Start

1. Open the **Cave** tab.
2. Click **Show Editor** to open the waypoint editor.
3. Stand at your starting location and click **Add Goto**.
4. Walk to your next location and click **Add Goto** again.
5. Repeat until your route is complete.
6. Save your config with a name (e.g. `Dragon_Darashia`).
7. Toggle CaveBot **ON** and press **Start** (`Ctrl+Z`).

---

## Waypoint Types

### Movement

#### goto

Walk to a specific coordinate.

```text
32000,32000,7        → Walk to exact position
32000,32000,7,3      → Walk within 3 tiles of position
```

> Use the **precision** parameter (4th value) to avoid wasting time on exact positioning. A value of 2–3 is recommended for most waypoints.

#### label

Mark a named position for jumps.

```text
label:hunt
label:refill
label:depot
```

> Labels are case-sensitive. `Hunt` and `hunt` are different labels.

#### gotolabel

Jump execution to a named label.

```text
gotolabel:hunt       → Resume from the "hunt" label
gotolabel:depot      → Jump to depot sequence
```

### Conditional

#### checkSupplies

Check item quantity and branch if low.

```text
3160,50,refill       → If mana potions < 50, goto "refill"
3155,20,depot        → If SD runes < 20, goto "depot"
```

#### checkCapacity

Check carrying capacity and branch if low.

```text
200,depot            → If cap < 200 oz, goto "depot"
```

#### posCheck

Check if the player is on a specific floor or position and branch accordingly.

### Town Actions

#### depositor

Deposit all loot in the depot. Works with the Depositor configuration panel where you set which items to deposit and which to keep.

#### buy

Buy items from an NPC.

```text
3160,200,Eremo       → Buy 200 mana potions from Eremo
```

#### sell

Sell items to an NPC. The Sell All module can automatically sell all configured loot items.

#### bank

Deposit or withdraw gold from the bank NPC.

### Tools

#### rope / shovel / machete

Use the corresponding tool at the current position. CaveBot detects rope holes, stone piles, and jungle grass automatically.

#### door

Open a door at the current waypoint position.

### Special

#### lure

Pull a specified number of creatures before continuing.

```text
lure Dragon 1        → Pull 1 Dragon before moving on
```

#### standLure

Stand in place and lure creatures to your position. Unlike regular lure, the character doesn't chase — it waits for monsters to come.

#### action

Execute custom Lua code at a waypoint.

```lua
action() function()
  if player:getHealth() < 200 then
    CaveBot.setOff()
  end
end
```

#### travel

Use boats, carpets, or teleports to travel between cities.

#### imbuing

Automatically apply imbuements at an imbuing shrine (OTCR-specific).

#### tasker

Interact with task NPCs to accept or complete tasks.

#### withdraw / d_withdraw / inbox_withdraw

Withdraw items from the depot, depot box, or inbox.

---

## Walking Engine (v3.2)

The walking engine is the heart of CaveBot. It handles pathfinding, field avoidance, and floor-change safety.

### Floor-Change Prevention

Before walking any path, the engine validates every tile along the route. If any tile contains a floor-change element (stairs, ladders, ramps), the walk is truncated to stop **before** that tile.

```text
Path Found → Validate each step → Floor change detected?
                                        ↓ Yes
                  Stop before the floor-change tile
                  Walk only to the safe point
```

### Field Handling

When a path crosses fire, poison, or energy fields:

1. Normal pathfinding tries without `ignoreFields`
2. If it fails, retries with `ignoreFields = true`
3. Uses keyboard step-by-step walking (`walk(direction)`) to cross each field tile
4. This bypasses autoWalk's inability to cross damaging fields

Enable **"Ignore fields"** in the CaveBot config panel to allow field crossing.

### Chunked Walking

Paths are split into segments of **max 15 tiles** per autoWalk call. This keeps pathfinding fresh and prevents stale routes in dynamic environments.

### Stuck Detection

If the player hasn't moved for 3 seconds while walking to a waypoint, CaveBot triggers recovery — it cancels the current walk and retries with alternative pathfinding strategies.

### Pathfinding Strategy

```text
1. Try autoWalk (client's built-in fast pathfinding)
2. If that fails → findPath with simple settings
3. If still failing and distance ≤ 30 → findPath ignoring creatures
4. If distance ≤ 15 → findPath allowing unseen tiles
5. If distance > 50 → use autoWalk only (prevents freezes)
```

---

## Waypoint Guard

The Waypoint Guard prevents infinite loops when waypoints become unreachable.

| Behavior | Details |
|----------|---------|
| **Checks** | Current focused waypoint (not the first one) |
| **Rate** | Every 5 seconds (not every tick) |
| **Trigger** | Player is on wrong floor or > 100 tiles away |
| **Recovery** | After 3 consecutive failures, skips to next waypoint |

---

## Supply Management

### Supply Check

Before continuing a hunt loop, CaveBot can check your supply levels:

- Health potions, mana potions, spirit potions
- Runes (SD, Avalanche, GFB, etc.)
- Ammunition (arrows, bolts)
- Carrying capacity

If any supply is below threshold, CaveBot routes to the refill label.

### Refill Flow

A typical refill sequence:

```text
label:hunt
  ... hunting waypoints ...
  checkSupplies:3160,50,refill
  checkCapacity:200,depot
  gotolabel:hunt

label:refill
  goto NPC location
  buy:3160,200,NPC_Name
  gotolabel:hunt

label:depot
  goto depot location
  depositor
  bank
  gotolabel:refill
```

---

## Depositor

The Depositor module handles loot depositing at the depot. Configure it through the **Depositor Config** panel:

- Set which items to deposit
- Set items to keep (stackable supplies)
- Configure deposit-all behavior
- Works with both standard depots and OTCR stash

---

## Pull System Integration

When TargetBot's Lure/Pull system is active, CaveBot **pauses** waypoint execution so the player stays in place and fights. Navigation only resumes after the lure target count is satisfied or all nearby monsters are dead.

---

## Recorder

The CaveBot Recorder allows you to record waypoints by simply walking your route:

1. Click **Record** in the editor
2. Walk your hunting route manually
3. The recorder captures each position as a goto waypoint
4. Stop recording and save

This is the fastest way to create a new route.

---

## Configuration

### Settings

| Setting | Description | Default |
|---------|-------------|---------|
| **Use Delay** | Delay after using items | 400ms |
| **Walk Delay** | Delay between steps | 100ms |
| **Ping Compensation** | Added to all delays | 0ms |
| **Auto Use Tools** | Use rope/shovel automatically | ON |
| **Ignore Fields** | Allow walking through fields | OFF |

### Saving and Loading Configs

CaveBot configs are saved as `.cfg` files in the `cavebot_configs/` folder. Each config contains the complete list of waypoints for a hunting route.

nExBot ships with **50+ pre-built configs** for popular hunting spots:

- Asura Port Hope
- Banuta Hydra/Medusa
- Dragon Darashia
- Demon Alburn
- Hydra Oramond
- Naga Astraea
- And many more...

---

## Script Examples

### Basic Hunting Loop

```text
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

### Full Refill with Bank

```text
label:hunt
  ... waypoints ...
  checkSupplies:3160,50,refill
  checkCapacity:300,depot
  gotolabel:hunt

label:depot
  goto depot
  depositor
  bank
  gotolabel:refill

label:refill
  goto NPC
  buy:3160,200,NPC_Name
  gotolabel:hunt
```

### Custom Action Waypoint

```lua
action() function()
  -- Only hunt during green stamina
  if Player.staminaInfo().greenRemaining > 0 then
    CaveBot.setOn()
  else
    CaveBot.setOff()
  end
end
```

---

## Troubleshooting

### CaveBot stops moving

1. Is CaveBot **enabled** and **started** (`Ctrl+Z`)?
2. Is TargetBot's Pull System pausing navigation?
3. Are the waypoint coordinates reachable from your current position?
4. Is there a door or obstacle blocking the path?
5. Check for field tiles — enable "Ignore fields" if needed.

### Stuck at a door

- Enable **Auto Open Doors** in config
- Add a manual `door` waypoint before the goto past the door
- Verify the door item IDs are recognized

### Wrong floor after teleport

- Add a waypoint on each floor so CaveBot knows the expected floor
- Use the floor-change prevention setting to avoid accidental stair use

### Client freezes when far from waypoint

This is already handled. The Waypoint Guard detects when you're > 100 tiles from the current waypoint and uses autoWalk instead of expensive pathfinding. If it still freezes, check that your route doesn't have unreachable waypoints.
