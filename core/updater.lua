--[[
  nExBot Auto-Updater
  
  Checks GitHub for new versions and updates automatically.
  
  Flow:
    1. Probe for available HTTP API (HTTP / g_http)
    2. Read local version from /version file (or storage)
    3. Fetch remote version from GitHub raw content
    4. Compare using semver (via nExBot.Shared)
    5. If remote > local: download & apply update with retry + progress
    
  Compatible with: OTCv8 (HTTP.*) and OpenTibiaBR (g_http.*)
  Fallback: opens GitHub releases page when no HTTP module found
  
  GitHub Repository: https://github.com/mCodex/nExBot
]]

local Updater = {}

if not nExBot or not nExBot.Shared or not nExBot.paths then
  warn("[Updater] nExBot.Shared or nExBot.paths not available — updater disabled.")
  nExBot = nExBot or {}
  nExBot.Updater = Updater
  return Updater
end

if nExBot.isModInstall then
  info("[Updater] Running from mod folder — auto-updates disabled.")
  nExBot.Updater = Updater
  return Updater
end

local Shared = nExBot.Shared
local P = nExBot.paths

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local GITHUB_OWNER    = "mCodex"
local GITHUB_REPO     = "nExBot"
local GITHUB_BRANCH   = "main"
local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/"
    .. GITHUB_OWNER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH
local GITHUB_API_BASE = "https://api.github.com/repos/"
    .. GITHUB_OWNER .. "/" .. GITHUB_REPO
local GITHUB_RELEASES = "https://github.com/"
    .. GITHUB_OWNER .. "/" .. GITHUB_REPO .. "/releases"

local VERSION_FILE       = "version"
local CHECK_INTERVAL_MS  = 3600000  -- 1 hour
local MAX_RETRIES        = 2        -- extra retries per file download
local RETRY_DELAY_MS     = 500
local DOWNLOAD_DELAY_MS  = 50       -- polite delay between sequential files

-- Patterns for files we SKIP during update (user configs, docs, meta).
local EXCLUDE_PATTERNS = {
  "^data/", "^docs/", "^%.", "^CONTRIBUTING", "^README", "^LICENSE",
  "nExBot_configs/", "cavebot_configs/", "targetbot_configs/", "^storage/",
}

-- Extensions we DO update.
local INCLUDE_EXT = { lua = true, otui = true, ui = true, cfg = true }

-- ============================================================================
-- FILE SYSTEM (SRP: only file I/O)
-- ============================================================================

local function readLocalVersion()
  local ok, content = pcall(g_resources.readFileContents, P.base .. "/" .. VERSION_FILE)
  return ok and content and content:match("^%s*(.-)%s*$") or nil
end

--- Read version from storage. Trims and validates; returns nil (and clears
--- storage) if empty, whitespace-only, or not a valid semver.
local function readStorageVersion()
  local raw = storage.updaterInstalledVersion
  if type(raw) ~= "string" then return nil end
  local trimmed = raw:match("^%s*(.-)%s*$")
  if not trimmed or trimmed == "" then
    storage.updaterInstalledVersion = nil
    return nil
  end
  if not Shared.parseSemver(trimmed) then
    warn("[Updater] Invalid stored version '" .. trimmed .. "' — clearing.")
    storage.updaterInstalledVersion = nil
    return nil
  end
  return trimmed
end

--- Best known local version: prefers storage over file.
local function effectiveLocalVersion()
  return readStorageVersion() or readLocalVersion()
end

local function writeLocalVersion(versionStr)
  storage.updaterInstalledVersion = versionStr
  pcall(g_resources.writeFileContents, P.base .. "/" .. VERSION_FILE, versionStr)
  return true
end

local function writeFile(relativePath, content)
  local fullPath = P.base .. "/" .. relativePath
  local ok, err = pcall(g_resources.writeFileContents, fullPath, content)
  if not ok then warn("[Updater] Write failed: " .. relativePath .. " - " .. tostring(err)) end
  return ok
end

