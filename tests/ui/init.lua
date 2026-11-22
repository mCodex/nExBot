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
  end, debug.traceback)
  if not ok then g_logger.fatal(err) end
  print("nExBot native UI tests passed")
  scheduleEvent(g_app.exit, 200)
end, 350)
