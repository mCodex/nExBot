CaveBot.Editor = {}
local zChanging = nExBot.zChanging or function() return false end
CaveBot.Editor.Actions = {}

-- Table-mode registerAction entries (the "add a waypoint of this type"
-- palette), populated as modules register and rendered as a single
-- searchable DataTable instead of one button per action.
CaveBot.Editor.Palette = {}

-- These three are pure modules with no g_ui dependency (see
-- cavebot/editor_selection.lua, editor_history.lua, editor_icons.lua) and are
-- dofiled immediately before this file, so resolving them eagerly here is
-- safe - unlike the ui/shell component modules below, which load later.
local Selection = (nExBot and nExBot.Nav and nExBot.Nav["cavebot.editor_selection"]) or
  (type(require) == "function" and require("cavebot.editor_selection"))
local History = (nExBot and nExBot.Nav and nExBot.Nav["cavebot.editor_history"]) or
  (type(require) == "function" and require("cavebot.editor_history"))
local Icons = (nExBot and nExBot.Nav and nExBot.Nav["cavebot.editor_icons"]) or
  (type(require) == "function" and require("cavebot.editor_icons"))

-- Editor tracks its own selection so action buttons and the Delete key stay
-- bound to what the user picked in the editor, not to CaveBot.Route's focus
-- (which the walking engine changes on its own).
CaveBot.Editor.selected = nil
CaveBot.Editor.Selection = Selection.new()
local editorHistory = History.new()

