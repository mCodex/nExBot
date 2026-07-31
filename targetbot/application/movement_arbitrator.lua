local MovementArbitrator = {}

function MovementArbitrator.new(options)
  options = options or {}
  local self = {
    featureArbitrator = options.featureArbitrator,
    movementCoordinator = options.movementCoordinator,
    lastDecision = nil,
  }
  setmetatable(self, { __index = MovementArbitrator })
  return self
end

function MovementArbitrator:tick(intents, context)
  if not intents or #intents == 0 then
    self.lastDecision = { success = false, reason = "no_intents" }
    return false, "no_intents"
  end

  if not self.featureArbitrator then
    self.lastDecision = { success = false, reason = "no_arbitrator" }
    return false, "no_arbitrator"
  end

  local result = self.featureArbitrator:resolve(intents, context)

  if not result.selected then
    self.lastDecision = { success = false, reason = "no_selected_intent", rejected = result.rejected }
    return false, "no_selected_intent"
  end

  local selected = result.selected

  if not selected.position or not selected.position.x or not selected.position.y then
    self.lastDecision = { success = false, reason = "no_position", intent = selected }
    return false, "no_position"
  end

  self.lastDecision = {
    success = true,
    reason = "executed",
    intent = selected,
    rejected = result.rejected,
  }

  if self.movementCoordinator then
    local ok = self.movementCoordinator(selected)
    if not ok then
      self.lastDecision.success = false
      self.lastDecision.reason = "execution_failed"
      return false, "execution_failed"
    end
  end

  return true, "executed"
end

function MovementArbitrator:getLastDecision()
  return self.lastDecision
end

function MovementArbitrator:reset()
  self.lastDecision = nil
end

return MovementArbitrator
