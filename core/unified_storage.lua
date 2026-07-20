local StorageEngine = nExBot.StorageEngine
if not StorageEngine then
  warn("[UnifiedStorage] StorageEngine not loaded")
  return
end
local getClient = nExBot.Shared.getClient
local deepClone = nExBot.Shared.deepClone

local CURRENT_SCHEMA_VERSION = 6
local CURRENT_MIGRATION_VERSION = 1

local function getContextKey(context)
  if not context then return nil end
  return string.format("%s/%s/%s/%s",
    context.clientFamily or "unknown",
    context.clientProfileKey or "default",
    context.serverKey or "unknown",
    context.characterKey or "unknown"
  )
end

local function getContextFilename(context)
  local key = getContextKey(context)
  if not key then return "UnifiedStorage.json" end
  return "UnifiedStorage_" .. key:gsub("[/\\:*?\"<>|]", "_") .. ".json"
end

local function buildEngine(context)
  return StorageEngine.new({
    filename = getContextFilename(context),
    pathStrategy = "character",
    debounceMs = 300,
    maxFileSize = 10 * 1024 * 1024,
    defaults = {
      schemaVersion = CURRENT_SCHEMA_VERSION,
      migrationVersion = CURRENT_MIGRATION_VERSION,
      revision = 0,
      updatedAtMs = 0,
      context = {
        clientProfileKey = "",
        serverKey = "",
        worldKey = "",
        characterKey = "",
      },
      modules = {
        cavebot = {
          selectedConfig = "",
          desiredEnabled = false,
          updatedAtMs = 0,
          revision = 0,
        },
        targetbot = {
          selectedConfig = "",
          desiredEnabled = false,
          explicitlyDisabledByUser = false,
          updatedAtMs = 0,
          revision = 0,
        },
        healbot = {
          desiredEnabled = false,
          updatedAtMs = 0,
          revision = 0,
        },
        attackbot = {
          desiredEnabled = false,
          updatedAtMs = 0,
          revision = 0,
        },
      },
      controls = {},
    },
  })
end

local engine = buildEngine(nil)
UnifiedStorage = {}
for k, v in pairs(engine) do UnifiedStorage[k] = v end

UnifiedStorage._context = nil
UnifiedStorage._boundEngines = {}
UnifiedStorage._readyCallbacks = {}
UnifiedStorage._lastBackup = 0

local function getEngine(context)
  context = context or UnifiedStorage._context
  if not context then return engine end
  local key = getContextKey(context)
  if UnifiedStorage._boundEngines[key] then
    return UnifiedStorage._boundEngines[key]
  end
  local eng = buildEngine(context)
  UnifiedStorage._boundEngines[key] = eng
  return eng
end

function UnifiedStorage.bind(context)
  if not context then return end
  UnifiedStorage._context = context
  local eng = getEngine(context)
  if not eng.getStats().initialized and hasLocalPlayer() then
    eng.load()
  end
end

function UnifiedStorage.isBoundTo(context)
  if not context or not UnifiedStorage._context then return false end
  return UnifiedStorage._context:matches(context)
end

function UnifiedStorage.load(context)
  local eng = getEngine(context)
  local result = eng.load()
  if not result then return result end
  if not eng.isReady() then return result end

  local rawName = nil
  if player and player.getName then pcall(function() rawName = player:getName() end) end
  if not rawName then
    local C = getClient()
    local lp = (C and C.getLocalPlayer) and C.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
    if lp then rawName = lp:getName() end
  end
  result.characterName = rawName or eng.getCharName()
  if not result.createdAt or result.createdAt == 0 then result.createdAt = os.time() end

  if result.schemaVersion and result.schemaVersion < CURRENT_SCHEMA_VERSION then
    result = UnifiedStorage.migrate(result)
  end

  for _, cb in ipairs(UnifiedStorage._readyCallbacks) do pcall(cb) end
  UnifiedStorage._readyCallbacks = {}
  if EventBus then EventBus.emit("storage:initialized", context and context.characterKey or eng.getCharName()) end
  return result
end

function UnifiedStorage.onReady(cb)
  local eng = getEngine()
  if eng.isReady and eng.isReady() then pcall(cb)
  else table.insert(UnifiedStorage._readyCallbacks, cb) end
end

function UnifiedStorage.set(path, value, context)
  local eng = getEngine(context)
  local r = eng.set(path, value)
  if EventBus then EventBus.emit("storage:changed", path, value, context and context.characterKey or eng.getCharName()) end
  return r
end

function UnifiedStorage.batch(updates, context)
  local eng = getEngine(context)
  eng.batch(updates)
  if EventBus then EventBus.emit("storage:batchChanged", updates, context and context.characterKey or eng.getCharName()) end
end

function UnifiedStorage.transaction(context, fn)
  local eng = getEngine(context)
  local data = eng.getData() or {}
  local ok, result = pcall(fn, data)
  if ok and result ~= nil then
    eng.batch(result)
  elseif ok then
    eng.batch(data)
  end
  if EventBus then EventBus.emit("storage:changed", "*", nil, context and context.characterKey or eng.getCharName()) end
  return ok
end

function UnifiedStorage.flush(context)
  local eng = getEngine(context)
  if eng.save then
    eng.save()
    return true
  end
  return false
end

function UnifiedStorage.unbind(context)
  context = context or UnifiedStorage._context
  if not context then return end
  local key = getContextKey(context)
  if key and UnifiedStorage._boundEngines[key] then
    UnifiedStorage._boundEngines[key] = nil
  end
  if UnifiedStorage._context and UnifiedStorage._context.matches and UnifiedStorage._context:matches(context) then
    UnifiedStorage._context = nil
  end
