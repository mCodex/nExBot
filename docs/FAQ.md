# ❓ Frequently Asked Questions

**Quick answers to common questions**

---

## 🎯 General Questions

<details>
<summary><b>What is nExBot?</b></summary>

nExBot is an advanced automation bot for OTClient V8. It provides:
- **TargetBot** - Intelligent targeting and combat
- **CaveBot** - Waypoint navigation
- **HealBot** - Healing automation  
- **AttackBot** - Attack spell/rune automation
- **And more!**

</details>

<details>
<summary><b>How do I install nExBot?</b></summary>

1. Download the nExBot folder
2. Place it in `OTClientV8/bot/` directory
3. Launch OTClient
4. Enable the bot in-game

</details>

<details>
<summary><b>Is nExBot safe to use?</b></summary>

> [!WARNING]
> Using bots may violate server rules. Use at your own risk!

nExBot includes safety features like:
- Anti-AFK detection
- Random delays
- Human-like behavior patterns

</details>

---

## 🎮 TargetBot Questions

<details>
<summary><b>How does Pull System work?</b></summary>

Pull System makes your character:
1. Attack a monster at range
2. Run backward to pull it
3. Stack multiple monsters
4. **PAUSE** CaveBot while pulling (NEW!)
5. Only continue when monsters are killed

> [!NOTE]
> Pull System now pauses waypoints to prevent losing your respawn!

</details>

<details>
<summary><b>Why is my character not looting?</b></summary>

**Check:**
1. Is looting enabled in TargetBot?
2. Is there a loot container assigned?
3. Is the container open?
4. Is there capacity available?

</details>

<details>
<summary><b>How do I set target priority?</b></summary>

Higher numbers = higher priority.

```
Dragon Lord: Priority 10 (kill first)
Dragon: Priority 5 (kill second)
Dragon Hatchling: Priority 1 (kill last)
```

</details>

---

## 🗺️ CaveBot Questions

<details>
<summary><b>Why does my character freeze when far from waypoint?</b></summary>

**Fixed in v1.0.0!**

The bot now:
1. Uses **autoWalk first** (client's fast pathfinding)
2. Limits manual pathfinding to 50 tiles max
3. Only uses expensive pathfinding for short distances (≤30 tiles)
4. **Waypoint Guard** skips unreachable waypoints after 3 failures

</details>

<details>
<summary><b>CaveBot gets stuck in the middle of the cave</b></summary>

**Fixed with Waypoint Guard!**

Old problem: Bot checked distance from **first waypoint** (depot), which is always far when you're in the cave.

New solution: Bot checks distance from **current focused waypoint**:
1. If unreachable for 3 consecutive checks (15 seconds)
2. Automatically **skips to next waypoint**
3. No more infinite loops!

</details>

<details>
<summary><b>How do I create a hunting script?</b></summary>

1. Open CaveBot Editor
2. Walk to first spot and click "Add Goto"
3. Repeat for your entire route
4. Add "label:hunt" at start
5. Add "gotolabel:hunt" at end
6. Save!

See [CaveBot Documentation](./CAVEBOT.md) for more details.

</details>

<details>
<summary><b>My script gets stuck at doors</b></summary>

**Solutions:**
1. Enable "Auto Open Doors"
2. Add a `use` waypoint at the door
3. Check if door requires a key

</details>

---

## ❤️ HealBot Questions

<details>
<summary><b>What's the best heal setup?</b></summary>

**Recommended order (top to bottom):**
```
1. HP < 25%: Supreme Health Potion (emergency)
2. HP < 50%: Strong healing spell
3. HP < 80%: Light healing spell
4. MP < 30%: Mana Potion
5. MP < 60%: Mana regeneration
```

</details>

<details>
<summary><b>My heals are delayed</b></summary>

**Causes:**
1. Spell is on cooldown
2. Not enough mana
3. Another action blocking
4. Ping issues

**Fix:** Add a backup heal with potions (no cooldown)

</details>

---

## ⚔️ AttackBot Questions

<details>
<summary><b>How do I set up AoE attacks?</b></summary>

Add monster count condition:
```
Groundshaker: Monsters >= 4
Great Fireball: Monsters >= 3
Single Target: Monsters >= 1
```

</details>

<details>
<summary><b>My attacks aren't firing</b></summary>

**Check:**
1. Is AttackBot enabled?
2. Is there a target selected?
3. Is the spell on cooldown?
4. Do you have enough mana?
5. Are monster count conditions met?

</details>

---

## 📦 Container Questions

<details>
<summary><b>How do I set up auto-loot?</b></summary>

1. Assign a loot container
2. Enable looting in TargetBot
3. Configure what items to loot
4. Hunt and profit! 💰

</details>

<details>
<summary><b>How does quiver management work?</b></summary>

The bot automatically:
1. Detects low arrow/bolt count
2. Finds arrows in containers
3. Moves them to quiver
4. No configuration needed!

> [!NOTE]
> This is enabled by default for all characters.

</details>

---

## ⚡ Performance Questions

<details>
<summary><b>Why is my client slow?</b></summary>

**Check:**
1. Too many modules enabled?
2. Complex hunting script?
3. Far from waypoints?

**See:** [Performance Guide](./PERFORMANCE.md)

</details>

<details>
<summary><b>How do I reduce CPU usage?</b></summary>

nExBot v1.0.0 includes many optimizations:
- Cached calculations
- Event-driven updates
- Pathfinding limits

If still slow:
1. Reduce active modules
2. Simplify conditions
3. Increase macro intervals

</details>

---

## 🔧 Troubleshooting

<details>
<summary><b>Bot not loading</b></summary>

**Check:**
1. Files in correct location?
2. Lua syntax errors in console?
3. Missing dependencies?

**Fix:** Check `_Loader.lua` for errors.

</details>

<details>
<summary><b>Eat Food not working</b></summary>

**How it works now:**
- Simple 3-minute timer
- Searches all open containers for food
- Supports Brown Mushroom and other common foods

**Check:**
1. Is your food container **open**?
2. Is "Eat Food (3 min)" macro enabled?
3. Do you have supported food items? (Brown Mushroom = 3725)

> [!TIP]
> The bot searches ALL open containers including nested ones!

</details>

<details>
<summary><b>Random disconnections</b></summary>

**Possible causes:**
1. Server anti-bot detection
2. Network issues
3. Client bugs

**Tips:**
1. Add random delays
2. Don't hunt 24/7
3. Use human-like patterns

</details>

---

## 📚 More Help

| Need | Resource |
|------|----------|
| TargetBot help | [TARGETBOT.md](./TARGETBOT.md) |
| CaveBot help | [CAVEBOT.md](./CAVEBOT.md) |
| HealBot help | [HEALBOT.md](./HEALBOT.md) |
| AttackBot help | [ATTACKBOT.md](./ATTACKBOT.md) |
| Container help | [CONTAINERS.md](./CONTAINERS.md) |
| Performance | [PERFORMANCE.md](./PERFORMANCE.md) |

---

## 💬 Still Need Help?

> [!TIP]
> Check the documentation first - most answers are there!

If you found a bug or have a feature request:
1. Check existing issues
2. Provide detailed reproduction steps
3. Include your configuration
4. Describe expected vs actual behavior
