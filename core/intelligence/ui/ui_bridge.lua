local sections = {
  "Overview", "Targeting", "Dynamic Lure", "Pull System", "Wave Avoidance",
  "CaveBot Intelligence", "Monster Profiles", "Navigation Profiles",
  "Resource Efficiency", "Replay", "Diagnostics", "Advanced",
}

local path = nExBot.paths.base .. "/core/intelligence/ui/ui_bridge.otui"
local content = g_resources and g_resources.readFileContents and g_resources.readFileContents(path)
if not content then return end
g_ui.loadUIFromString(content)

local window = UI.createWindow("IntelligenceConsoleWindow")
window:hide()
local selected = sections[1]
for _, section in ipairs(sections) do window.section:addOption(section) end

local function modelSummary()
  local lines = {}
  for _, name in ipairs(IntelligenceModelCatalog.names()) do
    local entry = nExBot.Intelligence.models:get(name)
    lines[#lines + 1] = name .. ": " .. (entry and entry.mode or "OFF")
  end
  return table.concat(lines, "\n")
end

local function render()
  local Intelligence = nExBot.Intelligence
  local text
  if selected == "Overview" then
    text = string.format("Lifecycle: %s\nSnapshot: %d\nRoute: %s\nModels: SHADOW by default",
      Intelligence.lifecycle.active and "active" or "stopped", Intelligence.lifecycle:generation("snapshot"), Intelligence.route.state)
  elseif selected == "Targeting" then
    text = "Target selection is arbitrated before AttackStateMachine execution.\nReachability authority: TargetReachability."
  elseif selected == "Dynamic Lure" then text = "State: " .. Intelligence.dynamicLure.state
  elseif selected == "Pull System" then text = "State: " .. Intelligence.pull.state
  elseif selected == "Wave Avoidance" then text = "State: " .. Intelligence.waveBeam.state
  elseif selected == "CaveBot Intelligence" then text = "Route state: " .. Intelligence.route.state .. "\nGeneration: " .. Intelligence.route.generation
  elseif selected == "Monster Profiles" then text = modelSummary()
  elseif selected == "Navigation Profiles" then text = "Learned costs are bounded, decayed, and additive."
  elseif selected == "Resource Efficiency" then text = "Resource events: " .. #Intelligence.resources:recent() .. "\nLoot observations: " .. #Intelligence.loot:recent()
  elseif selected == "Replay" then text = "Retained records: " .. #Intelligence.replay:export()
  elseif selected == "Diagnostics" then
    local issues = IntelligenceBotDoctor.inspect(IntelligenceBotDoctor.capture(Intelligence))
    local lines = {}
    for _, issue in ipairs(issues) do lines[#lines + 1] = issue.code .. ": " .. issue.message .. "\n" .. issue.action end
    text = #lines == 0 and "No reported issues." or table.concat(lines, "\n\n")
  else text = "Performance budgets preserve safety and deterministic execution."
  end
  window.content.text:setText(text)
end

window.section.onOptionChange = function(_, option) selected = option; render() end
window.buttons.refresh.onClick = render
window.buttons.close.onClick = function() window:hide() end
window.buttons.shadow.onClick = function()
  for _, name in ipairs(IntelligenceModelCatalog.names()) do nExBot.Intelligence.models:setMode(name, "SHADOW") end
  render()
end

setDefaultTab("Main")
UI.Button("nExBot Tactical Intelligence", function()
  local root = g_ui.getRootWidget()
  if root then
    window:setWidth(math.max(260, math.min(460, root:getWidth() - 20)))
    window:setHeight(math.max(280, math.min(500, root:getHeight() - 40)))
  end
  window:show(); window:raise(); window:focus(); render()
end)

UnifiedTick.register("intelligence_ui", {
  interval = 500,
  priority = UnifiedTick.Priority.LOW,
  group = "intelligence",
  handler = function() if window:isVisible() then render() end end,
})
