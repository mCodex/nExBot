local modules = {
  "core/quiver_manager.lua",
  "core/eat_food.lua",
  "core/equip.lua",
  "core/Equipper.lua",
  "core/exeta.lua",
}

local function source(path)
  local file = assert(io.open(path, "r"))
  local contents = file:read("*a")
  file:close()
  return contents
end

describe("headless equipment modules", function()
  it("does not construct legacy left-panel controls", function()
    for _, path in ipairs(modules) do
      local contents = source(path)
      assert.is_nil(contents:find("setDefaultTab", 1, true), path)
      assert.is_nil(contents:find("setupUI", 1, true), path)
      assert.is_nil(contents:find("UI.Separator", 1, true), path)
    end
  end)

  it("keeps configuration behind controller APIs", function()
    assert.is_truthy(source("core/equip.lua"):find("nExBot.AutoEquip =", 1, true))
    assert.is_truthy(source("core/Equipper.lua"):find("nExBot.Equipper =", 1, true))
    assert.is_truthy(source("core/eat_food.lua"):find("setEatingEnabled", 1, true))
    assert.is_truthy(source("core/exeta.lua"):find("nExBot.Exeta.setEnabled", 1, true))
  end)
end)