end

function UnifiedStorage.getRevision(context)
  local eng = getEngine(context)
  local data = eng.getData()
  return data and data.revision or 0
end

function UnifiedStorage.onReadyContext(context, callback)
  local eng = getEngine(context)
  if eng.isReady and eng.isReady() then
    pcall(callback)
  else
    local origLoad = eng.load
    eng.load = function()
      local result = origLoad()
      if eng.isReady and eng.isReady() then
        pcall(callback)
      end
      return result
    end
  end
end

local function createBackup(context)
  local eng = getEngine(context)
  local data = eng.getData()
  if not data then return end
  local stats = eng.getStats()
  if not stats.basePath then return end
  local backupDir = stats.basePath .. "backups/"
  if not g_resources.directoryExists(backupDir) then g_resources.makeDir(backupDir) end
  local ts = os.date("%Y%m%d_%H%M%S")
  local key = getContextKey(context)
  local backupFile = backupDir .. "UnifiedStorage_" .. (key and key:gsub("[/\\:*?\"<>|]", "_") .. "_" or "") .. ts .. ".json"
  local content = json.encode(data, 2)
  if content then pcall(function() g_resources.writeFileContents(backupFile, content) end) end
  pcall(function()
    local files = g_resources.listDirectoryFiles(backupDir, false, false)
    if files and #files > 5 then
      table.sort(files)
      for i = 1, #files - 5 do g_resources.deleteFile(backupDir .. files[i]) end
    end
  end)
  UnifiedStorage._lastBackup = os.time()
end

function UnifiedStorage.backup(context) createBackup(context) end

function UnifiedStorage.save()
  local eng = getEngine()
  local data = eng.getData()
  if data then data.lastModified = os.time() end
  eng.save()
  if EventBus then EventBus.emit("storage:saved", eng.getCharName(), 0) end
end

function UnifiedStorage.getStats()
  local eng = getEngine()
  local s = eng.getStats()
  return s
end

function UnifiedStorage.migrate(data)
  if not data then return data end
  local migrated = false

  if data.version and not data.schemaVersion then
    data.schemaVersion = data.version
    migrated = true
  end

  if not data.migrationVersion then
    data.migrationVersion = 0
    migrated = true
  end

  if not data.revision then
    data.revision = 0
    migrated = true
  end

  if not data.updatedAtMs then
    data.updatedAtMs = 0
    migrated = true
  end

  if not data.context then
    data.context = {
      clientProfileKey = "",
      serverKey = "",
      worldKey = "",
      characterKey = "",
    }
    migrated = true
  end

  if data.cavebot and not data.modules then
    data.modules = data.modules or {}
    data.modules.cavebot = {
      selectedConfig = data.cavebot.selectedConfig or "",
      desiredEnabled = data.cavebot.enabled or false,
      updatedAtMs = data.cavebot.updatedAtMs or 0,
      revision = 0,
    }
    migrated = true
  end

  if data.targetbot and not data.modules then
    data.modules = data.modules or {}
    data.modules.targetbot = {
      selectedConfig = data.targetbot.selectedConfig or "",
      desiredEnabled = data.targetbot.enabled or false,
      explicitlyDisabledByUser = data.targetbot.explicitlyDisabledByUser or false,
      updatedAtMs = data.targetbot.updatedAtMs or 0,
      revision = 0,
    }
    migrated = true
  end

  if data.healbot and not data.modules then
    data.modules = data.modules or {}
    data.modules.healbot = {
      desiredEnabled = data.healbot.enabled or false,
      updatedAtMs = 0,
      revision = 0,
    }
    migrated = true
  end

  if data.attackbot and not data.modules then
    data.modules = data.modules or {}
    data.modules.attackbot = {
      desiredEnabled = data.attackbot.enabled or false,
      updatedAtMs = 0,
      revision = 0,
    }
    migrated = true
  end

  if not data.modules then
    data.modules = {}
  end
  data.modules.cavebot = data.modules.cavebot or {
    selectedConfig = "", desiredEnabled = false, updatedAtMs = 0, revision = 0
  }
  data.modules.targetbot = data.modules.targetbot or {
    selectedConfig = "", desiredEnabled = false, explicitlyDisabledByUser = false, updatedAtMs = 0, revision = 0
  }
  data.modules.healbot = data.modules.healbot or {
    desiredEnabled = false, updatedAtMs = 0, revision = 0
  }
  data.modules.attackbot = data.modules.attackbot or {
    desiredEnabled = false, updatedAtMs = 0, revision = 0
  }

  data.controls = data.controls or {}

  data.schemaVersion = CURRENT_SCHEMA_VERSION
  data.migrationVersion = CURRENT_MIGRATION_VERSION

  if migrated then
    print("[UnifiedStorage] Migrated storage to schema v" .. CURRENT_SCHEMA_VERSION)
  end

  return data
end

local function hasLocalPlayer()
  local C = getClient()
  local lp = (C and C.getLocalPlayer) and C.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
  return lp ~= nil
end

if hasLocalPlayer() then UnifiedStorage.load() end

local function registerPersistenceListeners()
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
    if os.time() - (UnifiedStorage._lastBackup or 0) > 300 and UnifiedStorage.getData() then UnifiedStorage.backup() end
  end)
end

schedule(100, function()
  if not EventBus then
    schedule(500, function()
      if EventBus then registerPersistenceListeners() end
    end)
    return
  end
  registerPersistenceListeners()
  if not engine.getStats().initialized and hasLocalPlayer() then UnifiedStorage.load() end
end)

nExBot = nExBot or {}
nExBot.UnifiedStorage = UnifiedStorage