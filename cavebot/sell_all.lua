CaveBot.Extensions.SellAll = {}

local sellAllCap = 0
local sellAllRetries = 0
local MAX_SELL_RETRIES = 3

-- Fallback: Manual sell implementation when modules.game_npctrade fails
local function manualSellAll(wait, itemsToSell)
  local npcTrade = modules.game_npctrade
  if not npcTrade or not npcTrade.getTradeItems then
    print("CaveBot[SellAll]: game_npctrade module not available")
    return false
  end

  local tradeItems = npcTrade.getTradeItems()
  if not tradeItems or #tradeItems == 0 then
    print("CaveBot[SellAll]: No items in trade window")
    return false
  end

  local sellExceptions = {}
  for _, v in ipairs(itemsToSell) do
    if type(v) == "number" then
      sellExceptions[v] = true
    end
  end

  local soldCount = 0
  for _, item in ipairs(tradeItems) do
    if item and item.id and sellExceptions[item.id] then
      local count = item.count or 1
      if wait then
        schedule(soldCount * 300, function()
          if npcTrade.sellItem then
            npcTrade.sellItem(item.id, count)
          end
        end)
      else
        if npcTrade.sellItem then
          npcTrade.sellItem(item.id, count)
        end
      end
      soldCount = soldCount + 1
    end
  end

  if soldCount > 0 then
    print("CaveBot[SellAll]: Manual sell executed for " .. soldCount .. " item types")
    return true
  end

  return false
end

-- Safe wrapper for modules.game_npctrade.sellAll with error handling
local function safeSellAll(wait, itemsToSell)
  local npcTrade = modules.game_npctrade
  if not npcTrade or not npcTrade.sellAll then
    return manualSellAll(wait, itemsToSell)
  end

  -- Ensure sellQueue is initialized (fixes the nil length error)
  if npcTrade.sellQueue == nil then
    npcTrade.sellQueue = {}
  end

  local success, err = pcall(function()
    npcTrade.sellAll(wait, itemsToSell)
  end)

  if not success then
    print("CaveBot[SellAll]: sellAll failed: " .. tostring(err) .. " - trying manual sell")
    return manualSellAll(wait, itemsToSell)
  end

  return true
end

CaveBot.Extensions.SellAll.setup = function()
  CaveBot.registerAction("SellAll", "#b78aff", function(value, retries)
    local val = string.split(value, ",")
    local wait

    -- table formatting
    for i, v in ipairs(val) do
      v = v:trim()
      v = tonumber(v) or v
      val[i] = v
    end

    if table.find(val, "yes", true) then
      wait = true
    end

    local npcName = val[1]
    local npc = SafeCall.getCreatureByName(npcName)
    if not npc then 
      print("CaveBot[SellAll]: NPC not found! skipping")
      return false 
    end

    if retries > 10 then
      print("CaveBot[SellAll]: can't sell, skipping")
      return false
    end

    if freecap() == sellAllCap then
      sellAllCap = 0 
      sellAllRetries = 0
      print("CaveBot[SellAll]: Sold everything, proceeding")
      return true
    end

    delay(800)
    if not CaveBot.ReachNPC(npcName) then
      return "retry"
    end

    -- Wait for trade window to be fully open
    local tradeOpenRetries = 0
    while not NPC.isTrading() and tradeOpenRetries < 5 do
      CaveBot.OpenNpcTrade()
      delay(storage.extras.talkDelay * 2)
      tradeOpenRetries = tradeOpenRetries + 1
    end

    if not NPC.isTrading() then
      print("CaveBot[SellAll]: Failed to open trade with " .. npcName)
      return "retry"
    end

    -- Verify trade window has items before selling
    local npcTrade = modules.game_npctrade
    local tradeItems = npcTrade and npcTrade.getTradeItems and npcTrade.getTradeItems()
    if not tradeItems or #tradeItems == 0 then
      print("CaveBot[SellAll]: Trade window empty, retrying")
      return "retry"
    end

    if retries == 0 then
      sellAllCap = freecap()
      sellAllRetries = 0
    end

    -- Get sell exceptions from profile storage
    local sellExceptions = {}
    if getCavebotSellItems then
      sellExceptions = getCavebotSellItems() or {}
    elseif ProfileStorage then
      sellExceptions = ProfileStorage.get("cavebotSell") or {}
    else
      sellExceptions = storage.cavebotSell or {}
    end
    
    for i, item in ipairs(sellExceptions) do
      local data = type(item) == 'number' and item or item.id
      if not table.find(val, data) then
        table.insert(val, data)
      end
    end

    table.dump(val)
    
    -- Use safe wrapper with fallback
    local ok = safeSellAll(wait, val)
    if not ok then
      sellAllRetries = sellAllRetries + 1
      if sellAllRetries >= MAX_SELL_RETRIES then
        print("CaveBot[SellAll]: Max retries reached, skipping")
        sellAllRetries = 0
        return false
      end
      return "retry"
    end

    sellAllRetries = 0
    if wait then
      print("CaveBot[SellAll]: Sold All with delay")
    else
      print("CaveBot[SellAll]: Sold All without delay")
    end

    return "retry"
  end)

  CaveBot.Editor.registerAction("sellall", "sell all", {
    value="NPC",
    title="Sell All",
    description="NPC Name, 'yes' if sell with delay, exceptions: id separated by comma",
  })
end