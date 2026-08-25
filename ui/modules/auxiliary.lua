-- Secondary managers grouped by user goal. Domain modules own all state.
local Components = nExBot.UI["ui.components.components"]
local Actions = nExBot.UI["ui.core.actions"]
local Registry = nExBot.UI.ModuleRegistry

local function macro(key)
  return BotDB and BotDB.getMacro and BotDB.getMacro(key)
end

local managers = {
  tools = { label = "Tools", order = 80, items = {
    { "Containers", "Backpack setup and sorting", "open_containers", function() return Containers end },
    { "Depositer", "Deposit and sell lists", "open_depositer", function() return nExBot.Depositer end },
    { "Dropper", "Drop configured items", "toggle_dropper", function() return nExBot.Dropper end, true },
    { "Depot withdraw", "Withdraw configured supplies", "toggle_depot_withdraw", function() return nExBot.DepotWithdraw end, true },
    { "Tools settings", "Client and hunt preferences", "open_extras", function() return nExBot.Extras end },
  } },
  safety = { label = "Safety", order = 90, items = {
    { "Alarms", "Alerts and emergency actions", "open_alarms", function() return Alarms end, true, "toggle_alarms" },
    { "Conditions", "Cures and protective spells", "show_conditions", function() return Conditions end, true, "toggle_conditions" },
    { "Anti-RS", "Stops unsafe combat activity", "toggle_antirs", function() return AntiRs end, true },
    { "Push Max", "Push protection and hotkey", "open_pushmax", function() return PushMax end, true, "toggle_pushmax" },
    { "Combo", "Leader-assisted attacks", "open_combo", function() return ComboBot end, true, "toggle_combo" },
  } },
  equipment = { label = "Character", order = 100, items = {
    { "Attack rotation", "Spells, runes and priorities", "open_attack_config", function() return AttackBot end },
    { "Healing", "Self-healing rules", "open_healing", function() return HealBot end },
    { "Friend healer", "Party healing priorities", "open_friend_healer", function() return HealBot and HealBot.showAlly end },
    { "Equipment rules", "Automatic equipment conditions", "open_equipper", function() return nExBot.Equipper end, true, "toggle_equipper" },
    { "Quiver manager", "Automatic ammunition refill", "toggle_quiver", function() return macro("quiverManager") end, true },
  } },
  analytics = { label = "Analytics", order = 110, items = {
    { "Hunt analyzer", "XP, profit, waste and kills", "open_analyzer", function() return Analyzer end },
  } },
  utilities = { label = "Advanced", order = 120, items = {
    { "Hold target", "Keep the selected target", "toggle_hold_target", function() return nExBot.HoldTarget end, true },
    { "Floor spy", "Inspect nearby floors", "toggle_spy_level", function() return nExBot.SpyLevel end, true },
    { "Scripts", "Edit personal Lua scripts", "open_script_editor", function() return IngameEditor end },
  } },
}

local function enabled(module)
  if not module then return nil end
  local getter = module.isEnabled or module.isOn
  if type(getter) ~= "function" then return nil end
  local ok, value = pcall(getter)
  if not ok then return nil end
  return value == true
end

local function runAndRefresh(shell, actionId)
  local ok = Actions.run(actionId)
  if ok and shell and shell.renderCurrent then shell:renderCurrent() end
end

local function renderCategory(shell, category, content)
  Components.sectionHeader(content, { title = category.label })
  for _, item in ipairs(category.items) do
    local module = item[4]()
    local canToggle, isEnabled = item[5], item[5] and enabled(module) or nil
    local openAction = item[6] and item[3] or (not canToggle and item[3])
    local toggleAction = item[6] or (canToggle and item[3])
    local rowActions = {}
    if module then
      if openAction then
        rowActions[#rowActions + 1] = {
          id = openAction, text = "Open",
          onClick = function() runAndRefresh(shell, openAction) end,
        }
      end
      if toggleAction and isEnabled ~= nil then
        rowActions[#rowActions + 1] = {
          id = toggleAction, text = isEnabled and "Turn off" or "Turn on",
          onClick = function() runAndRefresh(shell, toggleAction) end,
        }
      end
    end
    local status = not module and "UNKNOWN"
      or (isEnabled ~= nil and (isEnabled and "ACTIVE" or "DISABLED"))
    Components.listRow(content, {
      id = "manager_" .. item[3], title = item[1], subtitle = item[2],
      status = status,
      statusText = not module and "Not loaded" or (isEnabled ~= nil and (isEnabled and "On" or "Off")),
      actions = rowActions,
    })
  end
end

for id, category in pairs(managers) do
  local definition = category
  Registry.register({
    id = id, label = definition.label, order = definition.order,
    render = function(shell, content) renderCategory(shell, definition, content) end,
  })
end

nExBot.UI.Auxiliary = managers
nExBot.UI["ui.modules.auxiliary"] = managers
return managers
