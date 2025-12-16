-- inventory_utils.lua: recursive inventory search for OTClient

local function findItemInContainer(container, itemId)
  for _, item in ipairs(container:getItems() or {}) do
    if item:getId() == itemId then
      return item
    end
    if item:isContainer() then
      local found = findItemInContainer(item, itemId)
      if found then return found end
    end
  end
  return nil
end

function findItem(itemId)
  for _, container in ipairs(getContainers()) do
    local found = findItemInContainer(container, itemId)
    if found then return found end
  end
  return nil
end

return {
  findItem = findItem
}
