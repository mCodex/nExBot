if not nExBot then nExBot = {} end

local VALID_MODES = { OFF = true, OBSERVE = true, SHADOW = true, ACTIVE = true, CANARY = true }

local Interface = {}
Interface.__index = Interface

function Interface.new(config)
  config = config or {}
  local mode = config.mode or "OBSERVE"
  assert(VALID_MODES[mode], "invalid mode: " .. tostring(mode))
  return setmetatable({ mode = mode, version = config.version or 1, history = {} }, Interface)
end

function Interface:predict(state)
  if self.mode == "OFF" or self.mode == "OBSERVE" then return nil end
  return { probability = 0.5, confidence = 0, actionable = self.mode == "ACTIVE",
    state = state }
end

function Interface:observe(decision, outcome, reward)
  if self.mode == "OFF" then return end
  self.history[#self.history + 1] = { decision = decision, outcome = outcome,
    reward = reward }
end

function Interface:getVersion() return self.version end

function Interface:getMode() return self.mode end

function Interface:getHistory() return self.history end

nExBot.IntelligenceModelInterfaceV2 = Interface

return Interface
