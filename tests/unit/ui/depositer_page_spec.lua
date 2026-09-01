local Harness = require("tests.helpers.widget_harness")

describe("Depositer page stash list", function()
  it("renders stash items and lets the user add and remove them", function()
    Harness.reset()
    Harness.install()

    local items = { { id = 100, index = 3 } }
    local removed
    local added
    _G.nExBot = { UI = {}, Depositer = {
      getItems = function() return items end,
      addItem = function(id, index)
        added = { id, index }
        items[#items + 1] = { id = id, index = index }
        return true
      end,
      removeItem = function(id)
        removed = id
        for i, entry in ipairs(items) do
          if entry.id == id then
            table.remove(items, i)
            return true
          end
        end
        return false
      end,
    } }
    for _, file in ipairs({ "tokens", "typography", "density", "status" }) do
      dofile("ui/design_system/" .. file .. ".lua")
    end
    dofile("ui/components/components.lua")
    dofile("ui/components/table_model.lua")
    nExBot.UI.VisualAssetResolver = { item = function(_, id) return { name = "Item " .. id } end }
    dofile("ui/components/data_table.lua")
    local Registry = dofile("ui/core/module_registry.lua")
    dofile("ui/modules/depositer.lua")

    assert.same({ "depositer" }, Registry.ids())

    local root = g_ui.createWidget("Root", nil)
    local shell = {
      defer = function(_, callback) callback() end,
      renderCurrent = function(self)
        root:destroyChildren()
        Registry.get("depositer").render(self, root)
      end,
    }
    shell:renderCurrent()

    local row = root:recursiveGetChildById("depositerItems_100")
    assert.is_truthy(row)
    assert.are_equal("Item 100", row:recursiveGetChildById("title"):getText())

    -- Removing an entry calls the domain setter and drops the row.
    root:recursiveGetChildById("remove_100"):click()
    assert.are_equal(100, removed)
    assert.is_nil(root:recursiveGetChildById("depositerItems_100"))

    -- Adding an item through the form calls the domain setter and re-renders.
    root:recursiveGetChildById("depositerItemId"):recursiveGetChildById("input").onTextChange(nil, "200")
    root:recursiveGetChildById("depositerIndex"):recursiveGetChildById("input").onTextChange(nil, "5")
    root:recursiveGetChildById("addDepositerItem"):click()
    assert.same({ 200, 5 }, added)
    assert.is_truthy(root:recursiveGetChildById("depositerItems_200"))
    assert.are_equal("Stash to depot: 5", root:recursiveGetChildById("depositerItems_200"):recursiveGetChildById("secondary"):getText())
  end)
end)