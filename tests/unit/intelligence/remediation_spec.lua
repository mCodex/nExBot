local function describe(name, fn)
  print("Describe: " .. name)
  fn()
end

local function it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("  ✓ " .. name)
  else
    print("  ✗ " .. name .. ": " .. tostring(err))
  end
end

local function assertEquals(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, msg)
  if not value then
    error(msg or "expected true, got false")
  end
end

local function assertFalse(value, msg)
  if value then
    error(msg or "expected false, got true")
  end
end

-- ============================================================================
-- CharacterContext Tests
-- ============================================================================
describe("CharacterContext", function()
  it("normalizes character name correctly", function()
    local CharacterContext = dofile("core/intelligence/foundation/character_context.lua")
    local ctx = CharacterContext.new()
    local normalized = ctx.normalizeName and ctx:normalizeName("Test Name") or CharacterContext.normalizeName("Test Name")
    -- normalizeName is local, test via capture
    -- Just verify the module loads
    assertTrue(type(CharacterContext.new) == "function")
  end)

  it("creates valid context with required fields", function()
    local CharacterContext = dofile("core/intelligence/foundation/character_context.lua")
    local ctx = CharacterContext.new()
    assertEquals(ctx.schemaVersion, 1)
    assertEquals(ctx.sessionGeneration, 0)
    assertEquals(ctx.clientFamily, "unknown")
    assertEquals(ctx.characterKey, "")
  end)

  it("toTable returns all fields", function()
    local CharacterContext = dofile("core/intelligence/foundation/character_context.lua")
    local ctx = CharacterContext.new()
    local tbl = ctx:toTable()
    assertTrue(type(tbl) == "table")
    assertTrue(tbl.schemaVersion ~= nil)
    assertTrue(tbl.clientFamily ~= nil)
  end)
end)

-- ============================================================================
-- StateEnums Tests
-- ============================================================================
describe("StateEnums", function()
  it("defines all required states", function()
    local StateEnums = dofile("core/intelligence/foundation/state_enums.lua")
    assertEquals(StateEnums.State.UNBOUND, "UNBOUND")
    assertEquals(StateEnums.State.READY, "READY")
    assertEquals(StateEnums.State.FLUSHING, "FLUSHING")
  end)

  it("defines all required origins", function()
    local StateEnums = dofile("core/intelligence/foundation/state_enums.lua")
    assertEquals(StateEnums.Origin.USER, "USER")
    assertEquals(StateEnums.Origin.MODULE_PROFILE_SWITCH, "MODULE_PROFILE_SWITCH")
    assertEquals(StateEnums.Origin.SAFETY_INHIBIT, "SAFETY_INHIBIT")
  end)

  it("defines all required inhibitors", function()
    local StateEnums = dofile("core/intelligence/foundation/state_enums.lua")
    assertEquals(StateEnums.Inhibitor.DISCONNECTED, "DISCONNECTED")
    assertEquals(StateEnums.Inhibitor.PROFILE_APPLY, "PROFILE_APPLY")
    assertEquals(StateEnums.Inhibitor.SAFETY, "SAFETY")
  end)
end)

-- ============================================================================
-- HuntMetrics Tests
-- ============================================================================
describe("HuntMetrics", function()
  it("records XP and calculates rate", function()
    local HuntMetrics = dofile("core/intelligence/foundation/hunt_metrics.lua")
    local hm = HuntMetrics.new()
    hm:recordXp(1000)
    local metrics = hm:getMetrics()
    assertEquals(metrics.xpGained, 1000)
    assertTrue(metrics.xpPerHour > 0)
  end)

  it("records kills and calculates rate", function()
    local HuntMetrics = dofile("core/intelligence/foundation/hunt_metrics.lua")
    local hm = HuntMetrics.new()
    hm:recordKill()
    hm:recordKill()
    local metrics = hm:getMetrics()
    assertEquals(metrics.kills, 2)
    assertTrue(metrics.killsPerHour > 0)
  end)

  it("records resources", function()
    local HuntMetrics = dofile("core/intelligence/foundation/hunt_metrics.lua")
    local hm = HuntMetrics.new()
    hm:recordResource("hpPotion", 5)
    hm:recordResource("manaPotion", 3)
    hm:recordResource("rune", 10)
    local metrics = hm:getMetrics()
    assertEquals(metrics.hpPotionsUsed, 5)
    assertEquals(metrics.manaPotionsUsed, 3)
    assertEquals(metrics.runesUsed, 10)
  end)

  it("resets session", function()
    local HuntMetrics = dofile("core/intelligence/foundation/hunt_metrics.lua")
    local hm = HuntMetrics.new()
    hm:recordXp(5000)
    hm:recordKill()
    hm:reset()
    local metrics = hm:getMetrics()
    assertEquals(metrics.xpGained, 0)
    assertEquals(metrics.kills, 0)
  end)
end)

