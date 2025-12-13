local version = "1.0.0"

UI.Label("nExBot v" .. version)
UI.Separator()

-- Create a panel with blinking label
local blinkUI = setupUI([[
Panel
  height: 20
  Label
    id: blinkLabel
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: TibiaRPGBrasil!
    color: #ff5555
]])

local label = blinkUI.blinkLabel
local colors = {"#ff5555", "#ffaa00"}  -- alternate colors
local idx = 1

macro(300, function() -- change every 300ms
  idx = (idx % #colors) + 1
  label:setColor(colors[idx])
end)

local docBtn = UI.Button("Website", function()
  g_platform.openUrl("https://tibiarpgbrasil.com")
end)
if docBtn then
  docBtn:setTooltip("Opens RPG's website. More than 20 years online!")
end

UI.Label("The project wouldn't be possible without RPG's staff!")

UI.Separator()
