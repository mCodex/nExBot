local CharacterProfileStateCoordinator = {}
CharacterProfileStateCoordinator.__index = CharacterProfileStateCoordinator

local EventBus = EventBus
local UnifiedStorage = nExBot.UnifiedStorage
local CharacterContext = nExBot.CharacterContext
local StateEnums = nExBot.StateEnums

local State = StateEnums.State
local Origin = StateEnums.Origin
local Inhibitor = StateEnums.Inhibitor

local MODULE_IDS = {
  "cavebot",
  "targetbot",
  "healbot",
  "attackbot",
  "containers",
}

local function nowMs()
  return nExBot.Shared and nExBot.Shared.nowMs and nExBot.Shared.nowMs() or (os.time() * 1000)
end

local function deepCopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local result = {}
  for k, v in pairs(tbl) do
    result[k] = deepCopy(v)
  end
  return result
end

function CharacterProfileStateCoordinator.new()
  local self = setmetatable({}, CharacterProfileStateCoordinator)
  self.state = State.UNBOUND
  self.context = CharacterContext.new()
  self.desiredState = {}
  self.effectiveState = {}
  self.inhibitors = {}
  self.moduleProfiles = {}
  self.revision = 0
  self.listeners = {}
  self.readyCallbacks = {}
  self.generationTimers = {}
  self.lastFlushMs = 0
  self.migrationVersion = 1
  self._initialized = false
  return self
end

function CharacterProfileStateCoordinator:getState()
  return self.state
end

function CharacterProfileStateCoordinator:getContext()
  return self.context
end

function CharacterProfileStateCoordinator:getSessionGeneration()
  return self.context.sessionGeneration
end

function CharacterProfileStateCoordinator:transition(newState)
  if self.state == newState then return end
  local oldState = self.state
  self.state = newState
  self:emit("stateChanged", { from = oldState, to = newState })
end

function CharacterProfileStateCoordinator:emit(event, data)
  if EventBus then
    EventBus.emit("profileCoordinator:" .. event, data)
  end
  for _, cb in ipairs(self.listeners[event] or {}) do
    pcall(cb, data)
  end
end

function CharacterProfileStateCoordinator:on(event, callback)
  self.listeners[event] = self.listeners[event] or {}
  table.insert(self.listeners[event], callback)
  return function()
    for i, cb in ipairs(self.listeners[event] or {}) do
      if cb == callback then
        table.remove(self.listeners[event], i)
        break
      end
    end
  end
end

function CharacterProfileStateCoordinator:onReady(callback)
  if self.state == State.READY then
    pcall(callback)
  else
    table.insert(self.readyCallbacks, callback)
  end
end

function CharacterProfileStateCoordinator:_fireReady()
  for _, cb in ipairs(self.readyCallbacks) do
    pcall(cb)
  end
  self.readyCallbacks = {}
end

function CharacterProfileStateCoordinator:initialize()
  if self._initialized then return end
  self._initialized = true

  local ClientLifecycle = nExBot.ClientLifecycle
  if ClientLifecycle then
    ClientLifecycle:on("gameStart", function()
      self:onGameStart()
    end)
    ClientLifecycle:on("gameEnd", function()
      self:onGameEnd()
    end)
  end
end

function CharacterProfileStateCoordinator:onGameStart()
  local gen = self.context.sessionGeneration + 1
  self.context.sessionGeneration = gen
  self:cancelGenerationTimers(gen)

  local captured = self.context:capture()
  if not captured:isValid() then
    self:transition(State.WAITING_FOR_CHARACTER)
    schedule(500, function()
      if self:getSessionGeneration() == gen then
        self:onGameStart()
      end
    end)
    return
  end

  self:transition(State.BINDING)
  self:bindStorage()

  self:transition(State.LOADING)
  self:loadSnapshot()

  self:transition(State.MIGRATING)
  self:migrateIfNeeded()

  self:transition(State.APPLYING_SILENTLY)
  self:applySilently()

  self:transition(State.READY)
  self:reconcileEffective()
  self:_fireReady()
  self:emit("ready", { context = self.context:toTable(), revision = self.revision })
end

