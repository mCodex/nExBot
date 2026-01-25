--[[
  nExBot ACL - OTCv8 Adapter
  
  Implements the ACL interfaces for OTCv8 client.
  This is the original client that nExBot was designed for.
  
  OTCv8 Specific Features:
  - moveRaw function for raw item movement
  - Bot module with contentsPanel.config pattern
  - Specific spectator patterns
]]

-- Load base adapter
local BaseAdapter = dofile("/core/acl/adapters/base.lua")

-- Create OTCv8 adapter extending base
local OTCv8Adapter = {}

-- Copy all base adapter properties
for k, v in pairs(BaseAdapter) do
  if type(v) == "table" then
    OTCv8Adapter[k] = {}
    for k2, v2 in pairs(v) do
      OTCv8Adapter[k][k2] = v2
    end
  else
    OTCv8Adapter[k] = v
  end
end

-- Adapter metadata
OTCv8Adapter.NAME = "OTCv8"
OTCv8Adapter.VERSION = "1.0.0"

--------------------------------------------------------------------------------
-- OTCv8 SPECIFIC GAME OPERATIONS
--------------------------------------------------------------------------------

-- OTCv8 has moveRaw for more control over movement
function OTCv8Adapter.game.moveRaw(thing, toPosition, count)
  if g_game and g_game.moveRaw then
    return g_game.moveRaw(thing, toPosition, count or 1)
  else
    return BaseAdapter.game.move(thing, toPosition, count)
  end
end

-- OTCv8 autoWalk implementation
function OTCv8Adapter.game.autoWalk(destination, maxSteps, options)
  if g_game and g_game.autoWalk then
    return g_game.autoWalk(destination, maxSteps, options)
  end
  return false
end

--------------------------------------------------------------------------------
-- OTCv8 SPECIFIC MAP OPERATIONS
--------------------------------------------------------------------------------

-- OTCv8 getSpectators with pattern support
function OTCv8Adapter.map.getSpectators(pos, multifloor)
  if not g_map then return {} end
  
  -- Use the bot context's getSpectators if available (more feature-rich)
  if G and G.botContext and G.botContext.getSpectators then
    return G.botContext.getSpectators(pos, multifloor)
  end
  
  -- Fallback to g_map.getSpectators
  if g_map.getSpectators then
    local specs = g_map.getSpectators(pos, multifloor or false)
    return specs or {}
  end
  
  return {}
end

-- OTCv8 specific spectators with pattern
function OTCv8Adapter.map.getSpectatorsByPattern(pos, pattern)
  if g_map and g_map.getSpectatorsByPattern then
    return g_map.getSpectatorsByPattern(pos, pattern) or {}
  end
  return OTCv8Adapter.map.getSpectators(pos, false)
end

-- OTCv8 path finding
function OTCv8Adapter.map.findPath(startPos, goalPos, options)
  -- OTCv8 uses findPath through g_map or modules
  if g_map and g_map.findPath then
    options = options or {}
    local maxComplexity = options.maxComplexity or 10000
    local maxSteps = options.maxSteps or 50
    return g_map.findPath(startPos, goalPos, maxSteps, maxComplexity)
  end
  return nil
end

--------------------------------------------------------------------------------
-- OTCv8 SPECIFIC COOLDOWN OPERATIONS
--------------------------------------------------------------------------------

OTCv8Adapter.cooldown = {}

function OTCv8Adapter.cooldown.isCooldownIconActive(iconId)
  local cooldownModule = modules.game_cooldown
  if cooldownModule and cooldownModule.isCooldownIconActive then
    return cooldownModule.isCooldownIconActive(iconId)
  end
  return false
end

function OTCv8Adapter.cooldown.isGroupCooldownIconActive(groupId)
  local cooldownModule = modules.game_cooldown
  if cooldownModule and cooldownModule.isGroupCooldownIconActive then
    return cooldownModule.isGroupCooldownIconActive(groupId)
  end
  return false
end

--------------------------------------------------------------------------------
-- OTCv8 SPECIFIC BOT OPERATIONS
--------------------------------------------------------------------------------

OTCv8Adapter.bot = {}

