local ControlStateRegistry = {}
ControlStateRegistry.__index = ControlStateRegistry

local Scope = {
  GLOBAL = "GLOBAL",
  CLIENT_PROFILE = "CLIENT_PROFILE",
  CHARACTER = "CHARACTER",
  CHARACTER_ROOT_PROFILE = "CHARACTER_ROOT_PROFILE",
  CHARACTER_MODULE_PROFILE = "CHARACTER_MODULE_PROFILE",
  SESSION_ONLY = "SESSION_ONLY",
}

local controls = {}
local initialized = false

function ControlStateRegistry.register(def)
  if not def or not def.id then
    error("ControlStateRegistry: missing required 'id' field")
  end
  
  if controls[def.id] then
    error("ControlStateRegistry: duplicate control ID: " .. def.id)
  end
  
  local scope = def.scope or Scope.CHARACTER_ROOT_PROFILE
  local validScopes = { 
    [Scope.GLOBAL] = true,
    [Scope.CLIENT_PROFILE] = true,
    [Scope.CHARACTER] = true,
    [Scope.CHARACTER_ROOT_PROFILE] = true,
    [Scope.CHARACTER_MODULE_PROFILE] = true,
    [Scope.SESSION_ONLY] = true,
  }
  
  if not validScopes[scope] then
    error("ControlStateRegistry: invalid scope for " .. def.id .. ": " .. tostring(scope))
  end
  
  local control = {
    id = def.id,
    scope = scope,
    defaultValue = def.defaultValue,
    valueType = def.valueType or "boolean",
    apply = def.apply,
    readEffective = def.readEffective,
    validate = def.validate,
    getStorageKey = def.getStorageKey or function(context)
      return def.id
    end,
    persist = scope ~= Scope.SESSION_ONLY,
  }
  
  controls[def.id] = control
  return control
end

function ControlStateRegistry.get(id)
  return controls[id]
end

function ControlStateRegistry.getAll()
  return controls
end

function ControlStateRegistry.getByScope(scope)
  local result = {}
  for _, control in pairs(controls) do
    if control.scope == scope then
      table.insert(result, control)
    end
  end
  return result
end

function ControlStateRegistry.validateAll()
  for id, control in pairs(controls) do
    if control.validate then
      local default = control.defaultValue
      if not control.validate(default) then
        warn("[ControlStateRegistry] Default value invalid for " .. id)
      end
    end
  end
end

function ControlStateRegistry.getScope()
  return Scope
end

