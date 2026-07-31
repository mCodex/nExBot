local FeatureArbitrator = {}

local COMPATIBLE = "COMPATIBLE"
local MERGEABLE = "MERGEABLE"
local MUTUALLY_EXCLUSIVE = "MUTUALLY_EXCLUSIVE"
local PREEMPTABLE = "PREEMPTABLE"
local HARD_OVERRIDE = "HARD_OVERRIDE"

FeatureArbitrator.COMPATIBILITY = {
  COMPATIBLE = COMPATIBLE,
  MERGEABLE = MERGEABLE,
  MUTUALLY_EXCLUSIVE = MUTUALLY_EXCLUSIVE,
  PREEMPTABLE = PREEMPTABLE,
  HARD_OVERRIDE = HARD_OVERRIDE,
}

FeatureArbitrator.PRECEDENCE = {
  HARD_SAFETY = 100,
  MANUAL_OVERRIDE = 95,
  FINISH_KILL_COMMITMENT = 90,
  ATTACK_CONTINUITY = 85,
  WAVE_AVOIDANCE = 80,
  REPOSITION = 70,
  PULL = 65,
  DYNAMIC_LURE = 60,
  LURE = 55,
  KEEP_DISTANCE = 50,
  CHASE = 45,
  ROUTE_ADVANCEMENT = 30,
  ML_TIE_BREAKER = 10,
}

local PRECEDENCE = FeatureArbitrator.PRECEDENCE

local COMPATIBILITY_MATRIX = {
  FINISH_KILL_COMMITMENT = {
    LURE = HARD_OVERRIDE,
    DYNAMIC_LURE = HARD_OVERRIDE,
    PULL = HARD_OVERRIDE,
    ROUTE_ADVANCEMENT = HARD_OVERRIDE,
  },
  WAVE_AVOIDANCE = {
    LURE = PREEMPTABLE,
    DYNAMIC_LURE = PREEMPTABLE,
    PULL = PREEMPTABLE,
    REPOSITION = PREEMPTABLE,
    CHASE = PREEMPTABLE,
    KEEP_DISTANCE = PREEMPTABLE,
    ROUTE_ADVANCEMENT = PREEMPTABLE,
  },
  LURE = {
    DYNAMIC_LURE = MUTUALLY_EXCLUSIVE,
  },
  CHASE = {
    KEEP_DISTANCE = MUTUALLY_EXCLUSIVE,
  },
}

local function getCompatibility(sourceA, sourceB)
  local a = COMPATIBILITY_MATRIX[sourceA]
  if a and a[sourceB] then return a[sourceB] end
  local b = COMPATIBILITY_MATRIX[sourceB]
  if b and b[sourceA] then return b[sourceA] end
  return COMPATIBLE
end

local function getPrecedence(intent)
  if intent.precedence then return intent.precedence end
  return PRECEDENCE[intent.source] or 0
end

local function score(intent)
  return getPrecedence(intent) + (intent.confidence or 0.5)
end

local COMMITMENT_BLOCKED_SOURCES = {
  lure = true,
  pull = true,
  route = true,
  ROUTE_ADVANCEMENT = true,
  LURE = true,
  PULL = true,
  DYNAMIC_LURE = true,
}

function FeatureArbitrator.new()
  local self = {}
  setmetatable(self, { __index = FeatureArbitrator })
  return self
end

