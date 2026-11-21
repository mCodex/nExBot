nExBot = nExBot or {}
local MI = dofile("core/intelligence/learning/model_interface_v2.lua")

describe("intelligence model interface v2", function()
  it("constructs with defaults", function()
    local m = MI.new()
    assert.equals("OBSERVE", m:getMode())
    assert.equals(1, m:getVersion())
    assert.is_not_nil(_G.nExBot.IntelligenceModelInterfaceV2)
  end)

  it("accepts all valid modes", function()
    for _, mode in ipairs({ "OFF", "OBSERVE", "SHADOW", "ACTIVE", "CANARY" }) do
      local m = MI.new({ mode = mode })
      assert.equals(mode, m:getMode())
    end
  end)

  it("rejects invalid mode", function()
    assert.has_error(function() MI.new({ mode = "INVALID" }) end)
  end)

  it("predict abstains in OBSERVE and OFF", function()
    for _, mode in ipairs({ "OFF", "OBSERVE" }) do
      local m = MI.new({ mode = mode })
      assert.is_nil(m:predict({}))
    end
  end)

  it("predict returns baseline in ACTIVE, SHADOW, CANARY", function()
    for _, mode in ipairs({ "ACTIVE", "SHADOW", "CANARY" }) do
      local m = MI.new({ mode = mode })
      local r = m:predict({ hp = 100 })
      assert.is_table(r)
      assert.equals(0.5, r.probability)
      assert.equals(0, r.confidence)
    end
  end)

  it("ACTIVE predict is actionable", function()
    local m = MI.new({ mode = "ACTIVE" })
    assert.is_true(m:predict({}).actionable)
  end)

  it("observe records in OBSERVE", function()
    local m = MI.new({ mode = "OBSERVE" })
    m:observe("test", 1.0, 0.8)
    assert.equals(1, #m:getHistory())
  end)

  it("observe no-ops in OFF", function()
    local m = MI.new({ mode = "OFF" })
    m:observe("test", 1.0, 0.8)
    assert.equals(0, #m:getHistory())
  end)

  it("observe records in all non-OFF modes", function()
    for _, mode in ipairs({ "OBSERVE", "SHADOW", "ACTIVE", "CANARY" }) do
      local m = MI.new({ mode = mode })
      m:observe("d", 1, 0.5)
      assert.equals(1, #m:getHistory())
    end
  end)
end)
