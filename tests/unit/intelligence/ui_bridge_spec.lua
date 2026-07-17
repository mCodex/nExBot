describe("intelligence OTClient UI bridge", function()
  it("exposes one Tactical Intelligence window with the unified sections", function()
    local file = assert(io.open("core/intelligence/ui/ui_bridge.lua", "r"))
    local source = file:read("*a")
    file:close()

    for _, section in ipairs({
      "Overview",
      "Hunt Analytics",
      "Monster Intelligence",
      "ML Models",
      "Targeting Decisions",
      "Resources",
      "Routes & Navigation",
      "Replay",
      "Data Pipeline",
      "Diagnostics",
      "Advanced",
    }) do
      assert.is_truthy(source:find('"' .. section .. '"', 1, true), section)
    end

    assert.is_truthy(source:find('UI.Button("Tactical Intelligence"', 1, true))
    assert.is_truthy(source:find('UnifiedTick.register("tactical_intelligence_ui"', 1, true))
  end)
end)
