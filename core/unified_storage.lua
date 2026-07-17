local StorageEngine = nExBot.StorageEngine
if not StorageEngine then
  warn("[UnifiedStorage] StorageEngine not loaded")
  return
end
local getClient = nExBot.Shared.getClient
local deepClone = nExBot.Shared.deepClone

local engine = StorageEngine.new({
  filename = "UnifiedStorage.json",
  pathStrategy = "character",
  debounceMs = 300,
  maxFileSize = 10 * 1024 * 1024,
  defaults = {
    version = 5, characterName = "", createdAt = 0, lastModified = 0,
    intelligence = { migrated = false, models = { defaultMode = "SHADOW" },
      flags = { replay = true, diagnostics = true, learning = true, neuralModel = false } },
    targetbot = {
      enabled = false, selectedConfig = "",
      priority = { enabled = true, emergencyHP = 25, combatTimeout = 12, scanRadius = 2 },
      monsterPatterns = {}, combatActive = false, emergency = false,
    },
    cavebot = {
      enabled = false, selectedConfig = "",
      walking = { pathSmoothingEnabled = true, floorChangeDelay = 200, stuckTimeout = 5000 },
    },
    healbot = { enabled = false, rules = {} },
    attackbot = { enabled = false, rules = {} },
    newHealer = { enabled = false, priorities = {}, settings = {}, conditions = {}, customPlayers = {} },
    macros = {
      exchangeMoney = false, autoTradeMsg = false, autoHaste = false,
      autoMount = false, manaTraining = false, eatFood = false,
      antiRs = false, holdTarget = false, exetaLowHp = false,
      exetaIfPlayer = false, depotWithdraw = false, quiverManager = false,
      fishing = false,
    },
    tools = {
      manaTraining = { spell = "exura", minManaPercent = 80 },
      autoTradeMessage = "nExBot is online!",
      fishing = { dropFish = true },
    },
    dropper = { enabled = false, trashItems = {}, useItems = {}, capItems = {} },
    equipper = { enabled = false, rules = {}, activeRule = nil },
    containers = { purse = true, autoMinimize = true, autoOpenOnLogin = false, containerList = {} },
    supplies = { eatFromCorpses = false, sellItems = {} },
    combobot = { enabled = false, spell = "", attack = "", follow = "" },
    analytics = { showOnStartup = false },
    extras = { looting = 40, lootLast = false },
  },
})

UnifiedStorage = {}
for k, v in pairs(engine) do UnifiedStorage[k] = v end

local _readyCallbacks = {}
local _backupScheduled = false
local _lastBackup = 0
local BACKUP_INTERVAL = 300
local MAX_BACKUPS = 5

function UnifiedStorage.onReady(cb)
  if UnifiedStorage.isReady() then pcall(cb)
  else table.insert(_readyCallbacks, cb) end
end

local _engineLoad = engine.load
function UnifiedStorage.load()
  local result = _engineLoad()
  if not result then return result end
  if not UnifiedStorage.isReady() then return result end
  local rawName = nil
  if player and player.getName then pcall(function() rawName = player:getName() end) end
  if not rawName then
    local C = getClient()
    local lp = (C and C.getLocalPlayer) and C.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
    if lp then rawName = lp:getName() end
  end
  result.characterName = rawName or UnifiedStorage.getCharName()
  if not result.createdAt or result.createdAt == 0 then result.createdAt = os.time() end
  for _, cb in ipairs(_readyCallbacks) do pcall(cb) end
  _readyCallbacks = {}
  if EventBus then EventBus.emit("storage:initialized", UnifiedStorage.getCharName()) end
  return result
end

local _engineSet = engine.set
function UnifiedStorage.set(path, value)
  local r = _engineSet(path, value)
  if EventBus then EventBus.emit("storage:changed", path, value, UnifiedStorage.getCharName()) end
  return r
end

local _engineBatch = engine.batch
function UnifiedStorage.batch(updates)
  _engineBatch(updates)
  if EventBus then EventBus.emit("storage:batchChanged", updates, UnifiedStorage.getCharName()) end
