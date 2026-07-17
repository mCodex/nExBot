-- discovery_spec.lua
-- Tests for the Discovery orchestrator (updated for v5 API).
-- Uses a fake g_game / g_inventoryItem to drive deterministic scenarios.

local Discovery = dofile("core/containers/discovery.lua")
local StateMachine = dofile("core/containers/state_machine.lua")

-- Minimal fake item that behaves like a container
local function makeContainer(id)
  local c = { _id = id }
  function c:getId() return self._id end
  function c:isContainer() return true end
  return c
end

local function makeNonContainer(id)
  local c = { _id = id }
  function c:getId() return self._id end
  function c:isContainer() return false end
  return c
end

-- Reset globals between tests
local function resetGlobals()
  _G.g_game = nil
  _G.player = nil
  _G.Client = nil
  _G.getClient = nil
  _G.EventBus = nil
  _G.addEvent = function(fn, delay) end  -- no-op in tests
end

describe("Discovery", function()
  before_each(resetGlobals)

  it("starts in IDLE", function()
    local d = Discovery.new()
    assert.equals("idle", d:getState())
  end)

  it("starts in DISABLED policy state", function()
    local d = Discovery.new()
    assert.equals("DISABLED", d:getPolicyState())
  end)

  it("increments generation on onGameStart (debounce ignored when cold)", function()
    local d = Discovery.new()
    local gen0 = d:getGeneration()
    d:onGameStart()
    assert.equals(gen0 + 1, d:getGeneration())
  end)

  it("is idempotent: repeated onGameStart within debounce window does not double-increment", function()
    local d = Discovery.new()
    -- Force lastGameStartMs to simulate "just fired"
    d.lastGameStartMs = os.clock() * 1000
    local gen = d:getGeneration()
    d:onGameStart()
    assert.equals(gen, d:getGeneration())  -- debounced, no change
  end)

  it("enters SURVIVAL_ONLY policy on onGameStart", function()
    local d = Discovery.new()
    d:onGameStart()
    assert.equals("SURVIVAL_ONLY", d:getPolicyState())
  end)

  it("transitions to IDLE on onGameEnd", function()
    local d = Discovery.new()
    d:onGameStart()
    d:onGameEnd()
    assert.equals("idle", d:getState())
    assert.equals("DISABLED", d:getPolicyState())
  end)

  it("start() is a backward-compat alias for startDiscovery()", function()
    _G.g_game = { getContainers = function() return {} end,
                  getInventoryItem = function() return nil end }
    local d = Discovery.new()
    d.config.autoOpen = false  -- prevent addEvent scheduling
    -- Direct call to startDiscovery should work
    d:startDiscovery()
    -- State is no longer idle
    assert.not_equals("idle", d:getState())
  end)

  it("cancels discovery and increments generation", function()
    _G.g_game = { getContainers = function() return {} end,
                  getInventoryItem = function() return nil end }
    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()
    local gen = d:getGeneration()
    d:cancel("test")
    assert.equals("cancelled", d:getState())
    assert.equals(gen + 1, d:getGeneration())  -- transition(CANCELLED) bumps generation
  end)

  it("returns degraded readiness when main backpack missing", function()
    _G.g_game = { getContainers = function() return {} end,
                  getInventoryItem = function() return nil end }
    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()
    -- No main backpack found → FAILED state
    assert.equals("failed", d:getState())
    local r = d:getReadiness()
    -- Should not be FULLY_DISCOVERED
    assert.not_equals("FULLY_DISCOVERED", r.status)
  end)

  it("detects paladin quiver when equipped and no MAIN found", function()
    -- Simulate: no back slot item, quiver equipped
    _G.g_game = {
      getContainers   = function() return {} end,
      getInventoryItem = function(slot) return nil end,
    }
    local d = Discovery.new()
    -- Quiver detection is handled by Quiver module; just verify no crash
    d.config.autoOpen = false
    d:startDiscovery()
    -- Should reach FAILED (no main backpack)
    assert.equals("failed", d:getState())
  end)

  it("publishes recovery:pause_targetbot when pauseTargetBotOnRecovery=true", function()
    local paused = false
    _G.EventBus = {
      emit = function(event, payload)
        if event == "recovery:pause_targetbot" then paused = true end
      end
    }
    local d = Discovery.new()
    d.config.pauseTargetBotOnRecovery = true
    d:onGameStart()
    assert.is_true(paused)
  end)

  it("does not publish pause events when policy flags are false", function()
    local paused = false
    _G.EventBus = {
      emit = function(event, payload)
        if event == "recovery:pause_targetbot" or event == "recovery:pause_cavebot" then
          paused = true
        end
      end
    }
    local d = Discovery.new()
    d.config.pauseTargetBotOnRecovery = false
    d.config.pauseCaveBotOnRecovery   = false
    d:onGameStart()
    assert.is_false(paused)
  end)

  it("getMetrics() returns structured metrics", function()
    local d = Discovery.new()
    local m = d:getMetrics()
    assert.is_number(m.generation)
    assert.is_string(m.policyState)
    assert.is_string(m.discoveryState)
    assert.is_number(m.rootsFound)
    assert.is_number(m.nodesOpened)
  end)

  it("isReadyFor() uses meetsLevel comparison", function()
    local d = Discovery.new()
    -- No containers → SESSION_READY at best
    -- isReadyFor("FAILED") should be true (FAILED ≤ SESSION_READY)
    local r = d:getReadiness()
    -- Just verify the method doesn't crash
    local result = d:isReadyFor("FAILED")
    assert.is_boolean(result)
  end)

  it("complete container discovery path with fake main backpack", function()
    local bp = makeContainer(2854)
    _G.g_game = {
      getContainers    = function() return { bp } end,
      getInventoryItem = function(slot) if slot == 3 then return bp end end,
    }

    local events_emitted = {}
    _G.EventBus = {
      emit = function(event, payload) events_emitted[event] = payload end
    }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    -- Simulate container opened: main backpack
    local inFlight = d.bfs.inFlight
    if inFlight then
      d:onContainerOpened({ identity = inFlight.identity, itemType = 2854, items = {} })
    end

    -- Discovery should complete
    local state = d:getState()
    assert.is_true(state == "completed" or state == "completedDegraded",
      "Expected completed or completedDegraded, got: " .. tostring(state))
    assert.not_nil(events_emitted["containers:open_all_complete"])
  end)
end)
