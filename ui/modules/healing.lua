--[[
  Healing module page — health, mana, emergency, conditions, party.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Healing = {}

local SECTIONS = {
  "Health", "Mana", "Emergency", "Conditions", "Party", "Diagnostics",
}

function Healing.viewModel(state)
  state = state or {}
  local vm = VM.new("healing")
  local enabled = state.enabled == true

  vm:setState("READY")
  vm:setHeader({
    module = "healing",
    title = "Healing",
    status = enabled and "ACTIVE" or "DISABLED",
    statusText = enabled and "Enabled" or "Disabled",
  })

  local sections = {}

  sections[#sections + 1] = {
    id = "overview",
    title = "Overview",
    rows = {
      { key = "HP", value = state.hp and (state.hp .. "%") or "-" },
      { key = "Mana", value = state.mana and (state.mana .. "%") or "-" },
      { key = "Profile", value = state.profile or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "health",
    title = "Health Healing",
    rows = {
      { key = "Spells", value = tostring(state.spellCount or 0) },
      { key = "Potions", value = tostring(state.itemCount or 0) },
    },
  }

  sections[#sections + 1] = {
    id = "emergency",
    title = "Emergency",
    rows = {
      { key = "Critical HP", value = state.criticalHp or 20 },
      { key = "Danger critical", value = state.dangerCritical or 50 },
    },
  }

  sections[#sections + 1] = {
    id = "party",
    title = "Party / Friend Healing",
    rows = {
      { key = "Friend healing", value = state.friendHealing and "on" or "off", status = state.friendHealing and "ACTIVE" or "DISABLED" },
    },
  }

  sections[#sections + 1] = {
    id = "diagnostics",
    title = "Diagnostics",
    rows = { { key = "Errors", value = state.errorCount or 0, status = state.errorCount and state.errorCount > 0 and "WARNING" or "OK" } },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "toggle_healing", label = enabled and "Disable" or "Enable" },
    { id = "open_config", label = "Heal config" },
    { id = "open_conditions", label = "Conditions" },
  })

  if state.errorCount and state.errorCount > 0 then vm:addError("HEALING_ERRORS", state.errorCount .. " errors") end
  vm:commit()
  return vm
end

function Healing.statusProvider()
  return Healing.viewModel({
    enabled = HealBot and HealBot.isOn and HealBot.isOn() or false,
    hp = hppercent,
    mana = manapercent,
    profile = HealBot and HealBot.getActiveProfile and HealBot.getActiveProfile() or "-",
    spellCount = HealBotConfig and HealBotConfig.spellCount or 0,
    itemCount = HealBotConfig and HealBotConfig.itemCount or 0,
    criticalHp = HealContext and HealContext.hpCritical or 20,
    dangerCritical = HealContext and HealContext.dangerCritical or 50,
    friendHealing = BotCore and BotCore.FriendHealer and BotCore.FriendHealer.isEnabled and BotCore.FriendHealer.isEnabled() or false,
  })
end

function Healing.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Healing.statusProvider().snapshot)
end

function Healing.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "healing",
    label = "Healing",
    icon = "healing",
    order = 40,
    sections = SECTIONS,
    statusProvider = Healing.statusProvider,
    render = Healing.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Healing.register() end

return Healing
