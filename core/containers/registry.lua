-- registry.lua
-- Physical container registry.  Owns: container identities, open/closed state,
-- parent/child edges, role assignments, incremental item index.
-- All operations O(1) average.

local Registry = {}

function Registry.new()
  return setmetatable({
    candidates      = {},   -- identity → candidate
    byState         = {},   -- state → {identity → true}
    itemIndex       = {},   -- itemType → {identity → candidate}
    parentToChildren= {},   -- parentIdentity → {childIdentity → true}
    roleIndex       = {},   -- role → identity
    -- Flat item-slot index: containerIdentity → slotIndex → item
    slotIndex_      = {},
    -- Item type → list of {containerIdentity, slotIndex}
    itemTypeSlots   = {},
  }, { __index = Registry })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Candidate management
-- ─────────────────────────────────────────────────────────────────────────────

function Registry:add(candidate)
  self.candidates[candidate.identity] = candidate
  self:_addToStateIndex(candidate.state, candidate.identity)
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
  self:_removeFromStateIndex(candidate.state, identity)
  if candidate.itemType and self.itemIndex[candidate.itemType] then
    self.itemIndex[candidate.itemType][identity] = nil
  end
  -- Remove role binding.
  if candidate.role then
    if self.roleIndex[candidate.role] == identity then
      self.roleIndex[candidate.role] = nil
    end
  end
end

function Registry:setState(identity, state)
  local candidate = self.candidates[identity]
  if not candidate then return false end
  self:_removeFromStateIndex(candidate.state, identity)
  candidate.state = state
  self:_addToStateIndex(state, identity)
  return true
end

function Registry:countByState(state)
  if not self.byState[state] then return 0 end
  local count = 0
  for _ in pairs(self.byState[state]) do count = count + 1 end
  return count
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Item indexing (slot-level)
-- ─────────────────────────────────────────────────────────────────────────────

-- Index a single item slot inside a container.
-- containerIdentity : physical identity of the container
-- slotIndex         : 0-based slot number
-- item              : client item object (duck-typed: must respond to :getId())
function Registry:indexItem(containerIdentity, slotIndex, item)
  if not item then return end
  local ok, itemType = pcall(function() return item:getId() end)
  if not ok then return end

  -- Slot index.
  if not self.slotIndex_[containerIdentity] then
    self.slotIndex_[containerIdentity] = {}
  end
  self.slotIndex_[containerIdentity][slotIndex] = item

  -- Type-based lookup.
  if not self.itemTypeSlots[itemType] then
    self.itemTypeSlots[itemType] = {}
  end
  -- Remove stale entry for same container+slot if type changed.
  for i, entry in ipairs(self.itemTypeSlots[itemType]) do
    if entry.containerIdentity == containerIdentity and entry.slotIndex == slotIndex then
      table.remove(self.itemTypeSlots[itemType], i)
      break
    end
  end
  table.insert(self.itemTypeSlots[itemType], {
    containerIdentity = containerIdentity,
    slotIndex         = slotIndex,
    item              = item,
  })
end

-- Returns the first indexed slot for the given item type, or nil.
-- Suitable for finding the first available ammo source.
function Registry:findItemByType(itemType)
  local slots = self.itemTypeSlots[itemType]
  if not slots or #slots == 0 then return nil end
  return slots[1]
end

-- Returns all indexed slots for the given item type.
function Registry:findAllByItemType(itemType)
  return self.itemTypeSlots[itemType] or {}
end

-- Returns the item at a specific container slot, or nil.
function Registry:getSlotItem(containerIdentity, slotIndex)
  local c = self.slotIndex_[containerIdentity]
  return c and c[slotIndex] or nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Parent / child edges
-- ─────────────────────────────────────────────────────────────────────────────

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
      local c = self.candidates[childId]
      if c then children[#children + 1] = c end
    end
  end
  return children
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Role assignment
-- ─────────────────────────────────────────────────────────────────────────────

-- Assign a role to a physical container identity.
-- role     : string constant (e.g. "MAIN", "QUIVER", "AMMO_RESERVE")
-- identity : physical identity string
function Registry:assignRole(role, identity)
  self.roleIndex[role] = identity
  local candidate = self.candidates[identity]
  if candidate then candidate.role = role end
end

-- Returns the identity assigned to a role, or nil.
function Registry:getRoleIdentity(role)
  return self.roleIndex[role]
end

-- Returns the candidate assigned to a role, or nil.
function Registry:getByRole(role)
  local identity = self.roleIndex[role]
  return identity and self.candidates[identity] or nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lookup helpers
-- ─────────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function Registry:clear()
  self.candidates       = {}
  self.byState          = {}
  self.itemIndex        = {}
  self.parentToChildren = {}
  self.roleIndex        = {}
  self.slotIndex_       = {}
  self.itemTypeSlots    = {}
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal
-- ─────────────────────────────────────────────────────────────────────────────

function Registry:_addToStateIndex(state, identity)
  if not state then return end
  if not self.byState[state] then self.byState[state] = {} end
  self.byState[state][identity] = true
end

function Registry:_removeFromStateIndex(state, identity)
  if not state then return end
  if self.byState[state] then
    self.byState[state][identity] = nil
  end
end

return Registry

