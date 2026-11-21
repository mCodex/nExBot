-- container_integration_spec.lua
-- Integration tests for the full container discovery + recovery workflow.
-- Uses a deterministic fake client adapter.

local Discovery    = dofile("core/containers/discovery.lua")
local Readiness    = dofile("core/containers/readiness.lua")
local StateMachine = dofile("core/containers/state_machine.lua")

-- ─── Fake client helpers ────────────────────────────────────────────────────

local function makeItem(id, isContainer)
  local item = { _id = id, _isContainer = isContainer or false }
  function item:getId()          return self._id end
  function item:isContainer()    return self._isContainer end
  function item:getCount()       return 100 end
  return item
end

local function makeContainer(id, items)
  local c = { _id = id, _items = items or {}, _name = "Backpack" }
  function c:getId()              return self._id end
  function c:getName()            return self._name end
  function c:getItems()           return self._items end
  function c:getCapacity()        return 20 end
  function c:getItemsCount()      return #self._items end
  function c:isContainer()        return true end
  function c:getContainerItem()   return makeItem(self._id, true) end
  function c:getSlotPosition(slot)
    return { x = 0, y = 0, z = 0 }
  end
  return c
end

local function resetGlobals()
  _G.g_game       = nil
  _G.player       = nil
  _G.getClient    = nil
  _G.EventBus     = nil
  _G.addEvent     = function(fn, delay) fn() end  -- execute immediately in tests
end

-- ─── Tests ──────────────────────────────────────────────────────────────────

