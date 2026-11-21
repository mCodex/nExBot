local DEFAULT_MAX_SESSIONS = 200
local DEFAULT_MAX_AGE_SECONDS = 1209600

local Retention = {}
Retention.__index = Retention

function Retention.new(config)
  local self = setmetatable({}, Retention)
  config = config or {}
  self.resources = config.resources
  self.maxSessions = config.maxSessions or DEFAULT_MAX_SESSIONS
  self.maxAgeSeconds = config.maxAgeSeconds or DEFAULT_MAX_AGE_SECONDS
  self.now = config.now or os.time
  return self
end

local function stripTrailingSlash(name)
  return name:gsub("/$", "")
end

function Retention:listDateFolders(root)
  if not self.resources or not self.resources.listDirectoryFiles then return {} end

  local ok, entries = pcall(self.resources.listDirectoryFiles, root, false, false)
  if not ok or type(entries) ~= "table" then return {} end

  local folders = {}
  for _, entry in ipairs(entries) do
    local name = stripTrailingSlash(entry)
    if name:match("^%d%d%d%d%-%d%d%-%d%d$") then
      table.insert(folders, name)
    end
  end

  table.sort(folders)
  return folders
end

function Retention:listSessionDirs(root)
  if not self.resources or not self.resources.listDirectoryFiles then return {} end

  local dateFolders = self:listDateFolders(root)
  local sessions = {}

  for _, dateFolder in ipairs(dateFolders) do
    local dateDir = root .. dateFolder .. "/"
    local ok, entries = pcall(self.resources.listDirectoryFiles, dateDir, false, false)
    if ok and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local name = stripTrailingSlash(entry)
        if name:match("^session%-") then
          table.insert(sessions, {
            name = name,
            path = dateDir .. name .. "/",
            date = dateFolder,
          })
        end
      end
    end
  end

  table.sort(sessions, function(a, b)
    if a.date ~= b.date then return a.date < b.date end
    return a.name < b.name
  end)

  return sessions
end

local function sessionAgeSeconds(session, nowFn)
  local year, month, day = session.date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not year then return 0 end

  local ok, timestamp = pcall(os.time, {
    year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 0,
  })
  if not ok or not timestamp then return 0 end

  return nowFn() - timestamp
end

local function cleanupSession(resources, sessionPath)
  if not resources or not resources.listDirectoryFiles or not resources.deleteFile then return end

  local ok, files = pcall(resources.listDirectoryFiles, sessionPath, false, false)
  if not ok or type(files) ~= "table" then return end

  for _, fileName in ipairs(files) do
    pcall(resources.deleteFile, sessionPath .. stripTrailingSlash(fileName))
  end
end

function Retention:enforce(root, activeSessionDir)
  local sessions = self:listSessionDirs(root)

  local toDelete = {}
  local marked = {}

  for _, session in ipairs(sessions) do
    if session.path ~= activeSessionDir then
      if sessionAgeSeconds(session, self.now) > self.maxAgeSeconds then
        marked[session] = true
      end
    end
  end

  if #sessions > self.maxSessions then
    local overCount = #sessions - self.maxSessions
    for i = 1, overCount do
      local session = sessions[i]
      if session.path ~= activeSessionDir then
        marked[session] = true
      end
    end
  end

  for _, session in ipairs(sessions) do
    if marked[session] then
      table.insert(toDelete, session)
    end
  end

  local deleted = {}
  for _, session in ipairs(toDelete) do
    cleanupSession(self.resources, session.path)
    table.insert(deleted, session.path)
  end

  return { deleted = deleted, keptCount = #sessions - #deleted }
end

nExBot = nExBot or {}
nExBot.IntelligenceTelemetryRetention = Retention

return Retention
