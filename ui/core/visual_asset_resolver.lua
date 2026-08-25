local Resolver = {}
Resolver.__index = Resolver

local function defaultItemName(itemId)
  if not g_things or not g_things.getThingType then return nil end
  local ok, thing = pcall(g_things.getThingType, itemId, ThingCategoryItem)
  if not ok or not thing or not thing.getName then return nil end
  local nameOk, name = pcall(thing.getName, thing)
  return nameOk and name or nil
end

local function defaultSpellIcon(spell)
  if type(getSpellData) ~= "function" then return nil end
  local ok, data = pcall(getSpellData, spell)
  if not ok or type(data) ~= "table" then return nil end
  local source = data.iconPath or data.imageSource
  return type(source) == "string" and source ~= "" and source or nil
end

function Resolver.new(dependencies)
  dependencies = dependencies or {}
  return setmetatable({
    getItemName = dependencies.getItemName or defaultItemName,
    getSpellIcon = dependencies.getSpellIcon or defaultSpellIcon,
    itemCache = {},
    spellCache = {},
    generation = 0,
  }, Resolver)
end

function Resolver:item(itemId)
  itemId = tonumber(itemId) or 0
  if self.itemCache[itemId] then return self.itemCache[itemId] end
  local name = self.getItemName and self.getItemName(itemId)
  local result = { kind = "item", itemId = itemId, name = name or ("Item " .. itemId) }
  self.itemCache[itemId] = result
  return result
end

function Resolver:spell(spell, itemId)
  local normalized = tostring(spell or ""):lower()
  local key = normalized .. ":" .. tostring(itemId or "")
  if self.spellCache[key] then return self.spellCache[key] end
  local source = self.getSpellIcon and self.getSpellIcon(normalized)
  local result
  if source then
    result = { kind = "native", source = source, text = spell }
  elseif itemId then
    result = { kind = "item", itemId = tonumber(itemId), text = spell }
  else
    result = { kind = "text", text = spell }
  end
  self.spellCache[key] = result
  return result
end

function Resolver:reset(generation)
  self.generation = generation or (self.generation + 1)
  self.itemCache = {}
  self.spellCache = {}
end

local shared = Resolver.new()
Resolver.shared = shared

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.VisualAssetResolver = shared
  nExBot.UI["ui.core.visual_asset_resolver"] = Resolver
end

return Resolver
