TargetProposal = {}

function TargetProposal.fromSelection(selection, context)
  if type(selection) ~= "table" or not selection.creature or not selection.config then
    return nil, "invalid_selection"
  end

  local ok, targetId = pcall(selection.creature.getId, selection.creature)
  if not ok or type(targetId) ~= "number" then return nil, "invalid_target" end

  local priority = tonumber(selection.priority)
  if not priority or priority <= 0 then return nil, "invalid_priority" end

  context = context or {}
  local createdAt = context.now or 0
  local generations = context.generations or {}
  return {
    domain = "combat",
    action = "attack",
    source = "TargetBot",
    targetId = targetId,
    configuredPriority = tonumber(selection.config.priority) or 0,
    basePriority = priority,
    priority = priority,
    confidence = 1,
    createdAt = createdAt,
    expiresAt = createdAt + (context.ttl or 250),
    snapshotGeneration = generations.snapshot or 0,
    combatGeneration = generations.combat or 0,
    selection = selection,
  }
end

return TargetProposal
