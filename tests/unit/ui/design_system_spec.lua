_G.nExBot = { UI = {} }
local Typography = dofile("ui/design_system/typography.lua")

describe("Typography", function()
  it("exposes named styles", function()
    for _, name in ipairs({
      "displayMetric", "windowTitle", "moduleTitle", "sectionTitle",
      "body", "rowTitle", "helper", "metadata", "badge", "mono",
    }) do
      local style = Typography.get(name)
      assert.is_table(style, "style " .. name)
      assert.is_string(style.font)
      assert.is_number(style.size)
    end
  end)

  it("all font names resolve through the approved map", function()
    for name in pairs(Typography.styles) do
      local style = Typography.styles[name]
      assert.is_truthy(Typography.fonts[style.font], "unapproved font " .. tostring(style.font))
    end
  end)

  it("falls back safely for an unknown style", function()
    assert.is_table(Typography.get("does_not_exist"))
    assert.are_equal("body", Typography.get("does_not_exist")._fallback)
  end)
end)

describe("Density", function()
  local Density
  before_each(function()
    _G.nExBot.UI.Density = nil
    Density = dofile("ui/design_system/density.lua")
  end)

  it("supports default, compact, comfortable, and touch", function()
    for _, name in ipairs({ "default", "compact", "comfortable", "touch" }) do
      assert.is_table(Density.get(name))
    end
  end)

  it("density changes are token-driven", function()
    local compact = Density.get("compact")
    local def = Density.get("default")
    assert.is_number(compact.rowHeight)
    assert.is_number(def.rowHeight)
    assert.is_true(compact.rowHeight <= def.rowHeight)
  end)

  it("touch density meets the ~44px minimum tap target", function()
    local touch = Density.get("touch")
    assert.is_true(touch.rowHeight >= 44)
    assert.is_true(touch.controlHeight >= 40)
    assert.is_true(touch.rowHeight > Density.get("comfortable").rowHeight)
  end)

  it("falls back to default for unknown density", function()
    assert.are_equal("default", Density.get("ultra")._fallback)
  end)
end)

describe("Status", function()
  local Status
  before_each(function()
    _G.nExBot.UI.Status = nil
    Status = dofile("ui/design_system/status.lua")
  end)

  it("maps status semantics to colors", function()
    assert.is_string(Status.color("ACTIVE"))
    assert.is_string(Status.color("PAUSED"))
    assert.is_string(Status.color("ERROR"))
    assert.is_string(Status.color("WARNING"))
    assert.is_string(Status.color("DISABLED"))
    assert.is_string(Status.color("OK"))
  end)

  it("status meanings are consistent", function()
    assert.are_equal(Status.color("OK"), Status.color("ACTIVE"))
    assert.are_equal(Status.color("ERROR"), Status.color("DANGER"))
  end)

  it("falls back to muted for unknown status", function()
    assert.are_equal(Status.color("???", "fallback-value"), "fallback-value")
  end)
end)
