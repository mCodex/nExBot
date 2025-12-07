--[[
  ItemClassifier
  Lightweight helper that tags items from items.xml into fast lookup sets.
]]

ItemClassifier = ItemClassifier or {}

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local ITEMS_XML_PATH = "/bot/" .. configName .. "/items.xml"

local CATEGORY_RULES = {
  door = function(key, value)
    if key ~= "type" or not value then
      return false
    end
    local lowered = value:lower()
    return lowered:find("door", 1, true) ~= nil
  end
}

local categorySets = {}
local parsed = false

local function addCategory(ids, category)
  local set = categorySets[category]
  if not set then
    set = {}
    categorySets[category] = set
  end
  for i = 1, #ids do
    set[ids[i]] = true
  end
end

local function extractIds(tagLine)
  local ids = {}
  local fromId = tagLine:match('fromid="(%d+)"')
  local toId = tagLine:match('toid="(%d+)"')
  if fromId and toId then
    local startId = tonumber(fromId)
    local finishId = tonumber(toId)
    if startId and finishId and finishId >= startId then
      for id = startId, finishId do
        ids[#ids + 1] = id
      end
    end
  else
    local singleId = tagLine:match('id="(%d+)"')
    if singleId then
      ids[1] = tonumber(singleId)
    end
  end
  return ids
end

local function processAttribute(ids, key, value)
  if not key or not value then
    return
  end
  for category, predicate in pairs(CATEGORY_RULES) do
    local ok, shouldRegister = pcall(predicate, key, value)
    if ok and shouldRegister then
      addCategory(ids, category)
    end
  end
end

local function parseItemsXml()
  if parsed then
    return
  end
  parsed = true

  if not g_resources.fileExists(ITEMS_XML_PATH) then
    warn(string.format("[ItemClassifier] Missing items.xml at %s", ITEMS_XML_PATH))
    return
  end

  local contents = g_resources.readFileContents(ITEMS_XML_PATH)
  if not contents or contents:len() == 0 then
    warn("[ItemClassifier] Empty items.xml content")
    return
  end

  local activeIds = nil
  for line in contents:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      if trimmed:find("^<item") then
        local ids = extractIds(trimmed)
        if #ids > 0 then
          activeIds = ids
        else
          activeIds = nil
        end
        if trimmed:find("/>%s*$") then
          activeIds = nil
        end
      elseif trimmed:find("^</item>") then
        activeIds = nil
      elseif activeIds and trimmed:find("^<attribute") then
        local key = trimmed:match('key="([^"]+)"')
        local value = trimmed:match('value="([^"]+)"')
        processAttribute(activeIds, key, value)
      end
    end
  end
end

local function ensureParsed()
  if not parsed then
    parseItemsXml()
  end
end

function ItemClassifier.hasTag(tag, itemId)
  if not itemId then
    return false
  end
  ensureParsed()
  local set = categorySets[tag]
  return set and set[itemId] == true or false
end

function ItemClassifier.getTagSet(tag)
  ensureParsed()
  return categorySets[tag]
end

function ItemClassifier.isDoor(itemId)
  return ItemClassifier.hasTag("door", itemId)
end

return ItemClassifier
