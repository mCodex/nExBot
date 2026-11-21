local modules = {
  "core/alarms.lua",
  "core/Conditions.lua",
  "core/antiRs.lua",
  "core/pushmax.lua",
  "core/combo.lua"
}

local function source(path)
  local file = assert(io.open(path, "r"))
  local contents = file:read("*a")
  file:close()
  return contents
end

describe("headless safety modules", function()
  it("does not construct legacy left-panel controls", function()
    for _, path in ipairs(modules) do
      local contents = source(path)
      assert.is_nil(contents:find("setDefaultTab", 1, true), path)
      assert.is_nil(contents:find("setupUI", 1, true), path)
    end
  end)

  it("keeps AntiRS event-driven without a polling macro", function()
    local contents = source("core/antiRs.lua")
    assert.is_nil(contents:find("macro(", 1, true))
    assert.is_truthy(contents:find("AntiRs = antiRsMacro", 1, true))
    assert.is_truthy(contents:find('BotDB.registerMacro(antiRsMacro, "antiRs")', 1, true))
  end)
end)