function OTCv8Adapter.bot.getConfigName()
  local botModule = modules.game_bot
  if botModule and botModule.contentsPanel and botModule.contentsPanel.config then
    local option = botModule.contentsPanel.config:getCurrentOption()
    return option and option.text or nil
  end
  return nil
end

function OTCv8Adapter.bot.getConfigPath()
  local configName = OTCv8Adapter.bot.getConfigName()
  if configName then
    return "/bot/" .. configName
  end
  return nil
end

--------------------------------------------------------------------------------
-- OTCv8 CALLBACK WRAPPERS
-- Wraps OTCv8's native callbacks to ACL standard
--------------------------------------------------------------------------------

-- These are the native callback registration functions for OTCv8
-- They should be called from the bot context

function OTCv8Adapter.callbacks.onCreatureAppear(callback)
  if onCreatureAppear then
    return onCreatureAppear(callback)
  end
  return BaseAdapter.callbacks.register("onCreatureAppear", callback)
end

function OTCv8Adapter.callbacks.onCreatureDisappear(callback)
  if onCreatureDisappear then
    return onCreatureDisappear(callback)
  end
  return BaseAdapter.callbacks.register("onCreatureDisappear", callback)
end

function OTCv8Adapter.callbacks.onCreaturePositionChange(callback)
  if onCreaturePositionChange then
    return onCreaturePositionChange(callback)
  end
  return BaseAdapter.callbacks.register("onCreaturePositionChange", callback)
end

function OTCv8Adapter.callbacks.onCreatureHealthPercentChange(callback)
  if onCreatureHealthPercentChange then
    return onCreatureHealthPercentChange(callback)
  end
  return BaseAdapter.callbacks.register("onCreatureHealthPercentChange", callback)
end

function OTCv8Adapter.callbacks.onPlayerPositionChange(callback)
  if onPlayerPositionChange then
    return onPlayerPositionChange(callback)
  end
  return BaseAdapter.callbacks.register("onPlayerPositionChange", callback)
end

function OTCv8Adapter.callbacks.onTalk(callback)
  if onTalk then
    return onTalk(callback)
  end
  return BaseAdapter.callbacks.register("onTalk", callback)
end

function OTCv8Adapter.callbacks.onTextMessage(callback)
  if onTextMessage then
    return onTextMessage(callback)
  end
  return BaseAdapter.callbacks.register("onTextMessage", callback)
end

function OTCv8Adapter.callbacks.onContainerOpen(callback)
  if onContainerOpen then
    return onContainerOpen(callback)
  end
  return BaseAdapter.callbacks.register("onContainerOpen", callback)
end

function OTCv8Adapter.callbacks.onContainerClose(callback)
  if onContainerClose then
    return onContainerClose(callback)
  end
  return BaseAdapter.callbacks.register("onContainerClose", callback)
end

function OTCv8Adapter.callbacks.onContainerUpdateItem(callback)
  if onContainerUpdateItem then
    return onContainerUpdateItem(callback)
  end
  return BaseAdapter.callbacks.register("onContainerUpdateItem", callback)
end

function OTCv8Adapter.callbacks.onAddItem(callback)
  if onAddItem then
    return onAddItem(callback)
  end
  return BaseAdapter.callbacks.register("onAddItem", callback)
end

function OTCv8Adapter.callbacks.onRemoveItem(callback)
  if onRemoveItem then
    return onRemoveItem(callback)
  end
  return BaseAdapter.callbacks.register("onRemoveItem", callback)
end

function OTCv8Adapter.callbacks.onTurn(callback)
  if onTurn then
    return onTurn(callback)
  end
  return BaseAdapter.callbacks.register("onTurn", callback)
end

function OTCv8Adapter.callbacks.onWalk(callback)
  if onWalk then
    return onWalk(callback)
  end
  return BaseAdapter.callbacks.register("onWalk", callback)
end

function OTCv8Adapter.callbacks.onUse(callback)
  if onUse then
    return onUse(callback)
  end
  return BaseAdapter.callbacks.register("onUse", callback)
end

