describe("intelligence runtime event contract", function()
  local function loadRuntime(nowMs)
    local listeners = {}
    _G.nExBot = { Shared = { nowMs = function() return nowMs or 200 end } }
    _G.g_clock = { millis = function() return nowMs or 200 end }
    _G.g_game = { getLocalPlayer = function() return {} end }
    _G.g_map = { getSpectators = function() return {} end }
    _G.EventBus = {
      on = function(name, callback)
        listeners[name] = callback
        return function()
          listeners[name] = nil
        end
      end,
      emit = function(name, ...)
        if listeners[name] then
          listeners[name](...)
        end
      end,
    }
    _G.UnifiedTick = {
      Priority = { HIGH = 75, IDLE = 10 },
      register = function(name, config)
        listeners.__ticks = listeners.__ticks or {}
        listeners.__ticks[name] = config
      end,
    }
    _G.onGameStart = function(callback)
      listeners.__start = callback
    end
    _G.onGameEnd = function(callback)
      listeners.__end = callback
    end

    dofile("core/intelligence/foundation/lifecycle.lua")
    dofile("core/intelligence/foundation/event_aggregator.lua")
    dofile("core/intelligence/foundation/tactical_blackboard.lua")
    dofile("core/intelligence/foundation/snapshot_builder.lua")
    dofile("core/intelligence/foundation/feature_pipeline.lua")
    dofile("core/intelligence/decisions/safety_envelope.lua")
    dofile("core/intelligence/decisions/default_safety.lua")
    dofile("core/intelligence/decisions/decision_engine.lua")
    dofile("core/intelligence/decisions/cavebot_route_state.lua")
    dofile("core/intelligence/learning/model_registry.lua")
    dofile("core/intelligence/foundation/feature_flags.lua")
    dofile("core/intelligence/learning/model_catalog.lua")
    dofile("core/intelligence/observability/replay.lua")
    dofile("core/intelligence/learning/calibration.lua")
    dofile("core/intelligence/foundation/performance_budget.lua")
    dofile("core/intelligence/decisions/dynamic_lure_state.lua")
    dofile("core/intelligence/decisions/pull_state.lua")
    dofile("core/intelligence/decisions/wave_beam_state.lua")
    dofile("core/intelligence/learning/navigation_cost.lua")
    dofile("core/intelligence/learning/tactical_memory.lua")
    dofile("core/intelligence/learning/context_adjustment.lua")
    dofile("core/intelligence/learning/latency_classifier.lua")
    dofile("core/intelligence/learning/observation_quality.lua")
    dofile("core/intelligence/learning/horizon_counters.lua")
    dofile("core/intelligence/observability/resource_observer.lua")
    dofile("core/intelligence/observability/loot_observer.lua")
    dofile("core/intelligence/learning/reward_model.lua")
    dofile("core/intelligence/learning/reward_vector.lua")
    dofile("core/intelligence/learning/reward_normalizer.lua")
    dofile("core/intelligence/foundation/metrics.lua")
    dofile("core/intelligence/observability/bot_doctor.lua")
    dofile("core/intelligence/foundation/adaptive_scheduler.lua")
    dofile("core/intelligence/ui/ui_presenter.lua")
    dofile("core/intelligence/runtime.lua")
    return nExBot.Intelligence, listeners
  end

  it("publishes canonical snapshot, loot, and session aliases", function()
    local intelligence, listeners = loadRuntime(200)

    listeners.__ticks["intelligence_orchestrator"].handler()
    local events = intelligence.events:recent()
    assert.equals("analytics:snapshot", events[#events].type)

    listeners["loot:received"]("Cyclops", "gold coin")
    events = intelligence.events:recent()
    assert.equals("analytics:loot_observed", events[#events].type)

    listeners["analytics:session:start"]()
    events = intelligence.events:recent()
    assert.equals("analytics:session_started", events[#events].type)

    listeners["analytics:session:end"]()
    events = intelligence.events:recent()
    assert.equals("analytics:session_ended", events[#events].type)
  end)

  it("keeps target_killed distinct from locked completion", function()
    local intelligence, listeners = loadRuntime(300)

    listeners["attacksm:state_changed"]("LOCKED", "ENGAGING", "target_killed")
    local events = intelligence.events:recent()
    assert.equals("TargetKilled", events[#events].type)
  end)

  it("does not register recursive analytics:session_started listener", function()
    local _, listeners = loadRuntime(200)
    assert.is_nil(listeners["analytics:session_started"])
  end)

  it("does not register recursive analytics:session_ended listener", function()
    local _, listeners = loadRuntime(200)
    assert.is_nil(listeners["analytics:session_ended"])
  end)

  it("does not register recursive analytics:loot_observed listener", function()
    local _, listeners = loadRuntime(200)
    assert.is_nil(listeners["analytics:loot_observed"])
  end)

  it("does not call contextAdjustments:observe when activeCombatContext is nil", function()
    local intelligence, listeners = loadRuntime(200)
    listeners["attacksm:state_changed"]("ENGAGING", "IDLE", "target_killed")
    local _, evidence = intelligence.contextAdjustments:get("test")
    assert.equals(0, evidence.samples)
  end)
end)
