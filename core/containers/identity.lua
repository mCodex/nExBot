local Identity = {}

function Identity.make(generation, rootKind, parentId, slotIndex, itemType, version)
  return string.format("%d:%s:%s:%d:%d:%s",
    generation, rootKind, parentId or "none", slotIndex or 0, itemType or 0, version or "0")
end

function Identity.parse(id)
  local gen, root, parent, slot, item, ver = id:match("^(%d+):([^:]+):([^:]+):(%d+):(%d+):(.+)$")
  return {
    generation = tonumber(gen),
    rootKind = root,
    parentId = parent,
    slotIndex = tonumber(slot),
    itemType = tonumber(item),
    version = ver,
  }
end

function Identity.matches(id, fields)
  local parts = Identity.parse(id)
  for k, v in pairs(fields) do
    if parts[k] ~= v then return false end
  end
  return true
end

return Identity
