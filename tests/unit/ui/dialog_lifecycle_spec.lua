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
      "core/equipper.otui",
      "core/Conditions.otui",
    }) do
      assert.is_nil(read(path):find("font:%s*cipsoftFont"), path)
    end
  end)

  it("avoids fill-anchor and child-sizing feedback loops", function()
    for _, path in ipairs({
      "cavebot/editor.otui",
      "core/AttackBot.otui",
      "core/HealBot.otui",
      "core/new_healer.otui",
      "core/equipper.otui",
      "core/Conditions.otui",
    }) do
      assert.is_nil(read(path):match("anchors%.fill: parent%s+fit%-children: true"), path)
    end
  end)
end)
