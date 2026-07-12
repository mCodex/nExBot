# FAQ

## Installation

**Where do I install?**
Copy `nExBot/` into your client's `bot/` directory. vBot: `%APPDATA%/OTClientV8/<ServerName>/bot/nExBot`. OTCR: `~/.local/share/<otcr-data>/<ServerName>/bot/nExBot`.

**Bot not loading:** Verify `_Loader.lua` is in root. Press `Ctrl+B` → Disable → Enable. Check console (`Ctrl+Shift+D`).

**Multiple servers?** Yes. Copy `nExBot/` to each server's `bot/`. Configs are per-server.

**How to update?** Back up config folders → delete old `nExBot/` → copy new → restore configs.

## HealBot

**Not healing:** Toggle enabled? Spells configured? Names correct? Enough mana? HP below threshold? On cooldown?

**Healing spells:** `exura` = small/fast, `exura vita` = medium, `exura gran` = large/slow. Use `exura vita` as main.

**Need potions with spells?** Yes. Spells cost mana. Potions as fallback when mana runs out.

**Dying too fast:** Lower thresholds (60% not 50%). Add potion fallbacks. Add `utamo vita`. Check hunting area difficulty.

## CaveBot

**How to create waypoints?** Cave tab → Show Editor → stand at position → Add Goto → walk → Add Goto → save. Or use Recorder.

**Stops moving:** Enabled? Started (`Ctrl+Z`)? Pull System pausing? Coordinates reachable? Door/field blocking?

**Tile-by-tile walking:** autoWalk needs ≥5 tiles with ≤55% direction changes. Many tight turns → keyboard stepping. Space waypoints 5–15 tiles apart.

**Stuck at door:** Enable Auto Open Doors. Add `door` waypoint. Verify door item IDs.

**Multiple routes?** Yes. Each route saved as `.cfg` in `cavebot_configs/`.

## TargetBot

**How to add monsters?** Target tab → + → enter name → configure → Save.

**Pattern matching:** `Dragon` = exact, `Dragon*` = starts with, `*, !Dragon` = except.

**Not attacking:** Enabled? Creatures configured? On screen? Mana?

**Zigzag switching:** Engagement Lock prevents this. FEW (2–3 monsters) = 5s cooldown. Enable `MonsterAI.DEBUG`.

**Not looting:** Enabled? Containers open? Creature in range?

## AttackBot

**Attacks not firing:** Enabled? Target exists? Off cooldown? Enough mana? Monster count met?

**AoE not triggering:** Threshold too high? Monsters in range? Creatures attackable?

**Wasting runes:** Add `Monsters ≥ 2` condition. Separate AoE from single-target.

## Containers

**Not opening:** Auto Open enabled? Assigned correctly? Wait a few seconds. Check console.

**Quiver not refilling:** Arrows/bolts in supply? Quiver equipped? Correct type?

## Performance

**Is nExBot fast?** HealBot 75ms, TargetBot 50ms, CaveBot 250ms. CPU ~3–5%, memory ~15–30MB.

**Reduce CPU:** Disable unused modules. Reduce TargetBot creatures. Increase CaveBot interval. Check for infinite loops in custom actions.

## Errors

**"Error loading config":** Corrupted. Delete and recreate. Don't edit `.cfg` manually.

**Stops randomly:** Died? Out of supplies? Anti-RS triggered? Condition blocking? Invalid waypoint?

**"Not enough mana":** Add mana potion or use lower-cost spell.

**"attempt to call global nil":** Module failed to load. Replace with latest version.

## Advanced

**Custom scripts?** Place `.lua` in `private/` folder. Auto-loaded after core modules.

**Debug mode:**
```lua
nExBot.showDebug = true
MonsterAI.DEBUG = true
nExBot.printStartupProfile()
print(AttackStateMachine.getState())
```

**Multiple bots?** One per OTClient instance. Use multiple windows.