--- Create all parent segments of relativePath under basePath iteratively.
local function ensureDirRecursive(basePath, relativePath)
  local segments = {}
  for seg in relativePath:gmatch("[^/]+") do segments[#segments + 1] = seg end
  local built = basePath
  for _, seg in ipairs(segments) do
    built = built .. "/" .. seg
    local ok, err = pcall(g_resources.makeDir, built)
    if not ok then
      warn("[Updater] makeDir threw: " .. built .. " - " .. tostring(err))
      return false
    end
    local okV, exists = pcall(g_resources.directoryExists, built)
    if not (okV and exists) then
      warn("[Updater] makeDir did not create: " .. built)
      return false
    end
  end
  return true
end

local function ensureDir(relativePath)
  return ensureDirRecursive(P.base, relativePath)
end

-- ============================================================================
-- HTTP LAYER — auto-detect available API
-- ============================================================================

local _httpBackend = nil  -- resolved once, cached for session

--- Probe available HTTP modules. Call once, result is cached.
-- @return string "HTTP" | "g_http" | nil
local function detectHttpBackend()
  if _httpBackend then return _httpBackend end

  -- OTCv8 exposes a global `HTTP` table
  if type(HTTP) == "table" and type(HTTP.get) == "function" then
    _httpBackend = "HTTP"
    info("[Updater] HTTP backend: OTCv8 (HTTP.*)")
    return _httpBackend
  end

  -- OpenTibiaBR / mehah fork exposes `g_http`
  if type(g_http) == "table" and type(g_http.get) == "function" then
    _httpBackend = "g_http"
    info("[Updater] HTTP backend: OpenTibiaBR (g_http.*)")
    return _httpBackend
  end

  warn("[Updater] No HTTP module detected - update will fallback to browser.")
  return nil
end

--- Unified GET request. callback(content, err)
local function httpGet(url, callback)
  local backend = detectHttpBackend()

  if backend == "HTTP" then
    HTTP.get(url, function(response, err)
      if err then
        callback(nil, tostring(err))
      elseif response and response ~= "" then
        callback(response, nil)
      else
        callback(nil, "Empty HTTP response")
      end
    end)
    return true
  end

  if backend == "g_http" then
    g_http.get(url, function(data, err)
      if err or not data then
        callback(nil, tostring(err or "No data"))
      else
        callback(data, nil)
      end
    end)
    return true
  end

  callback(nil, "No HTTP module available")
  return false
end

--- Open URL in the user's browser (best-effort).
local function openInBrowser(url)
  if g_platform and g_platform.openUrl then
    g_platform.openUrl(url)
  else
    warn("[Updater] Cannot open browser — g_platform.openUrl not available. Visit manually: " .. tostring(url))
  end
end

-- ============================================================================
-- GITHUB API
-- ============================================================================

local function fetchRemoteVersion(callback)
  httpGet(GITHUB_RAW_BASE .. "/" .. VERSION_FILE, function(content, err)
    if err then callback(nil, "Fetch version: " .. err) return end
    local ver = content and content:match("^%s*(.-)%s*$")
    if not ver or not Shared.parseSemver(ver) then
      callback(nil, "Invalid remote version: " .. tostring(content))
      return
    end
    callback(ver, nil)
  end)
end

local function fetchFileTree(callback)
  local url = GITHUB_API_BASE .. "/git/trees/" .. GITHUB_BRANCH .. "?recursive=1"
  httpGet(url, function(content, err)
    if err then callback(nil, "File tree: " .. err) return end
    local ok, data = pcall(json.decode, content)
    if not ok or not data or not data.tree then
      callback(nil, "Parse file tree failed")
      return
    end
    local files = {}
    for _, entry in ipairs(data.tree) do
      if entry.type == "blob" then files[#files + 1] = entry.path end
    end
    callback(files, nil)
  end)
end

--- Download a single file with automatic retry.
-- @param relativePath  e.g. "core/lib.lua"
-- @param callback      function(content, err)
-- @param attempt       (internal) current attempt number
local function downloadFile(relativePath, callback, attempt)
  attempt = attempt or 1
  httpGet(GITHUB_RAW_BASE .. "/" .. relativePath, function(content, err)
    if (err or not content) and attempt <= MAX_RETRIES then
      schedule(RETRY_DELAY_MS, function()
        downloadFile(relativePath, callback, attempt + 1)
      end)
      return
    end
    callback(content, err)
  end)
end

-- ============================================================================
-- UPDATE ENGINE
-- ============================================================================

local _state = {
  isChecking  = false,
  isUpdating  = false,
  localVer    = nil,
  remoteVer   = nil,
  progress    = 0,
  totalFiles  = 0,
  errors      = {},
  status      = "idle",   -- idle | checking | update_available | updating | done | error | no_http
}

--- Returns true when the given path should be included in an update.
local function isUpdatable(path)
  local ext = path:match("%.([^%.]+)$")
  local relevant = INCLUDE_EXT[ext] or path == "version" or path == "_Loader.lua"
  if not relevant then return false end
  for _, pat in ipairs(EXCLUDE_PATTERNS) do
    if path:match(pat) then return false end
  end
  return true
end

--- Check for update. callback(available, localStr, remoteStr, err)
local function checkForUpdate(callback)
  if _state.isChecking then callback(false, nil, nil, "Already checking") return end
  if not detectHttpBackend() then
    _state.status = "no_http"
    callback(false, nil, nil, "No HTTP module - cannot check")
    return
  end

  _state.isChecking = true
  _state.status = "checking"

  local localStr = effectiveLocalVersion()
  _state.localVer = localStr
  if not localStr then
    _state.isChecking = false; _state.status = "error"
    callback(false, nil, nil, "Cannot read local version"); return
  end
  local localSem = Shared.parseSemver(localStr)
  if not localSem then
    _state.isChecking = false; _state.status = "error"
    callback(false, nil, nil, "Invalid local version: " .. localStr); return
  end

  fetchRemoteVersion(function(remoteStr, err)
    _state.isChecking = false
    if err then _state.status = "error"; callback(false, localStr, nil, err); return end

    _state.remoteVer = remoteStr
    local remoteSem = Shared.parseSemver(remoteStr)
    if Shared.compareSemver(localSem, remoteSem) < 0 then
      _state.status = "update_available"
      callback(true, localStr, remoteStr, nil)
    else
      _state.status = "idle"
      callback(false, localStr, remoteStr, nil)
    end
  end)
end

--- Apply the update. callback(success, errMsg)
local function applyUpdate(callback, onProgress)
  if _state.isUpdating then callback(false, "Already updating") return end
  _state.isUpdating = true
  _state.status   = "updating"
  _state.progress = 0
  _state.errors   = {}

  info("[Updater] Updating to v" .. tostring(_state.remoteVer) .. " ...")

  fetchFileTree(function(fileList, err)
    if err or not fileList or #fileList == 0 then
      _state.isUpdating = false; _state.status = "error"
      callback(false, err or "No files found"); return
    end

    local updateFiles = {}
    for _, path in ipairs(fileList) do
      if isUpdatable(path) then updateFiles[#updateFiles + 1] = path end
    end
    _state.totalFiles = #updateFiles

    if #updateFiles == 0 then
      _state.isUpdating = false; _state.status = "error"
      callback(false, "No updatable files"); return
    end

    info("[Updater] Downloading " .. #updateFiles .. " files ...")

    local idx = 0
    local function downloadNext()
      idx = idx + 1
      if idx > #updateFiles then
        if _state.remoteVer then writeLocalVersion(_state.remoteVer) end
        _state.isUpdating = false
        _state.progress   = 100
        if onProgress then onProgress(100, #updateFiles, #updateFiles) end

        if #_state.errors > 0 then
          _state.status = "done"
          local msg = #_state.errors .. " failed: " .. table.concat(_state.errors, ", ")
          warn("[Updater] Completed with errors: " .. msg)
          callback(true, msg)
        else
          _state.status = "done"
          info("[Updater] v" .. tostring(_state.remoteVer) .. " installed ("
            .. #updateFiles .. " files). Restart bot to apply.")
          callback(true, nil)
        end
        return
      end

      local filePath = updateFiles[idx]
      _state.progress = math.floor((idx / #updateFiles) * 100)
      if onProgress then onProgress(_state.progress, idx, #updateFiles) end

      local dir = filePath:match("(.+)/[^/]+$")
      if dir then ensureDir(dir) end

      downloadFile(filePath, function(content, dlErr)
        if dlErr or not content then
          _state.errors[#_state.errors + 1] = filePath
          warn("[Updater] Failed: " .. filePath .. " - " .. tostring(dlErr))
        else
          writeFile(filePath, content)
        end
        schedule(DOWNLOAD_DELAY_MS, downloadNext)
      end)
    end

    downloadNext()
  end)
end

-- ============================================================================
-- UI
-- ============================================================================

local _ui

local function resetCheckButton(text)
  if not _ui then return end
  _ui.checkNow:enable()
  _ui.checkNow:setText(text or "Check")
end

local function bindCheckClick()
  if not _ui then return end
  _ui.checkNow.onClick = function()
    _ui.checkNow:setText("..."); _ui.checkNow:disable()

    if not detectHttpBackend() then
      info("[Updater] No HTTP module - opening releases page.")
      openInBrowser(GITHUB_RELEASES)
      schedule(2000, function() resetCheckButton() end)
      return
    end

    checkForUpdate(function(available, localVer, remoteVer, err)
      _ui.checkNow:enable()
      if err then
        _ui.checkNow:setText("Error"); warn("[Updater] " .. err)
        schedule(3000, function() resetCheckButton() end)
        return
      end

      if available then
        _ui.checkNow:setText("Update!")
        info("[Updater] v" .. tostring(localVer) .. " -> v" .. tostring(remoteVer))
        -- re-bind button to trigger download
        _ui.checkNow.onClick = function()
          _ui.checkNow:setText("0%"); _ui.checkNow:disable()
          applyUpdate(function(success, msg)
            if success then
              _ui.checkNow:setText("Done!")
              info("[Updater] Restart bot to apply update.")
            else
              _ui.checkNow:setText("Failed"); warn("[Updater] " .. tostring(msg))
            end
            schedule(5000, function() resetCheckButton(); bindCheckClick() end)
          end, function(pct)
            if _ui then _ui.checkNow:setText(pct .. "%") end
          end)
        end
      else
        _ui.checkNow:setText("Up to date")
        info("[Updater] v" .. tostring(localVer) .. " is current.")
        schedule(3000, function() resetCheckButton() end)
      end
    end)
  end
end

local function createUpdaterUI()
  setDefaultTab("Main")

  _ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: autoCheck
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Auto-Updater')

  Button
    id: checkNow
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Check
]])
  _ui:setId("nExBotUpdater")

  storage.updaterAutoCheck = storage.updaterAutoCheck ~= false
  _ui.autoCheck:setOn(storage.updaterAutoCheck)
  _ui.autoCheck.onClick = function(w)
    storage.updaterAutoCheck = not storage.updaterAutoCheck
    w:setOn(storage.updaterAutoCheck)
  end

  bindCheckClick()
  return _ui
end

-- ============================================================================
-- AUTO-CHECK SCHEDULER
-- ============================================================================

local function startAutoCheck()
  schedule(10000, function()
    if not storage.updaterAutoCheck then return end
    if not detectHttpBackend() then return end

    checkForUpdate(function(available, localVer, remoteVer, err)
      if err then warn("[Updater] Auto-check: " .. err) return end
      if available then
        info("[Updater] v" .. tostring(remoteVer) .. " available! Click 'Update!' to install.")
      end
    end)

    -- periodic re-checks
    local function loop()
      schedule(CHECK_INTERVAL_MS, function()
        if storage.updaterAutoCheck and detectHttpBackend() then
          checkForUpdate(function(available, _, remoteVer)
            if available then info("[Updater] v" .. tostring(remoteVer) .. " available.") end
          end)
        end
        loop()
      end)
    end
    loop()
  end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function Updater.checkForUpdate(cb) return checkForUpdate(cb) end
function Updater.applyUpdate(cb, onProgress) return applyUpdate(cb, onProgress) end

-- ============================================================================
-- INITIALIZE
-- ============================================================================

createUpdaterUI()
startAutoCheck()

nExBot.Updater = Updater
return Updater