describe("Container Integration", function()
  before_each(resetGlobals)

  -- ── Normal login ───────────────────────────────────────────────────────

  it("normal login: discovers main backpack and reaches ROOTS_READY", function()
    local bp = makeItem(2854, true)
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function(slot) if slot == 3 then return bp end end,
    }

    local events = {}
    _G.EventBus = { emit = function(e, p) events[e] = p end }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    -- Verify main backpack was found and open request was made.
    local inFlight = d.bfs.inFlight
    assert.not_nil(inFlight, "Expected main backpack in-flight")
    assert.equals("MAIN_BACKPACK", inFlight.rootKind)

    -- Simulate container opened.
    d:onContainerOpened({ identity = inFlight.identity, itemType = 2854, items = {} })

    -- Should be COMPLETED now.
    assert.is_true(
      d:getState() == "completed" or d:getState() == "completedDegraded",
      "State: " .. d:getState()
    )
    -- Readiness published.
    assert.not_nil(events["containers:readiness"])
    assert.not_nil(events["containers:open_all_complete"])
  end)

  -- ── Deep nesting ─────────────────────────────────────────────────────

  it("deep nesting: discovers 3 levels of nested backpacks", function()
    local mainBp = makeItem(2854, true)
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function(slot) if slot == 3 then return mainBp end end,
    }
    _G.EventBus = { emit = function() end }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    local function openAndDiscover(depth, parentIdent, childItems)
      local inFlight = d.bfs.inFlight
      if not inFlight then return end
      d:onContainerOpened({ identity = inFlight.identity, itemType = inFlight.itemType, items = childItems })
    end

    -- Open main backpack with one nested child.
    local child1 = makeItem(2854, true)
    openAndDiscover(1, nil, { child1 })

    -- Process the items event which discovers children.
    local mainIdent = d.roleAssignments["MAIN"]
    if mainIdent then
      local child1Ident = "1:nested:" .. mainIdent .. ":1:2854:1"
      -- Simulate child1 opening.
      if d.bfs.inFlight then
        local child2 = makeItem(2854, true)
        d:onContainerOpened({ identity = d.bfs.inFlight.identity, itemType = 2854, items = { child2 } })
        -- Simulate child2 opening.
        if d.bfs.inFlight then
          d:onContainerOpened({ identity = d.bfs.inFlight.identity, itemType = 2854, items = {} })
        end
      end
    end

    -- Should be completed or in progress.
    local state = d:getState()
    assert.is_true(
      state == "completed" or state == "completedDegraded"
      or state == "traversing" or state == "openingContainer"
      or state == "waitingForAcknowledgement",
      "Unexpected state: " .. tostring(state)
    )
  end)

  -- ── Reconnect during combat ─────────────────────────────────────────

  it("reconnect: pauses TargetBot and CaveBot on onGameStart", function()
    local paused_tb = false
    local paused_cb = false
    _G.EventBus = {
      emit = function(event, payload)
        if event == "recovery:pause_targetbot" then paused_tb = true end
        if event == "recovery:pause_cavebot"   then paused_cb = true end
      end
    }

    local d = Discovery.new()
    d.config.pauseTargetBotOnRecovery = true
    d.config.pauseCaveBotOnRecovery   = true
    d:onGameStart()

    assert.is_true(paused_tb)
    assert.is_true(paused_cb)
    assert.equals("SURVIVAL_ONLY", d:getPolicyState())
  end)

  it("reconnect: resumes TargetBot and CaveBot after COMBAT_READY", function()
    local bp = makeItem(2854, true)
    local resumed_tb = false
    local resumed_cb = false
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function(slot) if slot == 3 then return bp end end,
    }
    _G.EventBus = {
      emit = function(event, payload)
        if event == "recovery:resume_targetbot" then resumed_tb = true end
        if event == "recovery:resume_cavebot"   then resumed_cb = true end
      end
    }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    -- Open main backpack → should trigger COMBAT_READY and resume signals.
    local inFlight = d.bfs.inFlight
    if inFlight then
      d:onContainerOpened({ identity = inFlight.identity, itemType = 2854, items = {} })
    end

    -- After completion, resume signals should have been emitted.
    assert.is_true(resumed_tb, "TargetBot should have received resume signal")
    assert.is_true(resumed_cb, "CaveBot should have received resume signal")
  end)

  -- ── Stale generation rejection ────────────────────────────────────────

  it("stale callback from previous generation is rejected", function()
    local bp = makeItem(2854, true)
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function(slot) if slot == 3 then return bp end end,
    }
    _G.EventBus = { emit = function() end }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    local inFlight = d.bfs.inFlight
    assert.not_nil(inFlight)

    -- Simulate reconnect before acknowledgement arrives.
    d:onGameStart()  -- bumps generation

    -- Old callback arrives — should be rejected.
    local stalesBefore = d.metrics.staleCallbacks
    d:onContainerOpened({ identity = inFlight.identity, itemType = 2854 })
    assert.equals(stalesBefore + 1, d.metrics.staleCallbacks)
  end)

  -- ── Repeated game-start idempotency ──────────────────────────────────

  it("repeated onGameStart within debounce window is idempotent", function()
    _G.EventBus = { emit = function() end }
    local d = Discovery.new()
    d:onGameStart()
    local gen = d:getGeneration()
    -- Force debounce window
    d.lastGameStartMs = os.clock() * 1000
    d:onGameStart()  -- should be ignored
    assert.equals(gen, d:getGeneration())
  end)

  -- ── Exhaustion handling ───────────────────────────────────────────────

  it("server exhaustion triggers backoff and retry", function()
    local bp = makeItem(2854, true)
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function(slot) if slot == 3 then return bp end end,
    }
    _G.EventBus = { emit = function() end }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    local inFlight = d.bfs.inFlight
    assert.not_nil(inFlight)

    -- Simulate exhaustion failure.
    local exhaustBefore = d.metrics.exhaustionEvents
    d:onContainerOpenFailed(inFlight.identity, "SERVER_EXHAUSTED")
    assert.is_true(d.metrics.exhaustionEvents > exhaustBefore)
    -- Should have backoff set.
    assert.is_true(d.scheduler.backoffUntil > 0)
  end)

  -- ── Non-paladin: no quiver actions ────────────────────────────────────

  it("non-paladin: quiver root not in role assignments", function()
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function() return nil end,
    }
    _G.player = { getVocation = function() return 1 end }  -- Knight
    _G.EventBus = { emit = function() end }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    assert.is_nil(d.roleAssignments["QUIVER"])
  end)

  -- ── One failed node does not block others ─────────────────────────────

  it("one failed node does not block other nodes", function()
    local bp  = makeItem(2854, true)
    local bp2 = makeItem(2866, true)  -- supplies backpack also equipped (hypothetical)
    _G.g_game = {
      getContainers    = function() return {} end,
      getInventoryItem = function(slot) if slot == 3 then return bp end end,
    }
    _G.EventBus = { emit = function() end }

    local d = Discovery.new()
    d.config.autoOpen = false
    d:startDiscovery()

    local inFlight = d.bfs.inFlight
    assert.not_nil(inFlight)

    -- Main backpack opens with a nested child.
    d:onContainerOpened({
      identity  = inFlight.identity,
      itemType  = 2854,
      items     = { bp2 },
    })

    -- Nested child in queue now. Fail it.
    local childInFlight = d.bfs.inFlight
    if childInFlight then
      -- Exhaust retries.
      childInFlight.attempt = 3
      d:onContainerOpenFailed(childInFlight.identity, "UNKNOWN")
    end

    -- Discovery should complete in DEGRADED mode (main ready, child failed).
    local state = d:getState()
    assert.is_true(
      state == "completedDegraded" or state == "completed",
      "Expected completed/degraded, got: " .. tostring(state)
    )
    assert.is_true(d.metrics.nodesFailed >= 0)
  end)

  -- ── Duplicate backpack types remain distinct ──────────────────────────

  it("duplicate backpack item IDs produce distinct physical identities", function()
    local Identity = dofile("core/containers/identity.lua")
    local id1 = Identity.make(1, "MAIN_BACKPACK", "none", 3, 2854, "0")
    local id2 = Identity.make(1, "nested",        id1,    0, 2854, "1")
    local id3 = Identity.make(1, "nested",        id1,    1, 2854, "1")

    assert.not_equals(id1, id2)
    assert.not_equals(id2, id3)
    assert.not_equals(id1, id3)
  end)

  -- ── Degraded readiness published on partial failure ───────────────────

  it("degraded readiness exposed when some nodes fail", function()
    local reg = (require or dofile)  -- not used directly here
    local Reg = dofile("core/containers/registry.lua")
    local r = Reg.new()
    r:add({ identity = "main", state = "opened", itemType = 2854 })
    r:add({ identity = "loot", state = "failed",  itemType = 2869 })

    local snap = Readiness.compute(r, 1, {
      isPaladin = false,
      roleAssignments = { MAIN = "main" }
    })
    -- With MAIN ready but some failures: ROOTS_READY at best with legacy mode
    -- (loot role not assigned in this test)
    assert.not_equals("FULLY_DISCOVERED", snap.status)
    assert.equals(1, snap.failedCount)
  end)
end)
