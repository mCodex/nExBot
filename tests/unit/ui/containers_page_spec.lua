local Harness = require("tests.helpers.widget_harness")

describe("Containers page", function()
  local domain

  before_each(function()
    Harness.reset()
    Harness.install()
    _G.nExBot = { UI = {} }
    _G.Containers = {
      getContainerList = function()
        return {
          { name = "Main Backpack", enabled = true, itemId = 2854, items = { 3155, 3161 } },
          { name = "Supplies", enabled = false, itemId = 2866, items = {} },
        }
      end,
      getBehavior = function()
        return { sortEnabled = false, forceOpen = false, renameEnabled = false, lootBag = false }
      end,
      setSortEnabled = function(value) domain.sortEnabled = value end,
      setForceOpen = function(value) domain.forceOpen = value end,
      setRenameEnabled = function(value) domain.renameEnabled = value end,
      setLootBag = function(value) domain.lootBag = value end,
      setContainerEnabled = function(index, value) domain.enabled[index] = value end,
      removeContainer = function(index) domain.removed = index end,
      addContainer = function(name, itemId) domain.added = { name, itemId }; return true end,
    }
    domain = { enabled = {}, removed = nil, added = nil, sortEnabled = nil }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function(_, id) return { name = "Item " .. id } end }
    dofile("ui/components/data_table.lua")
    dofile("ui/core/module_registry.lua")
    dofile("ui/modules/containers.lua")
  end)

  local function render()
    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        nExBot.UI.ModuleRegistry.get("containers").render(self, root)
      end,
    }
    shell:renderCurrent()
    return root, shell
  end

  it("registers as a shell page and renders configured container rows", function()
    local root = render()
    assert.is_truthy(root:recursiveGetChildById("containersHeader"))
    assert.is_truthy(root:recursiveGetChildById("containerTable"))
    assert.are_equal("Main Backpack", root:recursiveGetChildById("containerTable_1"):recursiveGetChildById("title"):getText())
    assert.are_equal("Supplies", root:recursiveGetChildById("containerTable_2"):recursiveGetChildById("title"):getText())
    assert.is_truthy(root:recursiveGetChildById("behavior_sortEnabled"))
    assert.is_truthy(root:recursiveGetChildById("behavior_lootBag"))
  end)

  it("wires a behavior toggle to the domain setter", function()
    local root = render()
    root:recursiveGetChildById("behavior_sortEnabled"):recursiveGetChildById("switch"):click()
    assert.is_true(domain.sortEnabled)
  end)

  it("routes row enable/disable and removal through the domain", function()
    local root = render()
    root:recursiveGetChildById("containerToggle_1"):click()
    assert.is_false(domain.enabled[1])
    root:recursiveGetChildById("containerRemove_2"):click()
    assert.are_equal(2, domain.removed)
  end)

  it("adds a container from the name and item id fields", function()
    local root = render()
    root:recursiveGetChildById("containerName"):recursiveGetChildById("input").onTextChange(nil, "Purse")
    root:recursiveGetChildById("containerItemId"):recursiveGetChildById("input").onTextChange(nil, "23396")
    root:recursiveGetChildById("addContainer"):click()
    assert.same({ "Purse", "23396" }, domain.added)
  end)
end)