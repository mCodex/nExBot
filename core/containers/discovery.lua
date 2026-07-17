-- discovery.lua
-- Container discovery orchestrator and reconnect recovery coordinator.
-- Owns: session lifecycle, root discovery, reconnect policy state,
--       EventBus publishing, TargetBot/CaveBot resume decisions.
-- Uses: StateMachine, Registry, BFS, Scheduler, Quiver, Readiness, ClientAdapter.

local StateMachine  = dofile("core/containers/state_machine.lua")
local Registry      = dofile("core/containers/registry.lua")
local BFS           = dofile("core/containers/bfs.lua")
local Scheduler     = dofile("core/containers/scheduler.lua")
local Quiver        = dofile("core/containers/quiver.lua")
local Readiness     = dofile("core/containers/readiness.lua")
local ClientAdapter = dofile("core/containers/client_adapter.lua")
local Identity      = dofile("core/containers/identity.lua")

local Discovery = {}

-- Recovery policy states (reconnect coordinator).
Discovery.Policy = {
  DISABLED                    = "DISABLED",
  SURVIVAL_ONLY               = "SURVIVAL_ONLY",
  CONTAINER_CRITICAL_RECOVERY = "CONTAINER_CRITICAL_RECOVERY",
  COMBAT_DEGRADED             = "COMBAT_DEGRADED",
  COMBAT_READY                = "COMBAT_READY",
  FULLY_READY                 = "FULLY_READY",
}

-- Debounce window for duplicate onGameStart signals (ms).
local GAME_START_DEBOUNCE_MS = 500

-- Stability wait before root discovery after login (ms).
local INVENTORY_STABILITY_MS = 1200

-- Inventory slot for the main backpack (back slot).
-- Tibia: SLOT_BACK = 3.
local BACK_SLOT = 3

function Discovery.new()
  local sm = StateMachine.new()
  local reg = Registry.new()
  return setmetatable({
    stateMachine     = sm,
    registry         = reg,
    bfs              = BFS.new(reg, sm),
    scheduler        = Scheduler.new(),
    -- Recovery coordinator state.
    policyState      = Discovery.Policy.DISABLED,
    -- Role assignments: role string → physical identity string.
    roleAssignments  = {},
    -- Pending reconnect: timestamp of last onGameStart signal.
    lastGameStartMs  = nil,
    -- Whether a discovery run is currently active.
    running          = false,
    -- EventBus reference (injected or found from global).
    eventBus         = nil,
    -- Config (may be updated at runtime).
    config           = {
      autoOpen                  = false,
      windowMode                = "KEEP_ALL_OPEN",
      pauseCaveBotOnRecovery    = true,
      pauseTargetBotOnRecovery  = true,
      maxOpenWindows            = 19,
    },
    -- Metrics (bounded).
    metrics = {
      discoveryStartMs   = nil,
      rootsFound         = 0,
      nodesOpened        = 0,
      nodesFailed        = 0,
      retries            = 0,
      exhaustionEvents   = 0,
      staleCallbacks     = 0,
    },
  }, { __index = Discovery })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

-- Call from onGameStart / login event.
function Discovery:onGameStart()
  local now = os.clock() * 1000
  -- Debounce: ignore duplicate signals within the window.
  if self.lastGameStartMs and (now - self.lastGameStartMs) < GAME_START_DEBOUNCE_MS then
    return
  end
  self.lastGameStartMs = now

  -- Increment generation — invalidates all previous callbacks.
  self.stateMachine:incrementGeneration("onGameStart")
  self.scheduler:setGeneration(self.stateMachine.generation)

  -- Clear previous session state.
  self.registry:clear()
  self.running = false

  -- Enter survival-only policy immediately.
  self:_setPolicyState(Discovery.Policy.SURVIVAL_ONLY)

  -- Pause TargetBot and CaveBot if configured.
  if self.config.pauseTargetBotOnRecovery then
    self:_emit("recovery:pause_targetbot", { reason = "session_start", generation = self.stateMachine.generation })
  end
  if self.config.pauseCaveBotOnRecovery then
    self:_emit("recovery:pause_cavebot", { reason = "session_start", generation = self.stateMachine.generation })
  end

  self.stateMachine:transition(StateMachine.States.WAITING_FOR_SESSION, "onGameStart")

  if not self.config.autoOpen then return end

  -- Wait for inventory stability, then begin discovery.
  local gen = self.stateMachine.generation
  addEvent(function()
    if self.stateMachine.generation ~= gen then return end  -- Stale.
    self:startDiscovery()
  end, INVENTORY_STABILITY_MS)
