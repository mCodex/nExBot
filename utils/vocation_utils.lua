local VocationUtils = {}

local nameCache = {}
local CACHE_TTL = 600000

local VOCATION_SHORT = {
  ["knight"] = "EK",
  ["elite knight"] = "EK",
  ["paladin"] = "RP",
  ["royal paladin"] = "RP",
  ["sorcerer"] = "MS",
  ["master sorcerer"] = "MS",
  ["druid"] = "ED",
  ["elder druid"] = "ED",
  ["monk"] = "MN",
  ["exalted monk"] = "MN"
}

local function normalize(text)
  if not text then return "" end
  return text:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function getShortFromVocationName(vocationName)
  if not vocationName then return nil end
  local name = normalize(vocationName)

  if name:find("elite knight", 1, true) then return "EK" end
  if name:find("knight", 1, true) then return "EK" end
  if name:find("royal paladin", 1, true) then return "RP" end
  if name:find("paladin", 1, true) then return "RP" end
  if name:find("master sorcerer", 1, true) then return "MS" end
  if name:find("sorcerer", 1, true) then return "MS" end
  if name:find("elder druid", 1, true) then return "ED" end
  if name:find("druid", 1, true) then return "ED" end
  if name:find("exalted monk", 1, true) then return "MN" end
  if name:find("monk", 1, true) then return "MN" end

  return VOCATION_SHORT[name]
end

local function parseLookText(text)
  if not text then return nil end
  local t = normalize(text)
  if not t:find("you see", 1, true) then return nil end

  local name = t:match("you see ([^%.]+)%.%s*")
  local vocation = t:match("you are a ([^%.]+)%.%s*$") or t:match("you are an ([^%.]+)%.%s*$")
  if not vocation then
    vocation = t:match("he is a ([^%.]+)%.%s*$") or t:match("he is an ([^%.]+)%.%s*$")
      or t:match("she is a ([^%.]+)%.%s*$") or t:match("she is an ([^%.]+)%.%s*$")
      or t:match("it is a ([^%.]+)%.%s*$") or t:match("it is an ([^%.]+)%.%s*$")
  end

  if not name or not vocation then return nil end

  local short = getShortFromVocationName(vocation)
  if not short then return nil end

  return { name = name, short = short }
end

local function cachePut(name, short)
  if not name or not short then return end
  nameCache[name:lower()] = { short = short, ts = now or (os.time() * 1000) }
end

local function cacheGet(name)
  if not name then return nil end
  local entry = nameCache[name:lower()]
  if not entry then return nil end
  local nowt = now or (os.time() * 1000)
  if (nowt - entry.ts) > CACHE_TTL then
    nameCache[name:lower()] = nil
    return nil
  end
  return entry.short
end

function VocationUtils.getShortFromText(text)
  if not text then return nil end
  local t = normalize(text)
  if t:find("EK", 1, true) then return "EK" end
  if t:find("RP", 1, true) then return "RP" end
  if t:find("ED", 1, true) then return "ED" end
  if t:find("MS", 1, true) then return "MS" end
  if t:find("MN", 1, true) then return "MN" end
  return nil
end

function VocationUtils.getCreatureVocationShort(creature)
  if not creature or not creature.isPlayer or not creature:isPlayer() then return nil end
  local okText, text = pcall(function() return creature:getText() end)
  if okText and text and text:len() > 0 then
    local short = VocationUtils.getShortFromText(text)
    if short then return short end
  end

  local okName, name = pcall(function() return creature:getName() end)
  if okName and name then
    return cacheGet(name)
  end

  return nil
end

function VocationUtils.registerLookParser()
  if VocationUtils._registered then return end
  VocationUtils._registered = true

  if onTextMessage then
    onTextMessage(function(mode, text)
      local parsed = parseLookText(text)
      if not parsed then return end
      cachePut(parsed.name, parsed.short)
    end)
  end
end

VocationUtils.registerLookParser()

return VocationUtils
