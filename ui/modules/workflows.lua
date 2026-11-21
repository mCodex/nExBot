-- Responsive shell pages for the bot's primary workflows. Each workflow's
-- domain-specific controls live in ui/modules/workflows/<name>.lua; this
-- file owns the status-projection definitions and the module-registry
-- wiring that turns each one into a registered page.

local VM = nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]
local Page = nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]
local CavePage = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.cave"]
local TargetPage = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.target"]
local HealingPage = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.healing"]
local LootingPage = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.looting"]
local SuppliesPage = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.supplies"]

local Workflows = {}
Workflows.projectTargetRule = TargetPage.projectTargetRule

local LANDMARKS = {
  cavebot = 3003,
  targetbot = 3155,
  healing = 23375,
  looting = 2854,
  supplies = 23375,
  intelligence = 3155,
}

local function enabled(module)
  local state = Shared.call(module, "isOn")
  if state == nil then return "Unavailable", "WARNING" end
  return state and "On" or "Off", state and "ACTIVE" or "DISABLED"
end

local function snapshot(id, title, statusText, status, rows, actions)
  local vm = VM.new(id)
  vm:setState("READY")
  vm:setHeader({ module = id, title = title, itemId = LANDMARKS[id], status = status, statusText = statusText })
  vm:setSections({ { id = "overview", title = "Overview", rows = rows } })
  vm:setActions(actions or {})
  vm:commit()
  return vm
end

local definitions = {
  cavebot = {
    label = "Cave", order = 20,
    provider = function()
      local state, status = enabled(CaveBot)
      local config = storage and storage.cavebot or {}
      return snapshot("cavebot", "Cave", state, status, {
        { key = "Profile", value = config.selectedConfig or "-" },
        { key = "Waypoint", value = nExBot and nExBot.lastLabel or "-" },
        { key = "Navigation", value = state },
      }, {
        { id = "toggle_cavebot", label = state == "On" and "Stop" or "Start" },
      })
    end,
  },
  targetbot = {
    label = "Target", order = 30,
    provider = function()
      local state, status = enabled(TargetBot)
      local target = TargetBot and Shared.invoke(TargetBot.getCurrentTarget)
      local config = storage and storage.targetbot or {}
      return snapshot("targetbot", "Target", state, status, {
        { key = "Profile", value = config.selectedConfig or "-" },
        { key = "Current target", value = Shared.call(target, "getName") or "-" },
        { key = "Targeting", value = state },
      }, {
        { id = "toggle_targetbot", label = state == "On" and "Stop" or "Start" },
      })
    end,
  },
  healing = {
    label = "Heal", order = 40,
    provider = function()
      local state, status = enabled(HealBot)
      return snapshot("healing", "Heal", state, status, {
        { key = "Profile", value = HealBot and Shared.invoke(HealBot.getActiveProfile) or "-" },
        { key = "Healing", value = state },
      }, {
        { id = "toggle_healing", label = state == "On" and "Stop" or "Start" },
      })
    end,
  },
  looting = {
    label = "Loot", order = 50,
    provider = function()
      local looting = TargetBot and TargetBot.Looting
      local ready = looting and type(looting.getConfig) == "function"
      local statusText = ready and "Ready" or "Unavailable"
      local status = ready and "INFO" or "WARNING"
      return snapshot("looting", "Loot", statusText, status, {
        { key = "Looting", value = statusText },
        { key = "Activation", value = "Runs with Target" },
        { key = "Containers", value = Containers and "Ready" or "Unavailable" },
      })
    end,
  },
  supplies = {
    label = "Supplies", order = 60,
    provider = function()
      local profile = Supplies and Shared.invoke(Supplies.getCurrentProfile) or "-"
      return snapshot("supplies", "Supplies", Supplies and "Ready" or "Unavailable", Supplies and "INFO" or "WARNING", {
        { key = "Profile", value = profile },
        { key = "Refill", value = Supplies and "Configured" or "Unavailable" },
      }, {})
    end,
  },
  intelligence = {
    label = "AI", order = 70,
    provider = function()
      local intelligence = nExBot and nExBot.TacticalIntelligence
      local runtime = intelligence and intelligence.runtime or {}
      local pipeline = runtime.pipeline or {}
      return snapshot("intelligence", "AI Intelligence", intelligence and "Live" or "Unavailable", intelligence and "ACTIVE" or "WARNING", {
        { key = "State", value = pipeline.state or runtime.state or "-" },
        { key = "Decision", value = pipeline.decision or "-" },
        { key = "Confidence", value = pipeline.confidence or "-" },
      }, {})
    end,
  },
}

local EXTRA_RENDERERS = {
  cavebot = CavePage.render,
  targetbot = TargetPage.render,
  healing = HealingPage.render,
  looting = LootingPage.render,
  supplies = SuppliesPage.render,
}

for id, definition in pairs(definitions) do
  local workflowId = id
  local workflow = definition
  Workflows[workflowId] = {
    statusProvider = workflow.provider,
    render = function(shell, content, lifecycle)
      Page.render(shell, content, lifecycle, workflow.provider().snapshot)
      local renderExtra = EXTRA_RENDERERS[workflowId]
      if renderExtra then renderExtra(content, shell) end
    end,
  }
  nExBot.UI.ModuleRegistry.register({
    id = workflowId,
    label = workflow.label,
    order = workflow.order,
    statusProvider = workflow.provider,
    render = Workflows[workflowId].render,
  })
end

nExBot.UI.Workflows = Workflows
nExBot.UI["ui.modules.workflows"] = Workflows

return Workflows