end

-- Call from onGameEnd / logout / disconnect event.
function Discovery:onGameEnd()
  self.stateMachine:incrementGeneration("onGameEnd")
  self.scheduler:setGeneration(self.stateMachine.generation)
  self.registry:clear()
  self.running = false
  self:_setPolicyState(Discovery.Policy.DISABLED)
  -- Force return to IDLE regardless of current state.
  self.stateMachine.state = StateMachine.States.IDLE
end

-- Begin a discovery run (idempotent for the current generation).
function Discovery:startDiscovery()
  if self.running then return end
  if not self.stateMachine:canTransition(StateMachine.States.DISCOVERING_ROOTS) then
    self.stateMachine:transition(StateMachine.States.WAITING_FOR_SESSION, "startDiscovery reset")
  end

  self.running = true
  self.metrics.discoveryStartMs = os.clock() * 1000
  self:_setPolicyState(Discovery.Policy.CONTAINER_CRITICAL_RECOVERY)
  self.stateMachine:transition(StateMachine.States.DISCOVERING_ROOTS, "startDiscovery")
  self:_discoverRoots()
end

-- Cancel the current discovery run (e.g. bot reload).
function Discovery:cancel(reason)
  self.stateMachine:transition(StateMachine.States.CANCELLED, reason or "cancel")
  self.scheduler:setGeneration(self.stateMachine.generation)
  self.registry:clear()
  self.running = false
  self:_setPolicyState(Discovery.Policy.DISABLED)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Root Discovery
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:_discoverRoots()
  local roots = {}
  local gen   = self.stateMachine.generation

  -- 1. Reconcile already-open windows.
  self.stateMachine:transition(StateMachine.States.RECONCILING_OPEN_WINDOWS, "reconciling")
  local openContainers = ClientAdapter.getContainers() or {}
  local reconciledIds  = {}
  for _, c in ipairs(openContainers) do
    reconciledIds[c:getId()] = c
  end

  -- 2. Find main backpack from equipped back slot.
  local mainItem = self:_getInventoryItem(BACK_SLOT)
  if mainItem and mainItem.isContainer and mainItem:isContainer() then
    local itemType = mainItem:getId()
    local ident    = Identity.make(gen, "MAIN_BACKPACK", "none", BACK_SLOT, itemType, "0")
    roots[#roots + 1] = {
      rootKind  = "MAIN_BACKPACK",
      identity  = ident,
      item      = mainItem,
      itemType  = itemType,
      slotIndex = BACK_SLOT,
    }
    self.roleAssignments["MAIN"] = ident
    self.metrics.rootsFound = self.metrics.rootsFound + 1
  else
    -- Fallback: use first open container if any.
    if #openContainers > 0 then
      local c = openContainers[1]
      local itemType = c:getId()
      local ident    = Identity.make(gen, "MAIN_BACKPACK", "none", BACK_SLOT, itemType, "0")
      roots[#roots + 1] = {
        rootKind  = "MAIN_BACKPACK",
        identity  = ident,
        item      = c,
        itemType  = itemType,
        slotIndex = BACK_SLOT,
      }
      self.roleAssignments["MAIN"] = ident
      self.metrics.rootsFound = self.metrics.rootsFound + 1
    end
  end

  -- 3. Quiver root (Paladins only).
  local quiverRoot = Quiver.discoverRoot()
  if quiverRoot then
    local ident = Identity.make(gen, "QUIVER", "none", quiverRoot.slotIndex, quiverRoot.itemType, "0")
    roots[#roots + 1] = {
      rootKind  = "QUIVER",
      identity  = ident,
      item      = quiverRoot.item,
      itemType  = quiverRoot.itemType,
      slotIndex = quiverRoot.slotIndex,
    }
    self.roleAssignments["QUIVER"] = ident
    self.metrics.rootsFound = self.metrics.rootsFound + 1
  end

  if #roots == 0 then
    self.stateMachine:transition(StateMachine.States.FAILED, "noRootsFound")
    self.running = false
    self:_publishReadiness()
    return
  end

  -- 4. Start BFS.
  self.stateMachine:transition(StateMachine.States.TRAVERSING, "rootsReady")
  self.bfs:start(roots)
  self:_processNext()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BFS Loop
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:_processNext()
  if not self:_generationValid() then return end
  if not self.stateMachine:is(StateMachine.States.TRAVERSING) then return end

  local candidate = self.bfs:processNext()

  if not candidate then
    -- Queue empty — check readiness.
    self:_checkCompletion()
    return
  end

  self.stateMachine:transition(StateMachine.States.OPENING_CONTAINER, "dequeued")
  self:_sendOpenRequest(candidate)
