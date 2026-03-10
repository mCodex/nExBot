local version = nExBot.version or "0.0.0"

local getClient = nExBot.Shared.getClient

UI.Label("nExBot v" .. version)

local discordBtn = UI.Button("Join our Discord", function()
  g_platform.openUrl("https://discord.gg/qKasgMN7gG")
end)
if discordBtn then
  discordBtn:setTooltip("Join the nExBot Discord community for help, updates, and configs.")
end

UI.Separator()

if not storage.window_settings then
  storage.window_settings = {}
end

g_ui.loadUIFromString([[
WindowSettingsWindow < NxWindow
  !text: tr('Window Settings')
  size: 260 170
  padding: 15

  Label
    id: descLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-wrap: true
    text-auto-resize: true
    text: Configure the left panel dimensions below. These settings will override the default client layout and persist automatically.
    margin-top: 5

  Label
    text: Panel Width:
    font: verdana-11px-rounded
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 15
    width: 80

  NxTextInput
    id: widthInput
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 5
    
  Label
    text: Panel Height:
    font: verdana-11px-rounded
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 12
    width: 80

  NxTextInput
    id: heightInput
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 5

  NxButton
    id: closeButton
    !text: tr('Close')
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 45 21
]])

local windowSettingsWindow = nil

local function showWindowSettings()
  if not windowSettingsWindow then
    windowSettingsWindow = UI.createWindow('WindowSettingsWindow')
    if not windowSettingsWindow then return end
    
    windowSettingsWindow:hide()
    
    windowSettingsWindow.closeButton.onClick = function(widget)
      windowSettingsWindow:hide()
    end
    
    local leftPanel = modules.game_interface and modules.game_interface.getLeftPanel and modules.game_interface.getLeftPanel()
    
    local storedW = storage.window_settings.leftWidth or (leftPanel and leftPanel:getWidth()) or 260
    local storedH = storage.window_settings.leftHeight or (leftPanel and leftPanel:getHeight()) or 600
    
    windowSettingsWindow.widthInput:setText(tostring(storedW))
    windowSettingsWindow.heightInput:setText(tostring(storedH))
    
    windowSettingsWindow.widthInput.onTextChange = function(widget, text)
      local val = tonumber(text)
      if val and val > 0 then
        storage.window_settings.leftWidth = val
        if leftPanel then leftPanel:setWidth(val) end
      end
    end
    
    windowSettingsWindow.heightInput.onTextChange = function(widget, text)
      local val = tonumber(text)
      if val and val > 0 then
        storage.window_settings.leftHeight = val
        if leftPanel then leftPanel:setHeight(val) end
      end
    end
  end
  
  windowSettingsWindow:show()
  windowSettingsWindow:raise()
  windowSettingsWindow:focus()
end

UI.Button("Window Settings", function()
  showWindowSettings()
end)

UI.Separator()

-- Apply settings to panel on load if available
local leftPanel = modules.game_interface and modules.game_interface.getLeftPanel and modules.game_interface.getLeftPanel()
if leftPanel then
  if storage.window_settings.leftWidth then leftPanel:setWidth(storage.window_settings.leftWidth) end
  if storage.window_settings.leftHeight then leftPanel:setHeight(storage.window_settings.leftHeight) end
end