CaveBot.Extensions.BuySupplies = {}

CaveBot.Extensions.BuySupplies.setup = function()
  CaveBot.registerAction("BuySupplies", "#C300FF", function(value, retries)
    local possibleItems = {}

    local val = string.split(value, ",")
    local waitVal
    if #val == 0 or #val > 2 then 
      warn("CaveBot[BuySupplies]: incorrect BuySupplies value")
      return false 
    elseif #val == 2 then
      waitVal = tonumber(val[2]:trim())
    end

    local npcName = val[1]:trim()
    local npc = SafeCall.getCreatureByName(npcName)
    if not npc then 
      print("CaveBot[BuySupplies]: NPC not found")
      return false 
    end
    
    if not waitVal and #val == 2 then 
      warn("CaveBot[BuySupplies]: incorrect delay values!")
    elseif waitVal and #val == 2 then
      delay(waitVal)
    end

    if retries > 50 then
      print("CaveBot[BuySupplies]: Too many tries, can't buy")
      return false
    end

    if not CaveBot.ReachNPC(npcName) then
      return "retry"
    end

    if not NPC.isTrading() then
      CaveBot.OpenNpcTrade()
      CaveBot.delay(storage.extras.talkDelay*2)
      return "retry"
    end

    for _, item in pairs(NPC.getBuyItems()) do
      possibleItems[item.id] = true
    end

    local stock, byId = {}, {}
    local bridgeSafe = true
    local localPurchase
    for key, values in pairs(Supplies.getItemsData()) do
      local id = tonumber(key)
      if id and possibleItems[id] then
        local current, maximum = player:getItemsCount(id), values.max
        if current < maximum and not localPurchase then
          localPurchase = {id, math.min(100, maximum - current)}
        end
        if id < 1 or id > 65535 or id % 1 ~= 0 or current < 0 or current > 4294967295
            or current % 1 ~= 0 or maximum < 0 or maximum > 4294967295 or maximum % 1 ~= 0 then
          bridgeSafe = false
        end
        stock[#stock + 1] = {id, current, maximum}
        byId[id] = stock[#stock]
      end
    end

    local purchase = localPurchase
    if bridgeSafe and localPurchase and RustBridge and RustBridge.supplyRefill then
      table.sort(stock, function(left, right) return left[1] < right[1] end)
      local fingerprint = {npcName}
      for _, row in ipairs(stock) do
        fingerprint[#fingerprint + 1] = table.concat(row, ":")
      end
      local result, suggested = RustBridge.supplyRefill(stock, table.concat(fingerprint, "|"))
      if result == "pending" then
        -- This wait does not consume an NPC purchase retry.
        CaveBot.delay(50)
        return "walking"
      end
      if result == "ready" and type(suggested) == "table" then
        local row = byId[suggested[1]]
        if row and suggested[2] == math.min(100, row[3] - row[2]) and suggested[2] > 0 then
          purchase = suggested
        end
      end
    end

    if purchase then
      NPC.buy(purchase[1], purchase[2])
      print("CaveBot[BuySupplies]: bought " .. purchase[2] .. "x " .. purchase[1])
      return "retry"
    end

    print("CaveBot[BuySupplies]: bought everything, proceeding")
    return true
 end)

 CaveBot.Editor.registerAction("buysupplies", "buy supplies", {
  value="NPC name",
  title="Buy Supplies",
  description="NPC Name, delay(in ms, optional)",
 })
end