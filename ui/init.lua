--[[
  nExBot.UI bootstrap — loads the design system, core registries, shared
  components, and every module. Called by _Loader.lua after the analytics/UI
  phase.

  Module loading uses dofile() — the same pattern as navigation modules
  (OTClient's sandbox has no loadfile/package/require, and dofile discards
  return values). Each module self-registers into nExBot.UI as a side
  effect of running. Per-module error logging ensures silent failures
  are visible.
]]

nExBot.UI = nExBot.UI or {}

local errors = {}
local loaded = 0

-- ─── Module loading ────────────────────────────────────────────────────────
do
  local modules = {
    "ui.core.module_registry",
    "ui.core.icon_registry",
    "ui.core.view_model",
    "ui.core.command",
    "ui.core.lifecycle",
    "ui.core.perf",
    "ui.core.actions",
    "ui.design_system.tokens",
    "ui.design_system.typography",
    "ui.design_system.density",
    "ui.design_system.status",
    "ui.components.components",
    "ui.shell.shell",
    "ui.modules.page",
    "ui.modules.dashboard",
    "ui.modules.cavebot",
    "ui.modules.targetbot",
    "ui.modules.healing",
    "ui.modules.looting",
    "ui.modules.supplies",
    "ui.modules.scripts",
    "ui.modules.intelligence",
    "ui.modules.profiles",
    "ui.modules.settings",
    "ui.modules.diagnostics",
  }

  for i = 1, #modules do
    local name = modules[i]
    local path = "/" .. name:gsub("%.", "/") .. ".lua"
    -- OTClient sandbox has no loadfile/package/require; dofile is the only
    -- file-execution primitive. Each module self-registers into nExBot.UI
    -- as a side effect of running (same convention as navigation/*.lua),
    -- so the chunk's return value isn't relied on here.
    local ok, res = pcall(dofile, path)
    if ok then
      if res then nExBot.UI[name] = res end
      loaded = loaded + 1
    else
      warn("[nExBot] UI: " .. name .. " load error: " .. tostring(res))
      errors[#errors + 1] = name .. ":load"
    end
  end
  if loaded > 0 then
    info("[nExBot] UI: loaded " .. loaded .. "/" .. #modules .. " modules")
  end
end

-- ─── Verify self-registration ──────────────────────────────────────────────
do
  local required = {
    ModuleRegistry = "module_registry",
    IconRegistry   = "icon_registry",
    Tokens         = "design_system.tokens",
    Status         = "design_system.status",
    Shell          = "shell",
  }
  for shortName, modName in pairs(required) do
    if not nExBot.UI[shortName] then
      warn("[nExBot] UI: " .. shortName .. " not registered — " .. modName .. " may not have loaded")
      errors[#errors + 1] = shortName .. ":unregistered"
    end
  end
end

-- ─── Icon catalog registration ─────────────────────────────────────────────
do
  local R = nExBot.UI.IconRegistry
  if not R then
    warn("[nExBot] UI: IconRegistry not loaded — icon registration skipped")
  else
    local names = {
      "dashboard", "cavebot", "targetbot", "healing", "looting", "supplies",
      "scripts", "intelligence", "learning", "monsters", "navigation",
      "profiles", "settings", "diagnostics", "replay",
      "add", "remove", "edit", "save", "import", "export", "refresh", "search",
      "filter", "close", "info", "warning", "success", "paused", "active",
      "expand", "collapse", "reorder", "record", "stop",
      "waypoint", "route", "stairs-up", "stairs-down", "ladder", "hole",
      "rope", "shovel", "door", "obstacle", "recovery", "target", "shield",
      "potion", "backpack",
    }
    local base = "/bot/" .. (nExBot.paths and nExBot.paths.config or "nExBot") .. "/ui/assets/icons"
    for i = 1, #names do
      local id = names[i]
      R.register(id, {
        id = id,
        svg = base .. "/" .. id .. ".svg",
        raster = base .. "/generated/" .. id .. "_%d.png",
      })
    end
    info("[nExBot] UI: registered " .. R.count() .. " icons")
  end
end

-- ─── Import shell styles ───────────────────────────────────────────────────
do
  local botBase = "/bot/" .. (nExBot.paths and nExBot.paths.config or "nExBot")
  if g_ui and g_ui.importStyle then
    local ok, err = pcall(g_ui.importStyle, botBase .. "/ui/shell/styles.otui")
    if not ok then
      warn("[nExBot] UI: failed to import shell styles: " .. tostring(err))
    end
  end
end

-- ─── Shell host attachment ─────────────────────────────────────────────────
do
  local Shell = nExBot.UI.Shell
  if Shell and Shell.show then
    local function attach()
      pcall(function()
        local shell = Shell.show()
        shell:setupHostHooks()
      end)
    end
    if schedule then
      schedule(200, attach)
    else
      attach()
    end
  end
end

-- ─── Error summary ─────────────────────────────────────────────────────────
if #errors > 0 then
  warn("[nExBot] UI: " .. #errors .. " issue(s): " .. table.concat(errors, "; "))
end
