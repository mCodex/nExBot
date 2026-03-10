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
local depotWithdrawEnabled = false
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("depot_withdraw", {
    interval = 50,
    priority = UnifiedTick.Priority.NORMAL,
    handler = depotWithdrawHandler,
    group = "tools"
  })
  -- Start disabled; state restored below
  UnifiedTick.setEnabled("depot_withdraw", false)
else
  -- Fallback: nameless macro guarded by enabled flag
  macro(50, function()
    if not depotWithdrawEnabled then return end
    depotWithdrawHandler()
  end)
end

local depotWithdrawUI = setupUI([[
Panel
  height: 20

  NxSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    margin-top: 0
    !text: tr('Depot Withdraw')
]])

depotWithdrawUI.title.onClick = function(widget)
  depotWithdrawEnabled = not depotWithdrawEnabled
  widget:setOn(depotWithdrawEnabled)
  if UnifiedTick then
    UnifiedTick.setEnabled("depot_withdraw", depotWithdrawEnabled)
  end
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("macros.depotWithdraw", depotWithdrawEnabled)
  else
    BotDB.set("macros.depotWithdraw", depotWithdrawEnabled)
  end
end

local savedDepotWithdrawState = (function()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    return CharacterDB.get("macros.depotWithdraw") == true
  end
  return BotDB.get("macros.depotWithdraw") == true
end)()
if savedDepotWithdrawState then
  depotWithdrawEnabled = true
  depotWithdrawUI.title:setOn(true)
  if UnifiedTick then
    UnifiedTick.setEnabled("depot_withdraw", true)
  end
end