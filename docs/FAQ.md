# ❓ FAQ - Frequently Asked Questions

**Quick answers to common nExBot questions and issues**

---

## Table of Contents

- [Installation & Setup](#-installation--setup)
- [HealBot Questions](#-healbot-questions)
- [CaveBot Questions](#-cavebot-questions)
- [TargetBot Questions](#-targetbot-questions)
- [Performance & Optimization](#-performance--optimization)
- [Errors & Troubleshooting](#-errors--troubleshooting)
- [Advanced Topics](#-advanced-topics)

---

## 📦 Installation & Setup

### Q: Where do I install nExBot?

**A:** Copy the `nExBot` folder to:
```
C:\Users\YourName\AppData\Roaming\OTClientV8\<YourServerName>\bot\nExBot
```

Example:
```
C:\Users\matan\AppData\Roaming\OTClientV8\Tibia Realms RPG\bot\nExBot
```

Make sure `_Loader.lua` is in the root!

### Q: Bot not loading - how do I fix it?

**A:** Checklist:
1. ✅ Correct folder path? (see above)
2. ✅ `_Loader.lua` exists in root?
3. ✅ OTClientV8 v8+ installed?
4. ✅ Reload bot: `Ctrl+B` → Disable → Enable
5. ✅ Check console: `Ctrl+Shift+D` for errors

If still broken:
- Try fresh install (delete bot folder, reinstall)
- Check OTClientV8 logs for error messages
- Make sure no files are corrupted

### Q: Can I use nExBot on multiple servers?

**A:** **YES!** Copy the bot folder to each server's bot directory:
```
bot\Server1\nExBot\        ← nExBot on Server 1
bot\Server2\nExBot\        ← nExBot on Server 2
bot\MyServer\nExBot\       ← nExBot on MyServer
```

Configs are **per-server**, so each has independent setups.

### Q: Do I need to update nExBot?

**A:** Check version in README.md or Main tab. To update:
1. Backup your configs folder (important!)
2. Delete old bot folder
3. Install new version
4. Copy your configs back

Most updates are backward compatible!

---

## 💊 HealBot Questions

### Q: HealBot isn't healing me - why?

**A:** Check in order:

1. **Is HealBot ENABLED?**
   - Main tab → Healing section
   - Should see green toggle

2. **Do you have spells configured?**
   - Healing tab → see your spells?
   - Need at least one spell!

3. **Do you have enough MANA?**
   - Spell costs mana to cast
   - Check mana bar in-game
   - Low mana? → Add potion backup

4. **Is your HP below the threshold?**
   - Spell @ 50% triggers at ≤ 50% HP
   - If you're at 60%, spell won't cast!

5. **Is spell name correct?**
   - `exura` not `exra`
   - `exura vita` not `exuravita`
   - Copy-paste directly from spell list!

6. **Spell on cooldown?**
   - Healing spells have 1-2 sec cooldown
   - HealBot waits for cooldown to finish
   - This is NORMAL

> [!TIP]
> **INSTANT FIX**: Add a potion as backup at 40% HP. Potions are fast and reliable!

### Q: What's the difference between "exura" and "exura vita"?

**A:**
```
exura      = Small heal (~200 HP)
           = Lower mana cost (~20)
           = Slower casting

exura vita = Medium heal (~300 HP)
           = Higher mana cost (~60)
           = Faster casting

exura gran = Large heal (~600 HP)
           = Very high mana cost (~100)
           = Slowest casting
           = EMERGENCY only
```

**Recommendation:** Use `exura vita` as main heal, `exura` as backup.

### Q: Can I heal myself with different spells at different HP?

**A:** **YES!** This is the smart setup:

```
exura vita @ 50% HP  (medium health)
exura @ 30% HP       (low health, quick heal)
exura gran @ 10% HP  (emergency, last resort)
```

Each spell triggers at its threshold. HealBot casts whichever is active!

### Q: Do I need potions if I have healing spells?

**A:** **Strongly recommended**, because:
- Spells cost mana (limited resource)
- You can run out of mana!
- Potions work without mana
- Backup is critical for survival

**Best setup:** Spell + potion combo

### Q: How do I use potions I'm wearing?

**A:** HealBot finds potions:
- In backpack ✅
- Equipped in armor slots ✅
- On the ground ✅
- Anywhere! ✅

Just make sure potion is configured in Healing tab.

### Q: Can I heal with food (apples, meat)?

**A:** **Limited:**
- Food heals VERY slowly (passive)
- Use only for maintaining stamina
- Not for emergency healing
- Better for long AFK hunting

**Config:**
```
Food: Apple
Interval: Every 3 minutes
Effect: +~50 HP (slow)
```

### Q: What's "mana shield"?

**A:** Special support spell that:
- Converts damage to mana instead of HP
- 2:1 ratio (2 mana = 1 damage blocked)
- Great for standing still
- Don't use if low mana!

**Example:**
```
Without mana shield:  Take 50 damage → -50 HP
With mana shield:     Take 50 damage → -100 mana, +0 damage
```

---

## 🗺️ CaveBot Questions

### Q: How do I create waypoints?

**A:** Step by step:

1. **Open editor:** Cave tab → click "Waypoint Editor" button
2. **Stand at start position**
3. **Click "Add Goto"** → waypoint created
4. **Walk to next location** (on foot, manually)
5. **Click "Add Goto"** again
6. **Repeat** until you complete the route
7. **Click "Save"** and name your config (e.g., "Dragons_Oramond")
8. **Enable** CaveBot and select your config

### Q: What's the difference between waypoint types?

**A:**
```
goto (100,200,7)    = Walk to coordinates
label "Start"       = Mark location (no movement)
action SCRIPT       = Execute custom Lua code
buy ITEM,COUNT,NPC  = Trade with NPC
lure Monster        = Pull creature
rope/shovel         = Use tool
travel WAYPOINT     = Teleport to waypoint
```

Most hunts use `goto` + `action` for everything!

### Q: Why does CaveBot stop moving?

**A:** Usually:
1. **Floor change detected** - Stairs/ladder
   - CaveBot won't walk on stairs (safety)
   - Use `action` to handle manually
   
2. **Door blocking path**
   - Need `door` action in waypoint
   - CaveBot will open automatically

3. **Waypoint unreachable**
   - Check coordinates are correct
   - Use precision: `1000,1000,7,3` (3 tile radius)

4. **Field blocking path**
   - Fire/poison/energy field
   - CaveBot uses keyboard to cross
   - Takes longer, but works

### Q: Can CaveBot open doors?

**A:** **YES!** Add `door` action in waypoint:

```
goto 1000,1000,7
door
goto 1005,1005,7
```

CaveBot automatically:
- Detects door position
- Opens it
- Walks through
- Continues route

### Q: How do I make CaveBot use ropes and shovels?

**A:** Use `rope` or `shovel` actions:

```
goto 1000,1000,7      (walk to hole)
rope                  (use rope to descend)
goto 1000,1000,8      (now on floor 8)
```

Or for shovels:
```
goto 1000,1000,7
shovel
goto 1000,1000,7      (wait for hole to open)
```

### Q: Can CaveBot pull monsters?

**A:** **YES!** Use `lure` action:

```
goto 1000,1000,7
action() function()
  CaveBot.lure("Dragon", 1)  -- Pull 1 dragon
end

-- Then setup your normal combat
```

Or simpler:
```
lure Dragon 1
```

### Q: My CaveBot routes keep teleporting - why?

**A:** You probably set waypoint coordinates too far apart:
- Walking max ~15 tiles per call
- Waypoints > 50 tiles = teleport
- Keep waypoints within 10-20 tiles!

**Fix:** Add intermediate waypoints

### Q: Can I save multiple CaveBot routes?

**A:** **YES!**
```
CaveBot Config 1: Dragons_Oramond.cfg
CaveBot Config 2: Hydras_Fort.cfg
CaveBot Config 3: Demons_Darashia.cfg
```

Choose which to load before starting!

---

## 🎯 TargetBot Questions

### Q: How do I add monsters to target?

**A:** Target tab → click [+] button:

1. Enter monster name: `Dragon`
2. Choose spells: `exori`, `exori con`
3. Set spell properties (mana, range)
4. Click Save

Repeat for each monster type!

### Q: What's "pattern matching"?

**A:**
```
Dragon*      = Matches Dragon, Dragonlord, Dragon Knight
*Demon       = Matches Demon, Grand Demon, Evil Demon
!Dragon      = EXCLUDE Dragons (attack everything except)
#100-#110    = Target creature IDs 100-110 (advanced)
, !Red*      = Attack everything except Red creatures
```

**Examples:**
```
Pattern: "*, !Dragon"
= Attack every monster EXCEPT Dragons

Pattern: "Demon, Grand Demon"
= Attack Demons and Grand Demons only

Pattern: "*Evil*"
= Attack anything with "Evil" in name
```

### Q: Why isn't TargetBot attacking?

**A:** Check:

1. **Is TargetBot ENABLED?** (green toggle)
2. **Do monsters exist?** (need creatures to attack)
3. **Are monsters in range?** (spell maxDistance)
4. **Do you have MANA?** (spell costs mana)
5. **Is spell configured?** (in monster config)
6. **No target selected?** (need at least one monster type)

### Q: How do area spells work?

**A:** TargetBot:
1. Finds all nearby creatures
2. Calculates damage coverage for each position
3. Walks to best position
4. Casts AoE spell
5. Hits maximum creatures!

**Benefits:** Kill 5 monsters with 1 spell!

### Q: Can I use runes with TargetBot?

**A:** **YES!** Add runes to monster config:

```
Monster: Dragon
Spells: exori, exori con
Runes:  Sudden Death (slot 8)
```

TargetBot will:
- Cast spell when rune not available
- Use rune when spell on cooldown
- Smart selection!

---

## 🚀 Performance & Optimization

### Q: Is nExBot fast/slow?

**A:** **VERY FAST:**
```
HealBot:        75ms response (instant!)
TargetBot:      50ms targeting
CaveBot:        250ms movement tick
Hunt Analyzer:  20ms metric calc

CPU Usage:      ~3-5% (minimal!)
Memory:         ~15-30MB total
```

### Q: How do I reduce CPU usage?

**A:**

1. **Disable Hunt Analyzer** if not needed
   - Saves ~2-3% CPU

2. **Reduce TargetBot creatures**
   - More creatures = more calculations
   - Only target necessary monsters

3. **Increase CaveBot interval**
   - Default 250ms is fast
   - Can increase to 500ms (still fine)
   - Don't go below 100ms

4. **Disable unused features**
   - Anti-RS if not PvP
   - Equipment manager if manual
   - Condition handlers if not needed

### Q: Bot is using too much CPU - help!

**A:** Steps:
1. Close other programs (Chrome, Discord, etc)
2. Disable Hunt Analyzer
3. Reduce TargetBot creature list
4. Check for infinite loops in custom actions
5. Enable debug mode to see where time goes

### Q: Does nExBot work on old/slow PCs?

**A:** **YES!** But:
- Increase CaveBot interval to 500ms
- Limit TargetBot creatures
- Disable Hunt Analyzer
- Avoid complex custom actions
- Don't use AoE optimizing (expensive)

Should still work on older hardware!

---

## ❌ Errors & Troubleshooting

### Q: "Error loading config" - what happened?

**A:** Config file corrupted. Fix:

1. Open config file in text editor
2. Look for syntax errors:
   - Missing commas
   - Unclosed brackets
   - Wrong quotes
3. Or delete and recreate config

**Prevention:** Don't edit config files manually!

### Q: Bot stops randomly - why?

**A:** Common causes:

1. **Died** - Check death penalty
2. **Out of resources** - Need mana/potions
3. **Anti-RS triggered** - PvP flag detected
4. **Condition handler** - Poison/paralyze/burn
5. **CaveBot waypoint error** - Invalid coordinate

**Debug:** Check console with `Ctrl+Shift+D`

### Q: "Not enough mana" messages spam

**A:**
1. Spell costs 60 mana, you have 40
2. Options:
   - Use lower-cost spell
   - Drink mana potion
   - Increase magic level
   - Add potion fallback

### Q: Bot won't move - frozen in place

**A:** Possible causes:

1. **Paralyzed** - Wait ~30 seconds or use cure potion
2. **Stuck on wall** - CaveBot will auto-recover in 3 sec
3. **No valid paths** - Surrounded by walls/monsters
4. **CaveBot paused** - Check toggle switch

### Q: Getting killed frequently

**A:**

1. **Wrong hunting area** - Too difficult
2. **HealBot not working** - Check setup
3. **TargetBot pulling too many** - Reduce lure size
4. **Monster AI smarter than expected** - Give it more space

**Solution:** Hunt lower-level monsters until better geared

### Q: TargetBot keeps switching targets

**A:** This is NORMAL behavior:
- Prioritizes dying creatures (kill fastest)
- Switches if new threat appears
- Prevents wasted attacks

If it bothers you:
- Enable "lock target" option
- Once locked, won't switch until death

### Q: "Creature not found" - can't target monster

**A:**
1. **Monster name misspelled** - Check exact name
2. **Creature doesn't exist** - Wrong area
3. **Pattern doesn't match** - Use wildcard (e.g., `Dragon*`)
4. **Creature ID out of range** - Wrong level area

---

## 🎓 Advanced Topics

### Q: Can I create custom scripts for CaveBot?

**A:** **YES!** Use `action` waypoints:

```lua
action() function()
  -- Custom Lua code here
  print("Custom action running!")
  
  -- Access bot systems:
  if Player.getHealth() < 200 then
    CaveBot.pause()  -- Stop bot
  end
end
```

### Q: How do I profile/debug the bot?

**A:**
```lua
-- Enable debug mode:
nExBot.debug = true

-- Check load times:
print(nExBot.loadTimes)

-- Profile specific function:
local start = os.clock()
someFunction()
print("Took: " .. (os.clock() - start) * 1000 .. "ms")
```

### Q: Can I create custom conditions for healing?

**A:** Advanced setup:
```lua
Condition: if Player.staminaInfo().greenRemaining > 0
Spell: exura vita
```

Only heal during green stamina!

### Q: How do I completely reset the bot?

**A:**

1. Delete bot folder
2. Delete config folders
3. Reinstall fresh copy
4. Start from scratch

This clears ALL data/cache!

### Q: Can I run multiple bots simultaneously?

**A:** **NO** - One bot per OTClientV8 instance
- One bot per game window
- Use multiple windows for multibox

---

## 📞 Still Have Questions?

Check the full documentation:
- 📖 [README](README.md)
- 🗺️ [CaveBot Guide](docs/CAVEBOT.md)
- 🎯 [TargetBot Guide](docs/TARGETBOT.md)
- 💊 [HealBot Guide](docs/HEALBOT.md)
- 📊 [Hunt Analyzer](docs/SMARTHUNT.md)

---

<div align="center">

**nExBot FAQ** - Common Questions Answered ❓

*Powered by nExBot Documentation Team*

</div>
