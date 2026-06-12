-- loop_guard_v2.lua
-- Ring-buffer waypoint-cycle detector.
-- Records each recovery-focus event and detects oscillation (A→B→A cycling).
-- Integrated into NavigationV2's recovery path to break infinite blacklist loops.

CaveBot = CaveBot or {}

local RING_SIZE       = 8      -- slots in the circular buffer
local CYCLE_THRESHOLD = 3      -- same WP index seen >= this many times in window → cycling
local WINDOW_MS       = 30000  -- 30-second detection window

local LoopGuard = {
  _ring          = {},   -- circular buffer: each slot = { idx=int, t=ms }
  _head          = 0,    -- index of last-written slot (1-based, wraps mod RING_SIZE)
  _size          = 0,    -- number of filled slots (up to RING_SIZE)
  activations    = 0,    -- cumulative count of cycle-break escalations
  lastActivation = 0,    -- `now` timestamp of the last escalation
  COOLDOWN       = 5000, -- ms minimum between consecutive escalations
}

-- Record that NavigationV2 recovery just focused WP at `idx`.
function LoopGuard.recordFocus(idx)
  if not idx then return end
  LoopGuard._head = (LoopGuard._head % RING_SIZE) + 1
  LoopGuard._ring[LoopGuard._head] = { idx = idx, t = now }
  if LoopGuard._size < RING_SIZE then
    LoopGuard._size = LoopGuard._size + 1
  end
end

-- Count appearances of `idx` in the ring within the last WINDOW_MS.
local function countInWindow(idx)
  local cutoff = now - WINDOW_MS
  local n = 0
  for i = 1, LoopGuard._size do
    local slot = LoopGuard._ring[((LoopGuard._head - i) % RING_SIZE) + 1]
    if slot and slot.t >= cutoff and slot.idx == idx then
      n = n + 1
    end
  end
  return n
end

-- Returns true if focusing `idx` again would indicate a repeating cycle.
function LoopGuard.isCycling(idx)
  if not idx then return false end
  return countInWindow(idx) >= CYCLE_THRESHOLD
end

-- Clear the ring buffer (call on config change or confirmed route advance).
function LoopGuard.reset()
  LoopGuard._ring = {}
  LoopGuard._head = 0
  LoopGuard._size = 0
end

-- Record that a cycle was broken via blacklist escalation (for cooldown tracking).
function LoopGuard.markActivation()
  LoopGuard.activations = LoopGuard.activations + 1
  LoopGuard.lastActivation = now
end

-- True if still within cooldown period after the last escalation.
function LoopGuard.isCoolingDown()
  return (now - LoopGuard.lastActivation) < LoopGuard.COOLDOWN
end

function LoopGuard.getMetrics()
  return {
    activations    = LoopGuard.activations,
    lastActivation = LoopGuard.lastActivation,
  }
end

CaveBot.LoopGuard = LoopGuard
return LoopGuard
