-- Boot Diagnostics: Short-lived, safe instrumentation to capture startup event spikes
-- Enable by setting ProfileStorage.set("bootDiagnostics", true) before restarting the client
-- The module auto-disables itself after one run and writes a small summary to ProfileStorage

local function safeRequire(name)
  local ok, m = pcall(require, name)
  if not ok then return nil end
  return m
end

local function init()
  if not EventBus or not ProfileStorage then
    -- Delay init slightly until core modules are ready
    schedule(200, init)
    return
  end

  local enabled = ProfileStorage.get("bootDiagnostics")
  if not enabled then return end

  -- Disable the flag so it doesn't run repeatedly
  ProfileStorage.set("bootDiagnostics", false)

  local durationMs = 10000 -- total monitoring duration
  local intervalMs = 100 -- sampling interval
  local maxQueue = 0
  local maxMem = 0
  local appearCount = 0

  local unsub = EventBus.on("creature:appear", function() appearCount = appearCount + 1 end)

  local startTime = os.clock() * 1000
  local function sample()
    local now = os.clock() * 1000
    local q = (EventBus.queueSize and EventBus.queueSize()) or 0
    local mem = collectgarbage("count") or 0
    if q > maxQueue then maxQueue = q end
    if mem > maxMem then maxMem = mem end

    if (now - startTime) >= durationMs then
      -- Summary
      local summary = string.format("appear=%d, maxQueue=%d, maxMem=%.1fKB", appearCount, maxQueue, maxMem)
      warn("[BootDiagnostics] " .. summary)
      -- Persist last run summary for user inspection
      local ok, err = pcall(function()
        ProfileStorage.set("bootDiagnosticsLast", {appear = appearCount, maxQueue = maxQueue, maxMemKB = maxMem})
      end)
      if not ok then warn("[BootDiagnostics] failed to save summary: " .. tostring(err)) end
      if unsub then pcall(unsub) end
      return
    end

    schedule(intervalMs, sample)
  end

  -- Start sampling immediately
  schedule(0, sample)
end

-- Safe init
init()