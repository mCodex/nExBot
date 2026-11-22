local VERSION = "5.0.0-alpha.1"
local function status(message)
  print("[nExBot] Rust bridge v" .. VERSION .. " - " .. message)
end

if not HTTP or not HTTP.WebSocket or not json or not json.decode
  or not configDir or not _websockets or not onPlayerPositionChange or not schedule then
  status("bridge unavailable in this client")
  return
end

local token, proof
local socket, connect
local generation = 0
local watched, observationPending, lastObservation, latest
local watchingEnabled, routeProbed = false, false
local refillEnabled, pendingRefill
local lootAnalyticsEnabled
local containerMetricsEnabled
local lastHealSample
local lastHealSpell
local healTiming
local targetShadowEnabled, pendingTarget, lastTargetSample, rankedTarget
local pendingFiring, lastFiringSample
RustBridge = RustBridge or {}
RustBridge.firingStats = { samples = 0, matches = 0 }
RustBridge.targetStats = { samples = 0, matches = 0, stale = 0 }
local connected, sequence, lastProbeId = false, 0, 0
local function close(message)
  if not socket then return end
  generation = generation + 1
  healTiming, lastHealSample, lastHealSpell = false, nil, nil
  watched, observationPending, lastObservation, latest = nil, false, nil, nil
  routeProbed, sequence, lastProbeId = false, 0, 0
  targetShadowEnabled, pendingTarget, lastTargetSample, rankedTarget = false, nil, nil, nil
  refillEnabled, pendingRefill = false, nil
  connected, containerMetricsEnabled, lootAnalyticsEnabled = false, false, false
  local previous = socket
  socket = nil
  _websockets[previous.id] = nil
  previous.close()
  status(message)
  schedule(1000, connect)
end

local function emit(frame)
  sequence = sequence + 1
  frame.sequence = sequence
  socket.send(frame)
end

function RustBridge.observeReopen(metrics)
  if not connected or not containerMetricsEnabled then return end
  local current = generation
  schedule(0, function()
    if current ~= generation or not connected then return end
    emit({type = "container_metrics", metrics = metrics})
  end)
end

function RustBridge.measureHeal()
  return connected and healTiming and storage and storage.rustHealTiming == true
end

function RustBridge.sampleHeal()
  if not connected or not healTiming or not storage or storage.rustHealComparison ~= true then return false end
  local t = g_clock.realMillis()
  if lastHealSample and t - lastHealSample < 1000 then return false end
  lastHealSample = t
  return true
end

function RustBridge.observeHeal(frame)
  local current = generation
  schedule(0, function()
    if current == generation and connected and healTiming then emit(frame) end
  end)
end

function RustBridge.healDispatch(elapsed, action)
  if not RustBridge.measureHeal() then return end
  if action.kind == "spell" then
    lastHealSpell = {key = action.name:lower(), sent = g_clock.realMillis()}
  end
  RustBridge.observeHeal({type = "heal_dispatch", elapsed_ms = elapsed})
end

if onTalk then
  onTalk(function(name, _, _, text)
    if not lastHealSpell or not RustBridge.measureHeal() or not player or name ~= player:getName() then return end
    if text:lower() ~= lastHealSpell.key then return end
    local elapsed = g_clock.realMillis() - lastHealSpell.sent
    lastHealSpell = nil
    if elapsed >= 0 and elapsed <= 2000 then
      RustBridge.observeHeal({type = "heal_dispatch", elapsed_ms = elapsed, echo = true})
    end
  end)
end

local function localPosition()
  if not g_game.isOnline() then return nil end
  local player = g_game.getLocalPlayer()
  return player and player:getPosition()
end

local function isCoordinate(value, max)
  return type(value) == "number" and value >= 0 and value <= max and value % 1 == 0
end

local function isPosition(value)
  return type(value) == "table" and isCoordinate(value.x, 65535)
    and isCoordinate(value.y, 65535) and isCoordinate(value.z, 15)
end

function RustBridge.supplyRefill(stock, key)
  if not connected or not refillEnabled or #stock > 48 then return end
  local clock = g_clock.millis()
  if pendingRefill then
    local request = pendingRefill
    pendingRefill = nil
    if request.key == key and request.reply and clock - request.sent <= 250 then
      return "ready", request.reply.purchase
    end
    return
  end
  pendingRefill = {observation = sequence + 1, sent = clock, key = key}
  emit({type = "supply_refill", stock = stock})
  return "pending"