function FeatureArbitrator:resolve(intents, context)
  context = context or {}
  local rejected = {}

  if not intents or #intents == 0 then
    return { selected = nil, rejected = rejected }
  end

  if context.isManualOverride then
    local manual = nil
    for i = 1, #intents do
      if intents[i].source == "MANUAL_OVERRIDE" or intents[i].source == "manual" then
        manual = intents[i]
      else
        rejected[#rejected + 1] = { intent = intents[i], reason = "manual_override" }
      end
    end
    if manual then
      return { selected = manual, rejected = rejected }
    end
  end

  local active = {}
  for i = 1, #intents do
    active[#active + 1] = intents[i]
  end

  if context.playerHpPercent and context.playerHpPercent < 15 then
    local filtered = {}
    for i = 1, #active do
      local p = getPrecedence(active[i])
      if p >= PRECEDENCE.HARD_SAFETY or active[i].source == "HARD_SAFETY" or active[i].source == "WAVE_AVOIDANCE" then
        filtered[#filtered + 1] = active[i]
      else
        rejected[#rejected + 1] = { intent = active[i], reason = "safety_filter" }
      end
    end
    active = filtered
  end

  if context.hasCommitment and context.commitmentTargetId then
    local filtered = {}
    for i = 1, #active do
      local intent = active[i]
      if COMMITMENT_BLOCKED_SOURCES[intent.source] then
        if intent.position and context.commitmentTargetPosition then
          local ct = context.commitmentTargetPosition
          local ip = intent.position
          local dx = math.abs(ip.x - ct.x)
          local dy = math.abs(ip.y - ct.y)
          if dx > 3 or dy > 3 then
            rejected[#rejected + 1] = { intent = intent, reason = "commitment_violation" }
          else
            filtered[#filtered + 1] = intent
          end
        else
          rejected[#rejected + 1] = { intent = intent, reason = "commitment_violation" }
        end
      else
        filtered[#filtered + 1] = intent
      end
    end
    active = filtered
  end

  if #active == 0 then
    return { selected = nil, rejected = rejected }
  end

  local hardOverrides = {}
  for i = 1, #active do
    local isHardOverride = false
    for j = 1, #active do
      if i ~= j then
        local compat = getCompatibility(active[i].source, active[j].source)
        if compat == HARD_OVERRIDE and getPrecedence(active[i]) > getPrecedence(active[j]) then
          isHardOverride = true
          break
        end
      end
    end
    if isHardOverride then
      hardOverrides[#hardOverrides + 1] = active[i]
    end
  end

  if #hardOverrides > 0 then
    local survivors = {}
    local hardSet = {}
    for _, h in ipairs(hardOverrides) do hardSet[h] = true end

    for i = 1, #active do
      local dominated = false
      for _, h in ipairs(hardOverrides) do
        if active[i] ~= h then
          local compat = getCompatibility(h.source, active[i].source)
          if compat == HARD_OVERRIDE and getPrecedence(h) > getPrecedence(active[i]) then
            dominated = true
            break
          end
        end
      end
      if dominated then
        rejected[#rejected + 1] = { intent = active[i], reason = "hard_override" }
      else
        survivors[#survivors + 1] = active[i]
      end
    end
    active = survivors
  end

  local removed = {}
  local survivors = {}
  for i = 1, #active do
    if not removed[active[i]] then
      survivors[#survivors + 1] = active[i]
    end
  end

  for i = 1, #survivors do
    for j = i + 1, #survivors do
      local a, b = survivors[i], survivors[j]
      if a and b and not removed[a] and not removed[b] then
        local compat = getCompatibility(a.source, b.source)
        if compat == MUTUALLY_EXCLUSIVE then
          if score(a) >= score(b) then
            removed[b] = true
            rejected[#rejected + 1] = { intent = b, reason = "mutually_exclusive" }
          else
            removed[a] = true
            rejected[#rejected + 1] = { intent = a, reason = "mutually_exclusive" }
          end
        elseif compat == PREEMPTABLE then
          local preemptor = (getPrecedence(a) > getPrecedence(b)) and a or b
          local preempted = (preemptor == a) and b or a
          removed[preempted] = true
          rejected[#rejected + 1] = { intent = preempted, reason = "preempted" }
        end
      end
    end
  end

  local final = {}
  for i = 1, #survivors do
    if not removed[survivors[i]] then
      final[#final + 1] = survivors[i]
    end
  end

  if #final == 0 then
    return { selected = nil, rejected = rejected }
  end

  table.sort(final, function(a, b)
    return score(a) > score(b)
  end)

  return { selected = final[1], rejected = rejected }
end

return FeatureArbitrator
