describe("Inventory and NPC runtime decisions", function()
  it("uses the Rust equipment slot decision and preserves a deliberate no-op", function()
    local env = setmetatable({
      nExBotRuntime = {
        decide = function(operation, input)
          assert.equals("equipment", operation)
          assert.is_true(input.slots[1].needs_change)
          assert.is_true(input.slots[1].available)
          assert.is_false(input.safe_to_unequip)
          return {index = 1, missing = true}
        end,
      },
    }, {__index = _G})
    local service = assert(loadfile("core/equipper_service.lua", "t", env))()
    local rule = {slots = {{mode = "equip", slotIdx = 8, itemId = 3000}}}
    local helpers = {
      slotHasItemId = function() return false end,
      isUnsafeToUnequip = function() return true end,
    }
    local action, missing = service.computeAction(rule, {}, {[3000] = {true}}, helpers)
    assert.same({kind = "equip", slotIdx = 8, itemId = 3000}, action)
    assert.is_true(missing)

    env.nExBotRuntime.decide = function() return {missing = true} end
    action, missing = service.computeAction(rule, {}, {[3000] = {true}}, helpers)
    assert.is_nil(action)
    assert.is_true(missing)
  end)

  it("dispatches the observed depot item and destination returned by Rust", function()
    local item = {getId = function() return 3010 end, isStackable = function() return true end}
    local chest = {}
    local bag = {getName = function() return "Supply Bag" end, getItems = function() return {item} end}
    local action, moved
    local env = setmetatable({
      CaveBot = {
        Extensions = {},
        Editor = {registerAction = function() end},
        registerAction = function(_, _, callback) action = callback end,
        GetLootItems = function() return {3010} end,
        ReachAndOpenDepot = function() return true end,
        PingDelay = function() end,
        StashItem = function(...) moved = {...} end,
      },
      nExBot = {Shared = {getClientVersion = function() return 1300 end}},
      getContainerByName = function() return chest end,
      getContainers = function() return {bag} end,
      getStashingIndexes = function() return {[3010] = 2} end,
      delay = function() end,
      statusMessage = function() end,
      nExBotRuntime = {
        decide = function(operation, input)
          assert.equals("deposit", operation)
          assert.same({{id = 3010, stackable = true, configured_index = 2}}, input.items)
          assert.same({3010}, input.loot)
          return {plan = {item = 1, destination_index = 2}}
        end,
      },
    }, {__index = _G})
    assert(loadfile("cavebot/depositor.lua", "t", env))()
    env.CaveBot.Extensions.Depositor.setup()
    assert.equals("retry", action("no", 1))
    assert.same({item, 2, chest}, moved)
  end)

  it("schedules only the supplied NPC messages using the runtime plan", function()
    local sent, scheduled = {}, {}
    local env = setmetatable({
      storage = {extras = {talkDelay = 500}},
      NPC = {say = function(phrase) sent[#sent + 1] = phrase end},
      schedule = function(delay, cb)
        scheduled[#scheduled + 1] = delay
        cb()
      end,
      nExBotRuntime = {
        decide = function(operation, input)
          assert.equals("npc_conversation", operation)
          assert.same({count = 2, interval_ms = 500}, input)
          return {delays = {0, 510}}
        end,
      },
    }, {__index = _G})
    assert(loadfile("core/new_cavebot_lib.lua", "t", env))()
    env.CaveBot.Conversation("hi", "trade")
    assert.same({"hi", "trade"}, sent)
    assert.same({0, 510}, scheduled)
  end)
end)