-- ui/shell's component modules (Components, DataTable) only finish loading
-- during ui/init.lua's synchronous pass, which runs after this file is
-- dofiled but before CaveBot.Editor.setup() is ever called (setup runs from
-- cavebot/cavebot.lua's deferred chain). Resolve them lazily inside
-- functions, never as top-level locals, so this file can be dofiled early.
local function resolveComponents()
  return (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or
    (type(require) == "function" and require("ui.components.components"))
end
local function resolveDataTable()
  return (nExBot and nExBot.UI and nExBot.UI["ui.components.data_table"]) or
    (type(require) == "function" and require("ui.components.data_table"))
end

CaveBot.Editor.setMessage = function(text)
  local ui = CaveBot.Editor.ui
  if ui and ui.message and ui.message.setText then ui.message:setText(text) end
end

CaveBot.Editor.select = function(item)
  CaveBot.Editor.selected = item
  if item and CaveBot.Route and CaveBot.Route.focusChild then
    CaveBot.Route:focusChild(item)
  end
end

CaveBot.Editor.withSelected = function(fn)
  local selected = CaveBot.Editor.selected
  if not selected or CaveBot.Route:getChildIndex(selected) < 1 then
    CaveBot.Editor.selected = nil
    CaveBot.Editor.setMessage("Select a waypoint first.")
    return
  end
  return fn(selected)
end

CaveBot.Editor.commitChange = function()
  if CaveBot.invalidateWaypointCache then CaveBot.invalidateWaypointCache() end
  if CaveBot.invalidateGotoDistCache then CaveBot.invalidateGotoDistCache() end
  CaveBot.save()
  CaveBot.Editor.refreshTable()
end

-- Kept as the single-target removal path: the public API other code may
-- still call directly, and the fallback used by deleteSelection() whenever
-- zero or one waypoint is targeted (no confirmation needed for that case).
CaveBot.Editor.removeSelected = function()
  CaveBot.Editor.withSelected(function(action)
    local index = CaveBot.Route:getChildIndex(action)
    editorHistory:push({
      kind = "delete",
      items = { { action = action.action, value = action.value, index = index } },
    })
    action:destroy()
    local replacement = CaveBot.Route:getChildByIndex(index) or CaveBot.Route:getChildByIndex(index - 1)
    CaveBot.Editor.select(replacement)
    CaveBot.Editor.commitChange()
    if not replacement then
      CaveBot.Editor.setMessage("Route is empty. Add a waypoint to start building.")
    end
  end)
end

-- Entry point for the Remove button and the Delete key: deletes whatever is
-- multi-selected, falling back to the single .selected waypoint when nothing
-- is multi-selected. Deleting more than one waypoint asks for confirmation
-- first; deleting zero or one never adds that friction.
CaveBot.Editor.deleteSelection = function()
  local targets = CaveBot.Editor.Selection:all()
  if #targets == 0 and CaveBot.Editor.selected then targets = { CaveBot.Editor.selected } end

  if #targets <= 1 then
    CaveBot.Editor.removeSelected()
    CaveBot.Editor.Selection:clear()
    return
  end

  local function performDelete()
    local snapshotItems = {}
    for _, entry in ipairs(targets) do
      snapshotItems[#snapshotItems + 1] = {
        action = entry.action, value = entry.value, index = CaveBot.Route:getChildIndex(entry),
      }
    end
    table.sort(snapshotItems, function(a, b) return a.index < b.index end)
    editorHistory:push({ kind = "delete", items = snapshotItems })

    local byIndexDesc = {}
    for i, entry in ipairs(targets) do byIndexDesc[i] = entry end
    table.sort(byIndexDesc, function(a, b) return CaveBot.Route:getChildIndex(a) > CaveBot.Route:getChildIndex(b) end)
    for _, entry in ipairs(byIndexDesc) do entry:destroy() end

    CaveBot.Editor.Selection:clear()
    local replacement = CaveBot.Route:getFirstChild()
    CaveBot.Editor.select(replacement)
    CaveBot.Editor.commitChange()
    if not replacement then
      CaveBot.Editor.setMessage("Route is empty. Add a waypoint to start building.")
    end
  end

  local Components = resolveComponents()
  if Components and Components.confirmDialog then
    Components.confirmDialog(g_ui.getRootWidget(), {
      message = "Delete " .. #targets .. " waypoints?",
      confirmText = "Delete",
      cancelText = "Cancel",
      onConfirm = performDelete,
    })
  else
    performDelete()
  end
end

-- Undoes the last delete or reorder (single level - a second undo without an
-- intervening action has nothing left to consume).
CaveBot.Editor.undo = function()
  local snapshot = editorHistory:undo()
  if not snapshot then
    CaveBot.Editor.setMessage("Nothing to undo.")
    return
  end

  if snapshot.kind == "delete" then
    for _, rec in ipairs(snapshot.items) do
      local widget = CaveBot.addAction(rec.action, rec.value)
      CaveBot.Route:moveChildToIndex(widget, rec.index)
    end
  elseif snapshot.kind == "reorder" then
    local replay = snapshot.items
    if snapshot.direction and snapshot.direction < 0 then
      replay = {}
      for i = #snapshot.items, 1, -1 do replay[#replay + 1] = snapshot.items[i] end
    end
    for _, rec in ipairs(replay) do
      if CaveBot.Route:getChildIndex(rec.entry) >= 1 then
        CaveBot.Route:moveChildToIndex(rec.entry, rec.index)
        CaveBot.Route:ensureChildVisible(rec.entry)
      end
    end
  end

  CaveBot.Editor.commitChange()
end

-- Moves every selected waypoint one step in `direction` (-1 up, 1 down) as a
-- single contiguous block, preserving their relative order. Falls back to
-- the single .selected waypoint when nothing is multi-selected.
local function moveSelectionBlock(direction)
  local targets = CaveBot.Editor.Selection:all()
  if #targets == 0 and CaveBot.Editor.selected then targets = { CaveBot.Editor.selected } end
  if #targets == 0 then
    CaveBot.Editor.setMessage("Select a waypoint first.")
    return
  end

  table.sort(targets, function(a, b)
    return CaveBot.Route:getChildIndex(a) < CaveBot.Route:getChildIndex(b)
  end)

  local topIndex = CaveBot.Route:getChildIndex(targets[1])
  local bottomIndex = CaveBot.Route:getChildIndex(targets[#targets])
  if direction < 0 and topIndex <= 1 then return end
  if direction > 0 and bottomIndex >= CaveBot.Route:getChildCount() then return end

  local snapshotItems = {}
  for _, entry in ipairs(targets) do
    snapshotItems[#snapshotItems + 1] = { entry = entry, index = CaveBot.Route:getChildIndex(entry) }
  end

  -- Move the leading item first (top-most going up, bottom-most going down)
  -- so a not-yet-moved sibling never gets displaced out from under it.
  local ordered = targets
  if direction > 0 then
    ordered = {}
    for i = #targets, 1, -1 do ordered[#ordered + 1] = targets[i] end
  end

  for _, entry in ipairs(ordered) do
    local index = CaveBot.Route:getChildIndex(entry)
    CaveBot.Route:moveChildToIndex(entry, index + direction)
    CaveBot.Route:ensureChildVisible(entry)
  end

  editorHistory:push({ kind = "reorder", direction = direction, items = snapshotItems })
  CaveBot.Editor.commitChange()
end

local function handleRowClick(item)
  local sel = CaveBot.Editor.Selection
  local ctrl = g_keyboard and g_keyboard.isCtrlPressed and g_keyboard.isCtrlPressed()
  local shift = g_keyboard and g_keyboard.isShiftPressed and g_keyboard.isShiftPressed()

  if shift and CaveBot.Editor.selected then
    sel:selectRange(CaveBot.Editor.selected, item, CaveBot.Route:getChildren())
    CaveBot.Editor.select(item)
  elseif ctrl then
    sel:toggle(item)
    local all = sel:all()
    CaveBot.Editor.select(all[#all])
  else
    sel:selectOnly(item)
    CaveBot.Editor.select(item)
  end

  CaveBot.Editor.refreshTable()
end

-- also works as registerAction(action, params), then text == action
-- params are options for text editor or function to be executed when clicked
-- you have many examples how to use it bellow
CaveBot.Editor.registerAction = function(action, text, params)
  if type(text) ~= 'string' then
    params = text
    text = action
  end

  if type(params) == 'function' then
    local button = UI.createWidget('CaveBotEditorButton', CaveBot.Editor.ui.commands)
    button:setText(text)
    button.onClick = params
    return button
  end

  local raction = CaveBot.Actions[action]
  if not raction then
    return warn("CaveBot editor warn: action " .. action .. " doesn't exist")
  end
  CaveBot.Editor.Actions[action] = params

  CaveBot.Editor.Palette[#CaveBot.Editor.Palette + 1] = {
    action = action,
    title = text,
    secondary = params.description,
    itemId = Icons.iconFor(action),
    onClick = function()
      CaveBot.Editor.edit(action, nil, function(action, value)
        local focusedAction = CaveBot.Editor.selected
        local index = CaveBot.Route:getChildCount()
        if focusedAction then
          index = CaveBot.Route:getChildIndex(focusedAction)
        end
        local widget = CaveBot.addAction(action, value)
        CaveBot.Route:moveChildToIndex(widget, index + 1)
        CaveBot.Editor.select(widget)
        CaveBot.Editor.commitChange()
      end)
    end,
  }

  -- setup() builds the palette DataTable from whatever's registered by then;
  -- modules that register their own actions later (after setup already ran)
  -- need this table live-refreshed so their entry actually shows up.
  local ui = CaveBot.Editor.ui
  if ui and ui.paletteHandle then
    ui.paletteHandle:update(ui.paletteOptions)
  end
end

CaveBot.Editor.refreshTable = function()
  local ui = CaveBot.Editor.ui
  if not ui or not ui.tableHandle then return end

  local children = CaveBot.Route:getChildren()
  CaveBot.Editor.Selection:prune(children)
  if CaveBot.Editor.selected and CaveBot.Route:getChildIndex(CaveBot.Editor.selected) < 1 then
    CaveBot.Editor.selected = nil
  end

  local rows = {}
  for index, item in ipairs(children) do
    rows[#rows + 1] = {
      __entry = item,
      itemId = Icons.iconFor(item.action, item.value),
      title = tostring(item.action or "?"),
      secondary = index .. ": " .. tostring(item.value or ""),
      selected = CaveBot.Editor.Selection:isSelected(item) or CaveBot.Editor.selected == item,
      onClick = function() handleRowClick(item) end,
    }
  end

  ui.tableOptions.rows = rows
  ui.tableHandle:update(ui.tableOptions)
end

CaveBot.Editor.setup = function()
  CaveBot.Editor.ui = UI.createWindow("CaveBotEditorPanel", g_ui.getRootWidget())
  local ui = CaveBot.Editor.ui
  local registerAction = CaveBot.Editor.registerAction
  local DataTable = resolveDataTable()
  if ui.close then ui.close.onClick = function() ui:hide() end end

  registerAction("move up", "Move Up", function() moveSelectionBlock(-1) end)
  registerAction("edit", "Edit", function()
    CaveBot.Editor.withSelected(function(action)
      if not action.onDoubleClick then return end
      action.onDoubleClick(action)
    end)
  end)
  registerAction("move down", "Move Down", function() moveSelectionBlock(1) end)
  registerAction("remove", "Remove", function()
    CaveBot.Editor.deleteSelection()
  end)

  registerAction("label", {
    value="labelName",
    title="Label",
    description="Add label",
    multiline=false
  })
  registerAction("delay", {
    value="500",
    title="Delay",
    description="Delay next action (in milliseconds),randomness (in percent-optional)",
    multiline=false,
    validation="^[0-9]{1,10}$|^[0-9]{1,10},[0-9]{1,4}$"
  })
  registerAction("gotolabel", "go to label", {
    value="labelName",
    title="Go to label",
    description="Go to label",
    multiline=false
  })
  registerAction("goto", "go to", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Go to position",
    description="Go to position (x,y,z)",
    multiline=false,
    validation="^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)$"
  })
  registerAction("use", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Use",
    description="Use item from position (x,y,z) or from inventory (itemId)",
    multiline=false
  })
  registerAction("usewith", "use with", {
    value=function() return "itemId," .. posx() .. "," .. posy() .. "," .. posz() end,
    title="Use with",
    description="Use item at position (itemid,x,y,z)",
    multiline=false,
    validation="^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)$"
  })
  registerAction("say", {
    value="text",
    title="Say",
    description="Enter text to say",
    multiline=false
  })
  registerAction("follow", {
    value="NPC name",
    title="Follow Creature",
    description="insert creature name to follow",
    multiline=false
  })
  registerAction("npcsay", {
    value="text",
    title="NPC Say",
    description="Enter text to NPC say",
    multiline=false
  })

  -- Ensure ExampleFunctions exists and has at least one entry
  local examples = CaveBot.Editor.ExampleFunctions
  local defaultExample = (examples and examples[1] and examples[1][2]) or "return true"

  registerAction("function", {
    title="Edit bot function",
    multiline=true,
    value=defaultExample,
    examples=CaveBot.Editor.ExampleFunctions or {},
    width=650
  })

  ui.tableOptions = {
    id = "waypoints",
    rowKey = function(row) return tostring(row.__entry) end,
    emptyMessage = "Route is empty. Use the palette to add a waypoint.",
    rows = {},
  }
  ui.tableHandle = DataTable.create(ui.tableContainer, ui.tableOptions)

  ui.paletteOptions = {
    id = "palette",
    searchable = true,
    title = "Add waypoint",
    rows = CaveBot.Editor.Palette,
    rowKey = function(row) return row.action end,
    searchText = function(row) return (row.title or "") .. " " .. row.action end,
    emptyMessage = "No actions available.",
  }
  ui.paletteHandle = DataTable.create(ui.palette, ui.paletteOptions)

  ui.autoRecording.onClick = function()
    if ui.autoRecording:isOn() then
      CaveBot.Recorder.disable()
    else
      CaveBot.Recorder.enable()
    end
  end

  -- callbacks
  onPlayerPositionChange(function(pos)
    if zChanging() then
      return
    end
    ui.pos:setText("Position: " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
  end)
  ui.pos:setText("Position: " .. posx() .. ", " .. posy() .. ", " .. posz())
  ui:hide()

  local lastRevision = -1
  macro(250, function()
    if not ui:isVisible() then return end
    local revision = CaveBot.Route:getRevision()
    if revision ~= lastRevision then
      lastRevision = revision
      CaveBot.Editor.refreshTable()
    end
  end)

  onKeyPress(function(keys)
    if not ui:isVisible() then return end
    if keys == 'Delete' then
      CaveBot.Editor.deleteSelection()
    elseif keys == 'Ctrl+Up' then
      moveSelectionBlock(-1)
    elseif keys == 'Ctrl+Down' then
      moveSelectionBlock(1)
    elseif keys == 'Ctrl+Z' then
      CaveBot.Editor.undo()
    end
  end)
end

CaveBot.Editor.show = function()
  CaveBot.Editor.refreshTable()
  CaveBot.Editor.ui:show()
end

CaveBot.Editor.hide = function()
  editorHistory:clear()
  CaveBot.Editor.ui:hide()
end

CaveBot.Editor.edit = function(action, value, callback) -- callback = function(action, value)
  local params = CaveBot.Editor.Actions[action]
  if not params then return end
  if not value then
    if type(params.value) == 'function' then
      value = params.value()
    elseif type(params.value) == 'string' then
      value = params.value
    end
  end

  UI.EditorWindow(value, params, function(newText)
    callback(action, newText)
  end)
end
