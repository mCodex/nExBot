--[[
  Profiles module page — character profiles, module state binding, presets.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))

local Profiles = {}

local SECTIONS = {
  "Character Profiles", "CaveBot Profiles", "TargetBot Profiles",
  "Module State", "Import / Export", "Backups",
}

function Profiles.viewModel(state)
  state = state or {}
  local vm = VM.new("profiles")

  vm:setState("READY")
  vm:setHeader({ module = "profiles", title = "Profiles", status = "INFO", statusText = state.character or "-" })

  local sections = {}

  sections[#sections + 1] = {
    id = "character",
    title = "Character Profiles",
    rows = {
      { key = "Character", value = state.character or "-" },
      { key = "Active profile", value = state.profile or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "module_state",
    title = "Module State Binding",
    rows = {
      { key = "CaveBot profile", value = state.cavebotProfile or "-" },
      { key = "TargetBot profile", value = state.targetbotProfile or "-" },
      { key = "Healing profile", value = state.healbotProfile or "-" },
      { key = "Supplies profile", value = state.suppliesProfile or "-" },
    },
  }

  sections[#sections + 1] = {
    id = "backups",
    title = "Backups",
    rows = { { key = "Available", value = tostring(state.backupCount or 0) } },
  }

  vm:setSections(sections)
  vm:setActions({
    { id = "save_profile", label = "Save profile" },
    { id = "import", label = "Import" },
    { id = "export", label = "Export" },
  })
  vm:commit()
  return vm
end

function Profiles.statusProvider()
  local storage = storage
  local get = function(k) return storage and storage[k] end
  return Profiles.viewModel({
    character = player and player.getName and player.getName() or "-",
    profile = get("profileName") or get("profile") or "-",
    cavebotProfile = get("cavebot") and get("cavebot").selectedConfig or "-",
    targetbotProfile = get("targetbot") and get("targetbot").selectedConfig or "-",
    healbotProfile = HealBot and HealBot.getActiveProfile and HealBot.getActiveProfile() or "-",
    suppliesProfile = Supplies and Supplies.getCurrentProfile and Supplies.getCurrentProfile() or "-",
    backupCount = UnifiedStorage and UnifiedStorage.getStats and UnifiedStorage.getStats().backupCount or 0,
  })
end

function Profiles.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Profiles.statusProvider().snapshot)
end

function Profiles.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "profiles",
    label = "Profiles",
    icon = "profiles",
    order = 90,
    sections = SECTIONS,
    statusProvider = Profiles.statusProvider,
    render = Profiles.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Profiles.register() end

return Profiles
