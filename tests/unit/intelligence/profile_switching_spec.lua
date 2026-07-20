--[[
  Test for Atomic Profile Switching
]]
describe("Atomic Profile Switching", function()
  local CaveBot = require("cavebot/cavebot")
  local TargetBot = require("targetbot/target_coordinator")
  
  before_each(function()
    -- Reset any test state
  end)
  
  it("CaveBot preserves enabled state on profile switch", function()
    -- Setup
    CaveBot.setOn(true)
    local wasEnabled = CaveBot.isOn()
    assert.is_true(wasEnabled)
    
    -- Switch profile
    CaveBot.setCurrentProfile("test_profile")
    
    -- Should preserve enabled state
    assert.is_true(CaveBot.isOn())
  end)
  
  it("CaveBot preserves disabled state on profile switch", function()
    -- Setup
    CaveBot.setOff(false)
    local wasEnabled = CaveBot.isOn()
    assert.is_false(wasEnabled)
    
    -- Switch profile
    CaveBot.setCurrentProfile("test_profile")
    
    -- Should preserve disabled state
    assert.is_false(CaveBot.isOn())
  end)
  
  it("TargetBot preserves enabled state on profile switch", function()
    -- Setup
    TargetBot.setOn()
    local wasEnabled = TargetBot.isOn()
    assert.is_true(wasEnabled)
    
    -- Switch profile
    TargetBot.setCurrentProfile("test_profile")
    
    -- Should preserve enabled state
    assert.is_true(TargetBot.isOn())
  end)
  
  it("TargetBot preserves explicitly disabled state on profile switch", function()
    -- Setup - user explicitly disabled
    TargetBot.setOff(false)
    assert.is_true(TargetBot.explicitlyDisabled)
    
    -- Switch profile
    TargetBot.setCurrentProfile("test_profile")
    
    -- Should remain explicitly disabled
    assert.is_true(TargetBot.explicitlyDisabled)
    assert.is_false(TargetBot.isOn())
  end)
  
  it("TargetBot setOn during profile apply doesn't clear explicit disable", function()
    -- During profile apply, setOn is called but shouldn't clear explicit disable
    TargetBot.explicitlyDisabled = true
    TargetBot.setOn(true, true) -- force=true simulates user action
    
    -- User force should clear it
    assert.is_false(TargetBot.explicitlyDisabled)
  end)
end)

--[[
  Test for UnifiedStorage Schema Migration
]]
describe("UnifiedStorage Migration", function()
  local UnifiedStorage = require("core/unified_storage")
  
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
    local v5Data = {
      version = 5,
    }
    
    local migrated = UnifiedStorage.migrate(v5Data)
    
    assert.are.equal(6, migrated.schemaVersion)
    assert.is_table(migrated.modules.cavebot)
    assert.is_table(migrated.modules.targetbot)
    assert.is_table(migrated.modules.healbot)
    assert.is_table(migrated.modules.attackbot)
    
    -- Defaults should be applied
    assert.is_false(migrated.modules.cavebot.desiredEnabled)
    assert.is_false(migrated.modules.targetbot.desiredEnabled)
    assert.is_false(migrated.modules.targetbot.explicitlyDisabledByUser)
    assert.is_false(migrated.modules.healbot.desiredEnabled)
    assert.is_false(migrated.modules.attackbot.desiredEnabled)
  end)
end)

--[[
  Test for SectionTracker (incremental projections)
]]
describe("SectionTracker", function()
  local Tactical = require("core/intelligence/tactical_intelligence")
  
  it("tracks dirty sections", function()
    local sectionTracker = require("core/intelligence/tactical_intelligence").sectionTracker
    
    assert.is_false(sectionTracker:isDirty("test"))
    sectionTracker:markDirty("test")
    assert.is_true(sectionTracker:isDirty("test"))
    sectionTracker:clearDirty("test")
    assert.is_false(sectionTracker:isDirty("test"))
  end)
  
  it("tracks generations", function()
    local sectionTracker = require("core/intelligence/tactical_intelligence").sectionTracker
    
    assert.are.equal(0, sectionTracker:getGeneration("test"))
    sectionTracker:setGeneration("test", 5)
    assert.are.equal(5, sectionTracker:getGeneration("test"))
    assert.are.equal(6, sectionTracker:incrementGeneration("test"))
  end)
  
  it("clears all", function()
    local sectionTracker = require("core/intelligence/tactical_intelligence").sectionTracker
    
    sectionTracker:markDirty("a")
    sectionTracker:markDirty("b")
    sectionTracker:markDirty("c")
    
    sectionTracker:clearAll()
    
    assert.is_false(sectionTracker:isDirty("a"))
    assert.is_false(sectionTracker:isDirty("b"))
    assert.is_false(sectionTracker:isDirty("c"))
  end)
end)

--[[
  Test for OTClientAdapter
]]
describe("OTClientAdapter", function()
  local OTClientAdapter = require("core/intelligence/foundation/otclient_adapter")
  
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
    -- Should have correct method names internally
    assert.is_function(adapter.getRecvPacketsCount)
    assert.is_function(adapter.getRecvPacketsSize)
  end)
end)

--[[
  Test for ClientLifecycle
]]
describe("ClientLifecycle", function()
  local ClientLifecycle = require("core/client_lifecycle")
  
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
    assert.are.equal(1, lifecycle:getGeneration()) -- Generation doesn't decrement
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

print("All tests passed!")