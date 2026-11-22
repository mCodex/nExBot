-- Exercise the real setup controls against an offline container and native widgets.
return function(parent)
  local sidebar, setup
  local window = g_ui.createWidget("UIWidget", parent)
  window:setId("container7")
  local title = g_ui.createWidget("Label", window)
  title:setId("miniwindowTitle")
  title:setText("Moon backpack")
  local bag = {
    window = window,
    getId = function() return 7 end,
    getContainerItem = function() return {getId = function() return 2866 end} end,
  }
  local noop = function() end
  local timers, opened = {}, nil
  local env = setmetatable({
    storage = {containerPanel = {autoMinimize = false, containerList = {
      {name = "Potions", itemId = 2866, enabled = true, items = {}}
    }}},
    nExBot = {paths = {core = "/core"}, Shared = {deepClone = table.copy}},
    setDefaultTab = noop, macro = noop, onContainerClose = noop, onPlayerHealthChange = noop,
    onAddItem = noop, onRemoveItem = noop, onPlayerInventoryChange = noop,
    onContainerOpen = function(fn) opened = fn end,
    g_game = {getContainers = function() return {[7] = bag} end,
              getContainer = function(id) if id == 7 then return bag end end},
    schedule = function(_, fn) table.insert(timers, fn) end,
    UI = {
      Separator = noop,
      Container = function(_, _, _, grid)
        grid.setItems = function(self, items) self.itemsForTest = items end
        grid.getItems = function(self) return self.itemsForTest or {} end
      end,
      createWidget = function(style) sidebar = g_ui.createWidget(style, parent) return sidebar end,
      createWindow = function(style) setup = g_ui.createWidget(style, parent) return setup end,
    },
  }, {__index = _G})
  env.load = function(source, path) return setfenv(assert(loadstring(source, path)), env) end
  local function flush()
    while #timers > 0 do table.remove(timers, 1)() end
  end
  setfenv(assert(loadstring(g_resources.readFileContents("/core/Containers.lua"))), env)()
  flush()
  sidebar.setupBtn:onClick()
  setup.renameEnabled:onClick()
  flush()
  assert(title:getText() == "Potions", "Rename must update the visible title of an open bag")
  setup.renameEnabled:onClick()
  assert(title:getText() == "Moon backpack", "Turning Rename off must restore the client's title")
  setup.renameEnabled:onClick()
  local entry = setup.containerList:getFirstChild()
  entry.enabled:onClick()
  assert(title:getText() == "Moon backpack", "Disabling the rule must restore its title")
  entry.enabled:onClick()
  assert(title:getText() == "Potions")
  title:setText("Moon backpack")
  opened(bag)
  flush()
  assert(title:getText() == "Potions", "Opening a matching bag must apply its rule")
  setup.containerName:setText("Supplies")
  -- The offline client has no DAT loaded for the selected inventory item.
  setup.containerId.getItemId = function() return 2866 end
  setup.addContainer:onClick()
  assert(title:getText() == "Supplies", "Editing a rule must update open bags immediately")
  setup.containerList:getFirstChild().remove:onClick()
  assert(title:getText() == "Moon backpack")
  sidebar:hide()
  setup:hide()
  window:hide()
end
