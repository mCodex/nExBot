IntelligenceSnapshotBuilder = {}
IntelligenceSnapshotBuilder.__index = IntelligenceSnapshotBuilder
local nowMs = nExBot and nExBot.Shared and nExBot.Shared.nowMs or function() return os.time() * 1000 end

local function callOrRead(value, field, method)
  if not value then return nil end
  if value[field] ~= nil then return value[field] end
  if value[method] then return value[method](value) end
end

local function positionOf(value)
  local position = callOrRead(value, "position", "getPosition")
  if not position then return nil end
  return { x = position.x, y = position.y, z = position.z }
end

local function ratio(current, maximum, percent)
  if percent ~= nil then return math.max(0, math.min(1, percent / 100)) end
  if not current or not maximum or maximum <= 0 then return 0 end
  return math.max(0, math.min(1, current / maximum))
end

local function distance(a, b)
  if not a or not b or a.z ~= b.z then return nil end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function flagOf(value, name)
  if not value then return false end
  if type(value[name]) == "function" then return value[name](value) == true end
  return value[name] == true
end

local function copyCreature(creature, playerPosition)
  local position = positionOf(creature)
  local healthPercent = callOrRead(creature, "healthPercent", "getHealthPercent")
  return {
    id = callOrRead(creature, "id", "getId"),
    name = callOrRead(creature, "name", "getName"),
    healthPercent = healthPercent,
    healthRatio = ratio(nil, nil, healthPercent),
    position = position,
    distance = distance(playerPosition, position),
    isMonster = flagOf(creature, "isMonster"),
    isPlayer = flagOf(creature, "isPlayer"),
  }
end

local function copyPlayer(player)
  if not player then return nil end
  local health = callOrRead(player, "health", "getHealth")
  local maxHealth = callOrRead(player, "maxHealth", "getMaxHealth")
  local mana = callOrRead(player, "mana", "getMana")
  local maxMana = callOrRead(player, "maxMana", "getMaxMana")
  return {
    id = callOrRead(player, "id", "getId"),
    position = positionOf(player),
    health = health,
    maxHealth = maxHealth,
    healthRatio = ratio(health, maxHealth, callOrRead(player, "healthPercent", "getHealthPercent")),
    mana = mana,
    maxMana = maxMana,
    manaRatio = ratio(mana, maxMana),
  }
end

function IntelligenceSnapshotBuilder.new(options)
  options = options or {}
  return setmetatable({
    now = options.now or nowMs,
    getSpectators = options.getSpectators or function() return g_map and g_map.getSpectators() or {} end,
    getPlayer = options.getPlayer or function() return g_game and g_game.getLocalPlayer() or nil end,
  }, IntelligenceSnapshotBuilder)
end

function IntelligenceSnapshotBuilder:build(context)
  context = context or {}
  local player = copyPlayer(context.player or self.getPlayer())
  local creatures, creaturesById, visibleMonsters, visiblePlayers = {}, {}, {}, {}
  for _, source in ipairs(self.getSpectators(player and player.position) or {}) do
    local creature = copyCreature(source, player and player.position)
    assert(creature.id ~= nil, "creature id is required")
    assert(not creaturesById[creature.id], "duplicate creature id: " .. tostring(creature.id))
    creatures[#creatures + 1] = creature
    creaturesById[creature.id] = creature
    if creature.isMonster then visibleMonsters[#visibleMonsters + 1] = creature end
    if creature.isPlayer then visiblePlayers[#visiblePlayers + 1] = creature end
  end
  table.sort(creatures, function(a, b) return a.id < b.id end)
  table.sort(visibleMonsters, function(a, b) return a.id < b.id end)
  table.sort(visiblePlayers, function(a, b) return a.id < b.id end)
  return {
    generation = context.generation or 0,
    timestamp = self.now(),
    player = player,
    creatures = creatures,
    creaturesById = creaturesById,
    visibleMonsters = visibleMonsters,
    visiblePlayers = visiblePlayers,
  }
end

return IntelligenceSnapshotBuilder
