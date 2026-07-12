# Extras and Tools

Additional utilities beyond core modules.

## Safety

### Anti-RS

Stops all combat on PvP flag change. Auto-unequips weapons. Can exit game. Configurable delays.

### Alarms

| Alarm | Trigger |
|-------|---------|
| Player detected | Player on screen |
| Low health | HP below threshold |
| Low mana | Mana below threshold |
| Private message | PM received |
| Disconnect | Connection lost |
| Death | Character dies |

Play sounds, flash screen, or trigger custom actions.

### Spy Level

Monitors creatures/players on adjacent floors.

## Equipment

### Equipper

Swap rings, weapons, amulets based on HP/mana thresholds.

### Outfit Cloner

Copy another player's outfit.

### Dropper

Auto-drop configured items from inventory.

## Combat

### Push Max

Push creatures into optimal positions for team hunts.

### Combo System

Synchronized spell casting — coordinate timing, trigger AoE simultaneously, leader/follower mode.

### Hold Target

Lock onto specific creature, prevent target switching.

## Supplies Panel

Real-time count of potions, runes, ammunition. Low-supply warnings. CaveBot supply check integration.

## Depositor Config

Configure depot behavior: items to deposit/keep, stackable handling, OTCR stash integration.

## NPC Talk

Automated NPC interaction — buy/sell, bank, quests, travel.

## In-Game Editor

Modify CaveBot waypoints and TargetBot configs in-client.

## Cavebot Control Panel

Quick-access: start/stop, current waypoint, skip, pause/resume.

## OTCR-Exclusive

| Feature | Description |
|---------|-------------|
| Imbuing | Auto-apply imbuements at shrines |
| Stash | Withdraw/deposit items |
| Forge | Fuse items, refinement cores |
| Prey | Prey system interaction |

## Per-Character Profiles

Separate profiles per character, auto-restored on switch:

```json
{
  "CharacterA": {
    "healProfile": 2,
    "attackProfile": 3,
    "cavebotProfile": "Dragon_Darashia",
    "targetbotProfile": "Dragons"
  }
}
```

Stored in `character_profiles.json`.

## Multi-Client

Multiple OTClient instances supported. Configs independent per character.

## macOS

`g_window.setTitle()` wrapped in `pcall()` to prevent C++ exception. Known OTClient issue.
