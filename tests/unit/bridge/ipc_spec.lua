describe("Rust bridge", function()
  local state, env, position
  local clientToken = string.rep("a", 64)
  local serverProof = string.rep("b", 64)

  before_each(function()
    state = { sent = {}, pending = {}, logs = {}, closed = false }
    position = { x = 100, y = 100, z = 7 }
    local player = { getPosition = function() return position end }

    env = setmetatable({
      print = function(message) table.insert(state.logs, message) end,
      configDir = "/bot/rust-probe",
      g_resources = {
        fileExists = function() return true end,
        readFileContents = function()
          return "19140\n" .. clientToken .. "\n" .. serverProof .. "\n"
        end,
      },
      g_game = {
        getLocalPlayer = function() return player end,
        isOnline = function() return true end,
      },
      g_map = {
        findPath = function(_, _, budget, flags)
          assert.equals(16, budget)
          assert.equals(0, flags)
          return { 1 }, 0
        end,
      },
      HTTP = {
        WebSocket = function(url, handlers)
          assert.equals("ws://127.0.0.1:19140/", url)
          state.handlers = handlers
          return {
            id = 1,
            send = function(frame) table.insert(state.sent, frame) end,
            close = function() state.closed = true end,
          }
        end,
      },
      json = { decode = function() return state.serverFrame end },
      _websockets = {},
      UI = { Label = function() error("the bridge must only report status in the console") end },
      onPlayerPositionChange = function(callback) state.move = callback end,
      onCreaturePositionChange = function(callback) state.creatureMove = callback end,
      schedule = function(_, callback) table.insert(state.pending, callback) end,
    }, { __index = _G })
  end)

  local function loadProfile()
    assert(loadfile("bridge/_Loader.lua", "t", env))()
  end

  it("loads the normal bot controls and the diagnostic bridge from the default profile", function()
    local loaded = {}
    env.modules = { game_bot = { contentsPanel = { config = {
      getCurrentOption = function() return { text = "nExBot" } end,
    } } } }
    env.g_resources.listDirectoryFiles = function() return {} end
    env.warn = function() end
    env.info = function() end
    env.setDefaultTab = function(tab) state.tab = tab end
    env.dofile = function(path)
      loaded[path] = (loaded[path] or 0) + 1
    end
    assert(loadfile("_Loader.lua", "t", env))()
    assert.equals(1, loaded["/core/main.lua"])
    assert.equals(1, loaded["/core/cavebot.lua"])
    assert.equals(1, loaded["/core/cavebot_control_panel.lua"])
    assert.equals("Main", state.tab)
    assert.equals(1, loaded["bridge/_Loader.lua"])
  end)

  local function start()
    loadProfile()
    state.handlers.onOpen()
  end

  local function receive(frame)
    state.serverFrame = frame
    state.handlers.onMessage("{}")
  end

  it("connects when the engine starts after the bot without reloading the profile", function()
    local available = false
    env.g_resources.fileExists = function(path)
      if path == env.configDir .. "/rust-service-session" then return false end
      assert.equals(env.configDir .. "/rust-session", path)
      return available
    end
    loadProfile()
    assert.is_nil(state.handlers)
    for _ = 1, 3 do
      assert.equals(1, #state.pending)
      table.remove(state.pending, 1)()
    end
    assert.same({ "[nExBot] Rust bridge v5.0.0-alpha.1 - waiting for the local Rust engine" }, state.logs)
    available = true
    table.remove(state.pending, 1)()
    assert.equals(0, #state.pending)
    state.handlers.onOpen()
    receive({ type = "ready", protocol = 1, proof = serverProof })
    assert.equals("snapshot", state.sent[2].type)
  end)

  it("reauthenticates after a disconnect and ignores callbacks from the old socket", function()
    start()
    receive({ type = "ready", protocol = 1, proof = serverProof })
    local old = state.handlers
    old.onClose()
    table.remove(state.pending, 1)()
    state.handlers.onOpen()
    old.onClose()
    receive({ type = "ready", protocol = 1, proof = serverProof })
    assert.equals("snapshot", state.sent[4].type)
    assert.equals(1, state.sent[4].sequence)
    assert.equals(0, #state.pending)
  end)

  it("authenticates before emitting snapshots and reports native query results", function()
    start()
    assert.equals("hello", state.sent[1].type)
    assert.equals(clientToken, state.sent[1].token)
    assert.equals(1, #state.sent)
    assert.same({ "[nExBot] Rust bridge v5.0.0-alpha.1 - connecting" }, state.logs)

    receive({ type = "ready", protocol = 1, proof = serverProof })
    assert.equals("[nExBot] Rust bridge v5.0.0-alpha.1 - connected and authenticated (diagnostic mode)", state.logs[2])
    assert.equals("snapshot", state.sent[2].type)
    assert.equals(1, state.sent[2].sequence)

    receive({
      type = "probe", id = 1, origin = position,
      destination = { x = 101, y = 100, z = 7 },
    })
    state.pending[1]()
    assert.same({ type = "ack", sequence = 2, id = 1, path_result = 0 }, state.sent[3])

    state.move({ x = 101, y = 100, z = 7 })
    assert.equals("move", state.sent[4].type)
  end)

  it("closes on bad proof and rejects a stale command without reading the map", function()
    start()
    receive({ type = "ready", protocol = 1, proof = clientToken })
    assert.is_true(state.closed)
    assert.equals(1, #state.sent)
    assert.equals("[nExBot] Rust bridge v5.0.0-alpha.1 - authentication failed", state.logs[2])

    state.sent = {}
    table.remove(state.pending, 1)()
    state.handlers.onOpen()
    receive({ type = "ready", protocol = 1, proof = serverProof })
    receive({
      type = "probe", id = 1, origin = position,
      destination = { x = 101, y = 100, z = 7 },
    })
    position = { x = 101, y = 100, z = 7 }
    state.pending[1]()
    assert.same({ type = "ack", sequence = 2, id = 1 }, state.sent[3])
  end)
  it("coalesces creature movement and discards scheduled data after disconnect", function()
    start()
    receive({ type = "ready", protocol = 1, proof = serverProof })
    local creature = { getId = function() return 10 end }
    state.creatureMove(creature, { x = 105, y = 100, z = 7 })
    state.creatureMove(creature, { x = 106, y = 100, z = 7 })
    assert.equals(1, #state.pending)
    state.pending[1]()
    assert.same({
      type = "creature_move", sequence = 2, id = 10, position = { x = 106, y = 100, z = 7 },
    }, state.sent[3])

    state.creatureMove(creature, { x = 107, y = 100, z = 7 })
    state.handlers.onClose()
    state.pending[2]()
    assert.equals(3, #state.sent)
  end)
  it("queries a bounded route and reports changes to the watched tile", function()
    local blocked = false
    local nextTile = { x = 101, y = 100, z = 7 }
    local tile = {
      getPosition = function() return nextTile end,
      isWalkable = function(_, ignoreCreatures) return ignoreCreatures or not blocked end,
    }
    env.g_map.findPath = function(_, _, budget, flags)
      assert.equals(512, budget)
      assert.equals(0, flags)
      return { 1, 1 }, 0
    end
    env.g_map.getTile = function() return tile end
    env.onAddThing = function(callback) state.changed = callback end
    env.onRemoveThing = env.onAddThing

    start()
    receive({ type = "ready", protocol = 1, proof = serverProof })
    receive({ type = "route_probe", id = 1, origin = position, destination = { x = 102, y = 100, z = 7 } })
    state.pending[1]()
    assert.same({ type = "route_ack", sequence = 2, id = 1, directions = { 1, 1 } }, state.sent[3])

    receive({ type = "watch_tile", position = nextTile })
    state.pending[2]()
    assert.same({ type = "tile", sequence = 3, position = nextTile, walkable = true, ignore_creatures = true }, state.sent[4])
    state.changed(tile)
    state.pending[3]()
    assert.equals(4, #state.sent)
    blocked = true
    state.changed(tile)
    state.pending[4]()
    assert.same({ type = "tile", sequence = 4, position = nextTile, walkable = false, ignore_creatures = true }, state.sent[5])
  end)
end)
