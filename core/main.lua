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

local windowSection = setupUI([[
NxBotSection
  height: 50
  
  ToolTipLabel
    text-align: center
    text: Window Settings (Left Panel)
    font: verdana-11px-rounded
    color: #3be4d0
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right

  Label
    text: Width:
    font: verdana-11px-rounded
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 8
    width: 40

  NxTextInput
    id: widthInput
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    width: 40
    margin-left: 2
    
  Label
    text: Height:
    font: verdana-11px-rounded
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    margin-left: 10
    width: 45

  NxTextInput
    id: heightInput
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    width: 40
    margin-left: 2
]])

if windowSection then
  local leftPanel = modules.game_interface and modules.game_interface.getLeftPanel and modules.game_interface.getLeftPanel()
  
  local storedW = storage.window_settings.leftWidth or (leftPanel and leftPanel:getWidth()) or 260
  local storedH = storage.window_settings.leftHeight or (leftPanel and leftPanel:getHeight()) or 600
  
  if leftPanel then
    if storage.window_settings.leftWidth then leftPanel:setWidth(storage.window_settings.leftWidth) end
    if storage.window_settings.leftHeight then leftPanel:setHeight(storage.window_settings.leftHeight) end
  end

  windowSection.widthInput:setText(tostring(storedW))
  windowSection.heightInput:setText(tostring(storedH))

  windowSection.widthInput.onTextChange = function(widget, text)
    local val = tonumber(text)
    if val and val > 0 then
      storage.window_settings.leftWidth = val
      if leftPanel then leftPanel:setWidth(val) end
    end
  end

  windowSection.heightInput.onTextChange = function(widget, text)
    local val = tonumber(text)
    if val and val > 0 then
      storage.window_settings.leftHeight = val
      if leftPanel then leftPanel:setHeight(val) end
    end
  end
end

UI.Separator()