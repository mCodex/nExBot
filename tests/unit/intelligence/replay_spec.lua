local Replay = dofile("core/intelligence/observability/replay.lua")

describe("intelligence deterministic replay", function()
  it("bounds, copies, exports, and replays records in order", function()
    local replay = Replay.new(2)
    local first = { events = { { type = "seen" } }, snapshotRef = 1, features = { hp = 90 },
      proposals = { { action = "attack" } }, selected = "attack", rejected = {}, outcome = "hit", reward = 1 }
    replay:record(first)
    first.features.hp = 0
    replay:record({ snapshotRef = 2, selected = "wait", reward = 0 })
    replay:record({ snapshotRef = 3, selected = "move", reward = 0.5 })

    local exported = replay:export()
    assert.equals(2, #exported)
    assert.equals(2, exported[1].snapshotRef)
    exported[1].selected = "changed"
    assert.equals("wait", replay:export()[1].selected)

    local seen = {}
    local results = replay:run(function(record, index)
      seen[#seen + 1] = record.snapshotRef
      return index .. ":" .. record.selected
    end)
    assert.same({ 2, 3 }, seen)
    assert.same({ "1:wait", "2:move" }, results)
  end)

  it("versions imports, rejects corruption, strips runtime values, and exports explicitly", function()
    local replay = Replay.new(2)
    replay:record({ snapshotRef = 7, features = { hp = 50, callback = function() end } })
    local document = replay:exportDocument()
    assert.equals(1, document.schemaVersion)
    assert.is_nil(document.records[1].features.callback)

    assert.is_false(select(1, replay:import({ schemaVersion = 99, records = {} })))
    assert.equals(7, replay:export()[1].snapshotRef)
    assert.is_true(replay:import({ schemaVersion = 1, records = { { snapshotRef = 8 } } }))
    assert.equals(8, replay:export()[1].snapshotRef)

    local written
    local ok, path = replay:exportFile("/tmp/replay.json", {
      writeFileContents = function(file, content) written = { file, content } end,
    }, { encode = function(value) return "schema=" .. value.schemaVersion end })
    assert.is_true(ok)
    assert.equals("/tmp/replay.json", path)
    assert.same({ "/tmp/replay.json", "schema=1" }, written)
  end)
end)