end

function RustBridge.targetEnabled()
  return connected and targetShadowEnabled
end

function RustBridge.useTargetRanking()
  return RustBridge.targetEnabled() and storage and storage.rustTargetRanking == true
end

function RustBridge.beginTargetSample()
  if not RustBridge.targetEnabled() then return false end
  local captured = g_clock.millis()
  if lastTargetSample and captured - lastTargetSample < 200 then return false end
  lastTargetSample = captured
  return true
end

function RustBridge.targetShadow(candidates, selected, current)
  if not RustBridge.targetEnabled() then return end
  local captured = g_clock.millis()
  local byId = {}
  for _, candidate in ipairs(candidates) do byId[candidate.id] = candidate end
  pendingTarget = {
    observation = sequence + 1, captured = captured, position = localPosition(),
    candidates = byId, count = #candidates, current = current, selected = selected,
  }
  emit({ type = "target_shadow", candidates = candidates, selected = selected, current = current })
end

function RustBridge.beginFiringSample()
  if not RustBridge.targetEnabled() then return false end
  local captured = g_clock.millis()
  if lastFiringSample and captured - lastFiringSample < 1000 then return false end
  lastFiringSample = captured
  return true
end

function RustBridge.firingShadow(target, min, max, selected, positions)
  if not RustBridge.targetEnabled() then return end
  pendingFiring = { observation = sequence + 1, sent = g_clock.millis() }
  emit({ type = "firing_shadow", target = target, min = min, max = max, selected = selected, positions = positions })
end

local function samePosition(a, b)
  return a and a.x == b.x and a.y == b.y and a.z == b.z
end

function RustBridge.rankedTarget(candidates, current)
  local result = rankedTarget
  if not RustBridge.useTargetRanking() or not result or result.changed
    or g_clock.millis() - result.captured >= 200 or result.current ~= current
    or result.count ~= #candidates or not samePosition(result.position, localPosition()) then return end

  for _, candidate in ipairs(candidates) do
    local captured = result.candidates[candidate.id]
    if not captured or not samePosition(captured.position, candidate.position)
      or captured.priority ~= candidate.priority or captured.hp ~= candidate.hp
      or captured.cost ~= candidate.cost or captured.sight ~= candidate.sight then return end
  end
  return result.suggested
end

local function observeTile()
  if not watched or observationPending then return end
  observationPending = true
  local current = generation
  schedule(25, function()
    if current ~= generation then return end
    observationPending = false
    if not connected or not watched then return end
    local tile = g_map.getTile(watched)
    local walkable, ignoreCreatures
    if tile then
      local normalOk, normal = pcall(tile.isWalkable, tile, false)
      local ignoredOk, ignored = pcall(tile.isWalkable, tile, true)
      if normalOk and ignoredOk and type(normal) == "boolean" and type(ignored) == "boolean" then
        walkable, ignoreCreatures = normal, ignored
      end
    end
    local observation = tostring(walkable) .. tostring(ignoreCreatures)
    if lastObservation ~= observation then
      lastObservation = observation
      emit({ type = "tile", position = watched, walkable = walkable, ignore_creatures = ignoreCreatures })
    end
  end)
end

local function watch(position)
  if not g_map.getTile then return end
  watched, lastObservation = position, nil
  if not watchingEnabled then
    watchingEnabled = true
    local function tileChanged(tile)
      if connected and watched and tile and samePosition(tile:getPosition(), watched) then observeTile() end
    end
    if onAddThing then onAddThing(tileChanged) end
    if onRemoveThing then onRemoveThing(tileChanged) end
  end
  observeTile()
end

