describe("ProfileStore", function()
  before_each(function()
    _G.nExBot = { paths = { config = "nExBot" } }
    _G.storage = { _configs = { cavebot_configs = { selected = "hunt", enabled = false } } }
    _G.json = { encode = function() return "{}" end, decode = function() return {} end }
    local files = { ["/bot/nExBot/cavebot_configs/hunt.cfg"] = "label:start\ngoto:1,2,7\n" }
    _G.g_resources = {
      readFileContents = function(path) assert(files[path], "missing " .. path); return files[path] end,
      writeFileContents = function(path, value) files[path] = value end,
      listDirectoryFiles = function() return { "hunt.cfg" } end,
      deleteFile = function(path) files[path] = nil end,
      fileExists = function(path) return files[path] ~= nil end,
    }
  end)

  it("loads and saves existing cfg profiles without UI.Config", function()
    local changed
    local store = dofile("core/profile_store.lua").open({
      key = "cavebot_configs", extension = "cfg",
      onChange = function(name, enabled, data) changed = { name, enabled, data } end,
    })

    assert.is_true(store.select("hunt"))
    assert.are_same({ "hunt", false, { { "label", "start" }, { "goto", "1,2,7" } } }, changed)
    store.setOn()
    assert.is_true(store.isOn())
    assert.is_true(store.save(changed[3]))
    assert.are_same({ "hunt" }, store.list())
    assert.is_true(store.rename("hunt", "hunt-v2"))
    assert.are_equal("hunt-v2", store.current())
  end)

  it("normalizes selected names that include the file extension", function()
    storage._configs.cavebot_configs.selected = "hunt.cfg"
    local store = dofile("core/profile_store.lua").open({
      key = "cavebot_configs", extension = "cfg", onChange = function() end,
    })
    assert.are_equal("hunt", store.current())
  end)
end)
