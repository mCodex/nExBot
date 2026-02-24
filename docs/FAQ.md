# ❓ FAQ

Frequently asked questions and troubleshooting guide.

---

## 💻 Installation

### Where do I install nExBot?

Copy the `nExBot` folder into your OTClient's bot directory:

- **vBot (OTClientV8):** `%APPDATA%/OTClientV8/<ServerName>/bot/nExBot`
- **OTCR (OpenTibiaBR):** `~/.local/share/<otcr-data>/<ServerName>/bot/nExBot`

See the full [Installing guide](INSTALLING.md) for detailed instructions.

### The bot isn't loading

1. Verify the folder path is correct and `_Loader.lua` is in the root
2. Press `Ctrl+B` → Disable → Enable to reload
3. Press `Ctrl+Shift+D` to check the console for error messages
4. Try a fresh install (backup configs first)

### Can I use nExBot on multiple servers?

Yes. Copy the `nExBot` folder to each server's bot directory. Configs are per-server, so each installation is independent.

### How do I update?

1. Back up `cavebot_configs/`, `targetbot_configs/`, and `nExBot_configs/`
2. Delete the old `nExBot/` folder
3. Copy the new release
4. Restore your config folders

---

## 💚 HealBot

### HealBot isn't healing me

1. Is the toggle **enabled** (green light)?
2. Spells configured? Check the Healing panel.
3. Spell names spelled correctly? (`exura vita`, not `exuravita`)
4. Enough mana for the spell?
5. HP actually below the threshold? A spell at 50% only fires at ≤50% HP.
6. Spell on cooldown? 1–2 second cooldowns are normal.

**Quick fix:** Add a potion at 40% HP as a fallback.

### What's the difference between healing spells?

| Spell | Healing | Mana Cost | Speed |
|-------|---------|-----------|-------|
| `exura` | Small (~200 HP) | Low (~20) | Fast |
| `exura vita` | Medium (~300 HP) | Medium (~60) | Medium |
| `exura gran` | Large (~600 HP) | High (~100) | Slow |

Use `exura vita` as your main heal, `exura` as backup, and `exura gran` for emergencies.

### Do I need potions if I have spells?

Strongly recommended. Spells cost mana — when you run out, potions are your only healing. Always configure at least one potion as a fallback.

### Why am I dying too fast?

- Thresholds too low — try healing at 60% instead of 50%
- No potion fallback — add potions for when mana runs out
- No support spells — `utamo vita` (mana shield) helps in dangerous areas
- Wrong hunting area — the spot may be too hard for your level

---

## 🧭 CaveBot

### How do I create waypoints?

1. Open the Cave tab → click **Show Editor**
2. Stand at position → click **Add Goto**
3. Walk to next position → click **Add Goto** again
4. Repeat for the full route
5. Save with a name

Or use the **Recorder** — click Record, walk your route, stop recording.

### CaveBot stops moving

- Is CaveBot enabled and started (`Ctrl+Z`)?
- Is TargetBot's Pull System pausing navigation?
- Are waypoint coordinates reachable?
- Is there a door or obstacle? Enable Auto Open Doors.
- Field blocking the path? Enable "Ignore fields".

### Bot walks tile-by-tile instead of smooth

- autoWalk activates for paths of 5+ tiles with ≤55% direction changes. If your corridor has many tight turns, the bot uses keyboard stepping with 2-step pipelining instead.
- Check that waypoints aren't all adjacent to floor-change tiles (pipelining is disabled near FC tiles).
- For smoother movement, space waypoints 5-15 tiles apart — this is the sweet spot for autoWalk.

### Bot is stuck at a door

- Enable **Auto Open Doors** in CaveBot config
- Add a manual `door` waypoint before the goto past the door
- Verify the door item ID is recognized

### Waypoints too far apart

Keep waypoints within 10–20 tiles of each other. autoWalk kicks in for paths of 5+ tiles (with ≤55% direction changes), making movement smooth. For paths >50 tiles, pathfinding is capped and recovery may trigger. Add intermediate waypoints for better control.

### Can I save multiple routes?

Yes. Each route is saved as a `.cfg` file in `cavebot_configs/`. Load different configs for different hunting spots.

