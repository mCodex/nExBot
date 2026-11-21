local Harness = require("tests.helpers.widget_harness")

local function loadPage(supplies)
  Harness.reset()
  Harness.install()
  _G.nExBot = { UI = {} }
  _G.Supplies = supplies
  for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
    dofile("ui/design_system/" .. file .. ".lua")
  end
  dofile("ui/components/components.lua")
  dofile("ui/components/table_model.lua")
  nExBot.UI.VisualAssetResolver = { item = function(_, id) return { name = "Item " .. id } end }
  dofile("ui/components/data_table.lua")
  dofile("ui/modules/workflows/shared.lua")
  dofile("ui/modules/workflows/supplies.lua")
  return nExBot.UI["ui.modules.workflows.supplies"]
end

local function render(page)
  local root = g_ui.createWidget("Root", nil)
  local shell = {
    defer = function(_, callback) callback() end,
    renderCurrent = function(self)
      root:destroyChildren()
      page.render(root, self)
    end,
  }
  shell:renderCurrent()
  return root, shell
end

describe("Supplies page", function()
  it("renders the items table with configured item data and all refill toggles", function()
    local page = loadPage({
      listProfiles = function() return { "Default" } end,
      getCurrentProfile = function() return "Default" end,
      setCurrentProfile = function() end,
      getItemsData = function() return { [268] = { min = 50, max = 200, avg = 25 } } end,
      getAdditionalData = function()
        return {
          softBoots = { enabled = false },
          imbues = { enabled = true },
          capacity = { enabled = true, value = 100 },
          stamina = { enabled = false, value = 30 },
        }
      end,
      setCondition = function() end,
      setItem = function() return true end,
      removeItem = function() return true end,
    })
    local root = render(page)

    local row = assert(root:recursiveGetChildById("supplyItems_268"))
    assert.are_equal("Item 268", row:recursiveGetChildById("title"):getText())
    assert.are_equal("268", row:recursiveGetChildById("visual"):getItemId())
    assert.is_truthy(row:recursiveGetChildById("secondary"):getText():find("50", 1, true))
    assert.is_truthy(root:recursiveGetChildById("addSupply"))
    assert.is_truthy(root:recursiveGetChildById("supplyCondition_softBoots"))
    assert.is_truthy(root:recursiveGetChildById("supplyCondition_imbues"))
    assert.is_truthy(root:recursiveGetChildById("supplyCondition_capacity"))
    assert.is_truthy(root:recursiveGetChildById("supplyCondition_stamina"))
  end)

  it("calls the domain setter when a refill condition is toggled", function()
    local toggled
    local page = loadPage({
      listProfiles = function() return { "Default" } end,
      getCurrentProfile = function() return "Default" end,
      setCurrentProfile = function() end,
      getItemsData = function() return {} end,
      getAdditionalData = function()
        return { softBoots = { enabled = false }, imbues = { enabled = false }, capacity = { enabled = false, value = 100 }, stamina = { enabled = false, value = 30 } }
      end,
      setCondition = function(name, enabled, value) toggled = { name, enabled, value } end,
      setItem = function() return true end,
      removeItem = function() return true end,
    })
    local root = render(page)

    root:recursiveGetChildById("supplyCondition_capacity"):recursiveGetChildById("switch"):click()
    assert.same({ "capacity", true, 100 }, toggled)
  end)

  it("calls setCurrentProfile when the profile select changes", function()
    local changed
    local page = loadPage({
      listProfiles = function() return { "Default", "Alt" } end,
      getCurrentProfile = function() return "Default" end,
      setCurrentProfile = function(name) changed = name end,
      getItemsData = function() return {} end,
      getAdditionalData = function()
        return { softBoots = { enabled = false }, imbues = { enabled = false }, capacity = { enabled = false }, stamina = { enabled = false } }
      end,
      setCondition = function() end,
      setItem = function() return true end,
      removeItem = function() return true end,
    })
    local root = render(page)

    root:recursiveGetChildById("supplyProfile"):recursiveGetChildById("combo").onOptionChange(nil, "Alt")
    assert.are_equal("Alt", changed)
  end)
end)