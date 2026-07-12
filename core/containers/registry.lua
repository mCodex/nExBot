local Registry = {}

function Registry.new()
  return setmetatable({
    candidates = {},
    byState = {},
    itemIndex = {},
    parentToChildren = {},
  }, { __index = Registry })
end

function Registry:add(candidate)
  self.candidates[candidate.identity] = candidate
  if not self.byState[candidate.state] then
    self.byState[candidate.state] = {}
  end
  self.byState[candidate.state][candidate.identity] = true

  if candidate.itemType then
    if not self.itemIndex[candidate.itemType] then
      self.itemIndex[candidate.itemType] = {}
    end
    self.itemIndex[candidate.itemType][candidate.identity] = candidate
  end
end

function Registry:get(identity)
  return self.candidates[identity]
end

function Registry:remove(identity)
  local candidate = self.candidates[identity]
  if not candidate then return end

  self.candidates[identity] = nil
  if self.byState[candidate.state] then
    self.byState[candidate.state][identity] = nil
  end
  if candidate.itemType and self.itemIndex[candidate.itemType] then
    self.itemIndex[candidate.itemType][identity] = nil
  end
end

function Registry:setState(identity, state)
  local candidate = self.candidates[identity]
  if not candidate then return false end

  if self.byState[candidate.state] then
    self.byState[candidate.state][identity] = nil
  end

  candidate.state = state

  if not self.byState[state] then
    self.byState[state] = {}
  end
  self.byState[state][identity] = true
  return true
end

function Registry:countByState(state)
  if not self.byState[state] then return 0 end
  local count = 0
  for _ in pairs(self.byState[state]) do
    count = count + 1
  end
  return count
end

function Registry:findByItemType(itemType)
  local results = {}
  local bucket = self.itemIndex[itemType]
  if bucket then
    for _, candidate in pairs(bucket) do
      results[#results + 1] = candidate
    end
  end
  return results
end

function Registry:setParent(parentId, childId)
  if not self.parentToChildren[parentId] then
    self.parentToChildren[parentId] = {}
  end
  self.parentToChildren[parentId][childId] = true
end

function Registry:getChildren(parentId)
  local children = {}
  local childMap = self.parentToChildren[parentId]
  if childMap then
    for childId in pairs(childMap) do
      local candidate = self.candidates[childId]
      if candidate then
        children[#children + 1] = candidate
      end
    end
  end
  return children
end

function Registry:clear()
  self.candidates = {}
  self.byState = {}
  self.itemIndex = {}
  self.parentToChildren = {}
end

return Registry