function OTCv8Adapter.callbacks.onUseWith(callback)
  if onUseWith then
    return onUseWith(callback)
  end
  return BaseAdapter.callbacks.register("onUseWith", callback)
end

function OTCv8Adapter.callbacks.onManaChange(callback)
  if onManaChange then
    return onManaChange(callback)
  end
  return BaseAdapter.callbacks.register("onManaChange", callback)
end

function OTCv8Adapter.callbacks.onStatesChange(callback)
  if onStatesChange then
    return onStatesChange(callback)
  end
  return BaseAdapter.callbacks.register("onStatesChange", callback)
end

function OTCv8Adapter.callbacks.onInventoryChange(callback)
  if onInventoryChange then
    return onInventoryChange(callback)
  end
  return BaseAdapter.callbacks.register("onInventoryChange", callback)
end

function OTCv8Adapter.callbacks.onSpellCooldown(callback)
  if onSpellCooldown then
    return onSpellCooldown(callback)
  end
  return BaseAdapter.callbacks.register("onSpellCooldown", callback)
end

function OTCv8Adapter.callbacks.onGroupSpellCooldown(callback)
  if onGroupSpellCooldown then
    return onGroupSpellCooldown(callback)
  end
  return BaseAdapter.callbacks.register("onGroupSpellCooldown", callback)
end

function OTCv8Adapter.callbacks.onAttackingCreatureChange(callback)
  if onAttackingCreatureChange then
    return onAttackingCreatureChange(callback)
  end
  return BaseAdapter.callbacks.register("onAttackingCreatureChange", callback)
end

function OTCv8Adapter.callbacks.onModalDialog(callback)
  if onModalDialog then
    return onModalDialog(callback)
  end
  return BaseAdapter.callbacks.register("onModalDialog", callback)
end

function OTCv8Adapter.callbacks.onImbuementWindow(callback)
  if onImbuementWindow then
    return onImbuementWindow(callback)
  end
  return BaseAdapter.callbacks.register("onImbuementWindow", callback)
end

function OTCv8Adapter.callbacks.onAddThing(callback)
  if onAddThing then
    return onAddThing(callback)
  end
  return BaseAdapter.callbacks.register("onAddThing", callback)
end

function OTCv8Adapter.callbacks.onRemoveThing(callback)
  if onRemoveThing then
    return onRemoveThing(callback)
  end
  return BaseAdapter.callbacks.register("onRemoveThing", callback)
end

--------------------------------------------------------------------------------
-- OTCv8 SPECIFIC UTILITIES
--------------------------------------------------------------------------------

-- Get creature by name (OTCv8 pattern)
function OTCv8Adapter.utils.getCreatureByName(name, caseSensitive)
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  
  local spectators = OTCv8Adapter.map.getSpectators(player:getPosition(), true)
  for _, creature in ipairs(spectators) do
    if caseSensitive then
      if creature:getName() == name then
        return creature
      end
    else
      if creature:getName():lower() == name:lower() then
        return creature
      end
    end
  end
  
  return nil
end

-- Find item in containers (OTCv8 pattern)
function OTCv8Adapter.utils.findItem(itemId, subType)
  -- First check inventory
  local player = g_game.getLocalPlayer()
  if player then
    for slot = 1, 10 do
      local item = player:getInventoryItem(slot)
      if item and item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          return item
        end
      end
    end
  end
  
  -- Then check containers
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          return item
        end
      end
    end
  end
  
  return nil
end

-- Count items in containers (OTCv8 pattern)
function OTCv8Adapter.utils.itemAmount(itemId, subType)
  local count = 0
  
  -- Count in inventory
  local player = g_game.getLocalPlayer()
  if player then
    for slot = 1, 10 do
      local item = player:getInventoryItem(slot)
      if item and item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          count = count + item:getCount()
        end
      end
    end
  end
  
  -- Count in containers
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        if not subType or item:getSubType() == subType then
          count = count + item:getCount()
        end
      end
    end
  end
  
  return count
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function OTCv8Adapter.init()
  if nExBot and nExBot.showDebug then
    print("[OTCv8Adapter] Initialized")
  end
  return true
end

return OTCv8Adapter
