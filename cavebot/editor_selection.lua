-- Pure multi-select set for the waypoint editor. No g_ui dependency.
local Selection = {}
Selection.__index = Selection

function Selection.new()
  return setmetatable({_order = {}, _set = {}}, Selection)
end

function Selection:isSelected(item)
  return self._set[item] == true
end

function Selection:all()
  local out = {}
  for i = 1, #self._order do out[i] = self._order[i] end
  return out
end

function Selection:clear()
  self._order = {}
  self._set = {}
end

function Selection:selectOnly(item)
  self:clear()
  self._set[item] = true
  self._order[1] = item
end

function Selection:toggle(item)
  if self._set[item] then
    self._set[item] = nil
    for i = 1, #self._order do
      if self._order[i] == item then
        table.remove(self._order, i)
        break
      end
    end
  else
    self._set[item] = true
    self._order[#self._order + 1] = item
  end
end

-- Selects every item between anchor and target (inclusive) in orderedItems'
-- list order. If the anchor is not found in orderedItems, falls back to
-- selecting only the target.
function Selection:selectRange(anchor, target, orderedItems)
  local anchorIndex, targetIndex
  for i = 1, #orderedItems do
    if orderedItems[i] == anchor then anchorIndex = i end
    if orderedItems[i] == target then targetIndex = i end
  end

  if not anchorIndex or not targetIndex then
    self:selectOnly(target)
    return
  end

  self:clear()
  local lo, hi = anchorIndex, targetIndex
  if lo > hi then lo, hi = hi, lo end
  for i = lo, hi do
    local item = orderedItems[i]
    self._set[item] = true
    self._order[#self._order + 1] = item
  end
end

-- Drops any selected item that is no longer present in liveItems.
function Selection:prune(liveItems)
  local live = {}
  for i = 1, #liveItems do live[liveItems[i]] = true end

  local kept = {}
  for i = 1, #self._order do
    local item = self._order[i]
    if live[item] then kept[#kept + 1] = item end
  end
  self._order = kept

  for item in pairs(self._set) do
    if not live[item] then self._set[item] = nil end
  end
end

if nExBot then
  nExBot.Nav = nExBot.Nav or {}
  nExBot.Nav["cavebot.editor_selection"] = Selection
end

return Selection
