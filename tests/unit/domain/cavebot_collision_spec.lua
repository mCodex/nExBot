describe("CaveBot first-step collision", function()
  local original
  local currentPosition
  local emitted
  local advances
  local cursor
  local canWalk
  local receivedCanWalkArgument
  local walkable
  local acceptsWalk
  local field
  local path

  before_each(function()
    original = {}
    for _, name in ipairs({ "CaveBot", "Directions", "East", "nExBot", "now", "onPlayerPositionChange",
      "PathUtils", "player", "pos", "walk", "nExBotRuntime" }) do
      original[#original + 1] = { name, _G[name] }
    end

    currentPosition = { x = 100, y = 100, z = 7 }
    emitted, advances = 0, 0
    canWalk, walkable, acceptsWalk = true, true, true
    receivedCanWalkArgument = nil
    field, path = false, { 1 }
    cursor = nil
    _G.CaveBot = {}
    _G.Directions = { DIR_TO_OFFSET = { [1] = { x = 1, y = 0 } } }
    _G.East = 1
    _G.now = 1000
    _G.onPlayerPositionChange = function() end
    _G.pos = function() return currentPosition end
    _G.walk = function() emitted = emitted + 1 end
    _G.player = {
      isWalking = function() return false end,
      canWalk = function(_, argument)
        receivedCanWalkArgument = argument
        return canWalk
      end,
    }
    _G.PathUtils = {
      isFloorChangeTile = function() return false end,
      isFieldTile = function() return field end,
      isTileWalkable = function() return walkable end,
    }
    _G.nExBot = {
      clientName = "OpenTibiaBR",
      Shared = { getClient = function() end },
      PathStrategy = {
        resetDirectionState = function() end,
        isCursorValid = function() return cursor ~= nil end,
        getCursor = function() return cursor end,
        resetCursor = function() cursor = nil end,
        setCursor = function(path) cursor = { path = path, idx = 1 } end,
        findPath = function() return path end,
        smoothPath = function() end,
        smoothDirection = function(direction) return direction end,
        safeStepCount = function() return #path end,
        rawStepDuration = function() return 180 end,
        advanceCursor = function() advances = advances + 1 end,
        walkStep = function()
          emitted = emitted + 1
          return acceptsWalk
        end,
      },
    }

    dofile("cavebot/walking.lua")
  end)

  after_each(function()
    for _, entry in ipairs(original) do _G[entry[1]] = entry[2] end
  end)

  local function walkEast()
    return CaveBot.walkTo({ x = 101, y = 100, z = 7 }, 20, { precision = 0 })
  end

  it("does not walk when the client rejects movement", function()
    canWalk = false
    assert.is_false(walkEast())
    assert.equals(0, emitted)
  end)

  it("does not dispatch the first step of a path through a blocked tile", function()
    walkable = false
    assert.is_false(walkEast())
    assert.equals(0, emitted)
  end)

  it("does not advance the path cursor after dispatch rejects a step", function()
    acceptsWalk = false
    assert.is_false(walkEast())
    assert.equals(0, advances)
    assert.equals(1, emitted)
  end)

  it("dispatches only one checked step through consecutive fields", function()
    field, path = true, { 1, 1, 1 }
    assert.is_true(CaveBot.walkTo({ x = 103, y = 100, z = 7 }, 20, { precision = 0, ignoreFields = true }))
    assert.equals(1, emitted)
    assert.equals(1, advances)
  end)

  it("dispatches the segment selected by Rust without skipping native validation", function()
    path = { 1, 1, 1, 1 }
    local strategy = nExBot.PathStrategy
    local destination = { x = 103, y = 100, z = 7 }
    strategy.chunkDestination = function(_, _, _, steps)
      assert.equals(3, steps)
      return destination
    end
    strategy.nativePathIsSafe = function(_, target)
      assert.same(destination, target)
      return true
    end
    strategy.autoWalk = function(target)
      assert.same(destination, target)
      emitted = emitted + 1
      return true
    end
    _G.nExBotRuntime = { decide = function(operation, observation)
      assert.equals("movement_dispatch", operation)
      assert.same({ safe_steps = 4, field_ahead = false, allow_segment = true }, observation)
      return 3
    end }

    assert.is_true(CaveBot.walkTo({ x = 104, y = 100, z = 7 }, 20, { precision = 0 }))
    assert.equals(1, emitted)
    assert.equals(1, advances)
  end)

  it("rejects a Rust segment crossing a checked field", function()
    field, path = true, { 1, 1, 1 }
    _G.nExBotRuntime = { decide = function() return 3 end }
    assert.is_false(CaveBot.walkTo({ x = 103, y = 100, z = 7 }, 20, { precision = 0, ignoreFields = true }))
    assert.equals(0, emitted)
    assert.equals(0, advances)
  end)

  it("dispatches an allowed step", function()
    assert.is_true(walkEast())
    assert.equals(1, emitted)
    assert.equals(1, advances)
  end)

  it("calls the client-specific movement API without bypassing locks", function()
    assert.is_true(walkEast())
    assert.is_false(receivedCanWalkArgument)

    nExBot.clientName = "OTCv8"
    assert.is_true(walkEast())
    assert.equals(1, receivedCanWalkArgument)
  end)
end)

describe("PathStrategy recovery flags", function()
  it("recomputes flags when a retry changes the collision options", function()
    local oldDirections, oldBot, oldMap, oldFindPath = Directions, nExBot, g_map, findPath
    local strategy
    local flagsUsed = {}
    _G.Directions, _G.nExBot, _G.findPath = {}, {}, nil
    _G.g_map = {
      findPath = function(_, _, _, flags)
        flagsUsed[#flagsUsed + 1] = flags
      end,
    }
    strategy = dofile("utils/path_strategy.lua")

    local options = { ignoreCreatures = false }
    local start, goal = { x = 100, y = 100, z = 7 }, { x = 105, y = 100, z = 7 }
    strategy.findPath(start, goal, options)
    options.ignoreCreatures = true
    strategy.findPath(start, goal, options)
    _G.Directions, _G.nExBot, _G.g_map, _G.findPath = oldDirections, oldBot, oldMap, oldFindPath

    assert.same({ 0, 16 }, flagsUsed)
  end)
end)
