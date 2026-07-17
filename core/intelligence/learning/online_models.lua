IntelligenceOnlineModels = {}
local Models = IntelligenceOnlineModels

function Models.ewma(alpha)
  assert(alpha > 0 and alpha <= 1, "alpha must be in (0, 1]")
  return { update = function(self, value)
    self.value = self.value == nil and value or self.value + alpha * (value - self.value)
    return self.value
  end }
end

function Models.welford()
  return {
    count = 0, mean = 0, m2 = 0,
    update = function(self, value)
      self.count = self.count + 1
      local delta = value - self.mean
      self.mean = self.mean + delta / self.count
      self.m2 = self.m2 + delta * (value - self.mean)
    end,
    variance = function(self) return self.count > 1 and self.m2 / (self.count - 1) or 0 end,
  }
end

function Models.beta(alpha, beta)
  return {
    alpha = alpha or 1, beta = beta or 1, samples = 0,
    update = function(self, success, weight)
      weight = math.max(0, weight or 1)
      if success then self.alpha = self.alpha + weight else self.beta = self.beta + weight end
      self.samples = self.samples + 1
    end,
    mean = function(self) return self.alpha / (self.alpha + self.beta) end,
  }
end

function Models.markov(maxStates)
  local model = { transitions = {}, totals = {}, stateCount = 0, maxStates = maxStates or 32 }
  function model:observe(from, to)
    if not self.transitions[from] then
      if self.stateCount >= self.maxStates then return false end
      self.transitions[from], self.totals[from] = {}, 0
      self.stateCount = self.stateCount + 1
    end
    self.transitions[from][to] = (self.transitions[from][to] or 0) + 1
    self.totals[from] = self.totals[from] + 1
    return true
  end
  function model:predict(from)
    local transitions, total = self.transitions[from], self.totals[from]
    if not transitions or total == 0 then return nil end
    local best, count
    for state, value in pairs(transitions) do
      if not count or value > count or value == count and tostring(state) < tostring(best) then best, count = state, value end
    end
    return { state = best, probability = count / total, evidence = total }
  end
  return model
end

return Models
