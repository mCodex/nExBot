# 🛠️ Extras and Tools

Additional utilities and quality-of-life features built into nExBot.

---

## 📖 Overview

Beyond the core HealBot, AttackBot, CaveBot, and TargetBot modules, nExBot includes a rich set of extra tools and utilities accessible from the **Extras** panel on the Main tab.

---

## 🛡️ Safety Systems

### Anti-RS (Rapid Skulling Protection)

Protects you from accidentally attacking a player and getting a PK skull:

- Detects PvP flag changes
- Immediately stops all combat
- Auto-unequips weapons
- Can exit the game safely
- Configurable reaction delays

### Alarm System

Configurable alarms for various game events:

| Alarm | Trigger |
|-------|---------|
| Player detected | Another player appears on screen |
| Low health | HP drops below threshold |
| Low mana | Mana drops below threshold |
| Private message | You receive a PM |
| Disconnect | Connection lost |
| Death | Your character dies |

Alarms can play sounds, flash the screen, or trigger custom actions.

### Spy Level

Monitors nearby creatures and players on adjacent floors, providing awareness of threats you can't see on your current floor.

---

## 🧰 Equipment Management

### Equipper

Automatic equipment swapping based on combat conditions:

- Swap rings (life ring, mana ring, etc.) based on HP/mana thresholds
- Switch weapons for different combat situations
- Equip amulets/necklaces conditionally
- Belt slot management

### Outfit Cloner

Copies the outfit of another player. Useful for blending in on PvP servers.

### Dropper

Automatically drops configured items from your inventory. Useful for clearing junk loot.

---

## 💥 Push Max

Automated pushing system for team hunts:

- Pushes creatures into optimal positions
- Configurable push targets and directions
- Works with TargetBot's movement coordinator

---

## 🎮 Combo System

Synchronized spell casting for team hunts:

- Coordinate attack timing with party members
- Trigger AoE combos simultaneously
- Configurable combo chains
- Leader/follower mode

---

## 🔒 Hold Target

Locks onto a specific creature and prevents target switching. Useful when you need to focus down a specific monster regardless of what else appears.

---

## 🎒 Supplies Panel

The Supplies panel provides an overview of your current supply status:

- Real-time count of potions, runes, and ammunition
- Low-supply warnings
- Integration with CaveBot's supply check waypoints

---

## 📦 Depositor Config

Configure what happens when CaveBot reaches a depot:

- Set items to deposit
- Set items to keep
- Configure stackable item handling
- Deposit-all vs. selective deposit
- OTCR stash integration

---

## 💬 NPC Talk

Automated NPC interaction:

- Predefined conversation flows for buying/selling
- Bank operations (deposit gold, withdraw)
- Quest NPC interactions
- Travel NPC conversations

---

## ✏️ In-Game Editor

The in-game editor allows you to modify CaveBot waypoints and TargetBot configs directly within the client UI, without editing files manually.

---

## 🎮 Cavebot Control Panel

A quick-access panel for controlling CaveBot without opening the full editor:

- Start/Stop buttons
- Current waypoint indicator
- Skip waypoint
- Pause/Resume

---

## ✨ OTCR-Exclusive Features

These features are available only when running on OpenTibiaBR's OTCR client:

### Imbuing

Automate imbuement application at imbuing shrines:

- Configure desired imbuements per equipment slot
- Automatic shrine interaction
- Protection charm support
- Integrated into CaveBot waypoints

### Stash Operations

Interact with the OTCR stash system:

- Withdraw items from stash
- Deposit items to stash
- Integrated with the depositor flow

### Forge Operations

Access OTCR's forge system:

- Fuse items
- Use refinement cores
- All through the ACL adapter

### Prey System

Interact with OTCR's prey system through the adapter layer.

---

## 👤 Per-Character Profiles

nExBot saves separate profiles for each character:

| Module | Profile Type | Storage |
|--------|-------------|---------|
| HealBot | Profile 1–5 | Numbered |
| AttackBot | Profile 1–5 | Numbered |
| CaveBot | Config name | String |
| TargetBot | Config name | String |

When you switch characters, their last-used profiles are automatically restored. Profiles are stored in `character_profiles.json`.

```json
{
  "CharacterA": {
    "healProfile": 2,
    "attackProfile": 3,
    "cavebotProfile": "Dragon_Darashia",
    "targetbotProfile": "Dragons"
  },
  "CharacterB": {
    "healProfile": 1,
    "attackProfile": 1,
    "cavebotProfile": "Hydra_Oramond",
    "targetbotProfile": "Hydras"
  }
}
```

---

## 🖼️ Multi-Client Support

nExBot supports running multiple OTClient instances simultaneously. Each character's configurations are independent — there is no conflict between running bots.