end

local function createBackup()
  local data = UnifiedStorage.getData()
  if not data then return end
  local stats = engine.getStats()
  if not stats.basePath then return end
  local backupDir = stats.basePath .. "backups/"
  if not g_resources.directoryExists(backupDir) then g_resources.makeDir(backupDir) end
  local ts = os.date("%Y%m%d_%H%M%S")
  local backupFile = backupDir .. "UnifiedStorage_" .. ts .. ".json"
  local content = json.encode(data, 2)
  if content then pcall(function() g_resources.writeFileContents(backupFile, content) end) end
  pcall(function()
    local files = g_resources.listDirectoryFiles(backupDir, false, false)
    if files and #files > MAX_BACKUPS then
      table.sort(files)
      for i = 1, #files - MAX_BACKUPS do g_resources.deleteFile(backupDir .. files[i]) end
    end
  end)
  _lastBackup = os.time()
end

function UnifiedStorage.backup() createBackup() end

local _engineSave = engine.save
function UnifiedStorage.save()
  local data = UnifiedStorage.getData()
  if data then data.lastModified = os.time() end
  _engineSave()
  if EventBus then EventBus.emit("storage:saved", UnifiedStorage.getCharName(), 0) end
end

function UnifiedStorage.getStats()
  local s = engine.getStats()
  s.lastBackup = _lastBackup
  return s
end

local function hasLocalPlayer()
  local C = getClient()
  local lp = (C and C.getLocalPlayer) and C.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  return lp ~= nil
end

if hasLocalPlayer() then UnifiedStorage.load() end

schedule(100, function()
  if not EventBus then
    schedule(500, function()
      if EventBus then
        EventBus.on("targetbot:configChanged", function(cn) UnifiedStorage.set("targetbot.selectedConfig", cn) end)
        EventBus.on("cavebot:configChanged", function(cn) UnifiedStorage.set("cavebot.selectedConfig", cn) end)
        EventBus.on("macro:toggled", function(mn, en) UnifiedStorage.set("macros." .. mn, en) end)
        EventBus.on("module:toggled", function(mn, en) UnifiedStorage.set(mn .. ".enabled", en) end)
        EventBus.on("monsterAI:patternUpdated", function(monster, pattern)
          local p = UnifiedStorage.get("targetbot.monsterPatterns") or {}
          p[monster] = pattern
          UnifiedStorage.set("targetbot.monsterPatterns", p)
        end)
        EventBus.on("player:logout", function() UnifiedStorage.save() end)
        EventBus.on("tick:slow", function()
          if os.time() - _lastBackup > BACKUP_INTERVAL and UnifiedStorage.getData() then createBackup() end
        end)
      end
    end)
    return
  end
  EventBus.on("targetbot:configChanged", function(cn) UnifiedStorage.set("targetbot.selectedConfig", cn) end)
  EventBus.on("cavebot:configChanged", function(cn) UnifiedStorage.set("cavebot.selectedConfig", cn) end)
  EventBus.on("macro:toggled", function(mn, en) UnifiedStorage.set("macros." .. mn, en) end)
  EventBus.on("module:toggled", function(mn, en) UnifiedStorage.set(mn .. ".enabled", en) end)
  EventBus.on("monsterAI:patternUpdated", function(monster, pattern)
    local p = UnifiedStorage.get("targetbot.monsterPatterns") or {}
    p[monster] = pattern
    UnifiedStorage.set("targetbot.monsterPatterns", p)
  end)
  EventBus.on("player:logout", function() UnifiedStorage.save() end)
  EventBus.on("tick:slow", function()
    if os.time() - _lastBackup > BACKUP_INTERVAL and UnifiedStorage.getData() then createBackup() end
  end)
  if not engine.getStats().initialized and hasLocalPlayer() then UnifiedStorage.load() end
end)

nExBot = nExBot or {}
nExBot.UnifiedStorage = UnifiedStorage
