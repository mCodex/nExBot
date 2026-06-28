setDefaultTab("Cave")

do
  local path = nExBot.paths.base .. "/core/cavebot_control_panel.otui"
  local content = nil
  if g_resources and g_resources.readFileContents then
    content = g_resources.readFileContents(path)
  end
  if content then
    g_ui.loadUIFromString(content)
  else
    warn("[CaveBot] Failed to load cavebot_control_panel.otui from " .. path)
  end
end

local panel = UI.createWidget("CaveBotControlPanel")

storage.caveBot = {
  forceRefill = false,
  backStop = false,
  backTrainers = false,
  backOffline = false
}

-- [[ B U T T O N S ]] --

local forceRefill = UI.Button("Force Refill", function(widget)
    storage.caveBot.forceRefill = true
end, panel.buttons)

local backStop = UI.Button("Back & Stop", function(widget)
    storage.caveBot.backStop = true
end, panel.buttons)

local backTrainers = UI.Button("To Trainers", function(widget)
    storage.caveBot.backTrainers = true
end, panel.buttons)

local backOffline = UI.Button("Offline", function(widget)
    storage.caveBot.backOffline = true
end, panel.buttons)