-- Register core bot controls
local function registerCoreControls()
  if initialized then return end
  initialized = true
  
  -- CaveBot controls
  ControlStateRegistry.register({
    id = "cavebot.enabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      if CaveBot and CaveBot.setDesiredEnabled then
        CaveBot.setDesiredEnabled(value, {origin = nExBot.Origin.USER})
      end
    end,
    readEffective = function(context)
      if CaveBot and CaveBot.getEffectiveEnabled then
        return CaveBot.getEffectiveEnabled()
      end
      return false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  ControlStateRegistry.register({
    id = "cavebot.selectedProfile",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = "",
    valueType = "string",
    apply = function(value, context)
      if CaveBot and CaveBot.setCurrentProfile then
        CaveBot.setCurrentProfile(value)
      end
    end,
    readEffective = function(context)
      if CaveBot and CaveBot.getCurrentProfile then
        return CaveBot.getCurrentProfile()
      end
      return ""
    end,
    validate = function(value) return type(value) == "string" end,
  })
  
  -- TargetBot controls
  ControlStateRegistry.register({
    id = "targetbot.enabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      if TargetBot and TargetBot.setDesiredEnabled then
        TargetBot.setDesiredEnabled(value, {origin = nExBot.Origin.USER})
      end
    end,
    readEffective = function(context)
      if TargetBot and TargetBot.getEffectiveEnabled then
        return TargetBot.getEffectiveEnabled()
      end
      return false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  ControlStateRegistry.register({
    id = "targetbot.selectedProfile",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = "",
    valueType = "string",
    apply = function(value, context)
      if TargetBot and TargetBot.setCurrentProfile then
        TargetBot.setCurrentProfile(value)
      end
    end,
    readEffective = function(context)
      if TargetBot and TargetBot.getCurrentProfile then
        return TargetBot.getCurrentProfile()
      end
      return ""
    end,
    validate = function(value) return type(value) == "string" end,
  })
  
  ControlStateRegistry.register({
    id = "targetbot.explicitlyDisabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      -- Managed by coordinator
    end,
    readEffective = function(context)
      return TargetBot and TargetBot.explicitlyDisabled or false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  -- HealBot
  ControlStateRegistry.register({
    id = "healbot.enabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      if HealBot and HealBot.setDesiredEnabled then
        HealBot.setDesiredEnabled(value, {origin = nExBot.Origin.USER})
      end
    end,
    readEffective = function(context)
      if HealBot and HealBot.getEffectiveEnabled then
        return HealBot.getEffectiveEnabled()
      end
      return HealBot and HealBot.isOn and HealBot.isOn() or false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  -- AttackBot
  ControlStateRegistry.register({
    id = "attackbot.enabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      if AttackBot and AttackBot.setDesiredEnabled then
        AttackBot.setDesiredEnabled(value, {origin = nExBot.Origin.USER})
      end
    end,
    readEffective = function(context)
      if AttackBot and AttackBot.getEffectiveEnabled then
        return AttackBot.getEffectiveEnabled()
      end
      return AttackBot and AttackBot.isOn and AttackBot.isOn() or false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  -- Containers
  ControlStateRegistry.register({
    id = "containers.enabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = true,
    valueType = "boolean",
    apply = function(value, context)
      if Containers and Containers.setDesiredEnabled then
        Containers.setDesiredEnabled(value, {origin = nExBot.Origin.USER})
      end
    end,
    readEffective = function(context)
      if Containers and Containers.getEffectiveEnabled then
        return Containers.getEffectiveEnabled()
      end
      return Containers and Containers.isEnabled and Containers.isEnabled() or false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  -- Tactical Intelligence UI
  ControlStateRegistry.register({
    id = "tactical.uiVisible",
    scope = Scope.CLIENT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      -- UI visibility handled by presenter
    end,
    readEffective = function(context)
      return false -- session-only
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  -- Follow Player
  ControlStateRegistry.register({
    id = "followPlayer.enabled",
    scope = Scope.CHARACTER_ROOT_PROFILE,
    defaultValue = false,
    valueType = "boolean",
    apply = function(value, context)
      if FollowPlayer and FollowPlayer.setDesiredEnabled then
        FollowPlayer.setDesiredEnabled(value, {origin = nExBot.Origin.USER})
      end
    end,
    readEffective = function(context)
      if FollowPlayer and FollowPlayer.isOn then
        return FollowPlayer.isOn()
      end
      return false
    end,
    validate = function(value) return type(value) == "boolean" end,
  })
  
  -- Extras
  local extraToggles = {
    "extras.antiRs",
    "extras.pushMax",
    "extras.equipSwap",
    "extras.comboSystem",
    "extras.alarmHp",
    "extras.alarmMana",
    "extras.alarmCap",
  }
  
  for _, id in ipairs(extraToggles) do
    ControlStateRegistry.register({
      id = id,
      scope = Scope.CHARACTER_ROOT_PROFILE,
      defaultValue = false,
      valueType = "boolean",
      apply = function(value, context) end,
      readEffective = function(context) return false end,
      validate = function(value) return type(value) == "boolean" end,
    })
  end
  
  ControlStateRegistry.validateAll()
end

registerCoreControls()

nExBot = nExBot or {}
nExBot.ControlStateRegistry = ControlStateRegistry
nExBot.ControlScope = Scope

return ControlStateRegistry