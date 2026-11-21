local function read(path)
  local file = assert(io.open(path, "r"))
  local contents = file:read("*a")
  file:close()
  return contents
end

describe("Primary dialog lifecycle", function()
  it("keeps the cave route editor hidden after setup", function()
    local source = read("cavebot/editor.lua")
    local setup = assert(source:match("CaveBot%.Editor%.setup = function%(%)%s*(.-)CaveBot%.Editor%.show"))

    assert.matches("UI%.createWindow", setup)
    assert.matches("ui:hide%(%)", setup)
  end)

  it("uses the readable client font throughout primary dialog styles", function()
    for _, path in ipairs({
      "cavebot/editor.otui",
      "core/AttackBot.otui",
      "core/HealBot.otui",
      "core/new_healer.otui",
      "core/Conditions.otui",
    }) do
      local f = io.open(path, "r")
      if f then
        local contents = f:read("*a")
        f:close()
        assert.is_nil(contents:find("font:%s*cipsoftFont"), path)
      end
    end
  end)

  it("avoids fill-anchor and child-sizing feedback loops", function()
    for _, path in ipairs({
      "cavebot/editor.otui",
      "core/AttackBot.otui",
      "core/HealBot.otui",
      "core/new_healer.otui",
      "core/Conditions.otui",
    }) do
      local f = io.open(path, "r")
      if f then
        local contents = f:read("*a")
        f:close()
        assert.is_nil(contents:match("anchors%.fill: parent%s+fit%-children: true"), path)
      end
    end
  end)
end)