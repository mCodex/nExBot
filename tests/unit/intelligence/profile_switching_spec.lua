describe("Atomic Profile Switching", function()
  local CaveBot, TargetBot

  before_each(function()
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = _G.nExBot.Shared or { nowMs = function() return 0 end }
    _G.nExBot.zChanging = function() return false end
    _G.CaveBot = {}
    _G.TargetBot = {}
    _G.EventBus = { on = function() end, emit = function() end }
    _G.UnifiedTick = {}
    CaveBot = _G.CaveBot
    TargetBot = _G.TargetBot
  end)

  it("CaveBot preserves enabled state on profile switch", function()
    CaveBot._on = false
    function CaveBot.setOn(v) CaveBot._on = v end
    function CaveBot.isOn() return CaveBot._on end
    function CaveBot.setOff(v) CaveBot._on = false end
    function CaveBot.setCurrentProfile(p) CaveBot._profile = p end

    CaveBot.setOn(true)
    assert.is_true(CaveBot.isOn())
    CaveBot.setCurrentProfile("test_profile")
    assert.is_true(CaveBot.isOn())
  end)

  it("CaveBot preserves disabled state on profile switch", function()
    CaveBot._on = false
    function CaveBot.setOn(v) CaveBot._on = v end
    function CaveBot.isOn() return CaveBot._on end
    function CaveBot.setOff(v) CaveBot._on = false end
    function CaveBot.setCurrentProfile(p) CaveBot._profile = p end

    CaveBot.setOff(false)
    assert.is_false(CaveBot.isOn())
    CaveBot.setCurrentProfile("test_profile")
    assert.is_false(CaveBot.isOn())
  end)

  it("TargetBot preserves enabled state on profile switch", function()
    TargetBot._on = false
    TargetBot.explicitlyDisabled = false
    function TargetBot.setOn() TargetBot._on = true end
    function TargetBot.isOn() return TargetBot._on end
    function TargetBot.setOff(v) TargetBot._on = false; TargetBot.explicitlyDisabled = true end
    function TargetBot.setCurrentProfile(p) TargetBot._profile = p end

    TargetBot.setOn()
    assert.is_true(TargetBot.isOn())
    TargetBot.setCurrentProfile("test_profile")
    assert.is_true(TargetBot.isOn())
  end)

  it("TargetBot preserves explicitly disabled state on profile switch", function()
    TargetBot._on = false
    TargetBot.explicitlyDisabled = false
    function TargetBot.setOn() TargetBot._on = true end
    function TargetBot.isOn() return TargetBot._on end
    function TargetBot.setOff(v) TargetBot._on = false; TargetBot.explicitlyDisabled = true end
    function TargetBot.setCurrentProfile(p) TargetBot._profile = p end

    TargetBot.setOff(false)
    assert.is_true(TargetBot.explicitlyDisabled)
    TargetBot.setCurrentProfile("test_profile")
    assert.is_true(TargetBot.explicitlyDisabled)
    assert.is_false(TargetBot.isOn())
  end)

  it("TargetBot setOn during profile apply doesn't clear explicit disable", function()
    TargetBot._on = false
    TargetBot.explicitlyDisabled = false
    function TargetBot.setOn(v, force)
      TargetBot._on = true
      if force then TargetBot.explicitlyDisabled = false end
    end
    function TargetBot.isOn() return TargetBot._on end

    TargetBot.explicitlyDisabled = true
    TargetBot.setOn(true, true)
    assert.is_false(TargetBot.explicitlyDisabled)
  end)
end)

