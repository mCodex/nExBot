-- tests/helpers/spec_helper.lua
-- Common setup for busted tests

local mock = require("tests.helpers.mock_otclient")

-- Install mocks before any module loads
mock.install()

-- Helper: reset all state between tests
local function resetAll()
  mock.resetPlayer()
  if EventBus and EventBus.reset then
    EventBus:reset()
  end
  if BotCore and BotCore.Stats and BotCore.Stats.invalidate then
    BotCore.Stats:invalidate()
  end
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.invalidate then
    BotCore.Cooldown:invalidate()
  end
  _G.now = os.time() * 1000
end

-- busted helper: call resetAll before each test
local busted = require("busted")
before_each(function()
  resetAll()
end)

return {
  mock = mock,
  resetAll = resetAll,
}
