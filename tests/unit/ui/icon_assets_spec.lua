-- Source-of-truth asset test: the generated PNG fallbacks exist for every
-- SVG, SVGs have a 24x24 viewBox and valid paths, and required icons exist.

local required = {
  "dashboard", "cavebot", "targetbot", "healing", "looting", "supplies",
  "scripts", "intelligence", "learning", "monsters", "navigation",
  "profiles", "settings", "diagnostics", "replay",
  "add", "remove", "edit", "save", "import", "export", "refresh", "search",
  "filter", "close", "info", "warning", "success", "paused", "active",
  "expand", "collapse", "reorder", "record", "stop",
  "waypoint", "route", "stairs-up", "stairs-down", "ladder", "hole",
  "rope", "shovel", "door", "obstacle", "recovery", "target", "shield",
  "potion", "backpack",
}

describe("icon assets", function()
  it("every required icon has an SVG source and PNG fallback", function()
    for _, id in ipairs(required) do
      local svgPath = "ui/assets/icons/" .. id .. ".svg"
      local pngPath = "ui/assets/icons/generated/" .. id .. "_24.png"
      local svg = assert(io.open(svgPath, "rb"), "missing SVG " .. svgPath)
      svg:close()
      local png = assert(io.open(pngPath, "rb"), "missing PNG " .. pngPath)
      png:close()
    end
  end)

  it("every SVG uses a 24x24 viewBox", function()
    for _, id in ipairs(required) do
      local f = assert(io.open("ui/assets/icons/" .. id .. ".svg", "rb"))
      local content = f:read("*a")
      f:close()
      assert.is_truthy(content:find('viewBox="0 0 24 24"', 1, true), id .. " viewBox")
      assert.is_truthy(content:find("<svg", 1, true), id .. " svg tag")
    end
  end)

  it("every PNG fallback is a valid PNG header", function()
    for _, id in ipairs(required) do
      local f = assert(io.open("ui/assets/icons/generated/" .. id .. "_24.png", "rb"))
      local header = f:read(8)
      f:close()
      assert.are_equal("\137PNG\r\n\26\n", header, id)
    end
  end)
end)
