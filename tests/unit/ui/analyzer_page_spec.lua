local Harness = require("tests.helpers.widget_harness")

describe("Analyzer page", function()
  local function cannedAnalyzer()
    return {
      getHuntStats = function()
        return {
          sessionTime = "00:05:00",
          xpGained = 120000,
          xpHour = "480k",
          loot = 250000,
          supplies = 80000,
          balance = 170000,
          balanceLabel = "170k (340k/h)",
          damage = 500000,
          damageHour = 300000,
          healing = 100000,
          healingHour = 60000,
          kills = { { name = "Dragon", count = 12 }, { name = "Demon", count = 5 } },
        }
      end,
      getLootStats = function()
        return { loot = 250000, lootHour = 300000, items = { { id = 2148, name = "gold coin", count = 1000 } } }
      end,
      getSupplyStats = function()
        return { supplies = 80000, suppliesHour = 96000, items = { { id = 268, name = "great health potion", count = 40 } } }
      end,
      getImpactStats = function()
        return {
          damage = 500000, bestDps = 1234, bestHit = 600,
          healing = 100000, bestHps = 500, bestHeal = 300,
          distribution = { { name = "Dragon: ", value = "60%" }, { name = "Demon: ", value = "40%" } },
        }
      end,
      getXpStats = function()
        return { xpGained = 120000, xpHour = "480k", nextLevel = "00:30:00", xpLeft = 5000 }
      end,
      getCaveBotStats = function()
        return {
          totalRounds = 3, avRoundTime = "00:05:00", totalRefills = 1,
          avRefillTime = "00:15:00", lastRefill = "00:02:00",
          roundSupplies = {}, refillSupplies = {},
        }
      end,
      getPartyStats = function()
        return { sessionTime = "00:05:00", loot = 400000, supplies = 90000, balance = 310000, sendData = true, members = {} }
      end,
      getDropTracker = function()
        return { { id = 2148, count = 12 } }
      end,
      getBossTracker = function()
        return { { name = "Scarlett Etzel", dueTime = os.time() + 3600, timeLeft = 3600 } }
      end,
      setSendPartyData = function() end,
    }
  end

  local function renderPage()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    _G.Analyzer = cannedAnalyzer()
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function(_, id) return { name = "Item " .. id } end }
    dofile("ui/components/data_table.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/analyzer.lua")

    local root = g_ui.createWidget("Root", nil)
    Registry.get("analytics").render(nil, root)
    return root
  end

  it("registers as the analytics page", function()
    renderPage()
    local desc = nExBot.UI.ModuleRegistry.get("analytics")
    assert.are_equal("Analyzer", desc.label)
    assert.are_equal(75, desc.order)
  end)

  it("renders headline metrics from the hunt stats", function()
    local root = renderPage()
    local function metric(id)
      return root:recursiveGetChildById(id):recursiveGetChildById("value"):getText()
    end
    assert.are_equal("17", metric("metricKills"))
    assert.are_equal("250,000", metric("metricLoot"))
    assert.are_equal("80,000", metric("metricSupplies"))
    assert.are_equal("480k", metric("metricXpHour"))
    assert.are_equal("500,000", metric("metricDamage"))
  end)

  it("renders loot and impact data tables with canned rows", function()
    local root = renderPage()
    local lootRow = root:recursiveGetChildById("analyzerLoot_loot_2148")
    assert.is_truthy(lootRow)
    assert.are_equal("gold coin", lootRow:recursiveGetChildById("title"):getText())

    local impactRow = root:recursiveGetChildById("analyzerImpact_impact_1")
    assert.is_truthy(impactRow)
    assert.are_equal("Dragon: ", impactRow:recursiveGetChildById("title"):getText())
    assert.are_equal("60%", impactRow:recursiveGetChildById("secondary"):getText())
  end)

  it("renders supplies, XP, party and tracker sections", function()
    local root = renderPage()
    assert.are_equal("3", root:recursiveGetChildById("kvRounds"):recursiveGetChildById("value"):getText())

    local xpRow = root:recursiveGetChildById("kvXpGained")
    assert.is_truthy(xpRow)
    assert.are_equal("120,000", xpRow:recursiveGetChildById("value"):getText())

    local partyToggle = root:recursiveGetChildById("analyzerSendParty")
    assert.is_truthy(partyToggle)
    assert.is_true(partyToggle:recursiveGetChildById("switch"):isChecked())

    local dropRow = root:recursiveGetChildById("analyzerDrops_drop_2148")
    assert.is_truthy(dropRow)
    assert.are_equal("Item 2148", dropRow:recursiveGetChildById("title"):getText())

    local bossRow = root:recursiveGetChildById("analyzerBosses_boss_Scarlett Etzel")
    assert.is_truthy(bossRow)
    assert.is_truthy(bossRow:recursiveGetChildById("status"):getText():find("remaining", 1, true))
  end)

  it("shows an error state when the Analyzer namespace is missing", function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    _G.Analyzer = nil
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/analyzer.lua")

    local root = g_ui.createWidget("Root", nil)
    Registry.get("analytics").render(nil, root)
    local msg = root:recursiveGetChildById("message")
    assert.is_truthy(msg)
    assert.is_truthy(msg:getText():find("Analyzer did not load", 1, true))
  end)
end)