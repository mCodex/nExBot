local panelName = "specialDeposit"

if not storage[panelName] then
    storage[panelName] = {
        items = {},
        height = 380
    }
end

local config = storage[panelName]

-- Safe no-op kept for legacy callers (actions.lua open_depositer): routes to
-- the shell page instead of opening a standalone window.
local function showDepositerWindow()
  local Shell = nExBot and nExBot.UI and nExBot.UI.Shell
  if Shell and Shell.select then
    pcall(Shell.select, "depositer")
  end
end

function getStashingIndex(id)
    for _, v in pairs(config.items) do
        if v.id == id then
            return v.index - 1
        end
    end
end

-- Profile storage helpers
local function getProfileSetting(key)
  if ProfileStorage then
    return ProfileStorage.get(key)
  end
  return storage[key]
end

local function setProfileSetting(key, value)
  if ProfileStorage then
    ProfileStorage.set(key, value)
  else
    storage[key] = value
  end
end

-- Load from profile storage
local cavebotSell = getProfileSetting("cavebotSell") or {23544, 3081}

local function setCavebotSellItems(items)
  cavebotSell = items
  setProfileSetting("cavebotSell", items)
end

-- Export for other modules to access
function getCavebotSellItems()
  return cavebotSell
end

-- The standalone window (core/depositer_config.otui) was retired in favor of
-- the shell page ui/modules/depositer.lua. addItem/removeItem/setItemIndex
-- mirror the window's item-list editing (it added via title double-click and
-- removed on double-click).
local function addItem(id, index)
  id = tonumber(id)
  if not id or id <= 0 then return false end
  for _, entry in ipairs(config.items) do
    if entry.id == id then return false end
  end
  config.items[#config.items + 1] = { id = id, index = tonumber(index) or 3 }
  return true
end

local function removeItem(id)
  for i, entry in ipairs(config.items) do
    if entry.id == id then
      table.remove(config.items, i)
      return true
    end
  end
  return false
end

local function setItemIndex(id, index)
  index = tonumber(index)
  if not index then return false end
  for _, entry in ipairs(config.items) do
    if entry.id == id then
      entry.index = index
      return true
    end
  end
  return false
end

nExBot.Depositer = {
  showWindow = showDepositerWindow,
  getItems = function() return config.items end,
  addItem = addItem,
  removeItem = removeItem,
  setItemIndex = setItemIndex,
  getStashingIndex = getStashingIndex,
  getSellItems = getCavebotSellItems,
  setSellItems = setCavebotSellItems,
}