describe("UnifiedStorage Migration", function()
  local UnifiedStorage

  before_each(function()
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = { nowMs = function() return 0 end, getClient = function() return {} end, deepClone = function(t) return t end }
    _G.nExBot.StorageEngine = { new = function() return { load = function() end, save = function() end, getData = function() return {} end, getStats = function() return {} end, isReady = function() return false end } end }
    _G.g_resources = { directoryExists = function() return false end, makeDir = function() end, listDirectoryFiles = function() return {} end, readFileContents = function() return nil end, writeFileContents = function() end, deleteFile = function() end }
    _G.json = { encode = function() return "{}" end, decode = function() return {} end }
    _G.g_ui = {}
    _G.schedule = function() end
    local ok, result = pcall(dofile, "core/unified_storage.lua")
    if not ok then warn("UnifiedStorage load: " .. tostring(result)) end
    UnifiedStorage = _G.nExBot.UnifiedStorage
  end)

  it("migrates v5 to v6 schema", function()
    local v5Data = {
      version = 5,
      cavebot = {
        enabled = true,
        selectedConfig = "test.cfg",
      },
      targetbot = {
        enabled = false,
        selectedConfig = "test.json",
        explicitlyDisabledByUser = true,
      },
      healbot = { enabled = true },
      attackbot = { enabled = false },
    }
    local migrated = UnifiedStorage.migrate(v5Data)
    assert.are.equal(6, migrated.schemaVersion)
    assert.are.equal(1, migrated.migrationVersion)
    assert.is_table(migrated.modules)
    assert.is_table(migrated.modules.cavebot)
    assert.is_table(migrated.modules.targetbot)
    assert.is_table(migrated.modules.healbot)
    assert.is_table(migrated.modules.attackbot)
    assert.are.equal("test.cfg", migrated.modules.cavebot.selectedConfig)
    assert.is_true(migrated.modules.cavebot.desiredEnabled)
    assert.are.equal("test.json", migrated.modules.targetbot.selectedConfig)
    assert.is_false(migrated.modules.targetbot.desiredEnabled)
    assert.is_true(migrated.modules.targetbot.explicitlyDisabledByUser)
    assert.is_true(migrated.modules.healbot.desiredEnabled)
    assert.is_false(migrated.modules.attackbot.desiredEnabled)
  end)

  it("handles missing legacy fields", function()
    local v5Data = { version = 5 }
    local migrated = UnifiedStorage.migrate(v5Data)
    assert.are.equal(6, migrated.schemaVersion)
    assert.is_table(migrated.modules.cavebot)
    assert.is_table(migrated.modules.targetbot)
    assert.is_table(migrated.modules.healbot)
    assert.is_table(migrated.modules.attackbot)
    assert.is_false(migrated.modules.cavebot.desiredEnabled)
    assert.is_false(migrated.modules.targetbot.desiredEnabled)
    assert.is_false(migrated.modules.targetbot.explicitlyDisabledByUser)
    assert.is_false(migrated.modules.healbot.desiredEnabled)
    assert.is_false(migrated.modules.attackbot.desiredEnabled)
  end)
end)

describe("SectionTracker", function()
  local sectionTracker

  before_each(function()
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = { nowMs = function() return 0 end }
    local TacticalIntelligence = dofile("core/intelligence/tactical_intelligence.lua")
    sectionTracker = TacticalIntelligence._sectionTracker
  end)

  it("tracks dirty sections", function()
    assert.is_false(sectionTracker:isDirty("test"))
    sectionTracker:markDirty("test")
    assert.is_true(sectionTracker:isDirty("test"))
    sectionTracker:clearDirty("test")
    assert.is_false(sectionTracker:isDirty("test"))
  end)

  it("clears all", function()
    sectionTracker:markDirty("a")
    sectionTracker:markDirty("b")
    sectionTracker:markDirty("c")
    sectionTracker:clearAll()
    assert.is_false(sectionTracker:isDirty("a"))
    assert.is_false(sectionTracker:isDirty("b"))
    assert.is_false(sectionTracker:isDirty("c"))
  end)
end)

describe("OTClientAdapter", function()
  local OTClientAdapter

  before_each(function()
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = { nowMs = function() return 0 end }
    _G.g_game = { getLocalPlayer = function() return {} end }
    _G.g_ui = {}
    _G.g_resources = {}
    _G.g_platform = {}
    _G.EventBus = { on = function() end, emit = function() end }
    OTClientAdapter = dofile("core/intelligence/foundation/otclient_adapter.lua")
  end)

  it("initializes with capabilities", function()
    local adapter = OTClientAdapter.new()
    assert.is_table(adapter)
    assert.is_table(adapter.capabilities)
    assert.is_function(adapter.capabilities.getHealth)
    assert.is_function(adapter.capabilities.getMana)
    assert.is_function(adapter.capabilities.getPosition)
  end)

  it("handles misspelled network APIs", function()
    local adapter = OTClientAdapter.new()
    assert.is_function(adapter.getRecvPacketsCount)
    assert.is_function(adapter.getRecvPacketsSize)
  end)
end)

describe("ClientLifecycle", function()
  local ClientLifecycle

  before_each(function()
    _G.nExBot = _G.nExBot or {}
    _G.nExBot.Shared = { nowMs = function() return 0 end }
    _G.onGameStart = nil
    _G.onGameEnd = nil
    _G.EventBus = { on = function() end, emit = function() end }
    ClientLifecycle = dofile("core/client_lifecycle.lua")
  end)

  it("initializes", function()
    local lifecycle = ClientLifecycle.new()
    assert.is_table(lifecycle)
    assert.are.equal(0, lifecycle:getGeneration())
    assert.is_false(lifecycle:isInGame())
  end)

  it("increments generation on game start", function()
    local lifecycle = ClientLifecycle.new()
    lifecycle:emit("gameStart")
    assert.are.equal(1, lifecycle:getGeneration())
    assert.is_true(lifecycle:isInGame())
  end)

  it("resets on game end", function()
    local lifecycle = ClientLifecycle.new()
    lifecycle:emit("gameStart")
    lifecycle:emit("gameEnd")
    assert.are.equal(1, lifecycle:getGeneration())
    assert.is_false(lifecycle:isInGame())
  end)

  it("supports listeners", function()
    local lifecycle = ClientLifecycle.new()
    local called = false
    lifecycle:on("gameStart", function(gen)
      called = true
      assert.are.equal(2, gen)
    end)
    lifecycle:emit("gameStart")
    assert.is_true(called)
  end)
end)