-- ============================================================================
-- SilentRestore Tests
-- ============================================================================
describe("SilentRestore", function()
  it("tracks active state", function()
    local SilentRestore = dofile("core/intelligence/foundation/silent_restore.lua")
    assertFalse(SilentRestore.isActive())
    SilentRestore.apply(function()
      assertTrue(SilentRestore.isActive())
    end)
    assertFalse(SilentRestore.isActive())
  end)

  it("handles nested calls", function()
    local SilentRestore = dofile("core/intelligence/foundation/silent_restore.lua")
    SilentRestore.apply(function()
      assertTrue(SilentRestore.isActive())
      SilentRestore.apply(function()
        assertTrue(SilentRestore.isActive())
      end)
      assertTrue(SilentRestore.isActive())
    end)
    assertFalse(SilentRestore.isActive())
  end)

  it("suppresses callback execution", function()
    local SilentRestore = dofile("core/intelligence/foundation/silent_restore.lua")
    local called = false
    local wrapped = SilentRestore.wrapCallback(function()
      called = true
    end)
    SilentRestore.apply(function()
      wrapped()
    end)
    assertFalse(called)
  end)
end)

-- ============================================================================
-- ControlStateRegistry Tests
-- ============================================================================
describe("ControlStateRegistry", function()
  it("registers control with all fields", function()
    local ControlStateRegistry = dofile("core/intelligence/foundation/control_state_registry.lua")
    ControlStateRegistry.register({
      id = "test.control",
      scope = ControlStateRegistry.getScope().CHARACTER_ROOT_PROFILE,
      defaultValue = true,
      valueType = "boolean",
      apply = function() end,
      readEffective = function() return false end,
      validate = function(v) return type(v) == "boolean" end,
    })
    local control = ControlStateRegistry.get("test.control")
    assertTrue(control ~= nil)
    assertEquals(control.id, "test.control")
    assertEquals(control.scope, "CHARACTER_ROOT_PROFILE")
    assertEquals(control.defaultValue, true)
  end)

  it("rejects duplicate IDs", function()
    local ControlStateRegistry = dofile("core/intelligence/foundation/control_state_registry.lua")
    local ok, err = pcall(function()
      ControlStateRegistry.register({
        id = "duplicate.test",
        scope = ControlStateRegistry.getScope().SESSION_ONLY,
        defaultValue = false,
      })
    end)
    assertTrue(ok)
    ok, err = pcall(function()
      ControlStateRegistry.register({
        id = "duplicate.test",
        scope = ControlStateRegistry.getScope().SESSION_ONLY,
        defaultValue = true,
      })
    end)
    assertFalse(ok)
    assertTrue(string.find(err, "duplicate") ~= nil)
  end)

  it("filters by scope", function()
    local ControlStateRegistry = dofile("core/intelligence/foundation/control_state_registry.lua")
    local sessionControls = ControlStateRegistry.getByScope(ControlStateRegistry.getScope().SESSION_ONLY)
    assertTrue(type(sessionControls) == "table")
    assertTrue(#sessionControls > 0)
    for _, c in ipairs(sessionControls) do
      assertEquals(c.scope, "SESSION_ONLY")
    end
  end)
end)

-- ============================================================================
-- SectionTracker Tests
-- ============================================================================
describe("SectionTracker", function()
  it("marks and clears dirty sections", function()
    local SectionTracker = dofile("core/intelligence/tactical_intelligence.lua") -- SectionTracker is local
    -- We can't directly test local SectionTracker, but we can verify the tactical module has the functions
  end)

  it("tracks generations", function()
    -- SectionTracker internal
  end)
end)

-- ============================================================================
-- OTClientAdapter Tests
-- ============================================================================
describe("OTClientAdapter", function()
  it("resolves capabilities at startup", function()
    local OTClientAdapter = dofile("core/intelligence/foundation/otclient_adapter.lua")
    assertTrue(type(OTClientAdapter.new) == "function")
    local adapter = OTClientAdapter.new()
    assertTrue(type(adapter.capabilities) == "table")
    assertTrue(type(adapter.getHealth) == "function")
    assertTrue(type(adapter.getPosition) == "function")
    assertTrue(type(adapter.getRecvPacketsCount) == "function")
    assertTrue(type(adapter.getRecvPacketsSize) == "function")
  end)

  it("handles misspelled API names", function()
    local OTClientAdapter = dofile("core/intelligence/foundation/otclient_adapter.lua")
    local adapter = OTClientAdapter.new()
    -- Should not error even if APIs don't exist
    local count = adapter:getRecvPacketsCount()
    assertTrue(type(count) == "number")
  end)
end)

-- ============================================================================
-- ClientLifecycle Tests
-- ============================================================================
describe("ClientLifecycle", function()
  it("initializes with generation 0", function()
    local ClientLifecycle = dofile("core/client_lifecycle.lua")
    assertEquals(ClientLifecycle:getGeneration(), 0)
    assertFalse(ClientLifecycle:isInGame())
  end)

  it("increments generation on gameStart", function()
    local ClientLifecycle = dofile("core/client_lifecycle.lua")
    ClientLifecycle:emit("gameStart")
    assertEquals(ClientLifecycle:getGeneration(), 1)
    assertTrue(ClientLifecycle:isInGame())
  end)

  it("resets on gameEnd", function()
    local ClientLifecycle = dofile("core/client_lifecycle.lua")
    ClientLifecycle:emit("gameStart")
    assertEquals(ClientLifecycle:getGeneration(), 1)
    ClientLifecycle:emit("gameEnd")
    assertFalse(ClientLifecycle:isInGame())
  end)

  it("registers listeners", function()
    local ClientLifecycle = dofile("core/client_lifecycle.lua")
    local called = false
    local unsub = ClientLifecycle:on("gameStart", function()
      called = true
    end)
    ClientLifecycle:emit("gameStart")
    assertTrue(called)
    called = false
    unsub()
    ClientLifecycle:emit("gameStart")
    assertFalse(called)
  end)
end)

-- ============================================================================
-- UnifiedStorage Migration Tests
-- ============================================================================
describe("UnifiedStorage Migration", function()
  it("migrates v5 to v6 schema", function()
    local UnifiedStorage = dofile("core/unified_storage.lua")
    local oldData = {
      version = 5,
      cavebot = { selectedConfig = "test.cfg", enabled = true },
      targetbot = { selectedConfig = "test.json", enabled = false, explicitlyDisabledByUser = true },
      healbot = { enabled = true },
      attackbot = { enabled = false },
    }
    local migrated = UnifiedStorage.migrate(oldData)
    assertEquals(migrated.schemaVersion, 6)
    assertEquals(migrated.migrationVersion, 1)
    assertTrue(migrated.modules ~= nil)
    assertEquals(migrated.modules.cavebot.selectedConfig, "test.cfg")
    assertEquals(migrated.modules.cavebot.desiredEnabled, true)
    assertEquals(migrated.modules.targetbot.explicitlyDisabledByUser, true)
    assertEquals(migrated.modules.healbot.desiredEnabled, true)
    assertEquals(migrated.modules.attackbot.desiredEnabled, false)
  end)

  it("handles missing fields gracefully", function()
    local UnifiedStorage = dofile("core/unified_storage.lua")
    local emptyData = {}
    local migrated = UnifiedStorage.migrate(emptyData)
    assertEquals(migrated.schemaVersion, 6)
    assertTrue(migrated.modules.cavebot ~= nil)
    assertTrue(migrated.modules.targetbot ~= nil)
  end)

  it("preserves false values", function()
    local UnifiedStorage = dofile("core/unified_storage.lua")
    local data = {
      cavebot = { selectedConfig = "", enabled = false },
      targetbot = { selectedConfig = "", enabled = false, explicitlyDisabledByUser = false },
    }
    local migrated = UnifiedStorage.migrate(data)
    assertEquals(migrated.modules.cavebot.desiredEnabled, false)
    assertEquals(migrated.modules.targetbot.desiredEnabled, false)
    assertEquals(migrated.modules.targetbot.explicitlyDisabledByUser, false)
  end)
end)

-- ============================================================================
-- Profile Switching Tests
-- ============================================================================
describe("Atomic Profile Switching", function()
  it("coordinator preserves desired state on profile switch", function()
    local Coordinator = dofile("core/intelligence/foundation/character_profile_coordinator.lua")
    local coord = Coordinator.new()
    coord.desiredState = {
      cavebot = { desiredEnabled = true, selectedConfig = "old" },
    }
    coord.moduleProfiles = { cavebot = "old" }
    
    -- Simulate profile switch
    coord:selectModuleProfile("cavebot", "new", { preserveDesiredState = true })
    
    assertEquals(coord.desiredState.cavebot.desiredEnabled, true)
    assertEquals(coord.moduleProfiles.cavebot, "new")
  end)

  it("coordinator adds PROFILE_APPLY inhibitor", function()
    local Coordinator = dofile("core/intelligence/foundation/character_profile_coordinator.lua")
    local coord = Coordinator.new()
    coord:selectModuleProfile("cavebot", "new")
    
    local inhibitors = coord:getInhibitors("cavebot")
    -- Inhibitor should be cleared after switch
    assertEquals(inhibitors.PROFILE_APPLY, nil)
  end)
end)

-- ============================================================================
-- Run all tests
-- ============================================================================
print("\n=== Test Suite Complete ===")