end

function Discovery:_sendOpenRequest(candidate)
  local gen  = self.stateMachine.generation
  local self_ = self

  self.scheduler:enqueue({
    type          = "open",
    identity      = candidate.identity,
    generation    = gen,
    priority      = Scheduler.Priority.CRITICAL_CONTAINER,
    correlationId = candidate.identity,
    maxAttempts   = 3,
    callback = function()
      if self_.stateMachine.generation ~= gen then return end
      -- Open using the actual item object if available; fall back to item type.
      if candidate.item then
        ClientAdapter.open(candidate.item)
      else
        -- Last-resort: try to find the container by item type in open windows.
        local containers = ClientAdapter.getContainers() or {}
        for _, c in ipairs(containers) do
          if c:getId() == candidate.itemType then
            ClientAdapter.open(c)
            return
          end
        end
      end
    end,
  })

  -- Dispatch immediately via scheduler tick.
  self.stateMachine:transition(StateMachine.States.WAITING_FOR_ACKNOWLEDGEMENT, "openRequested")
  self:_tickScheduler()
end

function Discovery:_tickScheduler()
  local action = self.scheduler:processNext()
  if action and action.callback then
    action.callback()
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Event Handlers (called from native client callbacks or EventBus)
-- ─────────────────────────────────────────────────────────────────────────────

-- Call when a container is opened in the client.
-- event: { containerId, itemType, capacity, itemCount, pageCount? }
function Discovery:onContainerOpened(event)
  if not self:_generationValid() then
    self.metrics.staleCallbacks = self.metrics.staleCallbacks + 1
    return
  end
  if not self.stateMachine:is(StateMachine.States.WAITING_FOR_ACKNOWLEDGEMENT) then
    return
  end

  -- Build identity from the event.  We look for the in-flight candidate.
  local inFlight = self.bfs.inFlight
  if not inFlight then return end

  -- Verify item type matches.
  if event.itemType and inFlight.itemType ~= event.itemType then
    return
  end

  -- Acknowledge in scheduler.
  local latencyMs = nil
  if self.scheduler.activeAt then
    latencyMs = os.clock() * 1000 - self.scheduler.activeAt
  end
  self.scheduler:acknowledge(inFlight.identity, latencyMs)

  -- Mark opened in BFS.
  local openedEvent = {
    identity    = inFlight.identity,
    containerId = event.containerId,
    itemCount   = event.itemCount,
    pageCount   = event.pageCount,
  }
  local opened = self.bfs:onContainerOpened(openedEvent)
  if not opened then return end

  self.metrics.nodesOpened = self.metrics.nodesOpened + 1

  -- Scan the container contents.
  self.stateMachine:transition(StateMachine.States.SCANNING_PAGE, "containerOpened")
  self:_scanContainer(opened, event)
end

