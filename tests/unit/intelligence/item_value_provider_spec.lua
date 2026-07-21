local ItemValueProvider = dofile("core/intelligence/learning/item_value_provider.lua")

describe("intelligence item value provider", function()
  it("returns value for known items", function()
    local provider = ItemValueProvider.new({ valueTable = { ["gold coin"] = 100, ["magic sword"] = 500 } })
    assert.equals(100, provider:getValue("gold coin"))
    assert.equals(500, provider:getValue("magic sword"))
  end)

  it("returns 0 for unknown items", function()
    local provider = ItemValueProvider.new({ valueTable = { ["gold coin"] = 100 } })
    assert.equals(0, provider:getValue("unknown item"))
  end)

  it("returns confidence for known items", function()
    local provider = ItemValueProvider.new({ valueTable = { ["gold coin"] = 100 } })
    assert.equals(0.5, provider:getConfidence("gold coin"))
  end)

  it("returns 0 confidence for unknown items", function()
    local provider = ItemValueProvider.new({ valueTable = { ["gold coin"] = 100 } })
    assert.equals(0, provider:getConfidence("unknown item"))
  end)

  it("returns all values as a copy", function()
    local values = { ["gold coin"] = 100, ["magic sword"] = 500 }
    local provider = ItemValueProvider.new({ valueTable = values })
    local result = provider:getAllValues()
    assert.same(values, result)
    result["gold coin"] = 999
    assert.equals(100, provider:getValue("gold coin"))
  end)

  it("handles empty value table", function()
    local provider = ItemValueProvider.new({ valueTable = {} })
    assert.equals(0, provider:getValue("anything"))
    assert.equals(0, provider:getConfidence("anything"))
    assert.same({}, provider:getAllValues())
  end)
end)
