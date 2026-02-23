# Private Scripts

Run your own custom Lua scripts alongside nExBot without modifying any core files. Drop them into the `private/` folder and they are loaded automatically on startup.

> **⚠ Trusted scripts only:** Files in `private/` are executed via Lua's `dofile` with full access to the bot environment. Only use scripts you wrote yourself or obtained from a trusted source — never run unverified code.

---

## Quick Start

1. Open the `private/` folder inside your nExBot directory:

```text
nExBot/
└── private/
    ├── my_script.lua
    └── subfolder/
        └── another_script.lua
```

2. Create a `.lua` file with your custom logic.
3. Reload the bot (disable → enable) or relog. Your script runs immediately.

That's it — no edits to `_Loader.lua` or any other file are needed.

---

## How It Works

During startup, nExBot scans the `private/` folder **recursively** for every `.lua` file. Each file is executed via `dofile()` in alphabetical order (paths sorted lexicographically, subfolders included). Scripts inside subfolders are loaded as well. Because scripts run with full privileges, only place files from trusted sources in this folder.

If a script fails to load, nExBot prints a warning to the console but continues loading the remaining scripts — one broken file won't break the rest.

```text
[Private] Failed to load '/private/bad_script.lua': ...error message...
```

---

## What You Can Use

Private scripts run in the same environment as all other bot modules, so you have access to:

| API / Global | Description |
|---|---|
| `macro(interval, callback)` | Create a repeating macro (interval in ms) |
| `addIcon(name, opts, macro)` | Add a toggleable icon to the bot panel |
| `player` / `g_game.getLocalPlayer()` | The local player object |
| `pos()` | Player's current position |
| `g_map`, `g_game` | Map and game API |
| `storage` | Persistent per-character storage table |
| `schedule(delay, fn)` | Run a function after `delay` ms |
| `now` | Current timestamp in ms (updated each tick) |
| `PathUtils` | Shared pathfinding: `findPath()`, `isFloorChangeTile()`, `isTileSafe()`, `getStepDuration()`, `chebyshevDistance()`, `posEquals()`, `getDirectionTo()`, `areSimilarDirections()`, direction constants (SSoT via `Directions`) |
| `PathStrategy` | High-level pathfinding: `findPath()`, `findPathRelaxed()`, `stepDuration()` (with jitter), `smoothPath()`, `smoothDirection()`, PathCursor, `nativePathIsSafe()`, `autoWalk()`, `walkStep()`. Delegates to `PathUtils` for shared utilities. |
| `Directions` | Direction constants SSoT: `DIR_TO_OFFSET`, `OPPOSITE`, `ADJACENT`, `OFFSET_TO_DIR`, plus helper functions |
| `CaveBot`, `TargetBot` | Bot module APIs |

> **Tip:** Any global that exists at startup time is available. Check the [Architecture](ARCHITECTURE.md) doc for the full module list.

---

## Writing a Script

A minimal private script looks like this:

```lua
-- private/hello.lua
local myMacro = macro(5000, function()
  if not g_game.isOnline() then return end
  print("[Hello] Player position: " .. tostring(pos()))
end)
```

### Adding a Toggleable Icon

Use `addIcon` to give your macro an on/off toggle in the bot panel:

```lua
-- private/auto_eat.lua
local eatMacro = macro(30000, function()
  if not g_game.isOnline() then return end
  -- your eat logic here
end)

addIcon("AutoEat", {item = {id = 3582}, text = "Eat", switchable = true}, eatMacro)
```

### Using Items on the Map

A common pattern is scanning nearby tiles and interacting with items:

```lua
-- private/use_item_nearby.lua
local TARGET_ITEMS = {1234, 5678}
local TOOL_ID = 3456

local function isInArray(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then return true end
  end
  return false
end

local myMacro = macro(1000, function()
  if not g_game.isOnline() then return end
  local playerPos = pos()

  for x = -1, 1 do
    for y = -1, 1 do
      local tilePos = {x = playerPos.x + x, y = playerPos.y + y, z = playerPos.z}
      local tile = g_map.getTile(tilePos)
      if tile then
        local top = tile:getTopThing()
        if top and top:isItem() and isInArray(TARGET_ITEMS, top:getId()) then
          g_game.useInventoryItemWith(TOOL_ID, top)
          return
        end
      end
    end
  end
end)

addIcon("UseTool", {item = {id = TOOL_ID}, text = "Tool", switchable = true}, myMacro)
```

---

## Subfolders

You can organize scripts into subfolders — they are discovered recursively:

```text
private/
├── mining/
│   ├── mining.lua
│   └── helpers.lua
├── runes/
│   └── money_rune.lua
└── greeting.lua
```

All `.lua` files across all subdirectories are loaded in sorted path order.

---

## Tips & Best Practices

- **Use `local`** for all variables and functions to avoid polluting the global namespace and conflicting with other scripts or core modules.
- **Guard with `g_game.isOnline()`** at the top of your macro callback to prevent errors when logged out.
- **Keep macro intervals reasonable** — polling every 50ms when 1000ms is enough wastes CPU.
- **Prefix your prints** (e.g. `[Mining]`) so you can identify which script is logging.
- **Back up your `private/` folder** before updating nExBot — the updater does not touch it, but it's good practice.
- **Test one script at a time** — if something breaks, temporarily move other scripts out to isolate the issue.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Script not loading | Check the console for `[Private] Failed to load` errors. Verify the file ends in `.lua`. |
| `attempt to index a nil value` | The API you're calling may not exist yet at load time. Wrap runtime logic inside a `macro()` or `schedule()`. |
| Conflicts with core modules | Make sure all your variables are `local`. Overwriting globals like `player` or `storage` will break things. |
| Script loads but icon doesn't appear | Ensure `addIcon` is called at the top level of the file (not inside a function that never runs). |
| Changes not taking effect | Disable and re-enable the bot, or relog. Scripts are only loaded once at startup. |
