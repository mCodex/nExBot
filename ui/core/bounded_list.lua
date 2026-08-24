--[[
  BoundedList — top-K bounded collection for list rendering.

  Guarantees a stable, bounded widget count when rendering rows: callers add
  records and the list evicts overflow by insertion order. Never renders the
  full domain record set.
]]

local BoundedList = {}
BoundedList.__index = BoundedList

function BoundedList.new(max)
  assert(type(max) == "number" and max > 0, "max rows must be > 0")
  return setmetatable({ max = math.floor(max), items = {} }, BoundedList)
end

function BoundedList:add(item)
  local items = self.items
  if #items >= self.max then
    table.remove(items, 1)
  end
  items[#items + 1] = item
end

function BoundedList:clear()
  self.items = {}
end

function BoundedList:count()
  return #self.items
end

function BoundedList:getItems()
  return self.items
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.core.bounded_list"] = BoundedList
end

return BoundedList
