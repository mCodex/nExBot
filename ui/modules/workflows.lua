-- Responsive shell pages for the bot's primary workflows.

local VM = nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]
local Page = nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]
local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]

local Workflows = {}
local LANDMARKS = {
  cavebot = 3003,
  targetbot = 3155,
  healing = 23375,
  looting = 2854,
  supplies = 23375,
  intelligence = 3155,
}

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
      local target = TargetBot and invoke(TargetBot.getCurrentTarget)
      local config = storage and storage.targetbot or {}
      return snapshot("targetbot", "Target", state, status, {
        { key = "Profile", value = config.selectedConfig or "-" },
        { key = "Current target", value = call(target, "getName") or "-" },
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
        { key = "Profile", value = HealBot and invoke(HealBot.getActiveProfile) or "-" },
        { key = "Healing", value = state },
      }, {
        { id = "toggle_healing", label = state == "On" and "Stop" or "Start" },
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

local function optionName(first, second)
  if type(second) == "string" then return second end
  if type(second) == "table" then return second.text or second.value end
  if type(first) == "string" then return first end
  if type(first) == "table" then return first.text or first.value end
end

local function profileSelect(content, options)
  Components.selectRow(content, {
    id = options.id,
    label = "Profile",
    options = options.items or {},
    value = options.value,
    onChange = function(first, second)
      local name = optionName(first, second)
      if name then options.onChange(name) end
    end,
  })
end

local function renderCaveControls(content)
  if not CaveBot then return end
  Components.sectionHeader(content, { title = "Route" })
  profileSelect(content, {
    id = "caveProfile",
    items = CaveBot.listProfiles and CaveBot.listProfiles() or {},
    value = CaveBot.getCurrentProfile and CaveBot.getCurrentProfile(),
    onChange = function(name)
      if CaveBot.setCurrentProfile then CaveBot.setCurrentProfile(name) end
    end,
  })

  local config = CaveBot.Config
  if not config or not config.get or not config.set then return end
  Components.sectionHeader(content, { title = "Navigation" })
  for _, setting in ipairs({
    { "ignoreFields", "Ignore fields" },
    { "mapClick", "Map click" },
    { "autoUseTools", "Auto tools" },
    { "autoOpenDoors", "Auto doors" },
  }) do
    local key, label = setting[1], setting[2]
    Components.toggleRow(content, {
      id = "cave_" .. key,
      label = label,
      value = config.get(key),
      onChange = function(value) config.set(key, value) end,
    })
  end
end

local function renderTargetControls(content)
  if not TargetBot then return end
  Components.sectionHeader(content, { title = "Creature profile" })
  profileSelect(content, {
    id = "targetProfile",
    items = TargetBot.listProfiles and TargetBot.listProfiles() or {},
    value = TargetBot.getCurrentProfile and TargetBot.getCurrentProfile(),
    onChange = function(name)
      if TargetBot.setCurrentProfile then TargetBot.setCurrentProfile(name) end
    end,
  })
end

local function renderHealingControls(content)
  if not HealBot then return end
  Components.sectionHeader(content, { title = "Healing profile" })
  profileSelect(content, {
    id = "healProfile",
    items = { "1", "2", "3", "4", "5" },
    value = tostring(HealBot.getActiveProfile and HealBot.getActiveProfile() or 1),
    onChange = function(profile)
      if HealBot.setActiveProfile then HealBot.setActiveProfile(tonumber(profile)) end
    end,
  })
end

local function renderSupplyItem(content, id, values)
  Components.itemRow(content, {
    id = "supplyItem_" .. id,
    itemId = id,
    title = "Item " .. id,
    subtitle = string.format("Min %s  Max %s  Avg %s", values.min or 0, values.max or 0, values.avg or 0),
  })

  local draft = { min = values.min or 0, max = values.max or 0, avg = values.avg or 0 }
  for _, field in ipairs({ "min", "max", "avg" }) do
    local key = field
    Components.inputRow(content, {
      id = "supply_" .. id .. "_" .. key,
      label = key:upper(),
      value = draft[key],
      onChange = function(text)
        local number = tonumber(text)
        if not number then return end
        draft[key] = number
        Supplies.setItem(id, draft.min, draft.max, draft.avg)
      end,
    })
  end
  Components.button(content, {
    id = "removeSupply_" .. id,
    text = "Remove item",
    variant = "danger",
    onClick = function() Supplies.removeItem(id) end,
  })
end

local function renderSupplyControls(content)
  if not Supplies then
    Components.emptyState(content, { message = "Supplies did not load. Check the startup log." })
    return
  end

  Components.sectionHeader(content, { title = "Profile" })
  profileSelect(content, {
    id = "supplyProfile",
    items = Supplies.listProfiles and Supplies.listProfiles() or {},
    value = Supplies.getCurrentProfile and Supplies.getCurrentProfile(),
    onChange = Supplies.setCurrentProfile,
  })

  Components.sectionHeader(content, { title = "Items" })
  local items = Supplies.getItemsData and Supplies.getItemsData() or {}
  local ids = {}
  for id in pairs(items) do ids[#ids + 1] = tostring(id) end
  table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
  if #ids == 0 then Components.emptyState(content, { message = "No supply items configured." }) end
  for _, id in ipairs(ids) do renderSupplyItem(content, id, items[id] or items[tonumber(id)]) end

  local newItem = { id = "", min = "0", max = "0", avg = "0" }
  for _, field in ipairs({ "id", "min", "max", "avg" }) do
    local key = field
    Components.inputRow(content, {
      id = "newSupply_" .. key,
      label = key:upper(),
      value = newItem[key],
      onChange = function(text) newItem[key] = text end,
    })
  end
  Components.button(content, {
    id = "addSupply",
    text = "Add item",
    onClick = function()
      Supplies.setItem(newItem.id, newItem.min, newItem.max, newItem.avg)
    end,
  })

  local additional = Supplies.getAdditionalData and Supplies.getAdditionalData() or {}
  Components.sectionHeader(content, { title = "Refill conditions" })
  for _, condition in ipairs({
    { "softBoots", "No soft boots" },
    { "imbues", "No imbues" },
    { "capacity", "Low capacity" },
    { "stamina", "Low stamina" },
  }) do
    local key, label = condition[1], condition[2]
    local current = additional[key] or {}
    Components.toggleRow(content, {
      id = "supplyCondition_" .. key,
      label = label,
      value = current.enabled,
      onChange = function(enabled) Supplies.setCondition(key, enabled, current.value) end,
    })
    if current.value ~= nil then
      Components.inputRow(content, {
        id = "supplyConditionValue_" .. key,
        label = "Value",
        value = current.value,
        onChange = function(value) Supplies.setCondition(key, current.enabled, value) end,
      })
    end
  end
end

local EXTRA_RENDERERS = {
  cavebot = renderCaveControls,
  targetbot = renderTargetControls,
  healing = renderHealingControls,
  supplies = renderSupplyControls,
}

for id, definition in pairs(definitions) do
  local workflowId = id
  local workflow = definition
  Workflows[workflowId] = {
    statusProvider = workflow.provider,
    render = function(shell, content, lifecycle)
      Page.render(shell, content, lifecycle, workflow.provider().snapshot)
      local renderExtra = EXTRA_RENDERERS[workflowId]
      if renderExtra then renderExtra(content) end
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
