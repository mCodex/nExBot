-- config
setDefaultTab("Tools")
local defaultBp = "shopping bag"
local id = 21411

-- script

local playerContainer = nil
local depotContainer = nil
local mailContainer = nil

function reopenLootContainer()
  for _, container in pairs(getContainers()) do
    if container:getName():lower() == defaultBp:lower() then
      g_game.close(container)
    end
  end

  local lootItem = findItem(id)
  if lootItem then
    schedule(500, function() g_game.open(lootItem) end)
  end

end

-- Depot withdraw handler function (shared by UnifiedTick and fallback macro)
local function depotWithdrawHandler()
  
  -- set the containers
  if not potionsContainer or not runesContainer or not ammoContainer then
    for i, container in pairs(getContainers()) do
      if container:getName() == defaultBp then
        playerContainer = container
      elseif string.find(container:getName(), "Depot") then
        depotContainer = container
      elseif string.find(container:getName(), "your inbox") then
        mailContainer = container
      end 
    end
  end

  if playerContainer and #playerContainer:getItems() == 20 then
    for j, item in pairs(playerContainer:getItems()) do
      if item:getId() == id then
        g_game.open(item, playerContainer)
       return
      end
    end
  end


if playerContainer and freecap() >= 200 then
  local time = 500
    if depotContainer then 
      for i, container in pairs(getContainers()) do
        if string.find(container:getName(), "Depot") then
          for j, item in pairs(container:getItems()) do
            g_game.move(item, playerContainer:getSlotPosition(playerContainer:getItemsCount()), item:getCount())
            return
          end
        end
      end
    end

    if mailContainer then 
      for i, container in pairs(getContainers()) do
        if string.find(container:getName(), "your inbox") then
          for j, item in pairs(container:getItems()) do
            g_game.move(item, playerContainer:getSlotPosition(playerContainer:getItemsCount()), item:getCount())
            return
          end
        end
      end
    end
end

end

-- Use UnifiedTick if available, fallback to standalone macro
local depotWithdrawMacro
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("depot_withdraw", {
    interval = 50,
    priority = UnifiedTick.Priority.NORMAL,
    handler = depotWithdrawHandler,
    group = "tools"
  })
  -- Create dummy macro for UI toggle and BotDB compatibility
  depotWithdrawMacro = macro(50, "Depot Withdraw", function() end)
  depotWithdrawMacro:setOn(true)
  depotWithdrawMacro.onSwitch = function(m)
    UnifiedTick.setEnabled("depot_withdraw", m:isOn())
  end
else
  depotWithdrawMacro = macro(50, "Depot Withdraw", depotWithdrawHandler)
end
BotDB.registerMacro(depotWithdrawMacro, "depotWithdraw")