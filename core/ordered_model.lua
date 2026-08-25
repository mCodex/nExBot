local OrderedModel = {}
OrderedModel.__index = OrderedModel

local function entry(model, value)
  local item = value or {}
  function item:setText(text) self.text = tostring(text or "") end
  function item:getText() return self.text or "" end
  function item:setColor(color) self.color = color end
  function item:focus() model:focus(self) end
  function item:destroy() return model:remove(self) end
  return item
end

function OrderedModel.new()
  return setmetatable({ items = {}, focused = nil, revision = 0, focusListeners = {} }, OrderedModel)
end

function OrderedModel:add(value, focus)
  local item = entry(self, value)
  self.items[#self.items + 1] = item
  self.revision = self.revision + 1
  if focus then self.focused = item end
  return item
end

function OrderedModel:remove(item)
  local index = self:getChildIndex(item)
  if index < 1 then return false end
  table.remove(self.items, index)
  if self.focused == item then
    local nextFocused = self.items[index] or self.items[index - 1]
    self.focused = nextFocused
    for _, listener in ipairs(self.focusListeners) do listener(nextFocused, item) end
  end
  self.revision = self.revision + 1
  return true
end

function OrderedModel:clear()
  self.items = {}
  self.focused = nil
  self.revision = self.revision + 1
end

function OrderedModel:getChildren() return self.items end
function OrderedModel:getChildCount() return #self.items end
function OrderedModel:getChildByIndex(index) return self.items[index] end
function OrderedModel:getFirstChild() return self.items[1] end
function OrderedModel:getFocusedChild() return self.focused end
function OrderedModel:getRevision() return self.revision end

function OrderedModel:getChildIndex(item)
  if not item then return -1 end
  for index = 1, #self.items do
    if self.items[index] == item then return index end
  end
  return -1
end

function OrderedModel:focus(item)
  if self:getChildIndex(item) < 1 then return false end
  local previous = self.focused
  self.focused = item
  self.revision = self.revision + 1
  if previous ~= item then
    for _, listener in ipairs(self.focusListeners) do listener(item, previous) end
  end
  return true
end

function OrderedModel:onFocusChange(listener)
  if type(listener) ~= "function" then return false end
  self.focusListeners[#self.focusListeners + 1] = listener
  return true
end

function OrderedModel:move(item, index)
  local current = self:getChildIndex(item)
  if current < 1 then return false end
  index = math.max(1, math.min(tonumber(index) or current, #self.items))
  if current == index then return true end
  table.remove(self.items, current)
  table.insert(self.items, index, item)
  self.revision = self.revision + 1
  return true
end

-- Temporary method names retained for private scripts during the atomic cutover.
OrderedModel.destroyChildren = OrderedModel.clear
OrderedModel.focusChild = OrderedModel.focus
OrderedModel.moveChildToIndex = OrderedModel.move
function OrderedModel:ensureChildVisible() end

nExBot.OrderedModel = OrderedModel
return OrderedModel
