local minimap = modules.game_minimap.minimapWidget

-- Safe helper to add waypoints to CaveBot
local function safeAddCaveBotWaypoint(x, y, z)
  -- Check all required CaveBot components exist
  if not CaveBot then
    print("[Minimap] CaveBot not loaded")
    return false
  end
  if not CaveBot.addAction then
    print("[Minimap] CaveBot.addAction not available")
    return false
  end
  if not CaveBot.actionList then
    print("[Minimap] CaveBot.actionList not initialized yet")
    return false
  end
  if not CaveBot.save then
    print("[Minimap] CaveBot.save not available")
    return false
  end
  
  local success, err = pcall(function()
    CaveBot.addAction("goto", x .. "," .. y .. "," .. z, true)
    CaveBot.save()
  end)
  
  if success then
    print("[CaveBot] Added goto: " .. x .. "," .. y .. "," .. z)
    return true
  else
    print("[Minimap] Error adding waypoint: " .. tostring(err))
    return false
  end
end

minimap.onMouseRelease = function(widget,pos,button)
  if not minimap.allowNextRelease then return true end
  minimap.allowNextRelease = false

  local mapPos = minimap:getTilePosition(pos)
  if not mapPos then return end
  
  -- ClientService helper for cross-client compatibility
  local function getClient()
    return ClientService or _G.ClientService
  end
  
  local Client = getClient()
  local localPlayer = (Client and Client.getLocalPlayer) and Client.getLocalPlayer() or (g_game and g_game.getLocalPlayer())
  if not localPlayer then return end

  if button == 1 then
    if minimap.autowalk then
      localPlayer:autoWalk(mapPos)
    end
    return true
  elseif button == 2 then
    local menu = g_ui.createWidget('PopupMenu')
    local playerPos = localPlayer:getPosition()
    
    menu:setId("minimapMenu")
    menu:setGameMenu(true)
    menu:addOption(tr('Create mark'), function() minimap:createFlagWindow(mapPos) end)
    
    -- Only show CaveBot options if CaveBot is fully loaded (including actionList)
    if CaveBot and CaveBot.addAction and CaveBot.actionList then
      -- Add goto with player's current floor (safer, more reliable)
      menu:addOption(tr('Add CaveBot GoTo (current floor)'), function()
        safeAddCaveBotWaypoint(mapPos.x, mapPos.y, playerPos.z)
      end)
      
      -- Add goto with minimap's floor (for multi-floor waypoints)
      if mapPos.z ~= playerPos.z then
        menu:addOption(tr('Add CaveBot GoTo (floor ' .. mapPos.z .. ')'), function()
          safeAddCaveBotWaypoint(mapPos.x, mapPos.y, mapPos.z)
        end)
      end
    end
    
    menu:display(pos)
    return true
  end
  return false
end