describe("BuySupplies", function()
  local function runFixture(reply)
    local action
    local purchases = {}
    local environment = setmetatable({
      print = function() end,
      string = setmetatable({split = function(value) return {{trim = function() return value end}} end},
        {__index = string}),
      CaveBot = {
        Extensions = {},
        Editor = {registerAction = function() end},
        registerAction = function(_, _, fn) action = fn end,
        ReachNPC = function() return true end,
        delay = function() end,
      },
      SafeCall = {getCreatureByName = function() return {} end},
      NPC = {
        isTrading = function() return true end,
        getBuyItems = function() return {{id = 201}} end,
        buy = function(id, quantity) purchases[#purchases + 1] = {id, quantity} end,
      },
      Supplies = {getItemsData = function() return {[201] = {max = 200}, [202] = {max = 50}} end},
      player = {getItemsCount = function() return 150 end},
      RustBridge = {supplyRefill = reply},
    }, {__index = _G})
    if setfenv then
      setfenv(assert(loadfile("cavebot/buy_supplies.lua")), environment)()
    else
      assert(loadfile("cavebot/buy_supplies.lua", "t", environment))()
    end
    environment.CaveBot.Extensions.BuySupplies.setup()
    return action, purchases
  end

  it("uses matching configured stock after a pending reply", function()
    local observed
    local action, purchases = runFixture(function(stock, signature)
      assert.same({{201, 150, 200}}, stock)
      if not observed then observed = signature; return "pending" end
      assert.equals(observed, signature)
      return "ready", {201, 50}
    end)
    assert.equals("walking", action("Trader", 0))
    assert.same({}, purchases)
    assert.equals("retry", action("Trader", 0))
    assert.same({{201, 50}}, purchases)
  end)

  it("falls back locally for an invalid quantity", function()
    local action, purchases = runFixture(function() return "ready", {201, 100} end)
    assert.equals("retry", action("Trader", 0))
    assert.same({{201, 50}}, purchases)
  end)
end)
