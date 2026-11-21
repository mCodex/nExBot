local function productionLuaFiles()
  local pipe = assert(io.popen("rg --files core cavebot targetbot ui -g '*.lua'"))
  local files = {}
  for file in pipe:lines() do files[#files + 1] = file end
  pipe:close()
  return files
end

describe("legacy left panel removal", function()
  it("has no tab-bound UI construction in production modules", function()
    local violations = {}
    for _, path in ipairs(productionLuaFiles()) do
      local file = assert(io.open(path, "r"))
      local source = file:read("*a")
      file:close()
      if source:find("setDefaultTab", 1, true)
        or source:find("setupUI", 1, true)
        or source:find("UI.Config()", 1, true)
        or source:find("UI%.createWidget%([^,\n%)]+%)")
        or source:find("macro%s*%([^,\n]+,%s*[\"']") then
        violations[#violations + 1] = path
      end
    end
    assert.are_same({}, violations)
  end)
end)
