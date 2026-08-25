-- Responsive shell pages for the bot's primary workflows.

local VM = nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]
local Page = nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]
local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Presenter = nExBot and nExBot.UI and nExBot.UI.RulePresenter
local Resolver = nExBot and nExBot.UI and nExBot.UI.VisualAssetResolver

local Workflows = {}
local PAGE_SIZE = 40
local targetPage = 1
local selectedSupplyId
local selectedLootEntry
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

local function present(value, fallback)
  if value == nil or tostring(value) == "" then return fallback end
  return tostring(value)
end

function Workflows.projectTargetRule(widget, index, selected)
  local value = widget.value or {}
  local name = present(widget.getText and widget:getText(), value.name)
  return {
    id = present(widget.getId and widget:getId(), "targetRule_" .. index),
    revision = table.concat({ index, name or "", value.pattern or "" }, ":"),
    title = present(name, "Target " .. index),
    secondary = present(value.pattern, present(value.name, "Creature rule")),
    status = selected and "ACTIVE" or "INFO",
    statusText = selected and "Selected" or "Configured",
  }
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
  if not shell or not shell.renderCurrent then return end
  -- Destroying the workspace content synchronously (e.g. from inside a
  -- ComboBox option-click, which is still unwinding its own popup-menu
  -- close logic) corrupts OTC's mouse-grab state and breaks all further
  -- clicks. Defer to the next tick so the triggering widget's own click
  -- handling finishes first.
  shell:defer(function()
    if shell.renderCurrent then shell:renderCurrent() end
  end, 0)
end

local function actionBar(content)
  return g_ui.createWidget("NexWorkflowActions", content)
end

local function actionButton(parent, options)
  options.style = "NexWorkflowButton"
  return Components.button(parent, options)
end

