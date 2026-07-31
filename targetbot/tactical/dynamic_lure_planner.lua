DynamicLurePlanner = {}
DynamicLurePlanner.__index = DynamicLurePlanner

local STATES = {
  INACTIVE = "INACTIVE",
  PLANNING = "PLANNING",
  GATHERING = "GATHERING",
  MOVING_TO_ANCHOR = "MOVING_TO_ANCHOR",
  WAITING_FOR_PARTICIPANTS = "WAITING_FOR_PARTICIPANTS",
  ATTACKING_WHILE_GATHERING = "ATTACKING_WHILE_GATHERING",
  REPLANNING = "REPLANNING",
  COMPLETED = "COMPLETED",
  ABORTED = "ABORTED",
}

DynamicLurePlanner.STATES = STATES

function DynamicLurePlanner.new(options)
  options = options or {}
  return setmetatable({
    state = STATES.INACTIVE,
    minCount = options.minCount or 3,
    maxCount = options.maxCount or 6,
    ttl = options.ttl or 250,
    enterDwellMs = options.enterDwellMs or 500,
    exitDwellMs = options.exitDwellMs or 1000,
    participants = {},
    participantCount = 0,
    enterStart = nil,
    exitStart = nil,
    completionStart = nil,
    dropStart = nil,
  }, DynamicLurePlanner)
end

function DynamicLurePlanner:getState()
  return self.state
end

function DynamicLurePlanner:getParticipants()
  local ids = {}
  for id in pairs(self.participants) do
    ids[#ids + 1] = id
  end
  return ids
end

function DynamicLurePlanner:reset()
  self.state = STATES.INACTIVE
  self.participants = {}
  self.participantCount = 0
  self.enterStart = nil
  self.exitStart = nil
  self.completionStart = nil
  self.dropStart = nil
end

local function buildProposal(self, observation, now, generation)
  local creatures = observation.creatures or {}
  local minCount = observation.minCount or self.minCount
  return {
    domain = "movement",
    action = "lure",
    source = "DynamicLure",
    priority = 60,
    safety = 1,
    confidence = math.min(1, 0.5 + (minCount - #creatures) / minCount * 0.3),
    createdAt = now,
    expiresAt = now + self.ttl,
    snapshotGeneration = generation,
    evidence = { count = #creatures, participants = creatures },
  }
end

function DynamicLurePlanner:update(observation, context)
  observation = observation or {}
  context = context or {}

  local now = context.now or 0
  local generation = observation.snapshotGeneration or 0
  local creatures = observation.creatures or {}
  local minCount = observation.minCount or self.minCount
  local maxCount = observation.maxCount or self.maxCount
  local safe = observation.safe
  local hasCommitment = observation.hasCommitment
  local targetHp = observation.targetHp

  local count = #creatures

  self.participants = {}
  for _, id in ipairs(creatures) do
    self.participants[id] = true
  end
  self.participantCount = count

  if self.state == STATES.INACTIVE then
    if count == 0 then
      return nil
    end
    if count >= minCount then
      if not self.enterStart then
        self.enterStart = now
      end
      if now - self.enterStart >= self.enterDwellMs then
        self.state = STATES.PLANNING
        self.enterStart = nil
      else
        return nil
      end
    else
      self.enterStart = nil
      self.state = STATES.GATHERING
      self.completionStart = nil
      self.dropStart = nil
      return buildProposal(self, observation, now, generation)
    end
  end

  if self.state == STATES.PLANNING then
    if safe == false then
      self.state = STATES.ABORTED
      return nil, "LURE_ABORTED_UNSAFE"
    end
    if hasCommitment and targetHp and targetHp < 30 then
      return nil, "LURE_DEFERRED_FINISH_TARGET"
    end
    if count < minCount then
      self.state = STATES.GATHERING
      self.completionStart = nil
      self.dropStart = nil
    elseif count >= maxCount then
      self.state = STATES.COMPLETED
      self.completionStart = now
    end
  end

  if self.state == STATES.GATHERING then
    if safe == false then
      self.state = STATES.ABORTED
      return nil, "LURE_ABORTED_UNSAFE"
    end
    if count >= maxCount then
      if not self.completionStart then
        self.completionStart = now
      end
      if now - self.completionStart >= self.exitDwellMs then
        self.state = STATES.COMPLETED
        self.dropStart = nil
        return nil
      end
    else
      self.completionStart = nil
    end
    if count < minCount then
      if not self.dropStart then
        self.dropStart = now
      end
      if now - self.dropStart >= self.enterDwellMs then
        self.state = STATES.REPLANNING
        self.completionStart = nil
        return nil
      end
    else
      self.dropStart = nil
    end
    return buildProposal(self, observation, now, generation)
  end

  if self.state == STATES.REPLANNING then
    if count >= minCount then
      self.state = STATES.GATHERING
      self.dropStart = nil
      self.completionStart = nil
      return buildProposal(self, observation, now, generation)
    end
    if count == 0 then
      self.state = STATES.INACTIVE
      self.dropStart = nil
      return nil
    end
    return nil
  end

  if self.state == STATES.COMPLETED then
    if count < maxCount then
      self.state = STATES.GATHERING
      self.completionStart = nil
      self.dropStart = nil
      return buildProposal(self, observation, now, generation)
    end
    return nil
  end

  if self.state == STATES.ABORTED then
    if safe ~= false and count > 0 then
      self.state = STATES.INACTIVE
      self.enterStart = nil
    end
    return nil
  end

  return nil
end

return DynamicLurePlanner
