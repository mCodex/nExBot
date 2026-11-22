describe("visible monster registry", function()
  it("reuses snapshots, handles duplicate and stale events, and reconciles every floor", function()
    local env = setmetatable({nExBot = {}}, {__index = _G})
    local VisibleMonsters = assert(loadfile("core/visible_monsters.lua", "t", env))()
    local center = {x = 50, y = 50, z = 7}
    local a = {id = 4, pos = center}
    local b = {id = 5, pos = {x = 51, y = 50, z = 7}}
    local native, scans = {a, b}, 0
    local index = VisibleMonsters.new({
      range = 14, reconcileMs = 1000,
      id = function(creature) return creature.id end,
      position = function(creature) return creature.pos end,
      eligible = function(creature) return not creature.dead end,
      scan = function() scans = scans + 1; return native end,
    })

    local count, visible = index.get(center, 0)
    assert.equals(2, count)
    assert.is_false(index.update(a, a.pos))
    local _, unchanged = index.get(center, 50)
    assert.equals(visible, unchanged)
    assert.equals(1, scans)

    local replacement = {id = a.id, pos = center}
    assert.is_true(index.update(replacement, center))
    assert.is_false(index.remove(a))
    assert.is_true(index.remove(replacement))
    assert.equals(1, index.get(center, 80))
    assert.equals(2, #visible)
    assert.is_true(index.update(b, {x = 65, y = 50, z = 7}))
    assert.equals(0, index.get(center, 90))
    assert.equals(1, scans)

    native = {b}
    assert.equals(1, index.get(center, 1000))
    assert.equals(0, index.get({x = 50, y = 50, z = 8}, 1001))
    assert.equals(3, scans)
  end)
end)
