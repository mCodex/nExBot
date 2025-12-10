# 📚 nExBot Documentation v1.0

<div align="center">

**Complete guide to all nExBot features and configurations**

[🎯 TargetBot](./TARGETBOT.md) • [🗺️ CaveBot](./CAVEBOT.md) • [💊 HealBot](./HEALBOT.md) • [⚔️ AttackBot](./ATTACKBOT.md) • [📊 HuntAnalyzer](./SMARTHUNT.md)

</div>

---

## 🆕 What's New in v1.0

- **🎯 Dynamic Scaling** - Movement thresholds scale with monster count
- **⚡ Adaptive Reactivity** - More reactive when surrounded (7+ monsters)
- **🧠 Movement Coordinator** - Dynamic confidence thresholds
- **🛡️ Balanced Behavior** - Conservative with few monsters, reactive with many
- **📊 Hunt Analyzer** - Better insights and recommendations

---

## 📖 Table of Contents

| Module | Description | Link |
|--------|-------------|------|
| 🎯 **TargetBot** | Creature targeting and combat | [View](./TARGETBOT.md) |
| 🗺️ **CaveBot** | Automated waypoint navigation | [View](./CAVEBOT.md) |
| 💊 **HealBot** | Healing spells and potions | [View](./HEALBOT.md) |
| ⚔️ **AttackBot** | Combo spells and AoE attacks | [View](./ATTACKBOT.md) |
| 📦 **Containers** | Auto container management | [View](./CONTAINERS.md) |
| 📊 **HuntAnalyzer** | Analytics, insights & efficiency tracking | [View](./SMARTHUNT.md) |
| ⚡ **Performance** | Optimization guide | [View](./PERFORMANCE.md) |
| ❓ **FAQ** | Common questions & answers | [View](./FAQ.md) |

---

## 🚀 Quick Start

### Step 1: Load the Bot

1. Open OTClientV8
2. Go to **Bot Settings** (usually `Ctrl+B`)
3. Select `nExBot` from the bot list
4. Click **Enable**

### Step 2: Configure Basics

> [!TIP]
> Start with HealBot - it's the most important module for survival!

1. **HealBot**: Set your healing spells and potions
2. **TargetBot**: Add creatures you want to attack
3. **CaveBot**: Load or create waypoint scripts

### Step 3: Start Hunting

1. Enable the modules you need
2. Load a CaveBot script for your hunting spot
3. Let the bot do the work!

---

## 🏗️ Architecture Overview

```
nExBot/
├── 📁 core/           # Core modules (HealBot, AttackBot, etc.)
├── 📁 cavebot/        # CaveBot system
├── 📁 targetbot/      # TargetBot system
│   ├── core.lua           # Pure utility functions
│   ├── monster_behavior.lua   # Behavior pattern recognition
│   ├── spell_optimizer.lua    # AoE position optimization
│   ├── movement_coordinator.lua   # Unified movement decisions
│   └── ...
├── 📁 cavebot_configs/    # Saved CaveBot scripts
├── 📁 targetbot_configs/  # Saved TargetBot configs
├── 📁 docs/           # This documentation
└── 📄 _Loader.lua     # Main entry point
```

---

## ⚡ Performance Tips

> [!IMPORTANT]
> nExBot is optimized for performance, but here are some tips to maximize it:

<details>
<summary><b>Click to expand performance tips</b></summary>

### ✅ Do's

- Keep your creature list focused (don't add unnecessary monsters)
- Use the recommended macro intervals (don't make them faster)
- Close unnecessary game windows
- Keep your backpack organized

### ❌ Don'ts

- Don't enable features you don't need
- Don't set extremely low intervals on macros
- Don't run multiple heavy scripts at once
- Don't have hundreds of waypoints in one script

</details>

---

## 🖥️ Multi-Client Support

> [!TIP]
> nExBot supports running multiple clients with independent configurations!

### Per-Character Profile Persistence

Each character automatically remembers their own active profiles. When you run multiple clients simultaneously, each character loads their own saved configuration.

**How It Works:**
- Profiles are saved per-character in `character_profiles.json`
- When you select a profile, it's saved for **your current character**
- On login, each character's profiles are restored **before** the UI loads
- No manual switching needed - just log in and your settings are ready!

### Per-Character Profile Persistence

Each character remembers their own active profiles:

| Bot | Profile Type | Stored As |
|-----|--------------|-----------|
| **HealBot** | Profile 1-5 | Number |
| **AttackBot** | Profile 1-5 | Number |
| **CaveBot** | Config name | String |
| **TargetBot** | Config name | String |

### How It Works

1. When you select a profile on any bot, it's saved for **your character**
2. When you log into a different character, **their last used profiles** are restored
3. Profiles are stored in `character_profiles.json`

### Example

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

## 🔒 Safety Features

> [!WARNING]
> Always review safety settings before AFK hunting!

| Feature | Description | Location |
|---------|-------------|----------|
| **Anti-RS** | Stops attacks if PK skull would result | AttackBot Settings |
| **PvP Safe** | Prevents hitting players with AoE | AttackBot Settings |
| **Blacklist** | Players to never attack | AttackBot Settings |
| **Alarm System** | Alerts for various conditions | Alarms Panel |

---

<div align="center">

**Made with ❤️ for the Tibia community**

*Last updated: January 2025 - v1.0.0*

</div>
