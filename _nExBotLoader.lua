--[[
  NexBot Loader
  Main entry point that loads all bot components
  
  Author: NexBot Team  
  Version: 1.0.0
  Date: December 2025
  
  This file replaces the old _Loader.lua for the NexBot system
]]

-- Get current config name
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

-- Load all OTUI style files
local configFiles = g_resources.listDirectoryFiles("/bot/" .. configName .. "/NexBot", true, false)
for i, file in ipairs(configFiles) do
  local ext = file:split(".")
  if ext[#ext]:lower() == "ui" or ext[#ext]:lower() == "otui" then
    g_ui.importStyle(file)
  end
end

-- Helper function to load scripts
local function loadScript(path)
  return dofile(path .. ".lua")
end

-- Load NexBot core first
local nexbotFiles = {
  "/NexBot/main",  -- Core initialization
}

-- Load NexBot core
for i, file in ipairs(nexbotFiles) do
  local success, err = pcall(function()
    loadScript(file)
  end)
  if not success then
    warn("[NexBot Loader] Failed to load " .. file .. ": " .. tostring(err))
  end
end

-- Set default tab and separator for private scripts
setDefaultTab("Main")
UI.Separator()
UI.Label("Private Scripts:")
UI.Separator()

-- Log completion
if logInfo then
  logInfo("NexBot Loader completed - All modules loaded")
end
