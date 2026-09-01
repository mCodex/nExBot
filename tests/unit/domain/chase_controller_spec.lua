describe("TargetBot native chase controller", function()
  it("applies chase mode through direct client access", function()
    local applied
    _G.now = 200
    _G.TargetBot = {}
    _G.EventBus = nil
    _G.ClientHelper = nil
    _G.nExBot = { Shared = { getClient = function() return nil end } }
    _G.g_game = {
      getChaseMode = function() return 0 end,
      setChaseMode = function(mode) applied = mode end,
    }
    dofile("targetbot/chase_controller.lua")
    ChaseController.setDesiredChase(true)
    assert.equals(1, applied)
    assert.is_true(ChaseController.isChasing())
  end)
end)
