local StorageEngine = {}
local deepClone = nExBot.Shared.deepClone
local getClient = nExBot.Shared.getClient

local function dotGet(obj, path)
  if type(obj) ~= "table" or type(path) ~= "string" then return nil end
  local cur = obj
  for k in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[k]
  end
  return cur
end

local function dotSet(obj, path, value)
  if type(path) ~= "string" then return obj end
  local r = deepClone(obj) or {}
  local cur = r
  local keys = {}
  for k in path:gmatch("[^%.]+") do keys[#keys + 1] = k end
  for i = 1, #keys - 1 do
    if type(cur[keys[i]]) ~= "table" then cur[keys[i]] = {} end
    cur = cur[keys[i]]
  end
  if #keys > 0 then cur[keys[#keys]] = value end
  return r
end

local function sanitize(data, schema)
  if type(schema) ~= "table" then return data ~= nil and data or schema end
  local r = {}
  for k, v in pairs(schema) do
    if type(v) == "table" and not (v[1] ~= nil) then
      r[k] = sanitize((type(data) == "table") and data[k] or nil, v)
    else
      r[k] = (type(data) == "table" and data[k] ~= nil) and data[k] or deepClone(v)
    end
  end
  if type(data) == "table" then
    for k, v in pairs(data) do
      if r[k] == nil then r[k] = deepClone(v) end
    end
  end
  return r
end

local function sanitizeName(name)
  if not name then return nil end
  return name:gsub("[/\\:*?\"<>|]", "_"):lower()
end

function StorageEngine.new(opts)
  local filename = opts.filename
  local defaults = opts.defaults or {}
  local strategy = opts.pathStrategy or "profile"
  local debounceMs = opts.debounceMs or 500
  local maxFileSize = opts.maxFileSize or 10 * 1024 * 1024
  local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

  local s = { cache = nil, dirty = false, scheduled = false, init = false, char = nil, base = nil, file = nil }

  local function getChar()
    if s.char then return s.char end
    if player and player.getName then
      local ok, n = pcall(function() return player:getName() end)
      if ok and n then s.char = sanitizeName(n); return s.char end
    end
    local C = getClient()
    local lp = (C and C.getLocalPlayer) and C.getLocalPlayer() or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
    if lp and lp:getName() then s.char = sanitizeName(lp:getName()); return s.char end
    return nil
  end

  local function buildPaths()
    if strategy == "profile" then
      local p = g_settings.getNumber('profile') or 1
      s.base = "/bot/" .. configName .. "/nExBot_configs/profile_" .. p .. "/"
      s.file = s.base .. filename
      return true
    end
    local c = getChar()
    if not c then return false end
    s.base = "/bot/" .. configName .. "/nExBot_configs/characters/" .. c .. "/"
    s.file = s.base .. filename
    return true
  end

  local function ensureDir()
    if not s.base then return end
    if not g_resources.directoryExists(s.base) then
      if strategy == "character" then
        local pp = "/bot/" .. configName .. "/nExBot_configs/characters/"
        if not g_resources.directoryExists(pp) then g_resources.makeDir(pp) end
      end
      g_resources.makeDir(s.base)
    end
  end

  local function readFile()
    if not s.file then return nil end
    if not g_resources.fileExists(s.file) then return nil end
    local ok, c = pcall(function() return g_resources.readFileContents(s.file) end)
    if not ok or not c then return nil end
    local ok2, d = pcall(function() return json.decode(c) end)
    if not ok2 or type(d) ~= "table" then return nil end
    return d
  end

  local function writeFile(data)
    if not s.file or not data then return false end
    local ok, c = pcall(function() return json.encode(data, 2) end)
    if not ok or not c then return false end
    if #c > maxFileSize then return false end
    ensureDir()
    return pcall(function() g_resources.writeFileContents(s.file, c) end)
  end

  local function load()
    if s.init and s.cache then return s.cache end
    if not buildPaths() then return deepClone(defaults) end
    s.cache = sanitize(readFile(), defaults)
    s.init = true
    return s.cache
  end

  local function scheduleSave()
    if s.scheduled then return end
    s.scheduled = true
    schedule(debounceMs, function()
      s.scheduled = false
      if s.dirty and s.cache then writeFile(s.cache); s.dirty = false end
    end)
  end

  local function get(path)
    local d = load()
    if not path then return d end
    return dotGet(d, path)
  end

  local function set(path, value)
    if not buildPaths() then return false end
    local d = load()
    s.cache = dotSet(d, path, value)
    s.dirty = true
    scheduleSave()
    return true
  end

  local function isReady()
    if strategy == "profile" then return s.init end
    return getChar() ~= nil and s.init
  end

  local function name()
    return s.char or getChar()
  end

  return {
    load = load,
    save = function() if s.cache then writeFile(s.cache); s.dirty = false end end,
    get = get,
    set = set,
    scheduleSave = scheduleSave,
    getData = function() return s.cache end,
    getPath = function() return s.file end,
    isReady = isReady,
    getCharName = name,
    getCharacterName = name,
    deepClone = deepClone,
    getSchema = function() return deepClone(defaults) end,
    reload = function() s.init = false; s.cache = nil; s.char = nil; load() end,
    getOr = function(p, d) local v = get(p); return v == nil and d or v end,
    batch = function(updates)
      if type(updates) ~= "table" then return end
      local d = load()
      for p, v in pairs(updates) do d = dotSet(d, p, v) end
      s.cache = d; s.dirty = true; scheduleSave()
    end,
    toggle = function(p) local v = get(p); set(p, not v); return not v end,
    getModule = function(m) return get(m) or deepClone(defaults[m] or {}) end,
    setModule = function(m, c) return set(m, c) end,
    migrateFromStorage = function(m, k)
      if not storage then return false end
      if not storage[k] then return false end
      local e = get(m)
      if e then local has = false; for _ in pairs(e) do has = true; break end; if has then return false end end
      set(m, deepClone(storage[k]))
      return true
    end,
    getStats = function()
      return { charName = s.char, initialized = s.init, dirty = s.dirty, basePath = s.base }
    end,
  }
end

nExBot.StorageEngine = StorageEngine
return StorageEngine
