describe("intelligence OTClient UI bridge", function()
  it("exposes every required section through one shared window", function()
    local file = assert(io.open("core/intelligence/ui/ui_bridge.lua", "r"))
    local source = file:read("*a")
    file:close()
    for _, section in ipairs({ "Overview", "Targeting", "Dynamic Lure", "Pull System", "Wave Avoidance",
      "CaveBot Intelligence", "Monster Profiles", "Navigation Profiles", "Resource Efficiency", "Replay",
      "Diagnostics", "Advanced" }) do
      assert.is_truthy(source:find('"' .. section .. '"', 1, true), section)
    end
    assert.is_truthy(source:find('UnifiedTick.register("intelligence_ui"', 1, true))
  end)
end)
