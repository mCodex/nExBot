local function read(path)
  local file = assert(io.open(path, "r"))
  local contents = file:read("*a")
  file:close()
  return contents
end

describe("TargetBot reachability architecture", function()
  it("keeps the attack client call behind the state-machine boundary", function()
    local handle = assert(io.popen("find targetbot -name '*.lua' -type f"))
    for path in handle:lines() do
      local source = read(path):gsub("%-%-[^\n]*", "")
      if path ~= "targetbot/attack_state_machine.lua" then
        assert.is_nil(source:match("g_game%.attack%s*%(") or source:match("Client%.attack%s*%("), path)
      end
    end
    handle:close()
  end)

  it("has no close-range or current-target reachability bypass", function()
    local source = read("targetbot/target_coordinator.lua")
    assert.is_nil(source:match("Fake short path"))
    assert.is_nil(source:match("local simplePath"))
    assert.is_nil(source:match("not isCurrentTarget"))
    assert.is_truthy(source:match("TargetReachability%.evaluate"))
  end)

  it("does not retain the old floor-only creature path cache", function()
    local source = read("targetbot/target_pathfinding.lua")
    assert.is_nil(source:match("playerZ"))
    assert.is_nil(source:match("creatureZ"))
    assert.is_truthy(source:match("TargetReachability"))
  end)
end)
