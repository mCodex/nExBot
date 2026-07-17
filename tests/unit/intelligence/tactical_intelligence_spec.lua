describe("tactical intelligence facade", function()
  local Tactical

  before_each(function()
    _G.nExBot = {
      Shared = {
        nowMs = function()
          return 1000
        end,
      },
    }

    _G.IntelligenceModelCatalog = {
      names = function()
        return { "MonsterBehaviorModel", "LatencyModel" }
      end,
    }

    _G.UnifiedStorage = {
      get = function(key)
        if key == "targetbot.monsterPatterns" then
          return {
            cyclops = {
              displayName = "Cyclops",
              samples = 4,
              lastSeen = 900,
              confidence = 0.7,
              waveCooldown = 1200,
            },
          }
        elseif key == "targetbot.monsterMetrics.typeStats" then
          return {
            ["dragon lord"] = {
              name = "Dragon Lord",
              sampleCount = 125,
              killCount = 9,
              avgSpeed = 84,
              avgDPS = 42,
              totalKillTime = 18000,
              lastSeen = 950,
            },
          }
        end
      end,
    }

    _G.nExBot.Analytics = {
      isActive = function()
        return true
      end,
      getElapsed = function()
        return 60000
      end,
      getMetrics = function()
        return {
          xpGained = 120,
          xpPerHour = 7200,
          kills = 6,
          killsPerHour = 360,
          combatUptime = 80,
          tilesWalked = 30,
          tilesPerKill = 5,
          damageTaken = 18,
          healingDone = 24,
          survivabilityIndex = 90,
          nearDeathCount = 1,
          hpPotionsUsed = 2,
          manaPotionsUsed = 1,
          runesUsed = 3,
          healSpellsCast = 4,
          attackSpellsCast = 5,
          manaSpent = 300,
          potionsPerHour = 3,
          runesPerHour = 4,
          manaSpentPerHour = 1800,
        }
      end,
      getTrends = function()
        return {
          xpPerHour = { 1000, 2000 },
          killsPerHour = { 2, 3 },
          potionsPerHour = { 1, 2 },
        }
      end,
    }

    _G.nExBot.MonsterAI = {
      Tracker = { monsters = { [1] = { name = "Cyclops" } } },
      getPredictionStats = function()
        return { accuracy = 0.5 }
      end,
      CombatFeedback = {
        getAccuracy = function()
          return { waveAttack = 0.75 }
        end,
      },
    }

    _G.nExBot.Intelligence = {
      lifecycle = {
        active = true,
        generation = function(_, name)
          return name == "snapshot" and 4 or 2
        end,
      },
      route = {
        state = "RUNNING",
        generation = 3,
        waypointIndex = 7,
      },
      blackboard = {
        read = function(_, key)
          if key == "currentTarget" then
            return { name = "Cyclops" }
          end
          if key == "currentRouteObjective" then
            return { name = "Route 1" }
          end
        end,
      },
      events = {
        recent = function()
          return {
            { type = "AttackStarted", source = "AttackStateMachine", timestamp = 10 },
            { type = "TargetKilled", source = "AttackStateMachine", timestamp = 20 },
          }
        end,
      },
      resources = {
        recent = function()
          return { { hpPotions = 1 } }
        end,
        totals = function()
          return { hpPotions = 1, manaPotions = 2, runes = 3, ammunition = 0, healingCasts = 4, damageTaken = 5 }
        end,
      },
      loot = {
        recent = function()
          return { { monsterId = "Cyclops", itemsAvailable = 1, itemsCaptured = 1 } }
        end,
      },
      replay = {
        export = function()
          return { { outcome = { type = "TargetKilled", reason = "target_killed" } } }
        end,
      },
      models = {
        entries = {
          MonsterBehaviorModel = {
            mode = "SHADOW",
            definition = { minEvidence = 1 },
            model = {
              diagnostics = function()
                return { samples = 3, pending = 0, confidence = 0.75, capability = "monster_behavior" }
              end,
            },
          },
          LatencyModel = {
            mode = "OFF",
            definition = { minEvidence = 1 },
            model = {
              diagnostics = function()
                return { samples = 0, pending = 0, confidence = 0, capability = "latency" }
              end,
            },
          },
        },
      },
      lastPersistAt = 42,
    }

    _G.IntelligenceBotDoctor = dofile("core/intelligence/observability/bot_doctor.lua")
    Tactical = dofile("core/intelligence/tactical_intelligence.lua")
  end)

  it("builds an immutable unified read model", function()
    local view = Tactical:view({ width = 1200, platform = "desktop" })

    assert.equals("active", view.overview.lifecycle)
    assert.equals("Cyclops", view.targeting.currentTarget.name)
    assert.equals(2, view.resources.totals.manaPotions)
    assert.equals(2, view.pipeline.eventCount)
    assert.equals("TargetKilled", view.overview.lastEvent)
    assert.equals(2, view.models.summary.total)
    assert.equals("wide", view.layout.mode)
  end)

  it("returns revisioned section snapshots", function()
    local overview = Tactical:getOverviewSnapshot()
    local models = Tactical:getModelSnapshot()

    assert.is_truthy(overview.revision)
    assert.equals(overview.sessionId, models.sessionId)
    assert.is_truthy(overview.updatedAt)
    assert.equals("active", overview.lifecycle)
  end)

  it("projects persisted Monster AI telemetry as learned profiles", function()
    local monsters = Tactical:getMonsterProfilesSnapshot()
    local dragonLord
    for _, profile in ipairs(monsters.profiles) do
      if profile.monsterKey == "dragon lord" then
        dragonLord = profile
      end
    end

    assert.is_truthy(dragonLord)
    assert.equals(125, dragonLord.samples)
    assert.equals(42, dragonLord.estimatedDps)
    assert.equals(2000, dragonLord.averageTtkMs)
    assert.equals("LEARNING", dragonLord.state)
  end)

  it("passes session and monster projection health to Bot Doctor", function()
    local diagnostics = Tactical:getDiagnosticsSnapshot()

    assert.equals(60000, diagnostics.capture.session.elapsedMs)
    assert.equals(1, diagnostics.capture.monsters.liveMonsters)
  end)
end)
