--[[
  Profiles module page — character profiles, module state binding, presets.
]]

local VM = (nExBot and nExBot.UI and nExBot.UI["ui.core.view_model"]) or (type(require) == "function" and require("ui.core.view_model"))
local Page = (nExBot and nExBot.UI and nExBot.UI["ui.modules.page"]) or (type(require) == "function" and require("ui.modules.page"))
local Components = (nExBot and nExBot.UI and nExBot.UI["ui.components.components"]) or (type(require) == "function" and require("ui.components.components"))

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
    cavebotProfile = CaveBot and CaveBot.getCurrentProfile and CaveBot.getCurrentProfile() or "-",
    targetbotProfile = TargetBot and TargetBot.getCurrentProfile and TargetBot.getCurrentProfile() or "-",
    healbotProfile = HealBot and HealBot.getActiveProfile and HealBot.getActiveProfile() or "-",
    suppliesProfile = Supplies and Supplies.getCurrentProfile and Supplies.getCurrentProfile() or "-",
    backupCount = UnifiedStorage and UnifiedStorage.getStats and UnifiedStorage.getStats().backupCount or 0,
  })
end

function Profiles.render(shell, content, lifecycle)
  Page.render(shell, content, lifecycle, Profiles.statusProvider().snapshot)
  Components.sectionHeader(content, { title = "Hunt profiles" })

  local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]
  local optionName = (Shared and Shared.optionName) or function(first, second)
    if type(second) == "string" then return second end
    if type(second) == "table" then return second.text or second.value end
    if type(first) == "string" then return first end
    if type(first) == "table" then return first.text or first.value end
  end

  Components.selectRow(content, {
    id = "caveProfile", label = "Cave",
    options = CaveBot and CaveBot.listProfiles and CaveBot.listProfiles() or {},
    value = CaveBot and CaveBot.getCurrentProfile and CaveBot.getCurrentProfile(),
    onChange = function(first, second)
      local name = optionName(first, second)
      if name and CaveBot and CaveBot.setCurrentProfile then CaveBot.setCurrentProfile(name) end
    end,
  })
  Components.selectRow(content, {
    id = "targetProfile", label = "Target",
    options = TargetBot and TargetBot.listProfiles and TargetBot.listProfiles() or {},
    value = TargetBot and TargetBot.getCurrentProfile and TargetBot.getCurrentProfile(),
    onChange = function(first, second)
      local name = optionName(first, second)
      if name and TargetBot and TargetBot.setCurrentProfile then TargetBot.setCurrentProfile(name) end
    end,
  })
end

function Profiles.register()
  local Registry = nExBot.UI.ModuleRegistry
  return Registry.register({
    id = "profiles",
    label = "Profiles",
    order = 90,
    sections = SECTIONS,
    statusProvider = Profiles.statusProvider,
    render = Profiles.render,
  })
end

local reg = nExBot.UI.ModuleRegistry
if reg and reg.register then Profiles.register() end

return Profiles
