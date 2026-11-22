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
local targetShadowEnabled, pendingTarget, lastTargetSent
RustBridge = RustBridge or {}
RustBridge.targetStats = { samples = 0, matches = 0, stale = 0 }
local connected, sequence, lastProbeId = false, 0, 0
local function close(message)
  if not socket then return end
  generation = generation + 1
  watched, observationPending, lastObservation, latest = nil, false, nil, nil
  routeProbed, sequence, lastProbeId = false, 0, 0
  targetShadowEnabled, pendingTarget, lastTargetSent = false, nil, nil
  connected = false
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

function RustBridge.targetEnabled()
  return connected and targetShadowEnabled
end

function RustBridge.targetShadow(candidates, selected, current)
  if not RustBridge.targetEnabled() then return end
  local captured = g_clock.millis()
  if lastTargetSent and captured - lastTargetSent < 200 then return end
  lastTargetSent = captured
  pendingTarget = { observation = sequence + 1, captured = captured, position = localPosition() }
  emit({ type = "target_shadow", candidates = candidates, selected = selected, current = current })
end

local function samePosition(a, b)
  return a and a.x == b.x and a.y == b.y and a.z == b.z
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
      targetShadowEnabled = message.target_shadow == true
      connected = true
      caveShadow, caveGoal = message.cave_shadow == true, nil
      emit({ type = "snapshot", position = position })
      status("connected and authenticated (diagnostic mode)")
      return
    end

    if message.type == "target_comparison" and targetShadowEnabled then
      local stats = RustBridge.targetStats
      if not pendingTarget or pendingTarget.observation ~= message.observation then
        stats.stale = stats.stale + 1
        return
      end
      local elapsed = g_clock.millis() - pendingTarget.captured
      local fresh = elapsed < 200 and samePosition(localPosition(), pendingTarget.position)
      pendingTarget = nil
      if fresh then
        stats.samples = stats.samples + 1
        stats.lastRoundTripMs = elapsed
        if message.selected == message.suggested then stats.matches = stats.matches + 1 end
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
  if not connected or not caveShadow or not storage or storage.rustCaveShadow ~= true then return end
  if not isPosition(position) or samePosition(caveGoal, position) then return end
  local origin = localPosition()
  if not origin or math.max(math.abs(origin.x - position.x), math.abs(origin.y - position.y)) > 32 then return end
  caveGoal = {x = position.x, y = position.y, z = position.z}
  emit({type = "route_goal", position = caveGoal})
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