local caveShadow, caveGoal
local pathProbe = g_map and type(g_map.findPath) == "function" or false
local callbacks = {
  onOpen = function()
    if not socket or not token then return end
    socket.send({ type = "hello", protocol = 1, token = token, bridge_version = VERSION, path_probe = pathProbe })
    token = nil
  end,
  onMessage = function(raw)
    if not socket then return end
    if type(raw) ~= "string" or #raw > 4096 then
      return close("invalid response")
    end
    local ok, message = pcall(json.decode, raw)
    if not ok or type(message) ~= "table" then
      return close("invalid response")
    end

    if not connected then
      if message.type ~= "ready" or message.protocol ~= 1 or message.proof ~= proof then
        return close("authentication failed")
      end

      proof = nil
      local position = localPosition()
      if not isPosition(position) then return close("character unavailable") end
      healTiming = message.heal_timing == true
      targetShadowEnabled = message.target_shadow == true
      containerMetricsEnabled = message.container_metrics == true
      lootAnalyticsEnabled = message.loot_analytics == true
      refillEnabled = message.supply_refill == true
      RustBridge.lootStats = {total = {reports = 0, nonempty = 0}, byMonster = {}}
      connected = true
      caveShadow, caveGoal = message.cave_shadow == true, nil
      emit({ type = "snapshot", position = position })
      status("connected and authenticated (diagnostic mode)")
      return
    end

    if message.type == "supply_refill_plan" and refillEnabled then
      if pendingRefill and pendingRefill.observation == message.observation then
        pendingRefill.reply = message
      end
      return
    end

    if message.type == "loot_summary" and lootAnalyticsEnabled then
      local stats = RustBridge.lootStats
      stats.total = message.total
      if type(message.monster_total) == "table" then
        stats.byMonster[message.monster] = message.monster_total
      end
      return
    end

    if message.type == "firing_comparison" and targetShadowEnabled then
      if pendingFiring and pendingFiring.observation == message.observation
        and g_clock.millis() - pendingFiring.sent < 200 then
        local stats = RustBridge.firingStats
        stats.samples = stats.samples + 1
        if message.matches == true then stats.matches = stats.matches + 1 end
        pendingFiring = nil
      end
      return
    end

    if message.type == "target_comparison" and targetShadowEnabled then
      local stats = RustBridge.targetStats
      if not pendingTarget or pendingTarget.observation ~= message.observation then
        stats.stale = stats.stale + 1
        return
      end
      local sample = pendingTarget
      pendingTarget = nil
      local elapsed = g_clock.millis() - sample.captured
      local fresh = not sample.changed and elapsed < 200 and samePosition(localPosition(), sample.position)
      if fresh then
        stats.samples = stats.samples + 1
        stats.lastRoundTripMs = elapsed
        if message.selected == message.suggested then stats.matches = stats.matches + 1 end
        if RustBridge.useTargetRanking() and message.selected == sample.selected
          and isCoordinate(message.suggested, 4294967295)
          and sample.candidates[message.suggested] and sample.candidates[message.suggested].priority > 0 then
          sample.suggested = message.suggested
          rankedTarget = sample
        else
          rankedTarget = nil
        end
      else
        stats.stale = stats.stale + 1
      end
      return
    end

    if message.type == "watch_tile" then
      if not routeProbed or not isPosition(message.position) then return close("invalid tile") end
      local player = localPosition()
      local tile = message.position
      if player and player.z == tile.z and math.max(math.abs(player.x - tile.x), math.abs(player.y - tile.y)) <= 1 then
        watch(tile)
      end
      return
    end

    local origin, destination = message.origin, message.destination
    local route = message.type == "route_probe"
    if (not route and message.type ~= "probe") or not pathProbe
      or not isCoordinate(message.id, 4294967295) or message.id <= lastProbeId
      or not isPosition(origin) or not isPosition(destination) or origin.z ~= destination.z then
      return close("invalid command")
    end

    local dx, dy = math.abs(origin.x - destination.x), math.abs(origin.y - destination.y)
    if (route and (math.max(dx, dy) > 32 or dx + dy == 0))
      or (not route and (message.id ~= 1 or dy ~= 0 or dx ~= 1)) then
      return close("invalid destination")
    end

    lastProbeId = message.id
    watched = nil
    routeProbed = routeProbed or route
    local current = generation
    schedule(0, function()
      if current ~= generation then return end
      if not connected then return end
      local frame = { type = route and "route_ack" or "ack", id = message.id }
      if samePosition(localPosition(), origin) then
        local valid, directions, result = pcall(g_map.findPath, origin, destination, route and 512 or 16, 0)
        if route then
          if valid and result == 0 and type(directions) == "table" and #directions <= 64 then
            frame.directions = directions
          end
        elseif valid and isCoordinate(result, 4) then
          frame.path_result = result
        end
      end
      emit(frame)
    end)
  end,
  onError = function() close("connection failed") end,
  onClose = function() close("disconnected") end,
}

