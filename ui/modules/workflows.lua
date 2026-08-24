-- Responsive shell pages for the bot's primary workflows.

local VM = nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]
local Page = nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]

local Workflows = {}

local function invoke(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, ...)
  if ok then return result end
  return nil
end

local function call(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, result = pcall(object[method], object)
  if ok then return result end
  return nil
end

local function enabled(module)
  local state = call(module, "isOn")
  if state == nil then return "Unavailable", "WARNING" end
  return state and "On" or "Off", state and "ACTIVE" or "DISABLED"
end

local function snapshot(id, title, statusText, status, rows, actions)
  local vm = VM.new(id)
  vm:setState("READY")
  vm:setHeader({ module = id, title = title, status = status, statusText = statusText })
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
        { id = "open_cave_editor", label = "Edit route" },
      })
    end,
  },
  targetbot = {
    label = "Target", order = 30,
    provider = function()
      local state, status = enabled(TargetBot)
      local target = TargetBot and invoke(TargetBot.getCurrentTarget)
      local config = storage and storage.targetbot or {}
      return snapshot("targetbot", "Target", state, status, {
        { key = "Profile", value = config.selectedConfig or "-" },
        { key = "Current target", value = call(target, "getName") or "-" },
        { key = "Targeting", value = state },
      }, {
        { id = "toggle_targetbot", label = state == "On" and "Stop" or "Start" },
        { id = "open_target_editor", label = "Edit creatures" },
      })
    end,
  },
  healing = {
    label = "Heal", order = 40,
    provider = function()
      local state, status = enabled(HealBot)
      return snapshot("healing", "Heal", state, status, {
        { key = "Profile", value = HealBot and invoke(HealBot.getActiveProfile) or "-" },
        { key = "Healing", value = state },
      }, {
        { id = "toggle_healing", label = state == "On" and "Stop" or "Start" },
        { id = "open_heal_config", label = "Edit rules" },
      })
    end,
  },
  looting = {
    label = "Loot", order = 50,
    provider = function()
      local state = TargetBot and invoke(TargetBot.isLootingEnabled)
      local statusText = state == nil and "Unavailable" or (state and "On" or "Off")
      local status = state == nil and "WARNING" or (state and "ACTIVE" or "DISABLED")
      return snapshot("looting", "Loot", statusText, status, {
        { key = "Looting", value = statusText },
        { key = "Containers", value = Containers and "Ready" or "Unavailable" },
      }, {
        { id = "toggle_looting", label = state and "Stop" or "Start" },
        { id = "open_loot_config", label = "Edit containers" },
      })
    end,
  },
  supplies = {
    label = "Supplies", order = 60,
    provider = function()
      local profile = Supplies and invoke(Supplies.getCurrentProfile) or "-"
      return snapshot("supplies", "Supplies", Supplies and "Ready" or "Unavailable", Supplies and "INFO" or "WARNING", {
        { key = "Profile", value = profile },
        { key = "Refill", value = Supplies and "Configured" or "Unavailable" },
      }, { { id = "open_supply_config", label = "Edit supplies" } })
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
      }, { { id = "open_intelligence_window", label = "Open details" } })
    end,
  },
}

for id, definition in pairs(definitions) do
  local workflowId = id
  local workflow = definition
  Workflows[workflowId] = {
    statusProvider = workflow.provider,
    render = function(shell, content, lifecycle)
      Page.render(shell, content, lifecycle, workflow.provider().snapshot)
    end,
  }
  nExBot.UI.ModuleRegistry.register({
    id = workflowId,
    label = workflow.label,
    order = workflow.order,
    statusProvider = workflow.provider,
    viewModelProvider = workflow.provider,
    render = Workflows[workflowId].render,
  })
end

nExBot.UI.Workflows = Workflows
nExBot.UI["ui.modules.workflows"] = Workflows

return Workflows
