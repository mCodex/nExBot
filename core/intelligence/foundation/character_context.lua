local CharacterContext = {}
CharacterContext.__index = CharacterContext

local function normalizeName(name)
  if not name then return "" end
  return name:lower():gsub("%s+", "")
end

local function getServerKey()
  if g_game and g_game.getWorldName then
    local world = g_game.getWorldName()
    if world and world ~= "" then return world end
  end
  if g_game and g_game.getServerName then
    local server = g_game.getServerName()
    if server and server ~= "" then return server end
  end
  return "unknown"
end

local function getWorldKey()
  if g_game and g_game.getWorldName then
    local world = g_game.getWorldName()
    if world and world ~= "" then return world end
  end
  return ""
end

function CharacterContext.new()
  local self = setmetatable({}, CharacterContext)
  self.schemaVersion = 1
  self.sessionGeneration = 0
  self.clientFamily = "unknown"
  self.clientProfileKey = ""
  self.serverKey = ""
  self.worldKey = ""
  self.characterKey = ""
  self.displayName = ""
  self.boundAtMs = 0
  return self
end

function CharacterContext:capture()
  local localPlayer = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  if not localPlayer then
    local C = nExBot.Shared and nExBot.Shared.getClient and nExBot.Shared.getClient()
    localPlayer = C and C.getLocalPlayer and C.getLocalPlayer()
  end

  if not localPlayer then
    return false
  end

  local name = localPlayer:getName()
  if not name or name == "" then
    return false
  end

  self.displayName = name
  self.characterKey = normalizeName(name)
  self.serverKey = getServerKey()
  self.worldKey = getWorldKey()
  self.clientFamily = nExBot.isOTCv8 and "otcv8" or (nExBot.isOpenTibiaBR and "otcr" or "unknown")
  self.clientProfileKey = nExBot.paths and nExBot.paths.config or "default"
  self.boundAtMs = nExBot.Shared and nExBot.Shared.nowMs and nExBot.Shared.nowMs() or (os.time() * 1000)

  return true
end

function CharacterContext:isValid()
  return self.characterKey ~= "" and self.serverKey ~= ""
end

function CharacterContext:toTable()
  return {
    schemaVersion = self.schemaVersion,
    sessionGeneration = self.sessionGeneration,
    clientFamily = self.clientFamily,
    clientProfileKey = self.clientProfileKey,
    serverKey = self.serverKey,
    worldKey = self.worldKey,
    characterKey = self.characterKey,
    displayName = self.displayName,
    boundAtMs = self.boundAtMs,
  }
end

function CharacterContext:matches(other)
  if not other then return false end
  return self.serverKey == other.serverKey
     and self.worldKey == other.worldKey
     and self.characterKey == other.characterKey
     and self.clientProfileKey == other.clientProfileKey
end

nExBot = nExBot or {}
nExBot.CharacterContext = CharacterContext

return CharacterContext