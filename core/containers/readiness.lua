local Readiness = {}

function Readiness.compute(registry, generation, isPaladin)
  local queued = registry:countByState("queued")
  local opening = registry:countByState("opening")
  local opened = registry:countByState("opened")
  local inspected = registry:countByState("inspected")
  local failed = registry:countByState("failed")

  local status
  if failed > 0 and queued == 0 and opening == 0 then
    status = "degraded"
  elseif inspected > 0 and queued == 0 and opening == 0 then
    status = "ready"
  elseif queued > 0 or opening > 0 then
    status = "discovering"
  else
    status = "notStarted"
  end

  return {
    generation = generation,
    status = status,
    mainBackpackReady = inspected > 0,
    quiverRequired = isPaladin,
    quiverReady = false,
    queuedCount = queued,
    openingCount = opening,
    openedCount = opened,
    inspectedCount = inspected,
    failedCount = failed,
    completedAt = (status == "ready" or status == "degraded") and os.time() or nil,
  }
end

return Readiness