function CharacterProfileStateCoordinator:onGameEnd()
  local gen = self.context.sessionGeneration
  self:cancelGenerationTimers(gen)

  self:setInhibitorAll(Inhibitor.DISCONNECTED, true)
  self:reconcileEffective()

  self:transition(State.FLUSHING)
  self:flush(gen)

  self:transition(State.UNBOUND)
  self:unbindStorage()
end

function CharacterProfileStateCoordinator:bindStorage()
  if UnifiedStorage and UnifiedStorage.bind then
    UnifiedStorage:bind(self.context)
  end
end

function CharacterProfileStateCoordinator:unbindStorage()
  if UnifiedStorage and UnifiedStorage.unbind then
    UnifiedStorage:unbind(self.context)
  end
end

function CharacterProfileStateCoordinator:loadSnapshot()
  if not UnifiedStorage or not UnifiedStorage.load then return end

  local data = UnifiedStorage:load(self.context)
  if not data then
    data = self:migrateLegacy()
  end

  if data then
    self.desiredState = data.modules or {}
    self.moduleProfiles = {}
    for moduleId, moduleData in pairs(self.desiredState) do
      self.moduleProfiles[moduleId] = moduleData.selectedConfig or ""
    end
    self.revision = data.revision or 0
  else
    self.desiredState = {}
    for _, id in ipairs(MODULE_IDS) do
      self.desiredState[id] = {
        selectedConfig = "",
        desiredEnabled = false,
        explicitlyDisabledByUser = false,
      }
    end
    self.revision = 0
  end
end

function CharacterProfileStateCoordinator:migrateLegacy()
  return nil
end

function CharacterProfileStateCoordinator:migrateIfNeeded()
end

function CharacterProfileStateCoordinator:applySilently()
  for _, moduleId in ipairs(MODULE_IDS) do
    local desired = self.desiredState[moduleId] or {}
    local profile = self.moduleProfiles[moduleId]
    self:applyModuleState(moduleId, desired, profile, Origin.INITIAL_RESTORE)
  end
end

function CharacterProfileStateCoordinator:applyModuleState(moduleId, desired, profile, origin)
  self:emit("moduleStateApplied", {
    moduleId = moduleId,
    desired = desired,
    profile = profile,
    origin = origin,
  })
end

function CharacterProfileStateCoordinator:reconcileEffective()
  for _, moduleId in ipairs(MODULE_IDS) do
    local desired = self.desiredState[moduleId] or {}
    local hasInhibitor = false
    for _, v in pairs(self.inhibitors[moduleId] or {}) do
      if v then hasInhibitor = true; break end
    end
    local ready = self:isModuleReady(moduleId)
    local effective = desired.desiredEnabled and ready and not hasInhibitor

    self.effectiveState[moduleId] = {
      desiredEnabled = desired.desiredEnabled,
      effectiveEnabled = effective,
      inhibitors = deepCopy(self.inhibitors[moduleId] or {}),
    }

    self:emit("effectiveStateChanged", {
      moduleId = moduleId,
      effective = self.effectiveState[moduleId],
    })
  end
end

function CharacterProfileStateCoordinator:isModuleReady(moduleId)
  if moduleId == "cavebot" then
    return CaveBot and CaveBot.isOn and CaveBot.isOn() ~= nil
  elseif moduleId == "targetbot" then
    return TargetBot and TargetBot.isOn and TargetBot.isOn() ~= nil
  elseif moduleId == "healbot" then
    return HealBot and HealBot.isOn and HealBot.isOn() ~= nil
  elseif moduleId == "attackbot" then
    return AttackBot and AttackBot.isOn and AttackBot.isOn() ~= nil
  elseif moduleId == "containers" then
    return Containers and Containers.isEnabled and Containers.isEnabled() ~= nil
  end
  return true
end

function CharacterProfileStateCoordinator:setDesiredEnabled(moduleId, enabled, options)
  options = options or {}
  local origin = options.origin or Origin.USER
  local desired = self.desiredState[moduleId] or {}

  if origin == Origin.USER then
    desired.desiredEnabled = enabled
    if enabled then
      desired.explicitlyDisabledByUser = false
    else
      desired.explicitlyDisabledByUser = true
    end
    desired.updatedAtMs = nowMs()
    desired.revision = (desired.revision or 0) + 1
  end

  self.desiredState[moduleId] = desired
  self.revision = self.revision + 1
  self:reconcileEffective()
  self:scheduleFlush()
