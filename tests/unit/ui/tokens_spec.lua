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

  it("keeps semantic text and state colors WCAG AA against the base surface", function()
    local function luminance(hex)
      local channels = {}
      for offset = 2, 6, 2 do
        local channel = tonumber(hex:sub(offset, offset + 1), 16) / 255
        channels[#channels + 1] = channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
      end
      return 0.2126 * channels[1] + 0.7152 * channels[2] + 0.0722 * channels[3]
    end

    local foreground = {
      DS.colors.text.primary, DS.colors.text.secondary, DS.colors.text.muted,
      DS.colors.active, DS.colors.disabled, DS.colors.warning, DS.colors.danger,
    }
    local backgrounds = {
      DS.colors.background.canvas,
      DS.colors.background.base,
      DS.colors.background.elevated,
    }
    for _, surface in ipairs(backgrounds) do
      local background = luminance(surface)
      for _, color in ipairs(foreground) do
        local value = luminance(color)
        local ratio = (math.max(value, background) + 0.05) / (math.min(value, background) + 0.05)
        assert.is_true(ratio >= 4.5, color .. " on " .. surface .. " contrast was " .. tostring(ratio))
      end
    end
  end)

  it("does not rely on color aliases for active, inactive, and warning states", function()
    assert.are_not_equal(DS.colors.active, DS.colors.disabled)
    assert.are_not_equal(DS.colors.active, DS.colors.warning)
    assert.are_not_equal(DS.colors.disabled, DS.colors.warning)
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
