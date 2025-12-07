local minimap = modules.game_minimap.minimapWidget

minimap.onMouseRelease = function(widget,pos,button)
  if not minimap.allowNextRelease then return true end
  minimap.allowNextRelease = false

  local mapPos = minimap:getTilePosition(pos)
  if not mapPos then return end
  
  local localPlayer = g_game.getLocalPlayer()
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
    
    -- Add goto with player's current floor (safer, more reliable)
    menu:addOption(tr('Add CaveBot GoTo (current floor)'), function()
      CaveBot.addAction("goto", mapPos.x .. "," .. mapPos.y .. "," .. playerPos.z, true)
      CaveBot.save()
      print("[CaveBot] Added goto: " .. mapPos.x .. "," .. mapPos.y .. "," .. playerPos.z)
    end)
    
    -- Add goto with minimap's floor (for multi-floor waypoints)
    if mapPos.z ~= playerPos.z then
      menu:addOption(tr('Add CaveBot GoTo (floor ' .. mapPos.z .. ')'), function()
        CaveBot.addAction("goto", mapPos.x .. "," .. mapPos.y .. "," .. mapPos.z, true)
        CaveBot.save()
        print("[CaveBot] Added goto: " .. mapPos.x .. "," .. mapPos.y .. "," .. mapPos.z)
      end)
    end
    
    menu:display(pos)
    return true
  end
  return false
end