end

function CharacterProfileStateCoordinator:selectModuleProfile(moduleId, profileName, options)
  options = options or {}
  local origin = options.origin or Origin.USER
  local preserveDesired = options.preserveDesiredState ~= false

  local desired = self.desiredState[moduleId] or {}
  local oldProfile = self.moduleProfiles[moduleId]

  if oldProfile == profileName then return end

  self:setInhibitor(moduleId, Inhibitor.PROFILE_APPLY, true)

  self.moduleProfiles[moduleId] = profileName
  desired.selectedConfig = profileName
  desired.updatedAtMs = nowMs()
  desired.revision = (desired.revision or 0) + 1

  if not preserveDesired then
    desired.desiredEnabled = false
    desired.explicitlyDisabledByUser = false
  end

  self.desiredState[moduleId] = desired
  self.revision = self.revision + 1

  self:applyModuleState(moduleId, desired, profileName, Origin.MODULE_PROFILE_SWITCH)
  self:flush()

  self:setInhibitor(moduleId, Inhibitor.PROFILE_APPLY, false)
  self:reconcileEffective()

  self:emit("profileChanged", {
    moduleId = moduleId,
    oldProfile = oldProfile,
    newProfile = profileName,
    origin = origin,
  })
end

function CharacterProfileStateCoordinator:setInhibitor(moduleId, inhibitor, active)
  self.inhibitors[moduleId] = self.inhibitors[moduleId] or {}
  if active then
    self.inhibitors[moduleId][inhibitor] = active
  else
    self.inhibitors[moduleId][inhibitor] = nil
  end
  self:reconcileEffective()
end

function CharacterProfileStateCoordinator:setInhibitorAll(inhibitor, active)
  for _, moduleId in ipairs(MODULE_IDS) do
    self:setInhibitor(moduleId, inhibitor, active)
  end
end

function CharacterProfileStateCoordinator:getDesiredEnabled(moduleId)
  return (self.desiredState[moduleId] or {}).desiredEnabled or false
end

function CharacterProfileStateCoordinator:getEffectiveEnabled(moduleId)
  return (self.effectiveState[moduleId] or {}).effectiveEnabled or false
end

function CharacterProfileStateCoordinator:getInhibitors(moduleId)
  return deepCopy(self.inhibitors[moduleId] or {})
end

function CharacterProfileStateCoordinator:getSelectedProfile(moduleId)
  return self.moduleProfiles[moduleId] or ""
end

function CharacterProfileStateCoordinator:flush(gen)
  gen = gen or self:getSessionGeneration()
  if UnifiedStorage and UnifiedStorage.flush then
    local ok = UnifiedStorage:flush(self.context)
    if ok then
      self.lastFlushMs = nowMs()
    end
    return ok
  end
  return false
end

function CharacterProfileStateCoordinator:scheduleFlush()
  local now = nowMs()
  if now - self.lastFlushMs < 5000 then return end
  self:flush()
end

function CharacterProfileStateCoordinator:cancelGenerationTimers(gen)
  for g, timers in pairs(self.generationTimers) do
    if g ~= gen then
      for _, timer in ipairs(timers) do
        pcall(removeEvent, timer)
      end
    end
  end
  self.generationTimers[gen] = nil
end

function CharacterProfileStateCoordinator:scheduleWithGeneration(gen, delay, fn)
  local timer = schedule(delay, function()
    if self:getSessionGeneration() == gen then
      pcall(fn)
    end
  end)
  self.generationTimers[gen] = self.generationTimers[gen] or {}
  table.insert(self.generationTimers[gen], timer)
  return timer
end

nExBot = nExBot or {}
nExBot.CharacterProfileStateCoordinator = CharacterProfileStateCoordinator.new()
nExBot.CharacterProfileStateCoordinator:initialize()

return CharacterProfileStateCoordinator