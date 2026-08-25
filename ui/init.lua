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

-- The bot loader may execute this file again after an off/on cycle.
-- Tear down the previous shell before replacing its module singleton.
local previousShell = nExBot.UI.Shell
if previousShell and previousShell.reset then pcall(previousShell.reset) end

local errors = {}
local loaded = 0

-- ─── Module loading ────────────────────────────────────────────────────────
do
  local modules = {
    "ui.core.module_registry",
    "ui.core.view_model",
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
    "ui.modules.cockpit",
    "ui.modules.workflows",
    "ui.modules.auxiliary",
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
      local ok, err = pcall(function()
        local shell = Shell.show()
        shell:setupHostHooks()
      end)
      if not ok then warn("[nExBot] UI cockpit attach failed: " .. tostring(err)) end
    end
    if schedule then
      schedule(200, attach)
    else
      attach()
    end
  end
end

-- Refresh the visible cockpit only when its truthful state fingerprint changes.
do
  local Shell = nExBot.UI.Shell
  if UnifiedTick and UnifiedTick.register and Shell then
    UnifiedTick.register("nexbot_cockpit_ui", {
      interval = 250,
      priority = UnifiedTick.Priority and UnifiedTick.Priority.LOW,
      group = "ui",
      handler = function()
        local shell = Shell.instance()
        if shell then shell:tick() end
      end,
    })
  end
end

-- ─── Error summary ─────────────────────────────────────────────────────────
if #errors > 0 then
  warn("[nExBot] UI: " .. #errors .. " issue(s): " .. table.concat(errors, "; "))
end