local function newProfileAction(content, options)
  local bar = actionBar(content)
  actionButton(bar, {
    id = options.id,
    text = options.text or "New Profile",
    onClick = function()
      local function create(name)
        local ok, reason = options.onCreate(name)
        if not ok then return warn(reason or "Could not create profile") end
        rerender(options.shell)
      end
      if options.prompt then
        displayTextInputBox(options.prompt.title, options.prompt.label, create)
      else
        create()
      end
    end,
  })
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
  newProfileAction(content, {
    id = "newCaveProfile", text = "New Profile", shell = shell,
    prompt = { title = "New Cave Profile", label = "Enter a name for the new profile" },
    onCreate = function(name)
      if not CaveBot.createProfile then return false, "Not available" end
      return CaveBot.createProfile(name)
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
  Components.sectionHeader(content, { title = "Waypoints" })
  Components.label(content, { text = string.format("%d waypoint(s) in this route", #waypoints), textStyle = "metadata" })
  if DataTable then
    local waypointRows = {}
    for index, widget in ipairs(waypoints) do
      local text = widget.getText and widget:getText() or tostring(widget.value or "Waypoint")
      waypointRows[#waypointRows + 1] = {
        id = widget.getId and widget:getId() or index,
        revision = tostring(index) .. ":" .. text,
        title = index .. "  " .. text,
        secondary = index == (route.getFocusedChild and route:getChildIndex(route:getFocusedChild()) or -1) and "Selected" or "Pending",
        status = index == (route.getFocusedChild and route:getChildIndex(route:getFocusedChild()) or -1) and "ACTIVE" or "INFO",
        statusText = index == (route.getFocusedChild and route:getChildIndex(route:getFocusedChild()) or -1) and "Selected" or "Pending",
        onClick = function() if route.focus then route:focus(widget) end end,
      }
    end
    DataTable.create(content, {
      id = "caveWaypoints", title = "Route", rows = waypointRows,
      rowKey = function(row) return row.id end, pageSize = PAGE_SIZE,
      emptyMessage = "No waypoints yet. Add the first route step.",
    })
  end

  local actions = actionBar(content)
  actionButton(actions, { id = "openWaypointEditor", text = "Open Waypoint Editor", onClick = function()
    if CaveBot.Editor and CaveBot.Editor.show then CaveBot.Editor.show() end
  end })
  if CaveBot.Recorder then
    local recording = CaveBot.Recorder.isOn and CaveBot.Recorder.isOn()
    actionButton(actions, {
      id = "recordRoute",
      text = recording and "Stop Recording" or "Record Route",
      variant = recording and "danger" or nil,
      onClick = function()
        if CaveBot.Recorder.isOn and CaveBot.Recorder.isOn() then
          CaveBot.Recorder.disable()
        else
          CaveBot.Recorder.enable()
        end
        rerender(shell)
      end,
    })
  end
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
  newProfileAction(content, {
    id = "newTargetProfile", text = "New Profile", shell = shell,
    prompt = { title = "New Target Profile", label = "Enter a name for the new profile" },
    onCreate = function(name)
      if not TargetBot.createProfile then return false, "Not available" end
      return TargetBot.createProfile(name)
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
  elseif DataTable then
    local tableRows = {}
    local selected = creatures:getFocusedChild()
    for index = first, last do
      local widget = rules[index]
      local row = Workflows.projectTargetRule(widget, index, widget == selected)
      row.onClick = function() creatures:focus(widget); rerender(shell) end
      tableRows[#tableRows + 1] = row
    end
    DataTable.create(content, {
      id = "targetRules", title = "Creature rules", rows = tableRows,
      rowKey = function(row) return row.id end, searchable = #tableRows > 4,
      searchText = function(row) return row.title .. " " .. row.secondary end,
      emptyMessage = "No target rules. Add the first target.",
    })
  else
    Components.label(content, { text = string.format("Showing %d-%d of %d", first, last, #rules), textStyle = "metadata" })
    local selected = creatures:getFocusedChild()
    for index = first, last do
      local rule = rules[index]
      local projected = Workflows.projectTargetRule(rule, index, rule == selected)
      local row = Components.listRow(content, {
        id = "targetRule_" .. index,
        title = projected.title,
        subtitle = projected.secondary,
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
  if DataTable and Presenter and Resolver then
    local tableRows = {}
    for index = first, last do
      local source = rules[index]
      local rule = source
      local visual = rule.itemId and Resolver:item(rule.itemId) or Resolver:spell(rule.spell)
      tableRows[#tableRows + 1] = {
        id = kind .. "_" .. rule.index,
        revision = rule.revision or (rule.index .. ":" .. tostring(rule.enabled)),
        itemId = rule.itemId,
        imageSource = not rule.itemId and visual.source or nil,
        title = rule.spell or (rule.itemId and visual.name) or rule.label,
        secondary = Presenter.healTrigger(rule),
        status = rule.enabled and "ACTIVE" or "DISABLED",
        statusText = rule.enabled and "Ready" or "Disabled",
        actions = {
          { id = "healRuleToggle_" .. kind .. "_" .. rule.index, text = rule.enabled and "Disable" or "Enable", onClick = function() HealBot.toggleRule(kind, rule.index); rerender(shell) end },
          { id = "healRuleUp_" .. kind .. "_" .. rule.index, text = "Up", onClick = function() if HealBot.moveRule then HealBot.moveRule(kind, rule.index, "up"); rerender(shell) end end },
          { id = "healRuleDown_" .. kind .. "_" .. rule.index, text = "Down", onClick = function() if HealBot.moveRule then HealBot.moveRule(kind, rule.index, "down"); rerender(shell) end end },
          { id = "healRuleRemove_" .. kind .. "_" .. rule.index, text = "Remove", variant = "danger", onClick = function() HealBot.removeRule(kind, rule.index); rerender(shell) end },
        },
      }
    end
    DataTable.create(content, {
      id = "healRules_" .. kind, title = title, rows = tableRows,
      rowKey = function(row) return row.id end,
      emptyMessage = kind == "spell" and "No healing spells yet." or "No healing items yet.",
    })
    return
  end
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
      rerender(shell)
    end,
  })

  renderHealRuleList(content, shell, "spell", "Healing Spells")
  renderHealRuleList(content, shell, "item", "Healing Items")

  local actions = actionBar(content)
  actionButton(actions, { id = "manageHealRules", text = "Add / Manage Rules", onClick = function()
    if HealBot.show then HealBot.show() end
  end })
  if HealBot.showAlly then
    actionButton(actions, { id = "healFriend", text = "Heal Friend", onClick = function()
      HealBot.showAlly()
    end })
  end
end

local function renderLootControls(content, shell)
  local looting = TargetBot and TargetBot.Looting
  if not looting or not looting.getConfig or not DataTable or not Resolver then return end
  local config = looting.getConfig()
  Components.toggleRow(content, { label = "Loot every item", value = config.everyItem, onChange = function(value) looting.setPreference("everyItem", value) end })
  Components.toggleRow(content, { label = "Eat corpse food", value = config.eatFromCorpses, onChange = function(value) looting.setPreference("eatFromCorpses", value) end })

  local function collectionRows(collection, kind)
    local rows = {}
    for _, entry in ipairs(collection or {}) do
      local id = tonumber(type(entry) == "table" and entry.id or entry)
      if id then
        local visual = Resolver:item(id)
        rows[#rows + 1] = {
          id = kind .. "_" .. id, itemId = id, title = visual.name,
          secondary = kind == "item" and "Loot item" or "Loot container",
          status = "INFO", statusText = "Configured",
          actions = {
            { id = "editLoot_" .. kind .. "_" .. id, text = "Edit", onClick = function()
              selectedLootEntry = { id = id, kind = kind }
              rerender(shell)
            end },
            { id = "removeLoot_" .. kind .. "_" .. id, text = "Remove", variant = "danger", onClick = function()
              if kind == "item" then looting.removeItem(id) else looting.removeContainer(id) end
              if selectedLootEntry and selectedLootEntry.id == id and selectedLootEntry.kind == kind then
                selectedLootEntry = nil
              end
              rerender(shell)
            end },
          },
        }
      end
    end
    return rows
  end

  local lootItems = collectionRows(config.items, "item")
  local lootContainers = collectionRows(config.containers, "container")
  DataTable.create(content, { id = "lootItems", title = "Loot items", rows = lootItems, searchable = #lootItems > 4, rowKey = function(row) return row.id end, emptyMessage = "No loot items configured." })
  DataTable.create(content, { id = "lootContainers", title = "Containers", rows = lootContainers, searchable = #lootContainers > 4, rowKey = function(row) return row.id end, emptyMessage = "No loot containers configured." })

  local selected = selectedLootEntry
  local draft = { id = selected and tostring(selected.id) or "", kind = selected and selected.kind or "item" }
  Components.sectionHeader(content, { title = selected and "Edit selected item" or "Add item" })
  local input = Components.inputRow(content, { label = "Item ID", value = draft.id, onChange = function(value) draft.id = value end })
  Components.selectRow(content, {
    label = "Type", value = draft.kind == "item" and "Loot item" or "Container",
    options = { { text = "Loot item", value = "item" }, { text = "Container", value = "container" } },
    onChange = function(_, value) if value then draft.kind = value end end,
  })
  local feedback = Components.label(content, { id = "lootFeedback", text = "", textStyle = "helper" })
  Components.button(content, { id = selected and "saveLootItem" or "addLootItem", text = selected and "Save changes" or "Add item", onClick = function()
    local id = tonumber(draft.id ~= "" and draft.id or input:getInput():getText())
    local ok
    if selected then
      ok = looting.updateEntry(selected.id, selected.kind, id, draft.kind)
    elseif draft.kind == "item" then
      ok = looting.addItem(id)
    else
      ok = looting.addContainer(id)
    end
    if not ok then
      feedback:setText("Enter a valid item ID that is not already configured.")
      return
    end
    selectedLootEntry = nil
    rerender(shell)
  end })
  if selected then
    Components.button(content, {
      id = "cancelLootEdit", text = "Cancel", variant = "ghost",
      onClick = function() selectedLootEntry = nil; rerender(shell) end,
    })
    Components.button(content, {
      id = "deleteLootItem", text = "Delete", variant = "danger",
      onClick = function()
        local ok
        if selected.kind == "item" then
          ok = looting.removeItem(selected.id)
        else
          ok = looting.removeContainer(selected.id)
        end
        if ok then selectedLootEntry = nil; rerender(shell) end
      end,
    })
  end
end

local function renderSupplyControls(content, shell)
  if not Supplies then
    Components.emptyState(content, { message = "Supplies did not load. Check the startup log." })
    return
  end

  Components.sectionHeader(content, { title = "Profile" })
  profileSelect(content, {
    id = "supplyProfile",
    items = Supplies.listProfiles and Supplies.listProfiles() or {},
    value = Supplies.getCurrentProfile and Supplies.getCurrentProfile(),
    onChange = function(name)
      if Supplies.setCurrentProfile then Supplies.setCurrentProfile(name) end
      rerender(shell)
    end,
  })
  newProfileAction(content, {
    id = "newSupplyProfile", text = "New Profile", shell = shell,
    onCreate = function()
      if not Supplies.createProfile then return false, "Not available" end
      return Supplies.createProfile()
    end,
  })

  Components.sectionHeader(content, { title = "Items" })
  local items = Supplies.getItemsData and Supplies.getItemsData() or {}
  local ids = {}
  for id in pairs(items) do ids[#ids + 1] = tostring(id) end
  table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
  if #ids == 0 then Components.emptyState(content, { message = "No supply items configured." }) end
  if not DataTable or not Resolver then
    for _, id in ipairs(ids) do
      local values = items[id] or items[tonumber(id)]
      Components.itemRow(content, { id = "supplyItem_" .. id, itemId = id, title = "Item " .. id,
        subtitle = string.format("Min %s  Max %s  Avg %s", values.min or 0, values.max or 0, values.avg or 0) })
    end
  else
  local supplyRows = {}
  for _, id in ipairs(ids) do
    local values = items[id] or items[tonumber(id)]
    local visual = Resolver:item(id)
    supplyRows[#supplyRows + 1] = {
      id = id, itemId = id, title = visual.name,
      secondary = string.format("Min %s · Max %s · Avg %s", values.min or 0, values.max or 0, values.avg or 0),
      status = selectedSupplyId == id and "ACTIVE" or "INFO",
      statusText = selectedSupplyId == id and "Selected" or "Configured",
      onClick = function() selectedSupplyId = id; rerender(shell) end,
      actions = { { id = "removeSupply_" .. id, text = "Remove", variant = "danger", onClick = function() Supplies.removeItem(id); selectedSupplyId = nil; rerender(shell) end } },
    }
  end
  DataTable.create(content, {
    id = "supplyItems", title = "Items", rows = supplyRows,
    rowKey = function(row) return row.id end, searchable = #supplyRows > 4,
    emptyMessage = "No supply items configured.",
  })

  local selected = selectedSupplyId and (items[selectedSupplyId] or items[tonumber(selectedSupplyId)])
  if selected then
    Components.sectionHeader(content, { title = "Edit selected item" })
    local draft = { min = selected.min or 0, max = selected.max or 0, avg = selected.avg or 0 }
    for _, field in ipairs({ "min", "max", "avg" }) do
      local key = field
      Components.inputRow(content, {
        id = "supply_" .. selectedSupplyId .. "_" .. key, label = key:upper(), value = draft[key],
        onChange = function(text)
          local number = tonumber(text)
          if not number then return end
          draft[key] = number
          Supplies.setItem(selectedSupplyId, draft.min, draft.max, draft.avg)
        end,
      })
    end
  end
  end

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
  looting = renderLootControls,
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