-- Call when a container's items are received.
-- event: { identity, containerId, items[], pageIndex }
function Discovery:onContainerItems(event)
  if not self:_generationValid() then return end

  self.stateMachine:transition(StateMachine.States.INDEXING_ITEMS, "itemsReceived")

  -- Index items and discover child containers.
  local childContainers = {}
  local gen = self.stateMachine.generation

  for slotIdx, item in ipairs(event.items or {}) do
    -- Register item in registry item index.
    self.registry:indexItem(event.identity, slotIdx, item)

    -- Check if this item is a container (nested backpack).
    local isContainer = item.isContainer and item:isContainer()
    if isContainer then
      local itemType = item:getId()
      local childIdentity = Identity.make(
        gen, "nested", event.identity, slotIdx, itemType,
        tostring(self.stateMachine.generation)
      )
      childContainers[#childContainers + 1] = {
        identity      = childIdentity,
        rootKind      = "nested",
        itemType      = itemType,
        slotIndex     = slotIdx,
        item          = item,
        parentIdentity= event.identity,
      }
    end
  end

  -- Discover children (BFS enqueues unseen ones).
  self.stateMachine:transition(StateMachine.States.DISCOVERING_CHILDREN, "scanDone")
  self.bfs:discoverChildren(event.identity, childContainers)

  -- Mark node inspected.
  self.bfs:onInspectionComplete(event.identity)

  -- Assign roles if this node matches a configured role.
  self:_tryAssignRole(event.identity)

  -- Publish intermediate readiness.
  self:_publishReadiness()

  -- Continue traversal.
  self.stateMachine:transition(StateMachine.States.TRAVERSING, "childrenDiscovered")
  self:_processNext()
end

-- Call when a container open fails or times out.
-- reason: Scheduler.Reason constant
function Discovery:onContainerOpenFailed(identity, reason)
  if not self:_generationValid() then return end

  self.metrics.nodesFailed = self.metrics.nodesFailed + 1

  if reason == Scheduler.Reason.SERVER_EXHAUSTED
    or reason == Scheduler.Reason.ACTION_COOLDOWN then
    -- Exhaustion: backoff and retry.
    self.metrics.exhaustionEvents = self.metrics.exhaustionEvents + 1
    self.scheduler:onExhaustion(reason)
    local retried = self.bfs:retry(identity)
    if retried then
      self.metrics.retries = self.metrics.retries + 1
    end
  elseif reason == Scheduler.Reason.STALE_GENERATION then
    -- Ignore.
  else
    -- Non-retryable or max retries reached.
    self.bfs:markFailed(identity)
  end

  self.stateMachine:transition(StateMachine.States.TRAVERSING, "openFailed")
  self:_processNext()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Completion and Readiness
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:_checkCompletion()
  if self.bfs:isActive() then return end  -- Still in flight.

  local failedCount = self.registry:countByState("failed")
  if failedCount > 0 then
    self.stateMachine:transition(StateMachine.States.COMPLETED_DEGRADED, "degraded")
  else
    self.stateMachine:transition(StateMachine.States.COMPLETED, "allDone")
  end

  self.running = false
  local readiness = self:_publishReadiness()

  -- Update recovery policy based on readiness.
  self:_updatePolicyFromReadiness(readiness)

  -- Resume TargetBot / CaveBot if policy allows.
  self:_maybeResumeModules(readiness)

  -- Emit completion event.
  self:_emit("containers:open_all_complete", readiness)
end

function Discovery:_updatePolicyFromReadiness(readiness)
  local status = readiness and readiness.status or "SESSION_READY"
  if Readiness.meetsLevel(status, "FULLY_DISCOVERED") then
    self:_setPolicyState(Discovery.Policy.FULLY_READY)
  elseif Readiness.meetsLevel(status, "COMBAT_READY") then
    self:_setPolicyState(Discovery.Policy.COMBAT_READY)
  elseif Readiness.meetsLevel(status, "SURVIVAL_READY") then
    self:_setPolicyState(Discovery.Policy.COMBAT_DEGRADED)
  elseif Readiness.meetsLevel(status, "DEGRADED") then
    self:_setPolicyState(Discovery.Policy.CONTAINER_CRITICAL_RECOVERY)
  end
end

function Discovery:_maybeResumeModules(readiness)
  if not readiness then return end
  local status = readiness.status

  if Readiness.meetsLevel(status, "COMBAT_READY") then
    -- Resume TargetBot: fresh state, no stale targets.
    self:_emit("recovery:resume_targetbot", {
      generation = self.stateMachine.generation,
      reason     = "COMBAT_READY",
      freshState = true,
    })
    -- Resume CaveBot: recalculate from current position.
    self:_emit("recovery:resume_cavebot", {
      generation    = self.stateMachine.generation,
      reason        = "COMBAT_READY",
      recalculate   = true,
    })
  end
end

