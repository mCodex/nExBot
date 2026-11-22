-- Screen membership is independent of pathfinding and of the tactical cache.
local VisibleMonsters = {}

function VisibleMonsters.new(observe)
  local byId, slots, list = {}, {}, {}
  local snapshot, center, reconciledAt

  local function remove(id, creature)
    local index = slots[id]
    if not index or (creature and list[index] ~= creature) then return false end
    local last = #list
    if index ~= last then
      local moved = list[last]
      list[index] = moved
      slots[observe.id(moved)] = index
    end
    list[last], slots[id], byId[id] = nil, nil, nil
    snapshot = nil
    return true
  end

  local function update(creature, position)
    if not center then return false end
    local id = observe.id(creature)
    if not id then return false end
    if not position or position.z ~= center.z
        or math.abs(position.x - center.x) > observe.range
        or math.abs(position.y - center.y) > observe.range
        or not observe.eligible(creature) then
      return remove(id, creature)
    end
    if byId[id] == creature then return false end
    if not slots[id] then slots[id] = #list + 1 end
    byId[id], list[slots[id]], snapshot = creature, creature, nil
    return true
  end

  local function reset()
    byId, slots, list = {}, {}, {}
    snapshot, center, reconciledAt = nil, nil, nil
  end

  local function get(position, time)
    if not position then reset(); return 0, {} end
    if not center or position.x ~= center.x or position.y ~= center.y or position.z ~= center.z
        or time < reconciledAt or time - reconciledAt >= observe.reconcileMs then
      reset()
      center, reconciledAt = position, time
      for _, creature in pairs(observe.scan(position) or {}) do
        update(creature, observe.position(creature))
      end
    end

    if not snapshot then
      snapshot = {}
      for i = 1, #list do snapshot[i] = list[i] end
    end
    return #list, snapshot
  end

  return {
    get = get, reset = reset, update = update,
    count = function() return #list end,
    remove = function(creature) return remove(observe.id(creature), creature) end,
  }
end

nExBot.VisibleMonsters = VisibleMonsters
return VisibleMonsters