---

## 🎯 TargetBot

### How do I add monsters?

Target tab → click **+** → enter monster name → configure spells and behavior → Save.

### What's pattern matching?

| Pattern | Effect |
|---------|--------|
| `Dragon` | Matches exactly "Dragon" |
| `Dragon*` | Matches Dragon, Dragon Lord, etc. |
| `*, !Dragon` | Everything except Dragons |
| `#100-#110` | Creature IDs 100–110 |

### TargetBot isn't attacking

1. Is TargetBot enabled?
2. Are creatures configured in the list?
3. Are matching monsters on screen?
4. Do you have mana for attack spells?

### Target keeps switching between monsters

The Engagement Lock should prevent this. If switches are happening:
- Check that creature priorities are configured
- With 2–3 monsters, the switch cooldown is 5 seconds
- Enable `MonsterAI.DEBUG = true` to see why switches happen

### Monsters not being looted

- Is looting enabled in the Target tab?
- Are loot containers open?
- Is the creature within looting range?

---

## ⚔️ AttackBot

### Attacks not firing

1. AttackBot enabled?
2. Valid target selected by TargetBot?
3. Spell on cooldown?
4. Enough mana?
5. Monster count conditions met?

### AoE not triggering

Lower the minimum monster count, check detection range, and verify creatures are attackable (not NPCs or summons).

### Wasting runes on single targets

Add a `Monsters ≥ 2` condition to area runes and separate AoE from single-target rules.

---

## 📦 Containers

### Containers not opening on login

1. Is **Auto Open** enabled?
2. Are containers correctly assigned?
3. Wait a few seconds — there's a deliberate startup delay
4. Check console for errors

### Quiver not refilling

1. Do you have arrows/bolts in a supply container?
2. Is the quiver equipped?
3. Are arrows the correct type for your weapon?

---

## ⚡ Performance

### Is nExBot fast?

Yes. Typical performance:
- HealBot: 75 ms response time
- TargetBot: 50 ms target evaluation
- CaveBot: 250 ms movement tick
- CPU usage: ~3–5%
- Memory: ~15–30 MB

### How do I reduce CPU usage?

1. Disable unused modules (Hunt Analyzer, Monster Inspector)
2. Reduce TargetBot creature list
3. Increase CaveBot interval (500 ms is fine)
4. Avoid complex custom actions in CaveBot

### Bot using too much CPU?

- PathCursor preservation eliminates redundant A* calls per tick — fewer pathfinding operations overall
- 4-entry LRU cache catches repeated pathfinding queries
- Close heavy programs (browser, Discord)
- Check for infinite loops in custom CaveBot actions
- Enable `nExBot.printStartupProfile()` to find slow modules

---

## 🚨 Errors

### "Error loading config"

Config file corrupted. Delete it and recreate from scratch. Don't edit `.cfg` files manually.

### Bot stops randomly

Common causes:
1. Character died
2. Out of supplies (potions, runes)
3. Anti-RS triggered (PvP flag detected)
4. Paralyze/condition handler blocking actions
5. Invalid CaveBot waypoint coordinate

Check the console with `Ctrl+Shift+D` for error messages.

### "Not enough mana" spam

The spell costs more mana than you have. Add a mana potion to your rotation, or use a lower-cost spell.

### "attempt to call global nil" errors

A module failed to load or is outdated. Replace the affected file with the latest version and restart the client.

---

## 🔧 Advanced

### Can I write custom scripts?

Yes. Place `.lua` files in a `private/` folder inside `nExBot/`. They're auto-loaded after all core modules and have access to the full API.

### CaveBot custom actions

Use `action` waypoints for Lua code:

```lua
action() function()
  if player:getHealth() < 200 then
    CaveBot.setOff()
  end
end
```

### How do I debug?

```lua
-- Enable verbose logging
nExBot.showDebug = true
MonsterAI.DEBUG = true

-- View startup profile
nExBot.printStartupProfile()

-- Check AttackStateMachine state
print(AttackStateMachine.getState())
```

### Can I run multiple bots?

One bot per OTClient instance. Use multiple client windows for multi-boxing.
