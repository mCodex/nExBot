# Private Scripts

Run custom Lua scripts without modifying core files.

> **Trusted scripts only.** Files in `private/` execute via `dofile()` with full bot access. Only use scripts you wrote or trust.

## Quick Start

1. Create `nExBot/private/my_script.lua`
2. Reload bot (disable → enable) or relog
3. Script runs immediately

```text
nExBot/
└── private/
    ├── my_script.lua
    └── subfolder/
        └── another_script.lua
```

## How It Works

Startup scans `private/` recursively for `.lua` files. Executed via `dofile()` in alphabetical order. One broken file doesn't break others.

```
[Private] Failed to load '/private/bad_script.lua': ...error...
```

## Available APIs

| API | Description |
|-----|-------------|
| `macro(interval, callback)` | Repeating macro (ms) |
| `addIcon(name, opts, macro)` | Toggleable panel icon |
| `player` / `g_game.getLocalPlayer()` | Local player |
| `pos()` | Current position |
| `g_map`, `g_game` | Map and game API |
| `storage` | Persistent per-character storage |
| `schedule(delay, fn)` | Run after delay |
| `now` | Current timestamp (ms) |
| `PathUtils` | pathfinding, tile checks, directions |
| `PathStrategy` | high-level pathfinding, autoWalk, walkStep |
| `Directions` | Direction constants (SSoT) |
| `CaveBot`, `TargetBot` | Module APIs |

Any global at startup is available.

## Examples

### Minimal

```lua
local myMacro = macro(5000, function()
  if not g_game.isOnline() then return end
  print("[Hello] Position: " .. tostring(pos()))
end)
```

### Toggleable Icon

```lua
local eatMacro = macro(30000, function()
  if not g_game.isOnline() then return end
end)
addIcon("AutoEat", {item = {id = 3582}, text = "Eat", switchable = true}, eatMacro)
```

### Use Item on Map

```lua
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

## Subfolders

Organize into subfolders — discovered recursively:

```text
private/
├── mining/
│   ├── mining.lua
│   └── helpers.lua
├── runes/
│   └── money_rune.lua
└── greeting.lua
```

All `.lua` files loaded in sorted path order.

## Tips

- Use `local` for all variables
- Guard with `g_game.isOnline()` at top of callbacks
- Reasonable intervals (1000ms, not 50ms)
- Prefix prints (e.g. `[Mining]`)
- Back up `private/` before updates

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Script not loading | Check console for `[Private] Failed to load`. Verify `.lua` extension. |
| `attempt to index a nil value` | API not available at load time. Wrap in `macro()` or `schedule()`. |
| Conflicts with core | Use `local` for all variables. Don't overwrite globals. |
| Icon doesn't appear | `addIcon` must be at top level, not inside a function. |
| Changes not taking effect | Disable → enable bot, or relog. Scripts load once at startup. |
