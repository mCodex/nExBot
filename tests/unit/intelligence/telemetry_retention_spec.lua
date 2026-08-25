local Retention = dofile("core/intelligence/telemetry/retention.lua")

local function makeResources(listings, opts)
  opts = opts or {}
  local deleted = {}
  local resources = {
    listDirectoryFiles = function(dir)
      if opts.listErrorFor and opts.listErrorFor[dir] then
        error("boom: listDirectoryFiles failed for " .. dir)
      end
      return listings[dir]
    end,
    deleteFile = function(path)
      if opts.deleteErrorFor and opts.deleteErrorFor[path] then
        error("boom: deleteFile failed for " .. path)
      end
      table.insert(deleted, path)
      return true
    end,
  }
  return resources, deleted
end

describe("IntelligenceTelemetryRetention", function()
  describe("new", function()
    it("returns a retention instance with default config", function()
      local retention = Retention.new()
      assert.is_not_nil(retention)
      assert.is_function(retention.listDateFolders)
      assert.is_function(retention.listSessionDirs)
      assert.is_function(retention.enforce)
      assert.equals(200, retention.maxSessions)
      assert.equals(1209600, retention.maxAgeSeconds)
    end)

    it("accepts overrides", function()
      local retention = Retention.new({ maxSessions = 5, maxAgeSeconds = 100 })
      assert.equals(5, retention.maxSessions)
      assert.equals(100, retention.maxAgeSeconds)
    end)
  end)

  describe("listDateFolders", function()
    it("filters non-date entries and sorts ascending", function()
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-03", "not-a-date/", "2026-08-01/", "2026-08-02", "junk" },
      })
      local retention = Retention.new({ resources = resources })
      local folders = retention:listDateFolders("telemetry/")
      assert.same({ "2026-08-01", "2026-08-02", "2026-08-03" }, folders)
    end)

    it("returns empty table when listDirectoryFiles errors", function()
      local resources = makeResources({}, { listErrorFor = { ["telemetry/"] = true } })
      local retention = Retention.new({ resources = resources })
      local folders = retention:listDateFolders("telemetry/")
      assert.same({}, folders)
    end)

    it("returns empty table when listDirectoryFiles returns nil", function()
      local resources = makeResources({ ["telemetry/"] = nil })
      local retention = Retention.new({ resources = resources })
      local folders = retention:listDateFolders("telemetry/")
      assert.same({}, folders)
    end)

    it("returns empty table when resources missing", function()
      local retention = Retention.new({})
      local folders = retention:listDateFolders("telemetry/")
      assert.same({}, folders)
    end)
  end)

  describe("listSessionDirs", function()
    it("filters non-session entries and builds correct paths", function()
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-01" },
        ["telemetry/2026-08-01/"] = { "session-a/", "session-b", "manifest.json" },
      })
      local retention = Retention.new({ resources = resources })
      local sessions = retention:listSessionDirs("telemetry/")
      assert.equals(2, #sessions)
      assert.equals("session-a", sessions[1].name)
      assert.equals("telemetry/2026-08-01/session-a/", sessions[1].path)
      assert.equals("2026-08-01", sessions[1].date)
      assert.equals("session-b", sessions[2].name)
      assert.equals("telemetry/2026-08-01/session-b/", sessions[2].path)
    end)

    it("collects and sorts across multiple date folders", function()
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-02", "2026-08-01" },
        ["telemetry/2026-08-01/"] = { "session-b" },
        ["telemetry/2026-08-02/"] = { "session-a" },
      })
      local retention = Retention.new({ resources = resources })
      local sessions = retention:listSessionDirs("telemetry/")
      assert.equals(2, #sessions)
      assert.equals("2026-08-01", sessions[1].date)
      assert.equals("2026-08-02", sessions[2].date)
    end)

    it("returns empty table when a date folder listing errors", function()
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-01" },
      }, { listErrorFor = { ["telemetry/2026-08-01/"] = true } })
      local retention = Retention.new({ resources = resources })
      local sessions = retention:listSessionDirs("telemetry/")
      assert.same({}, sessions)
    end)
  end)

  describe("enforce", function()
    it("deletes nothing when under maxSessions and none expired", function()
      local now = os.time({ year = 2026, month = 8, day = 25, hour = 0 })
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-24" },
        ["telemetry/2026-08-24/"] = { "session-a" },
        ["telemetry/2026-08-24/session-a/"] = { "manifest.json" },
      })
      local retention = Retention.new({
        resources = resources, maxSessions = 10, maxAgeSeconds = 1000000, now = function() return now end,
      })
      local result = retention:enforce("telemetry/")
      assert.same({}, result.deleted)
      assert.equals(1, result.keptCount)
    end)

    it("deletes sessions older than maxAgeSeconds", function()
      local now = os.time({ year = 2026, month = 8, day = 25, hour = 0 })
      local resources, deleted = makeResources({
        ["telemetry/"] = { "2026-08-01", "2026-08-24" },
        ["telemetry/2026-08-01/"] = { "session-old" },
        ["telemetry/2026-08-01/session-old/"] = { "manifest.json", "events-0001.json" },
        ["telemetry/2026-08-24/"] = { "session-new" },
        ["telemetry/2026-08-24/session-new/"] = { "manifest.json" },
      })
      local retention = Retention.new({
        resources = resources, maxSessions = 10, maxAgeSeconds = 86400 * 5, now = function() return now end,
      })
      local result = retention:enforce("telemetry/")
      assert.same({ "telemetry/2026-08-01/session-old/" }, result.deleted)
      assert.equals(1, result.keptCount)
      assert.same({
        "telemetry/2026-08-01/session-old/manifest.json",
        "telemetry/2026-08-01/session-old/events-0001.json",
      }, deleted)
    end)

    it("deletes oldest sessions exceeding maxSessions, keeping the newest", function()
      local now = os.time({ year = 2026, month = 8, day = 25, hour = 0 })
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-01", "2026-08-02", "2026-08-03" },
        ["telemetry/2026-08-01/"] = { "session-1" },
        ["telemetry/2026-08-01/session-1/"] = { "manifest.json" },
        ["telemetry/2026-08-02/"] = { "session-2" },
        ["telemetry/2026-08-02/session-2/"] = { "manifest.json" },
        ["telemetry/2026-08-03/"] = { "session-3" },
        ["telemetry/2026-08-03/session-3/"] = { "manifest.json" },
      })
      local retention = Retention.new({
        resources = resources, maxSessions = 2, maxAgeSeconds = 999999999, now = function() return now end,
      })
      local result = retention:enforce("telemetry/")
      assert.same({ "telemetry/2026-08-01/session-1/" }, result.deleted)
      assert.equals(2, result.keptCount)
    end)

    it("never deletes the active session even if expired or over-count", function()
      local now = os.time({ year = 2026, month = 8, day = 25, hour = 0 })
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-01", "2026-08-02" },
        ["telemetry/2026-08-01/"] = { "session-old" },
        ["telemetry/2026-08-01/session-old/"] = { "manifest.json" },
        ["telemetry/2026-08-02/"] = { "session-new" },
        ["telemetry/2026-08-02/session-new/"] = { "manifest.json" },
      })
      local retention = Retention.new({
        resources = resources, maxSessions = 0, maxAgeSeconds = 1, now = function() return now end,
      })
      local result = retention:enforce("telemetry/", "telemetry/2026-08-01/session-old/")
      assert.same({ "telemetry/2026-08-02/session-new/" }, result.deleted)
      assert.equals(1, result.keptCount)
    end)

    it("never throws when listDirectoryFiles or deleteFile error during cleanup", function()
      local now = os.time({ year = 2026, month = 8, day = 25, hour = 0 })
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-01" },
        ["telemetry/2026-08-01/"] = { "session-old" },
        ["telemetry/2026-08-01/session-old/"] = { "manifest.json", "events-0001.json" },
      }, {
        deleteErrorFor = { ["telemetry/2026-08-01/session-old/manifest.json"] = true },
      })
      local retention = Retention.new({
        resources = resources, maxSessions = 10, maxAgeSeconds = 1, now = function() return now end,
      })
      local ok, result = pcall(function() return retention:enforce("telemetry/") end)
      assert.is_true(ok)
      assert.same({ "telemetry/2026-08-01/session-old/" }, result.deleted)
    end)

    it("never throws when the whole listing for a doomed session errors", function()
      local now = os.time({ year = 2026, month = 8, day = 25, hour = 0 })
      local resources = makeResources({
        ["telemetry/"] = { "2026-08-01" },
        ["telemetry/2026-08-01/"] = { "session-old" },
      }, {
        listErrorFor = { ["telemetry/2026-08-01/session-old/"] = true },
      })
      local retention = Retention.new({
        resources = resources, maxSessions = 10, maxAgeSeconds = 1, now = function() return now end,
      })
      local ok, result = pcall(function() return retention:enforce("telemetry/") end)
      assert.is_true(ok)
      assert.same({ "telemetry/2026-08-01/session-old/" }, result.deleted)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceTelemetryRetention", function()
      assert.is_not_nil(nExBot.IntelligenceTelemetryRetention)
    end)
  end)
end)
