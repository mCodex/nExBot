local Components = nExBot.UI["ui.components.components"]
local Actions = nExBot.UI["ui.core.actions"]
local Registry = nExBot.UI.ModuleRegistry

local categories = {
  tools = {
    label = "Tools", order = 80,
    actions = {
      { "Supplies", nil, "supplies" }, { "Containers", nil, "looting" },
      { "Dropper", "toggle_dropper" }, { "Depot withdraw", "toggle_depot_withdraw" },
      { "Depositer", "open_depositer" },
    },
  },
  safety = {
    label = "Safety", order = 90,
    actions = {
      { "Heal", nil, "healing" }, { "Alarms", "open_alarms" },
      { "Conditions", "show_conditions" }, { "Anti-RS", "toggle_antirs" },
      { "Push Max", "open_pushmax" }, { "Combo", "open_combo" },
    },
  },
  equipment = {
    label = "Equipment", order = 100,
    actions = {
      { "Attack rotation", "open_attack_config" }, { "Equipment rules", "open_equipper" },
      { "Supplies", nil, "supplies" },
    },
  },
  analytics = {
    label = "Analytics", order = 110,
    actions = {
      { "Hunt analyzer", "open_analyzer" }, { "AI Intelligence", nil, "intelligence" },
      { "Diagnostics", nil, "diagnostics" },
    },
  },
  utilities = {
    label = "Utilities", order = 120,
    actions = {
      { "Hold target", "toggle_hold_target" }, { "Floor spy", "toggle_spy_level" },
      { "Extras", "open_extras" }, { "Scripts", "open_script_editor" },
      { "Profiles", nil, "profiles" }, { "Settings", nil, "settings" },
    },
  },
}

for id, category in pairs(categories) do
  local categoryId, definition = id, category
  Registry.register({
    id = categoryId, label = definition.label, order = definition.order,
    render = function(shell, content)
      for _, item in ipairs(definition.actions) do
        local label, actionId, pageId = item[1], item[2], item[3]
        Components.button(content, {
          text = label, id = categoryId .. "_" .. (actionId or pageId), variant = "ghost",
          onClick = function()
            if pageId then shell:select(pageId) else Actions.run(actionId) end
          end,
        })
      end
    end,
  })
end

nExBot.UI.Auxiliary = categories
nExBot.UI["ui.modules.auxiliary"] = categories
return categories
