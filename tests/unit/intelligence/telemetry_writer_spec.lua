local Writer = dofile("core/intelligence/telemetry/writer.lua")

local function makeResources(overrides)
  local calls = { directoryExists = {}, makeDir = {}, writeFileContents = {} }
  local existing = (overrides and overrides.existingDirs) or {}
  local resources = {
    directoryExists = function(path)
      calls.directoryExists[#calls.directoryExists + 1] = path
      if overrides and overrides.directoryExists then return overrides.directoryExists(path) end
      return existing[path] == true
    end,
    makeDir = function(path)
      calls.makeDir[#calls.makeDir + 1] = path
      if overrides and overrides.makeDir then return overrides.makeDir(path) end
      existing[path] = true
    end,
    writeFileContents = function(path, content)
      calls.writeFileContents[#calls.writeFileContents + 1] = { path, content }
      if overrides and overrides.writeFileContents then return overrides.writeFileContents(path, content) end
    end,
  }
  return resources, calls
end

local function makeCodec(overrides)
  return {
    encode = function(value, indent)
      if overrides and overrides.encode then return overrides.encode(value, indent) end
      return "encoded:" .. tostring(value.schemaVersion or value.chunkIndex or "manifest")
    end,
  }
end

describe("IntelligenceTelemetryWriter", function()
  describe("new", function()
    it("returns a writer instance with the expected interface", function()
      local writer = Writer.new({ resources = makeResources(), codec = makeCodec() })
      assert.is_not_nil(writer)
      assert.is_function(writer.ensureDir)
      assert.is_function(writer.writeChunk)
      assert.is_function(writer.writeManifest)
    end)
  end)

  describe("ensureDir", function()
    it("creates missing nested directories and skips existing ones", function()
      local resources, calls = makeResources({ existingDirs = { ["/bot/"] = true, ["/bot/Foo/"] = true } })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:ensureDir("/bot/Foo/telemetry/session/")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.same({ "/bot/", "/bot/Foo/", "/bot/Foo/telemetry/", "/bot/Foo/telemetry/session/" }, calls.directoryExists)
      assert.same({ "/bot/Foo/telemetry/", "/bot/Foo/telemetry/session/" }, calls.makeDir)
    end)

    it("does not call makeDir when all intermediate directories already exist", function()
      local resources, calls = makeResources({ directoryExists = function() return true end })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:ensureDir("/bot/Foo/telemetry/session/")
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(0, #calls.makeDir)
    end)

    it("returns false when makeDir fails", function()
      local resources = makeResources({
        makeDir = function(path) error("boom:" .. path) end,
      })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:ensureDir("/bot/Foo/telemetry/")
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)

    it("returns false, resources_unavailable when resources is missing methods", function()
      local writer = Writer.new({ resources = {}, codec = makeCodec() })
      local ok, err = writer:ensureDir("/bot/Foo/telemetry/")
      assert.is_false(ok)
      assert.equals("resources_unavailable", err)
    end)
  end)

  describe("writeChunk", function()
    it("rejects invalid dir without calling resources", function()
      local resources, calls = makeResources()
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeChunk(nil, 1, {})
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)
      assert.equals(0, #calls.directoryExists)
      assert.equals(0, #calls.writeFileContents)
    end)

    it("rejects invalid chunkIndex without calling resources", function()
      local resources, calls = makeResources()
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeChunk("/bot/Foo/telemetry/", 0, {})
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)
      assert.equals(0, #calls.directoryExists)
      assert.equals(0, #calls.writeFileContents)

      ok, err = writer:writeChunk("/bot/Foo/telemetry/", "1", {})
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)

      ok, err = writer:writeChunk("/bot/Foo/telemetry/", 1.5, {})
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)
    end)

    it("rejects invalid events without calling resources", function()
      local resources, calls = makeResources()
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeChunk("/bot/Foo/telemetry/", 1, "not a table")
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)
      assert.equals(0, #calls.directoryExists)
      assert.equals(0, #calls.writeFileContents)
    end)

    it("succeeds and returns the zero-padded 4-digit filename path", function()
      local resources = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, path = writer:writeChunk("/bot/Foo/telemetry/", 1, { { type = "seen" } })
      assert.is_true(ok)
      assert.equals("/bot/Foo/telemetry/events-0001.json", path)

      local ok2, path2 = writer:writeChunk("/bot/Foo/telemetry/", 42, {})
      assert.is_true(ok2)
      assert.equals("/bot/Foo/telemetry/events-0042.json", path2)
    end)

    it("writes the expected document shape to resources.writeFileContents", function()
      local resources, calls = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local encodedDoc
      local codec = makeCodec({
        encode = function(value)
          encodedDoc = value
          return "ENCODED"
        end,
      })
      local writer = Writer.new({ resources = resources, codec = codec })
      local events = { { type = "a" }, { type = "b" } }
      local ok, path = writer:writeChunk("/bot/Foo/telemetry/", 3, events)
      assert.is_true(ok)
      assert.equals("/bot/Foo/telemetry/events-0003.json", path)
      assert.equals(1, encodedDoc.schemaVersion)
      assert.equals(3, encodedDoc.chunkIndex)
      assert.equals(2, encodedDoc.count)
      assert.same(events, encodedDoc.events)
      assert.equals(1, #calls.writeFileContents)
      assert.equals("/bot/Foo/telemetry/events-0003.json", calls.writeFileContents[1][1])
      assert.equals("ENCODED", calls.writeFileContents[1][2])
    end)

    it("returns false, encode_failed when codec.encode errors", function()
      local resources = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local codec = makeCodec({ encode = function() error("bad encode") end })
      local writer = Writer.new({ resources = resources, codec = codec })
      local ok, err = writer:writeChunk("/bot/Foo/telemetry/", 1, {})
      assert.is_false(ok)
      assert.equals("encode_failed", err)
    end)

    it("returns false, encode_failed when codec.encode returns a non-string", function()
      local resources = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local codec = makeCodec({ encode = function() return nil end })
      local writer = Writer.new({ resources = resources, codec = codec })
      local ok, err = writer:writeChunk("/bot/Foo/telemetry/", 1, {})
      assert.is_false(ok)
      assert.equals("encode_failed", err)
    end)

    it("returns false when writeFileContents errors", function()
      local resources = makeResources({
        existingDirs = { ["/bot/Foo/telemetry/"] = true },
        writeFileContents = function(path) error("disk full: " .. path) end,
      })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeChunk("/bot/Foo/telemetry/", 1, {})
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)

    it("returns false, <ensureDir error> when the directory cannot be created", function()
      local resources = makeResources({
        makeDir = function(path) error("boom:" .. path) end,
      })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeChunk("/bot/Foo/telemetry/", 1, {})
      assert.is_false(ok)
      assert.is_not_nil(err)
    end)
  end)

  describe("writeManifest", function()
    it("writes to manifest.json", function()
      local resources, calls = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, path = writer:writeManifest("/bot/Foo/telemetry/", { sessions = {} })
      assert.is_true(ok)
      assert.equals("/bot/Foo/telemetry/manifest.json", path)
      assert.equals(1, #calls.writeFileContents)
    end)

    it("writes the manifest table directly without wrapping", function()
      local resources = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local encodedDoc
      local codec = makeCodec({ encode = function(value) encodedDoc = value; return "ENCODED" end })
      local writer = Writer.new({ resources = resources, codec = codec })
      local manifest = { version = 1, chunks = 3 }
      writer:writeManifest("/bot/Foo/telemetry/", manifest)
      assert.same(manifest, encodedDoc)
    end)

    it("can be called multiple times successfully, simulating overwrites", function()
      local resources = makeResources({ existingDirs = { ["/bot/Foo/telemetry/"] = true } })
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok1 = writer:writeManifest("/bot/Foo/telemetry/", { chunks = 1 })
      local ok2 = writer:writeManifest("/bot/Foo/telemetry/", { chunks = 2 })
      local ok3 = writer:writeManifest("/bot/Foo/telemetry/", { chunks = 3 })
      assert.is_true(ok1)
      assert.is_true(ok2)
      assert.is_true(ok3)
    end)

    it("rejects invalid dir without calling resources", function()
      local resources, calls = makeResources()
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeManifest("", { chunks = 1 })
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)
      assert.equals(0, #calls.writeFileContents)
    end)

    it("rejects invalid manifest without calling resources", function()
      local resources, calls = makeResources()
      local writer = Writer.new({ resources = resources, codec = makeCodec() })
      local ok, err = writer:writeManifest("/bot/Foo/telemetry/", "not a table")
      assert.is_false(ok)
      assert.equals("invalid_arguments", err)
      assert.equals(0, #calls.writeFileContents)
    end)
  end)

  describe("defensive dependency handling", function()
    it("never throws when resources and codec are absent", function()
      local writer = Writer.new({})
      assert.has_no.errors(function()
        local ok = writer:ensureDir("/bot/Foo/")
        assert.is_false(ok)
      end)
      assert.has_no.errors(function()
        local ok = writer:writeChunk("/bot/Foo/", 1, {})
        assert.is_false(ok)
      end)
      assert.has_no.errors(function()
        local ok = writer:writeManifest("/bot/Foo/", {})
        assert.is_false(ok)
      end)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceTelemetryWriter", function()
      assert.is_not_nil(nExBot.IntelligenceTelemetryWriter)
    end)
  end)
end)
