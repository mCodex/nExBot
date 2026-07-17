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

**Not opening all backpacks**
1. Is Auto Open enabled in the Containers panel?
2. Are roles assigned in the Roles subtab?
3. Wait 3–5 seconds — discovery runs at low priority.
4. Check the Diagnostics subtab for failed nodes.
5. If the main backpack is in the equipped back slot, it is detected automatically. If not, assign the role manually.

**Repeated backpack types — wrong one opens**
The bot tracks physical identity (generation + path + slot + item type), not just item type. Two identical brown backpacks remain distinct. If role assignment is ambiguous, the Roles subtab shows an ambiguity warning. Identify each container manually once and the selector persists through reconnects.

**Discovery runs but stops partway through**
A server exhaustion event likely triggered backoff. Check Diagnostics → exhaustion count. The bot retries automatically (up to 3 attempts per node). If all retries fail, that node shows as "failed" and discovery continues with the others, completing in DEGRADED mode. Use the **Retry Failed** button to attempt recovery.

**Quiver not detected**
1. Is the character a Paladin? (vocation IDs 2 or 12 are detected automatically)
2. Is the quiver actually equipped in the ammo/arrow slot (slot 10)?
3. Check the Quiver & Ammo subtab for detection status.
4. Some custom servers use non-standard quiver item IDs — add them to `QUIVER_ITEM_IDS` in `core/containers/quiver.lua`.
5. Check console for errors.

**Ammo not transferred to quiver**
1. Is compatible ammo configured in the Quiver & Ammo subtab?
2. Is the ammo reserve container assigned the `AMMO_RESERVE` role?
3. Is the quiver already full? (Check current count vs capacity in the subtab)
4. Was the ammo reserve container discovered? Check the Container Graph subtab.
5. Refill moves are serialized — they won't run during active container discovery.

**Recovery stuck at SURVIVAL_ONLY after reconnect**
1. Check that `autoOpen` is enabled.
2. Check whether root discovery succeeded — open the Containers panel → Overview subtab.
3. If the main backpack is not in the back slot, detection falls back to the first open container. Make sure at least one container is open.
4. Check console for load errors — if `discovery.lua` failed to load, recovery won't start.
5. Use **Safely Reset Runtime State** in the Overview subtab and re-enable Auto Open.

**TargetBot resumed attacking before containers were ready**
The reconnect recovery coordinator (`discovery.lua`) emits `recovery:resume_targetbot` only when `COMBAT_READY` is reached. If TargetBot resumed early:
1. Check that `pauseTargetBotOnRecovery = true` in container config.
2. TargetBot must subscribe to `recovery:pause_targetbot` and `recovery:resume_cavebot` events — verify in diagnostics.
3. Check for stale EventBus subscriptions left from a previous session.

**Container open window limit reached**
The bot defaults to a maximum of 19 simultaneously open containers. If your inventory exceeds this:
1. Switch to `PIN_CRITICAL_AND_TRAVERSE` window mode — keeps critical containers open, closes non-critical ones after scanning.
2. Or use `ROLE_CONTAINERS_ONLY` — opens only role-assigned containers.
3. Check server documentation for the actual limit and configure `maxOpenWindows` accordingly.

**Performance: bot slows during discovery**
- Container discovery runs at priority 25 (LOW). Healing (priority 0–1) always takes precedence.
- Check if another module is issuing competing open/move requests — all inventory actions must go through the scheduler.
- Increase `cooldownMs` in Advanced settings for high-latency servers.



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
