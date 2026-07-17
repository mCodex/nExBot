describe("intelligence legacy cleanup", function()
  it("removes standalone hunt and monster inspector UI assets", function()
    assert.is_nil(io.open("core/analyzer.otui", "r"))
    assert.is_nil(io.open("core/smart_hunt.otui", "r"))
  end)

  it("keeps legacy labels out of the source paths", function()
    for _, path in ipairs({
      "core/smart_hunt.lua",
      "core/cavebot.lua",
      "targetbot/monster_ai.lua",
    }) do
      local file = assert(io.open(path, "r"))
      local source = file:read("*a")
      file:close()
      assert.is_nil(source:find("HuntAnalyzerWindow", 1, true), path)
      assert.is_nil(source:find("MonsterInspectorWindow", 1, true), path)
      assert.is_nil(source:find("Monster Insights", 1, true), path)
    end
  end)
end)
