_G.nExBot = { UI = {} }
local DS = dofile("ui/design_system/tokens.lua")

describe("DesignTokens", function()
  it("exposes semantic colors", function()
    local c = DS.colors
    assert.is_string(c.background.canvas)
    assert.is_string(c.background.base)
    assert.is_string(c.background.elevated)
    assert.is_string(c.background.interactive)
    assert.is_string(c.background.selected)
    assert.is_string(c.text.primary)
    assert.is_string(c.text.secondary)
    assert.is_string(c.text.muted)
    assert.is_string(c.accent.primary)
    assert.is_string(c.success)
    assert.is_string(c.warning)
    assert.is_string(c.danger)
    assert.is_string(c.info)
    assert.is_string(c.active)
    assert.is_string(c.paused)
    assert.is_string(c.disabled)
    assert.is_string(c.degraded)
  end)

  it("all colors are hex strings", function()
    local function walk(t)
      for k, v in pairs(t) do
        if type(v) == "table" then
          walk(v)
        elseif k ~= "name" then
          assert.matches("^#[0-9a-fA-F]+$", v, "color " .. tostring(k))
        end
      end
    end
    walk(DS.colors)
  end)

  it("spacing scale is a sorted small set", function()
    assert.same({ 2, 4, 6, 8, 12, 16, 20, 24 }, DS.spacing)
  end)

  it("spacing accessor returns a named step", function()
    assert.are_equal(4, DS.sp(2))
    assert.are_equal(8, DS.sp(4))
    assert.are_equal(16, DS.sp(6))
  end)

  it("radii and borders exist", function()
    assert.is_number(DS.radii.sm)
    assert.is_number(DS.radii.md)
    assert.is_number(DS.radii.lg)
    assert.is_number(DS.borders.subtle)
    assert.is_number(DS.borders.default)
    assert.is_number(DS.borders.strong)
  end)

  it("exposes a compact frozen token table", function()
    assert.is_table(DS.colors)
    assert.is_table(DS.spacing)
    assert.is_table(DS.dimensions)
    assert.are_equal(1, DS.version)
  end)

  it("rejects writes to the frozen token table", function()
    assert.has_error(function() DS.colors.text.primary = "#000000" end)
  end)
end)
