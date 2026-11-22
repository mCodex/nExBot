-- From tests/ui, launch the OTClient binary with NEXBOT_CLIENT_ROOT pointing
-- to its source tree and --user-dir pointing to a temporary profile directory.
local client = assert(os.getenv("NEXBOT_CLIENT_ROOT"), "Set NEXBOT_CLIENT_ROOT")
local bot = g_resources.getWorkDir() .. "../../"
g_app.setCompactName("nexbot-ui-test")
for _, path in ipairs({client, client .. "/data", client .. "/modules", client .. "/mods", bot}) do
  assert(g_resources.addSearchPath(path, true), path)
end
g_resources.setupUserWriteDir("nexbot-ui-test/")
g_configs.loadSettings("/config.otml")
g_modules.discoverModules()
for _, module in ipairs({"corelib", "gamelib", "client_styles"}) do
  g_modules.ensureModuleLoaded(module)
end
tr = function(text) return text end
for _, file in ipairs({"basic", "panels", "config", "icons", "container"}) do
  assert(g_ui.importStyle("/game_bot/ui/" .. file .. ".otui"))
end
local controls = "/core/controls.otui"
assert(g_ui.importStyle(controls))
for _, directory in ipairs({"/core", "/cavebot", "/targetbot"}) do
  for _, file in ipairs(g_resources.listDirectoryFiles(directory, true, false)) do
    if file:match("%.otui$") and file ~= controls then assert(g_ui.importStyle(file), file) end
  end
end
g_window.resize({width = 900, height = 650})
g_window.show()
scheduleEvent(function()
  local ok, err = xpcall(function()
    dofile("/tests/ui/native_layout.lua")(g_ui.getRootWidget())
    if os.getenv("NEXBOT_TEST_NATIVE_RUNTIME") == "1" then
      assert(type(nexbotDecide) == "function", "native Rust binding is required")
      dofile("/bridge/native_runtime.lua")
      local decide = assert(nExBotRuntime).decide
      local heal = {
        hp = 49, mp = 90, mana = 200, in_pz = false,
        rules = {{hp = 50, above = false, potion = false, cost = 100, ready = true}},
      }
      assert(decide("self_heal", heal) == 1)
      assert(decide("movement_dispatch", {
        safe_steps = 5, field_ahead = false, allow_segment = true,
      }) == 5)
      assert(decide("npc_conversation", {count = 3, interval_ms = 150}).delays[3] == 300)
      assert(decide("reopen_page", {page = 0, capacity = 8, size = 10, visited = {0}}).page == 8)
      assert(decide("unknown", {}) == nil)
      local samples = {}
      for i = 1, 10000 do
        local start = g_clock.realMicros()
        local result = decide("self_heal", heal)
        samples[i] = g_clock.realMicros() - start
        assert(result == 1)
      end
      table.sort(samples)
      print(string.format("Rust self-heal adapter (10000 samples): p50=%d us p95=%d us p99=%d us",
        samples[5000], samples[9500], samples[9900]))

      print("nExBot native Rust runtime tests passed")
    end
  end, debug.traceback)
  if not ok then g_logger.fatal(err) end
  print("nExBot native UI tests passed")
  scheduleEvent(g_app.exit, 200)
end, 350)