onPlayerPositionChange(function(position)
  if connected and isPosition(position) then
    if pendingTarget then pendingTarget.changed = true end
    rankedTarget = nil
    emit({ type = "move", position = position })
  end
end)

-- Coalesce movement within each 50 ms window by creature ID.
if onCreaturePositionChange then
  onCreaturePositionChange(function(creature, position, previous)
    if connected and watched and (samePosition(previous, watched) or samePosition(position, watched)) then
      observeTile()
    end
    if not connected or not creature or creature == g_game.getLocalPlayer() or not isPosition(position) then return end
    local id = creature:getId()
    if not isCoordinate(id, 4294967295) or id == 0 then return end
    if pendingTarget and pendingTarget.candidates[id] and not samePosition(pendingTarget.candidates[id].position, position) then
      pendingTarget.changed = true
    end
    if rankedTarget and rankedTarget.candidates[id] and not samePosition(rankedTarget.candidates[id].position, position) then
      rankedTarget.changed = true
    end
    if not latest then
      local current = generation
      schedule(50, function()
        if current ~= generation then return end
        local frame = latest
        latest = nil
        if connected then
          for _, movement in pairs(frame) do emit(movement) end
        end
      end)
    end
    latest = latest or {}
    latest[id] = { type = "creature_move", id = id, position = position }
  end)
end

RustBridge = RustBridge or {}
function RustBridge.caveGoal(position)
  if not connected or not caveShadow then return end
  if not position or not storage or storage.rustCaveShadow ~= true then
    if caveGoal then
      caveGoal, watched = nil, nil
      emit({type = "route_goal"})
    end
    return
  end
  if not isPosition(position) or samePosition(caveGoal, position) then return end
  local origin = localPosition()
  if not origin or math.max(math.abs(origin.x - position.x), math.abs(origin.y - position.y)) > 32 then return end
  caveGoal = {x = position.x, y = position.y, z = position.z}
  emit({type = "route_goal", position = caveGoal})
end

if EventBus then
  EventBus.on("loot:received", function(monster, items)
    if not connected or not lootAnalyticsEnabled or not storage or storage.rustLootAnalytics ~= true then return end
    monster = monster:lower():match("^%s*(.-)%s*$")
    if #monster == 0 or #monster > 96 or monster:find("%c") then return end
    items = items:lower():match("^%s*(.-)%s*$")
    emit({type = "loot_report", monster = monster, nonempty = items ~= "" and items ~= "nothing"})
  end)
end

local manual = configDir .. "/rust-session"
local service = configDir .. "/rust-service-session"
local waiting = false
connect = function()
  local rendezvous = g_resources.fileExists(service) and service or manual
  if not g_resources.fileExists(rendezvous) then
    if not waiting then
      waiting = true
      status("waiting for the local Rust engine")
    end
    schedule(1000, connect)
    return
  end

  local port
  local ok, config = pcall(g_resources.readFileContents, rendezvous)
  if not ok or type(config) ~= "string" then
    schedule(1000, connect)
    return
  end
  port, token, proof = config:match("^(%d+)\n([a-f0-9]+)\n([a-f0-9]+)\n$")
  port = tonumber(port)
  if not port or port < 1 or port > 65535 or #token ~= 64 or #proof ~= 64 then
    schedule(1000, connect)
    return
  end

  local current = generation
  local handlers = {}
  for name, callback in pairs(callbacks) do
    handlers[name] = function(...)
      if current == generation then return callback(...) end
    end
  end
  local started
  started, socket = pcall(HTTP.WebSocket, "ws://127.0.0.1:" .. port .. "/", handlers, 5)
  if not started or not socket or type(socket.id) ~= "number" or socket.id < 0 then
    socket = nil
    generation = generation + 1
    status("could not open WebSocket")
    schedule(1000, connect)
    return
  end

  _websockets[socket.id] = socket
  status("connecting")
end

connect()
