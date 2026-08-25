-- Responsive shell pages for the bot's primary workflows.

local VM = nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]
local Page = nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]
local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]

local Workflows = {}
local PAGE_SIZE = 40
local routePage = 1
local targetPage = 1
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

local function pageBounds(page, count)
  local pages = math.max(1, math.ceil(count / PAGE_SIZE))
  page = math.max(1, math.min(page, pages))
  local first = (page - 1) * PAGE_SIZE + 1
  return page, pages, first, math.min(count, first + PAGE_SIZE - 1)
end

local function rerender(shell)
  if shell and shell.renderCurrent then shell:renderCurrent() end
end

local function actionBar(content)
  return g_ui.createWidget("NexWorkflowActions", content)
end

local function actionButton(parent, options)
  options.style = "NexWorkflowButton"
  return Components.button(parent, options)
end

local function renderCaveControls(content, shell)
  if not CaveBot then return end
  Components.sectionHeader(content, { title = "Route" })
  profileSelect(content, {
    id = "caveProfile",
    items = CaveBot.listProfiles and CaveBot.listProfiles() or {},
    value = CaveBot.getCurrentProfile and CaveBot.getCurrentProfile(),
    onChange = function(name)
      if CaveBot.setCurrentProfile then CaveBot.setCurrentProfile(name) end
      rerender(shell)
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

  local route = CaveBot.Route
  if not route or not route.getChildren then return end
  local waypoints = route:getChildren()
  local pages, first, last
  routePage, pages, first, last = pageBounds(routePage, #waypoints)
  Components.sectionHeader(content, { title = "Waypoints" })
  if #waypoints == 0 then
    Components.emptyState(content, { message = "No waypoints. Add the first route action." })
  else
    Components.label(content, { text = string.format("Showing %d-%d of %d", first, last, #waypoints), textStyle = "metadata" })
    local selected = route:getFocusedChild()
    for index = first, last do
      local waypoint = waypoints[index]
      local row = Components.listRow(content, {
        id = "waypoint_" .. index,
        title = waypoint.getText and waypoint:getText() or ((waypoint.action or "action") .. ":" .. tostring(waypoint.value or "")),
        subtitle = "Waypoint " .. index,
        status = waypoint == selected and "ACTIVE" or nil,
        statusText = waypoint == selected and "Selected" or nil,
      }).widget
      row.onClick = function()
        route:focus(waypoint)
        rerender(shell)
      end
    end
  end

  local paging = actionBar(content)
  actionButton(paging, { id = "routePrevious", text = "Previous", disabled = routePage == 1, onClick = function()
    routePage = routePage - 1; rerender(shell)
  end })
  actionButton(paging, { id = "routeNext", text = "Next", disabled = routePage == pages, onClick = function()
    routePage = routePage + 1; rerender(shell)
  end })

  local actions = actionBar(content)
  actionButton(actions, { id = "addWaypoint", text = "Add Waypoint", onClick = function()
    if CaveBot.Editor and CaveBot.Editor.show then CaveBot.Editor.show() end
  end })
  actionButton(actions, { id = "editWaypoint", text = "Edit", onClick = function()
    local selected = route:getFocusedChild()
    if selected and selected.onDoubleClick then selected.onDoubleClick(selected) end
  end })
  actionButton(actions, { id = "removeWaypoint", text = "Remove", variant = "danger", onClick = function()
    local selected = route:getFocusedChild()
    if not selected then return end
    selected:destroy()
    if CaveBot.invalidateWaypointCache then CaveBot.invalidateWaypointCache() end
    if CaveBot.invalidateGotoDistCache then CaveBot.invalidateGotoDistCache() end
    if CaveBot.save then CaveBot.save() end
    rerender(shell)
  end })
  actionButton(actions, { id = "moveWaypointUp", text = "Up", onClick = function()
    local selected = route:getFocusedChild()
    local index = route:getChildIndex(selected)
    if index > 1 then route:moveChildToIndex(selected, index - 1); if CaveBot.save then CaveBot.save() end; rerender(shell) end
  end })
  actionButton(actions, { id = "moveWaypointDown", text = "Down", onClick = function()
    local selected = route:getFocusedChild()
    local index = route:getChildIndex(selected)
    if index > 0 and index < route:getChildCount() then route:moveChildToIndex(selected, index + 1); if CaveBot.save then CaveBot.save() end; rerender(shell) end
  end })
end

local function renderTargetControls(content, shell)
  if not TargetBot then return end
  Components.sectionHeader(content, { title = "Creature profile" })
  profileSelect(content, {
    id = "targetProfile",
    items = TargetBot.listProfiles and TargetBot.listProfiles() or {},
    value = TargetBot.getCurrentProfile and TargetBot.getCurrentProfile(),
    onChange = function(name)
      if TargetBot.setCurrentProfile then TargetBot.setCurrentProfile(name) end
      rerender(shell)
    end,
  })

  local creatures = TargetBot.Creatures
  if not creatures or not creatures.getChildren then return end
  local rules = creatures:getChildren()
  local pages, first, last
  targetPage, pages, first, last = pageBounds(targetPage, #rules)
  Components.sectionHeader(content, { title = "Targets" })
  if #rules == 0 then
    Components.emptyState(content, { message = "No target rules. Add the first target." })
  else
    Components.label(content, { text = string.format("Showing %d-%d of %d", first, last, #rules), textStyle = "metadata" })
    local selected = creatures:getFocusedChild()
    for index = first, last do
      local rule = rules[index]
      local row = Components.listRow(content, {
        id = "targetRule_" .. index,
        title = rule.getText and rule:getText() or (rule.value and rule.value.name) or "Target",
        subtitle = rule.value and (rule.value.pattern or rule.value.name) or "Creature rule",
        status = rule == selected and "ACTIVE" or nil,
        statusText = rule == selected and "Selected" or nil,
      }).widget
      row.onClick = function()
        creatures:focus(rule)
        rerender(shell)
      end
    end
  end

  local paging = actionBar(content)
  actionButton(paging, { id = "targetPrevious", text = "Previous", disabled = targetPage == 1, onClick = function()
    targetPage = targetPage - 1; rerender(shell)
  end })
  actionButton(paging, { id = "targetNext", text = "Next", disabled = targetPage == pages, onClick = function()
    targetPage = targetPage + 1; rerender(shell)
  end })

  local actions = actionBar(content)
  actionButton(actions, { id = "addTarget", text = "Add Target", onClick = function()
    if TargetBot.addCreature then TargetBot.addCreature() end
  end })
  actionButton(actions, { id = "editTarget", text = "Edit", onClick = function()
    if creatures:getFocusedChild() and TargetBot.showCreatureEditor then TargetBot.showCreatureEditor() end
  end })
  actionButton(actions, { id = "removeTarget", text = "Remove", variant = "danger", onClick = function()
    if creatures:getFocusedChild() and TargetBot.removeSelectedCreature then TargetBot.removeSelectedCreature(); rerender(shell) end
  end })
end

local healPage = { spell = 1, item = 1 }

local function renderHealRuleList(content, shell, kind, title)
  if not HealBot.getRules then return end
  local rules = HealBot.getRules(kind)
  local pages, first, last
  healPage[kind], pages, first, last = pageBounds(healPage[kind], #rules)
  Components.sectionHeader(content, { title = title })
  if #rules == 0 then
    Components.emptyState(content, { message = "No rules configured." })
  else
    Components.label(content, { text = string.format("Showing %d-%d of %d", first, last, #rules), textStyle = "metadata" })
    for index = first, last do
      local rule = rules[index]
      Components.listRow(content, {
        id = "healRule_" .. kind .. "_" .. rule.index,
        title = rule.label,
        subtitle = rule.enabled and "Enabled" or "Disabled",
        status = rule.enabled and "ACTIVE" or "DISABLED",
        actions = {
          { id = "healRuleToggle_" .. kind .. "_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function()
            HealBot.toggleRule(kind, rule.index); rerender(shell)
          end },
          { id = "healRuleRemove_" .. kind .. "_" .. rule.index, text = "Remove", variant = "danger", onClick = function()
            HealBot.removeRule(kind, rule.index); rerender(shell)
          end },
        },
      })
    end
  end

  local paging = actionBar(content)
  actionButton(paging, { id = "heal" .. kind .. "Previous", text = "Previous", disabled = healPage[kind] == 1, onClick = function()
    healPage[kind] = healPage[kind] - 1; rerender(shell)
  end })
  actionButton(paging, { id = "heal" .. kind .. "Next", text = "Next", disabled = healPage[kind] == pages, onClick = function()
    healPage[kind] = healPage[kind] + 1; rerender(shell)
  end })
end

local function renderHealingControls(content, shell)
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

  renderHealRuleList(content, shell, "spell", "Healing Spells")
  renderHealRuleList(content, shell, "item", "Healing Items")

  local actions = actionBar(content)
  actionButton(actions, { id = "manageHealRules", text = "Add / Manage Rules", onClick = function()
    if HealBot.show then HealBot.show() end
  end })
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
