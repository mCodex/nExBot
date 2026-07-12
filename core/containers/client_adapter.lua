local ClientAdapter = {}

function ClientAdapter.open(item, destContainer)
  if _G.Client and _G.Client.open then
    return _G.Client.open(item, destContainer)
  elseif _G.g_game and _G.g_game.open then
    return _G.g_game.open(item, destContainer)
  end
end

function ClientAdapter.close(container)
  if _G.Client and _G.Client.close then
    return _G.Client.close(container)
  elseif _G.g_game and _G.g_game.close then
    return _G.g_game.close(container)
  end
end

function ClientAdapter.getContainers()
  if _G.Client and _G.Client.getContainers then
    return _G.Client.getContainers()
  elseif _G.g_game and _G.g_game.getContainers then
    return _G.g_game.getContainers()
  end
  return {}
end

function ClientAdapter.getContainer(id)
  if _G.Client and _G.Client.getContainer then
    return _G.Client.getContainer(id)
  elseif _G.g_game and _G.g_game.getContainer then
    return _G.g_game.getContainer(id)
  end
end

function ClientAdapter.seekInContainer(containerId, targetIndex)
  if _G.g_game and _G.g_game.seekInContainer then
    return _G.g_game.seekInContainer(containerId, targetIndex)
  end
end

function ClientAdapter.refreshContainer(containerId)
  if _G.Client and _G.Client.refreshContainer then
    return _G.Client.refreshContainer(containerId)
  end
end

function ClientAdapter.requestContainerQueue()
  if _G.Client and _G.Client.requestContainerQueue then
    return _G.Client.requestContainerQueue()
  end
end

return ClientAdapter