function Discovery:_publishReadiness()
  local context = {
    isPaladin       = Quiver.isPaladin(),
    roleAssignments = self.roleAssignments,
  }
  local snapshot = Readiness.compute(self.registry, self.stateMachine.generation, context)
  self:_emit("containers:readiness", snapshot)
  return snapshot
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Container Scanning
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:_scanContainer(opened, openEvent)
  -- For now trigger onContainerItems synchronously if items are embedded in the event.
  -- In a real client, the items arrive via a separate event; hook that event instead.
  if openEvent and openEvent.items then
    self:onContainerItems({
      identity    = opened.identity,
      containerId = opened.containerId,
      items       = openEvent.items,
      pageIndex   = 0,
    })
  else
    -- Transition back to traversing and wait for onContainerItems callback.
    self.stateMachine:transition(StateMachine.States.WAITING_FOR_PAGE, "waitingForItems")
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Role Assignment
-- ─────────────────────────────────────────────────────────────────────────────

-- Attempt to assign a role to the newly-inspected node based on configured selectors.
-- Extend this to support user-configured role selectors beyond root kinds.
function Discovery:_tryAssignRole(identity)
  local node = self.registry:get(identity)
  if not node then return end

  -- Auto-assign from rootKind if not already assigned.
  local roleForRoot = {
    MAIN_BACKPACK = "MAIN",
    QUIVER        = "QUIVER",
  }
  local role = roleForRoot[node.rootKind]
  if role and not self.roleAssignments[role] then
    self.roleAssignments[role] = identity
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Policy State
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:_setPolicyState(state)
  if self.policyState == state then return end
  self.policyState = state
  self:_emit("containers:recovery_policy", {
    state      = state,
    generation = self.stateMachine.generation,
    ts         = os.time(),
  })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:getState()
  return self.stateMachine.state
end

function Discovery:getPolicyState()
  return self.policyState
end

function Discovery:getGeneration()
  return self.stateMachine.generation
end

function Discovery:isReadyFor(level)
  local snap = self:getReadiness()
  return Readiness.meetsLevel(snap.status, level)
end

function Discovery:getReadiness()
  local context = {
    isPaladin       = Quiver.isPaladin(),
    roleAssignments = self.roleAssignments,
  }
  return Readiness.compute(self.registry, self.stateMachine.generation, context)
end

function Discovery:getMetrics()
  local sched = self.scheduler:getStatus()
  return {
    generation       = self.stateMachine.generation,
    policyState      = self.policyState,
    discoveryState   = self.stateMachine.state,
    rootsFound       = self.metrics.rootsFound,
    nodesOpened      = self.metrics.nodesOpened,
    nodesFailed      = self.metrics.nodesFailed,
    retries          = self.metrics.retries,
    exhaustionEvents = self.metrics.exhaustionEvents,
    staleCallbacks   = self.metrics.staleCallbacks,
    queueDepth       = self.bfs:getQueueSize(),
    schedulerLatency = sched.latencyEwmaMs,
    schedulerBackoff = sched.backoffRemaining,
  }
end

function Discovery:setConfig(cfg)
  for k, v in pairs(cfg) do
    self.config[k] = v
  end
end

-- Backward-compatible aliases for legacy callers and old tests.
function Discovery:start()
  return self:startDiscovery()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal Helpers
-- ─────────────────────────────────────────────────────────────────────────────

function Discovery:_generationValid()
  return self.bfs.generation == self.stateMachine.generation
end

function Discovery:_emit(event, payload)
  local eb = self.eventBus
    or (_G.EventBus)
    or (_G.nExBot and _G.nExBot.EventBus)
  if eb and eb.emit then
    eb.emit(event, payload)
  elseif eb and eb.on then
    -- Some EventBus implementations use publish/emit variants.
    local ok = pcall(eb.emit, eb, event, payload)
    if not ok then pcall(eb.publish, eb, event, payload) end
  end
end

function Discovery:_getInventoryItem(slot)
  if _G.getClient then
    local client = _G.getClient()
    if client and client.getInventoryItem then
      return client.getInventoryItem(slot)
    end
  end
  if _G.g_game and _G.g_game.getInventoryItem then
    return _G.g_game.getInventoryItem(slot)
  end
  return nil
end

return Discovery

