local Resolver = require("ui.core.visual_asset_resolver")

describe("VisualAssetResolver", function()
  it("caches native item metadata and falls back to the item id", function()
    local calls = 0
    local resolver = Resolver.new({
      getItemName = function(id)
        calls = calls + 1
        if id == 3160 then return "Ultimate Healing Rune" end
      end,
    })

    assert.are_equal("Ultimate Healing Rune", resolver:item(3160).name)
    assert.are_equal("Ultimate Healing Rune", resolver:item(3160).name)
    assert.are_equal(1, calls)
    assert.are_equal("Item 9999", resolver:item(9999).name)
  end)

  it("uses native spell icons and preserves text fallback", function()
    local resolver = Resolver.new({
      getSpellIcon = function(spell)
        if spell == "exori gran" then return "/native/exori-gran" end
      end,
    })

    local native = resolver:spell("exori gran")
    local fallback = resolver:spell("unknown spell")

    assert.are_equal("native", native.kind)
    assert.are_equal("/native/exori-gran", native.source)
    assert.are_equal("exori gran", native.text)
    assert.are_equal("text", fallback.kind)
    assert.are_equal("unknown spell", fallback.text)
  end)

  it("clears cached capability results on generation change", function()
    local source = "/first"
    local resolver = Resolver.new({ getSpellIcon = function() return source end })
    assert.are_equal("/first", resolver:spell("exura").source)
    source = "/second"
    assert.are_equal("/first", resolver:spell("exura").source)
    resolver:reset(2)
    assert.are_equal("/second", resolver:spell("exura").source)
  end)
end)
